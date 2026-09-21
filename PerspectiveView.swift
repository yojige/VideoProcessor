import SwiftUI
import AVFoundation
import CoreImage

struct PerspectiveView: View {
    @Environment(\.dismiss) var dismiss
    let asset: AVAsset
    let size: CGSize // 向き補正済みの動画実解像度 (例: 1080x1920)
    let thumbnail: UIImage
    @Binding var isProcessing: Bool
    var onComplete: (URL) -> Void

    @State private var pTopLeft: CGPoint = .zero
    @State private var pTopRight: CGPoint = .zero
    @State private var pBottomRight: CGPoint = .zero
    @State private var pBottomLeft: CGPoint = .zero
    @State private var transformedPreview: UIImage?
    @State private var currentViewSize: CGSize = .zero

    private let ciContext = CIContext()

    var body: some View {
        VStack(spacing: 16) {
            Text("4角の矢印をスワイプして射影変形")
                .font(.headline)
                .padding(.top, 16)

            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                ZStack {
                    Color.green // 余白プレビュー用グリーンバック

                    if let transformedPreview = transformedPreview {
                        Image(uiImage: transformedPreview)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                    }

                    GridOverlay()

                    // 4隅のドラッグハンドル
                    arrowHandle(point: $pTopLeft, viewSize: CGSize(width: w, height: h))
                    arrowHandle(point: $pTopRight, viewSize: CGSize(width: w, height: h))
                    arrowHandle(point: $pBottomRight, viewSize: CGSize(width: w, height: h))
                    arrowHandle(point: $pBottomLeft, viewSize: CGSize(width: w, height: h))
                }
                .border(Color.white.opacity(0.3), width: 1)
                .onAppear {
                    currentViewSize = CGSize(width: w, height: h)
                    // 初期位置（四隅）
                    pTopLeft = CGPoint(x: 24, y: 24)
                    pTopRight = CGPoint(x: w - 24, y: 24)
                    pBottomRight = CGPoint(x: w - 24, y: h - 24)
                    pBottomLeft = CGPoint(x: 24, y: h - 24)
                    updatePreview(viewSize: currentViewSize)
                }
            }
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .padding(.horizontal, 16)

            Button("射影変換を実行してプレビュー") {
                executeTransform()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 16)
        }
    }

    private func arrowHandle(point: Binding<CGPoint>, viewSize: CGSize) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
            .resizable()
            .frame(width: 44, height: 44)
            .foregroundColor(.white)
            .background(Circle().fill(Color.black.opacity(0.6)))
            .position(point.wrappedValue)
            .gesture(
                DragGesture().onChanged { value in
                    point.wrappedValue = value.location
                    updatePreview(viewSize: viewSize)
                }
            )
    }

    // 画面上の座標(左上原点)を Core Image 座標(左下原点)に変換するヘルパー
    private func convertToCICoordinates(viewPoint: CGPoint, viewSize: CGSize, targetExtent: CGSize) -> CGPoint {
        let scaleX = targetExtent.width / viewSize.width
        let scaleY = targetExtent.height / viewSize.height
        let x = viewPoint.x * scaleX
        let y = (viewSize.height - viewPoint.y) * scaleY // Y軸の反転
        return CGPoint(x: x, y: y)
    }

    private func updatePreview(viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0,
              let ciImg = CIImage(image: thumbnail) else { return }

        let extent = ciImg.extent.size
        let tl = convertToCICoordinates(viewPoint: pTopLeft, viewSize: viewSize, targetExtent: extent)
        let tr = convertToCICoordinates(viewPoint: pTopRight, viewSize: viewSize, targetExtent: extent)
        let br = convertToCICoordinates(viewPoint: pBottomRight, viewSize: viewSize, targetExtent: extent)
        let bl = convertToCICoordinates(viewPoint: pBottomLeft, viewSize: viewSize, targetExtent: extent)

        let filter = CIFilter(name: "CIPerspectiveTransform")!
        filter.setValue(ciImg, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: tl), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: tr), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: br), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: bl), forKey: "inputBottomLeft")

        if let output = filter.outputImage,
           let cgImg = ciContext.createCGImage(output, from: ciImg.extent) {
            self.transformedPreview = UIImage(cgImage: cgImg)
        }
    }

    private func executeTransform() {
        guard currentViewSize.width > 0, currentViewSize.height > 0 else { return }
        dismiss()
        isProcessing = true

        // 動画の実解像度(size)に合わせた Core Image 座標系(左下原点)へ変換
        let tl = convertToCICoordinates(viewPoint: pTopLeft, viewSize: currentViewSize, targetExtent: size)
        let tr = convertToCICoordinates(viewPoint: pTopRight, viewSize: currentViewSize, targetExtent: size)
        let br = convertToCICoordinates(viewPoint: pBottomRight, viewSize: currentViewSize, targetExtent: size)
        let bl = convertToCICoordinates(viewPoint: pBottomLeft, viewSize: currentViewSize, targetExtent: size)

        VideoProcessor.shared.applyPerspectiveTransform(
            asset: asset,
            inputTopLeft: tl,
            inputTopRight: tr,
            inputBottomRight: br,
            inputBottomLeft: bl,
            targetSize: size
        ) { result in
            isProcessing = false
            if case .success(let url) = result {
                onComplete(url)
            }
        }
    }
}
struct GridOverlay: View {
    var body: some View {
        GeometryReader { g in
            Path { path in
                let w = g.size.width
                let h = g.size.height
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
        }
    }
}
