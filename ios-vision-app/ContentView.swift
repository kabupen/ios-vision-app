//
//  ContentView.swift
//  ios-vision-app
//
//  Created by Kosuke Takeda on 2025/05/17.
//

import SwiftUI
import Vision
import VisionKit
import AVFoundation
import CoreML

struct ContentView: View {
    @State private var isShowingSettings = false
    @State private var recognizedText = ""
    @State private var isDetecting = false
    @State private var detectionResults : [DetectionResult] = []
    @StateObject var cameraManager: CameraManager
    @State private var inputText: String = ""
    
    let imageAreaRatio: CGFloat = 0.8
    
    init(cameraManager: CameraManager = CameraManager()) {
        _cameraManager = StateObject(wrappedValue: cameraManager)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let imageAreaHeight = geometry.size.height * imageAreaRatio
            let imageAreaWidth = geometry.size.width
            let headerHeight: CGFloat = 50
            let safeTop = geometry.safeAreaInsets.top
            
            VStack(spacing: 0) {
                // ----- ヘッダー -----
                HeaderView(isShowingSettings: $isShowingSettings)
                
                // --- 画像表示エリア ---
                ImageAreaView(
                    cameraManager: cameraManager,
                    detectionResults: detectionResults
                )
                .frame(height: geometry.size.height * 0.9) // ImageAreaView 自体のサイズ
                // .background(Color.red)
                
                // --- コントロールパネル ---
                ControlPanelView(
                    inputText: $inputText,
                    isDetecting: $isDetecting,
                    cameraManager: cameraManager,
                    detectionResults: $detectionResults,
                    onCapture: { cameraManager.capturePhoto() },
                    onClear: { clearImage() },
                    onInference: {
                        guard let img = cameraManager.capturedImage else { return }
                        isDetecting = true
                        detectionResults = []
                        detectObjectsInImage(img){results in
                            DispatchQueue.main.async {
                                detectionResults = results
                                isDetecting = false
                            }
                        }
                    }
                )
                .background(.yellow)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingView()
            }
        }
    }
    
    /**
     撮影画像に対する推論実施
     */
    func detectObjectsInImage(_ uiImage: UIImage, completion: @escaping ([DetectionResult]) -> Void) {
        // CoreML 用に画像を UIImage --> CIImage に変換
        guard let ciImage = CIImage(image: uiImage) else { completion([]); return }
        // モデル初期化, CoreML モデルを Vision 用にラップ
        guard let model = try? VNCoreMLModel(for: YOLOv3(configuration: MLModelConfiguration()).model) else { completion([]); return }
        
        let request = VNCoreMLRequest(model: model) { req, error in
            guard let results = req.results as? [VNRecognizedObjectObservation] else { completion([]); return }
            let mapped = results.map { obj in
                DetectionResult(
                    label: obj.labels.first?.identifier ?? "Unknown",
                    confidence: obj.confidence,
                    rect: obj.boundingBox
                )
            }
            completion(mapped)
        }
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        DispatchQueue.global().async {
            try? handler.perform([request])
        }
    }
    
    func clearImage() {
        cameraManager.capturedImage = nil
        detectionResults = []
    }
}


// ------- sub view --------


private struct HeaderView: View {
    @Binding var isShowingSettings: Bool
    
    var body: some View {
        HStack {
            // メニュー
            Button(action: {
                isShowingSettings = true
            }) {
                Image(systemName: "line.3.horizontal")
                    .resizable()
                    .frame(width: 24, height: 18)
                    .padding(8)
            }
            .accessibilityLabel("メニュー")
            // タイトル
            Text("iOS Vision App")
                .font(.headline)
            Spacer()
        }
    }
}


// 画像エリア
private struct ImageAreaView : View {
    @ObservedObject var cameraManager: CameraManager
    let detectionResults: [DetectionResult]

    var body: some View {
        GeometryReader { proxy in
            let areaWidth = proxy.size.width
            let areaHeight = proxy.size.height

            Group {
                // --- 撮影画像表示 ---
                if let image = cameraManager.capturedImage {
                    let imageAspect = image.size.width / image.size.height
                    let fitWidth = areaWidth / max(1, areaWidth / (areaHeight * imageAspect))
                    let fitHeight = fitWidth / imageAspect

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(imageAspect, contentMode: .fit)
                            .frame(width: fitWidth, height: fitHeight)
                            .background(Color.gray.opacity(0.1))
                        DetectionOverlay(
                            results: detectionResults,
                            frameSize: CGSize(width: fitWidth, height: fitHeight)
                        )
                    }
                    .frame(width: areaWidth, height: areaHeight, alignment: .center)
                } 
                // --- プレビュー用 ---
                else {
                    let previewAspect: CGFloat = 4.0 / 3.0
                    let fitWidth = areaWidth / max(1, areaWidth / (areaHeight * previewAspect))
                    let fitHeight = fitWidth / previewAspect

                    CameraPreview(session: cameraManager.session)
                        .onAppear { cameraManager.startSession() }
                        .onDisappear { cameraManager.stopSession() }
                }
            }
        }
    }
}





struct DetectionOverlay: View {
    let results: [DetectionResult]
    let frameSize: CGSize   // 表示ビューのサイズ
    
    var body: some View {
        ForEach(results) { result in
            let rect = result.rect
            // 0〜1正規化 -> 表示サイズへ変換
            let x = rect.minX * frameSize.width
            let y = (1.0 - rect.maxY) * frameSize.height // Visionは左下原点、SwiftUIは左上原点
            let width = rect.width * frameSize.width
            let height = rect.height * frameSize.height
            
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(Color.red, lineWidth: 2)
                    .frame(width: width, height: height)
                    .position(x: x + width/2, y: y + height/2)
                Text("\(result.label) \(Int(result.confidence * 100))%")
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .font(.caption)
                    .padding(2)
                    .position(x: x + 8, y: y + 12) // バウンディングボックスの左上付近に表示
            }
        }
    }
}


private struct ControlPanelView: View {
    @Binding var inputText: String
    @Binding var isDetecting: Bool
    @ObservedObject var cameraManager: CameraManager
    @Binding var detectionResults: [DetectionResult]
    let onCapture: () -> Void
    let onClear: () -> Void
    let onInference: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            TextField("Input", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(minWidth: 0, maxWidth: .infinity)
                .padding(.leading, 8)
            
            if cameraManager.capturedImage == nil {
                Button(action: onCapture) {
                    Image(systemName: "camera")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                        .foregroundColor(.blue)
                }
                .padding(.leading, 8)
                .disabled(isDetecting || !cameraManager.session.isRunning)
            } else {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                        .foregroundColor(.gray)
                }
                .padding(.leading, 8)
                .disabled(isDetecting)
            }
            
            Button(action: onInference) {
                Text(isDetecting ? "processing...": "Inference")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background((cameraManager.capturedImage != nil && !isDetecting) ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(cameraManager.capturedImage == nil || isDetecting)
            .padding(.horizontal)
        }
        /**
        // results
        if !detectionResults.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("== デバッグ出力 ==")
                    .font(.caption)
                    .foregroundColor(.gray)
                ForEach(detectionResults) { result in
                    Text("\(result.label) (\(Int(result.confidence * 100))%) rect: \(String(format: "%.2f,%.2f,%.2f,%.2f", result.rect.minX, result.rect.minY, result.rect.width, result.rect.height))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal)
        }
         */
    }
}


#Preview {
    ContentView(cameraManager: MockCameraManager())
}
