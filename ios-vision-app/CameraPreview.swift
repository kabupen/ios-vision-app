//
//  CameraView.swift
//  ios-vision-app
//
//  Created by Kosuke Takeda on 2025/05/17.
//


import SwiftUI
import AVFoundation
import Vision

struct CameraPreview: UIViewRepresentable {
    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }
    
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspect
        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {}
}

struct MockCameraPreview: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.1))
            .overlay(Text("Camera Preview").foregroundColor(.gray))
    }
}
