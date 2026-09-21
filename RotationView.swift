import SwiftUI
import AVFoundation

struct RotationView: View {
    @Environment(\.dismiss) var dismiss
    let asset: AVAsset
    let size: CGSize
    let thumbnail: UIImage
    @Binding var isProcessing: Bool
    var onComplete: (URL) -> Void

    @State private var axis: VideoProcessor.RotationAxis = .vertical
    @State private var axisPosition: CGFloat = 0.5 // 0.0 ~ 1.0

    var body: some View {
        VStack(spacing: 16) {
            Picker("回転軸", selection: $axis) {
                Text("縦軸回転").tag(VideoProcessor.RotationAxis.vertical)
                Text("横軸回転").tag(VideoProcessor.RotationAxis.horizontal)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 16)

            Text("赤い軸をドラッグして回転の中心位置を指定してください")
                .font(.caption)
                .foregroundColor(.secondary)

            // 動画のアスペクト比に応じたコンテナ
            GeometryReader { proxy in
                let frame = proxy.size

                ZStack {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()

                    // 赤い回転軸ライン
                    Path { path in
                        if axis == .vertical {
                            let x = frame.width * axisPosition
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: frame.height))
                        } else {
                            let y = frame.height * axisPosition
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: frame.width, y: y))
                        }
                    }
                    .stroke(Color.red, lineWidth: 3)
                    .gesture(
                        DragGesture().onChanged { value in
                            if axis == .vertical {
                                axisPosition = max(0, min(1, value.location.x / frame.width))
                            } else {
                                axisPosition = max(0, min(1, value.location.y / frame.height))
                            }
                        }
                    )
                }
                .border(Color.white.opacity(0.3), width: 1)
            }
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .padding(.horizontal, 16)

            Button("回転変換を実行してプレビュー") {
                executeRotation()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 16)
        }
    }

    private func executeRotation() {
        dismiss()
        isProcessing = true

        Task {
            let duration = try? await asset.load(.duration)
            let durationSec = CMTimeGetSeconds(duration ?? CMTime(seconds: 5, preferredTimescale: 600))

            VideoProcessor.shared.applyAxisRotation(
                asset: asset,
                axis: axis,
                axisPosition: axisPosition,
                duration: durationSec,
                targetSize: size
            ) { result in
                isProcessing = false
                if case .success(let url) = result {
                    onComplete(url)
                }
            }
        }
    }
}
