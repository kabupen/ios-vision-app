//
//  SettingView.swift
//  ios-vision-app
//
//  Created by Kosuke Takeda on 2025/05/17.
//


import SwiftUI

struct SettingView: View {
    @Environment(\.presentationMode) var presentationMode
    var detectionResults: [DetectionResult]    // ← ContentViewから受け取る
    
    @State private var selection: Int = 0
    
    func loadDebugImage() -> UIImage? {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documentsURL = urls.first else { return nil }
        let debugImageURL = documentsURL.appendingPathComponent("debug_bbox.png")
        return UIImage(contentsOfFile: debugImageURL.path)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("ページ切り替え", selection: $selection) {
                    Text("設定").tag(0)
                    Text("デバッグ").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if selection == 0 {
                    // 通常の設定
                    Text("ここに設定内容...")
                        .padding()
                } else {
                    // デバッグ用出力
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("推論ログ").font(.headline)
                            ForEach(detectionResults) { result in
                                Text("\(result.label) (\(Int(result.confidence * 100))%) rect: \(String(format: "%.2f,%.2f,%.2f,%.2f", result.rect.minX, result.rect.minY, result.rect.width, result.rect.height))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .padding()
                        
                        Text("デバッグ画像プレビュー")
                            .font(.headline)
                            .padding(.bottom, 4)
                        if let image = loadDebugImage() {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 350, maxHeight: 350)
                                .border(Color.blue)
                        } else {
                            Text("デバッグ画像が見つかりません")
                                .foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
            }
            .navigationBarTitle("設定", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
