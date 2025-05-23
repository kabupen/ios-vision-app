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
    @State private var showImagePicker = false
    @State private var uploadedImage: UIImage? = nil
    
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
                    detectionResults: detectionResults,
                    onClear: { clearImage() }
                )
                .frame(height: geometry.size.height * 0.87) // ImageAreaView 自体のサイズ
                // .background(Color.red)
                Spacer().frame(height: 10)
                
                // --- コントロールパネル ---
                ControlPanelView(
                    inputText: $inputText,
                    isDetecting: $isDetecting,
                    uploadedImage: $uploadedImage,
                    showImagePicker: $showImagePicker,
                    cameraManager: cameraManager,
                    detectionResults: $detectionResults,
                    onCapture: { cameraManager.capturePhoto() },
                    onClear: { clearImage() },
                    onInference: {
                        guard let img = cameraManager.capturedImage else { return }
                        print("---start")
                        isDetecting = true
                        detectionResults = []
                        detectObjectsInImage(img){results in
                            DispatchQueue.main.async {
                                detectionResults = results
                                isDetecting = false
                            }
                        }
                        print(detectionResults)
                        print("---end")
                    }
                )
                // .background(.yellow)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingView(detectionResults: detectionResults)
            }
            .sheet(isPresented: $showImagePicker, onDismiss: {
                if let image = uploadedImage {
                    cameraManager.capturedImage = image // ← ここでカメラ画像としてセット
                }
            }) {
                ImagePicker(image: $uploadedImage)
            }
        }
    }
    
    func drawBoundingBoxes(
        on image: UIImage,
        observations: [VNRecognizedObjectObservation]
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            // 画像をそのまま描画
            image.draw(in: CGRect(origin: .zero, size: image.size))
            // 描画スタイル設定
            ctx.cgContext.setLineWidth(4)
            ctx.cgContext.setStrokeColor(UIColor.red.cgColor)

            for obj in observations {
                let bbox = obj.boundingBox
                // boundingBoxは[0,1]正規化。UIImageは左上原点、Visionは左下原点
                let x = bbox.origin.x * image.size.width
                let y = (1 - bbox.origin.y - bbox.size.height) * image.size.height
                let width = bbox.size.width * image.size.width
                let height = bbox.size.height * image.size.height
                let rect = CGRect(x: x, y: y, width: width, height: height)
                ctx.cgContext.stroke(rect)
            }
        }
    }
    
    
    
    
    /**
     撮影画像に対する推論実施
     */
    func detectObjectsInImage(_ uiImage: UIImage, completion: @escaping ([DetectionResult]) -> Void) {
        let fixedImage = uiImage.fixedOrientation() // <--- ★ここでExif方向を「正立」に
        // CoreML 用に画像を UIImage --> CIImage に変換
        guard let ciImage = CIImage(image: fixedImage) else { completion([]); return }
        // guard let ciImage = CIImage(image: uiImage) else { completion([]); return }
        print(ciImage.extent.height, ciImage.extent.width)
        // モデル初期化, CoreML モデルを Vision 用にラップ
        // guard let model = try? VNCoreMLModel(for: YOLOv3(configuration: MLModelConfiguration()).model) else { completion([]); return }
        guard let model = try? VNCoreMLModel(for: yolov8s(configuration: MLModelConfiguration()).model) else { completion([]); return }
        
        let request = VNCoreMLRequest(model: model) { req, error in
            guard let results = req.results as? [VNRecognizedObjectObservation] else { completion([]); return }
            
            // デバッグ
            let debugImage = drawBoundingBoxes(on: uiImage, observations: results)
            if let data = debugImage.pngData() {
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("debug_bbox.png")
                try? data.write(to: url)
                print("Debug bbox image saved to \(url)")
            }
            
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
    let onClear: () -> Void
    
    
    // --- 計算ロジックはここで関数化 ---
    private func calculateImageDisplayRect(
        image: UIImage?,
        areaWidth: CGFloat,
        areaHeight: CGFloat
    ) -> (aspect: CGFloat, rect: CGRect) {
        guard let image = image else {
            return (1.0, CGRect(x: 0, y: 0, width: areaWidth, height: areaHeight))
        }
        let imageAspect = image.size.width / image.size.height
        let areaAspect = areaWidth / areaHeight
        var displayWidth: CGFloat = areaWidth
        var displayHeight: CGFloat = areaHeight

        if imageAspect > areaAspect {
            displayWidth = areaWidth
            displayHeight = areaWidth / imageAspect
        } else {
            displayHeight = areaHeight
            displayWidth = areaHeight * imageAspect
        }
        let originX = (areaWidth - displayWidth) / 2
        let originY = (areaHeight - displayHeight) / 2
        let rect = CGRect(x: originX, y: originY, width: displayWidth, height: displayHeight)
        return (imageAspect, rect)
    }

    var body: some View {
        GeometryReader { proxy in
            let areaWidth = proxy.size.width
            let areaHeight = proxy.size.height
                
            let image = cameraManager.capturedImage
            let (imageAspect, displayRect) = calculateImageDisplayRect(
                            image: image,
                            areaWidth: areaWidth,
                            areaHeight: areaHeight
                        )

            Group {
                // --- 撮影画像表示 ---
                if let image = cameraManager.capturedImage {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(imageAspect, contentMode: .fit)
                            .frame(width: displayRect.width, height: displayRect.height)
                            .background(Color.gray.opacity(0.1))
                        DetectionOverlay(
                            results: detectionResults,
                            imageDisplayRect: displayRect
                        )
                    }
                    .frame(width: areaWidth, height: areaHeight, alignment: .center)
                    
                    // --- 右上クリアボタン（✗） ---
                    Button(action: { onClear() }) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(Color(.systemGray2))
                            .padding()
                    }
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
    let imageDisplayRect: CGRect
        
    
    var body: some View {
        let _ = { if !results.isEmpty {
            print("results isn't empty : ")
            print(results)
        } }()
        
        ForEach(results) { result in
            let rect = result.rect
            // 0〜1正規化 -> 表示サイズへ変換
            let x = imageDisplayRect.origin.x + rect.minX * imageDisplayRect.width
            let y = imageDisplayRect.origin.y + (1.0 - rect.maxY) * imageDisplayRect.height
            let width = rect.width * imageDisplayRect.width
            let height = rect.height * imageDisplayRect.height
            
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
    @Binding var uploadedImage: UIImage?
    @Binding var showImagePicker: Bool
    @ObservedObject var cameraManager: CameraManager
    @Binding var detectionResults: [DetectionResult]
    let onCapture: () -> Void
    let onClear: () -> Void
    let onInference: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // テキスト入力
            TextField("Input text prompt ...", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(minWidth: 0, maxWidth: .infinity)
                .padding(.leading, 8)
            
            Button(action: {
                showImagePicker = true
            }) {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal)
            
            Button(action: {
                if cameraManager.capturedImage == nil {
                    onCapture()
                } else {
                    onInference()
                }
            }) {
                if cameraManager.capturedImage == nil {
                    // 撮影前
                    Image(systemName: "camera")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.blue)
                } else {
                    // 撮影後 → 推論
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundColor(isDetecting ? .gray : .green)
                }
            }
            .disabled(isDetecting)
            .padding(.horizontal)
        }
    }
}

// --------- 画像オリエンテーション補正拡張 ---------
/**
 iOSカメラ画像で発生する「Exif orientationによる向きズレ」を解消する
 推論や描画時に常に「見た目通りの正しい向き」で画像を扱えるようにする拡張。
 CoreMLやVisionなど画像処理フレームワークはExif方向を考慮しないので、 .up方向に補正する
 */
extension UIImage {
    /// 画像の orientation を「.up」に統一した UIImage を返す
    func fixedOrientation() -> UIImage {
        // 既に正しい場合はそのまま返す
        if self.imageOrientation == .up {
            return self
        }
        // グラフィックコンテキストで強制的に正立化
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: self.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return normalizedImage
    }
}


#Preview {
    ContentView(cameraManager: MockCameraManager())
}
