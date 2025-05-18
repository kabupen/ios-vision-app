//
//  CameraManager.swift
//  ios-vision-app
//
//  Created by Kosuke Takeda on 2025/05/17.
//

import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    @Published var capturedImage: UIImage?
    @Published var isSessionRunning: Bool = false
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }
    
    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = true
                }
            }
        }
    }
    
    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
            }
        }
    }
    
    func capturePhoto() {
        guard session.isRunning else {return}
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: data) else { return }
        DispatchQueue.main.async {
            self.capturedImage = uiImage
        }
    }
}

#if DEBUG
import UIKit


class MockCameraManager: CameraManager {
    override init() {
        super.init()
        // プロジェクトに追加した sample.heic を読み込む
        if let path = Bundle.main.path(forResource: "IMG_4263", ofType: "heic"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let image = UIImage(data: data) {
            self.capturedImage = image
        } else {
            self.capturedImage = UIImage(systemName: "photo") // フォールバック
        }
    }
    override func capturePhoto() {
        if let path = Bundle.main.path(forResource: "IMG_4263", ofType: "heic"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let image = UIImage(data: data) {
            self.capturedImage = image
        } else {
            self.capturedImage = UIImage(systemName: "photo")
        }
    }
}
#endif
