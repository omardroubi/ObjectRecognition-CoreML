//
//  ViewController.swift
//  ObjectRecognition-CoreML
//
//  Created by Omar Droubi on 4/11/18.
//  Copyright © 2018 Omar Droubi. All rights reserved.

import UIKit
import AVFoundation
import CoreML
import Vision
import CoreImage
import CoreVideo
import Accelerate

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var imageView :UIImageView!
    @IBOutlet weak var objectName: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Check if running on simulator
        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            let alert = UIAlertController(title: "You're running on simulator", message: "The simulator doesn't have a camera!", preferredStyle: UIAlertControllerStyle.alert)
            
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
            
            self.present(alert, animated: true, completion: nil)
        
        // else, Start Camera
        } else {
            let session = AVCaptureSession()

            session.sessionPreset = AVCaptureSession.Preset.photo
            let captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
            
            let deviceInput = try! AVCaptureDeviceInput(device: captureDevice!)
            let deviceOutput = AVCaptureVideoDataOutput()
            deviceOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            deviceOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
            session.addInput(deviceInput)
            session.addOutput(deviceOutput)
            
            let imageLayer = AVCaptureVideoPreviewLayer(session: session)
            imageLayer.frame = imageView.bounds
            imageView.layer.addSublayer(imageLayer)
            
            session.startRunning()
        }
    }
    
    // Get Prediction from CoreML model: Returns objectName
    func getPrediction(image: CVPixelBuffer) -> String {
        let imageModel: Inceptionv3 = Inceptionv3()

        if let prediciton = try? imageModel.prediction(image: image) {
            return prediciton.classLabel
        }
        
        return "Loading..."
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        DispatchQueue.main.async {
            guard var pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            
            pixelBuffer = self.resizePixelBuffer(pixelBuffer, width: 299, height: 299) as! CVImageBuffer 

            self.objectName.text = self.getPrediction(image: pixelBuffer)
        }
    }
    
    /**
     Creates a RGB pixel buffer of the specified width and height.
     */
    public func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height,
                                         kCVPixelFormatType_32BGRA, nil,
                                         &pixelBuffer)
        if status != kCVReturnSuccess {
            print("Error: could not create resized pixel buffer", status)
            return nil
        }
        return pixelBuffer
    }
    
    /**
     First crops the pixel buffer, then resizes it.
     */
    public func resizePixelBuffer(_ srcPixelBuffer: CVPixelBuffer,
                                  cropX: Int,
                                  cropY: Int,
                                  cropWidth: Int,
                                  cropHeight: Int,
                                  scaleWidth: Int,
                                  scaleHeight: Int) -> CVPixelBuffer? {
        
        CVPixelBufferLockBaseAddress(srcPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        guard let srcData = CVPixelBufferGetBaseAddress(srcPixelBuffer) else {
            print("Error: could not get pixel buffer base address")
            return nil
        }
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(srcPixelBuffer)
        let offset = cropY*srcBytesPerRow + cropX*4
        var srcBuffer = vImage_Buffer(data: srcData.advanced(by: offset),
                                      height: vImagePixelCount(cropHeight),
                                      width: vImagePixelCount(cropWidth),
                                      rowBytes: srcBytesPerRow)
        
        let destBytesPerRow = scaleWidth*4
        guard let destData = malloc(scaleHeight*destBytesPerRow) else {
            print("Error: out of memory")
            return nil
        }
        var destBuffer = vImage_Buffer(data: destData,
                                       height: vImagePixelCount(scaleHeight),
                                       width: vImagePixelCount(scaleWidth),
                                       rowBytes: destBytesPerRow)
        
        let error = vImageScale_ARGB8888(&srcBuffer, &destBuffer, nil, vImage_Flags(0))
        CVPixelBufferUnlockBaseAddress(srcPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        if error != kvImageNoError {
            print("Error:", error)
            free(destData)
            return nil
        }
        
        let releaseCallback: CVPixelBufferReleaseBytesCallback = { _, ptr in
            if let ptr = ptr {
                free(UnsafeMutableRawPointer(mutating: ptr))
            }
        }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(srcPixelBuffer)
        var dstPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreateWithBytes(nil, scaleWidth, scaleHeight,
                                                  pixelFormat, destData,
                                                  destBytesPerRow, releaseCallback,
                                                  nil, nil, &dstPixelBuffer)
        if status != kCVReturnSuccess {
            print("Error: could not create new pixel buffer")
            free(destData)
            return nil
        }
        return dstPixelBuffer
    }
    
    /**
     Resizes a CVPixelBuffer to a new width and height.
     */
    public func resizePixelBuffer(_ pixelBuffer: CVPixelBuffer,
                                  width: Int, height: Int) -> CVPixelBuffer? {
        return resizePixelBuffer(pixelBuffer, cropX: 0, cropY: 0,
                                 cropWidth: CVPixelBufferGetWidth(pixelBuffer),
                                 cropHeight: CVPixelBufferGetHeight(pixelBuffer),
                                 scaleWidth: width, scaleHeight: height)
    }
    
    /**
     Resizes a CVPixelBuffer to a new width and height.
     */
    public func resizePixelBuffer(_ pixelBuffer: CVPixelBuffer,
                                  width: Int, height: Int,
                                  output: CVPixelBuffer, context: CIContext) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = CGFloat(width) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sy = CGFloat(height) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaleTransform = CGAffineTransform(scaleX: sx, y: sy)
        let scaledImage = ciImage.transformed(by: scaleTransform)
        context.render(scaledImage, to: output)
    }
    
}
