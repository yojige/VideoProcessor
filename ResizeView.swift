import SwiftUI
import AVFoundation

struct ResizeView: View {
    @Environment(\.dismiss) var dismiss
    let asset: AVAsset
    let size: CGSize
    @Binding var isProcessing: Bool
    var onComplete: (URL) -> Void

    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var percentText: String = "100"

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("解像度 (px)")) {
                    HStack {
                        Text("幅:")
                        TextField("Width", text: $widthText)
                            .keyboardType(.numberPad)
                            .onChange(of: widthText) { newValue in
                                if let w = Double(newValue), size.width > 0 {
                                    percentText = String(format: "%.1f", (w / size.width) * 100)
                                }
                            }
                    }
                    HStack {
                        Text("高さ:")
                        TextField("Height", text: $heightText)
                            .keyboardType(.numberPad)
                    }
                }

                Section(header: Text("元の解像度に対する比率 (%)")) {
                    HStack {
                        Text("比率:")
                        TextField("Percentage", text: $percentText)
                            .keyboardType(.decimalPad)
                            .onChange(of: percentText) { newValue in
                                if let p = Double(newValue) {
                                    let ratio = p / 100.0
                                    widthText = String(format: "%.0f", size.width * ratio)
                                    heightText = String(format: "%.0f", size.height * ratio)
                                }
                            }
                    }
                }

                Button("サイズ変更を実行してプレビュー") {
                    if let w = Double(widthText), let h = Double(heightText) {
                        dismiss()
                        isProcessing = true
                        let targetSize = CGSize(width: w, height: h)
                        VideoProcessor.shared.applyResize(asset: asset, newSize: targetSize) { result in
                            isProcessing = false
                            if case .success(let url) = result {
                                onComplete(url)
                            }
                        }
                    }
                }
            }
            .navigationTitle("動画サイズ変更")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                widthText = String(format: "%.0f", size.width)
                heightText = String(format: "%.0f", size.height)
            }
        }
    }
}
