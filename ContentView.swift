import SwiftUI
import PhotosUI
import AVKit

struct ContentView: View {
    @State private var selectedVideoURL: URL?
    @State private var originalAsset: AVAsset?
    @State private var originalSize: CGSize = .zero
    @State private var previewThumbnail: UIImage?
    @State private var processedVideoURL: URL?

    @State private var isPickerPresented = false
    @State private var activeSheet: ActiveSheet?
    @State private var isProcessing = false
    @State private var isLoadingVideo = false // 動画読み込み中フラグ
    @State private var alertMessage = ""
    @State private var showAlert = false

    enum ActiveSheet: Identifiable {
        case perspective, rotate, resize, preview
        var id: Int { hashValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text("Video Transformer")
                    .font(.largeTitle.bold())
                    .padding(.top, 40)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 25) {
                    MenuIconButton(title: "動画選択", icon: "photo.on.rectangle", color: .blue) {
                        resetAllData()
                        isPickerPresented = true
                    }

                    MenuIconButton(title: "射影変換", icon: "arrow.up.left.and.down.right.magnifyingglass", color: .indigo, disabled: originalAsset == nil) {
                        activeSheet = .perspective
                    }

                    MenuIconButton(title: "回転変換", icon: "arrow.triangle.2.circlepath", color: .purple, disabled: originalAsset == nil) {
                        activeSheet = .rotate
                    }

                    MenuIconButton(title: "サイズ変更", icon: "aspectratio", color: .orange, disabled: originalAsset == nil) {
                        activeSheet = .resize
                    }

                    MenuIconButton(title: "変換動画の確認", icon: "play.rectangle.fill", color: .green, disabled: processedVideoURL == nil) {
                        activeSheet = .preview
                    }

                    MenuIconButton(title: "エキスポート", icon: "square.and.arrow.down.fill", color: .pink, disabled: processedVideoURL == nil) {
                        exportToPhotos()
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .overlay {
                // 変換中のオーバーレイ
                if isProcessing {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("動画を変換中...")
                        .padding(24)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(radius: 10)
                }

                // 動画読み込み中のオーバーレイ
                if isLoadingVideo {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("動画を読み込み中...")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .padding(28)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
            }
            .sheet(isPresented: $isPickerPresented) {
                VideoPicker(
                    selectedURL: $selectedVideoURL,
                    isLoading: $isLoadingVideo,
                    onLoaded: loadAsset
                )
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .perspective:
                    if let asset = originalAsset, let thumb = previewThumbnail {
                        PerspectiveView(asset: asset, size: originalSize, thumbnail: thumb, isProcessing: $isProcessing) { url in
                            handleConversionComplete(url: url)
                        }
                    }
                case .rotate:
                    if let asset = originalAsset, let thumb = previewThumbnail {
                        RotationView(asset: asset, size: originalSize, thumbnail: thumb, isProcessing: $isProcessing) { url in
                            handleConversionComplete(url: url)
                        }
                    }
                case .resize:
                    if let asset = originalAsset {
                        ResizeView(asset: asset, size: originalSize, isProcessing: $isProcessing) { url in
                            handleConversionComplete(url: url)
                        }
                    }
                case .preview:
                    if let url = processedVideoURL {
                        PlayerView(videoURL: url)
                    }
                }
            }
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func resetAllData() {
        selectedVideoURL = nil
        originalAsset = nil
        originalSize = .zero
        previewThumbnail = nil
        processedVideoURL = nil
    }

    private func loadAsset(url: URL) {
        let asset = AVAsset(url: url)
        Task {
            let (fixedSize, _) = await VideoProcessor.shared.getFixedVideoSize(asset: asset)
            let thumb = await VideoProcessor.shared.extractFirstFrame(asset: asset)

            await MainActor.run {
                self.originalAsset = asset
                self.originalSize = fixedSize
                self.previewThumbnail = thumb
                self.isLoadingVideo = false // 読み込み完了
            }
        }
    }

    private func handleConversionComplete(url: URL) {
        self.processedVideoURL = url
        self.activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.activeSheet = .preview
        }
    }

    private func exportToPhotos() {
        guard let url = processedVideoURL else { return }
        isProcessing = true
        VideoProcessor.shared.saveToPhotoLibrary(videoURL: url) { success, error in
            isProcessing = false
            alertMessage = success ? "写真アプリに保存しました。" : "保存に失敗しました: \(error?.localizedDescription ?? "")"
            showAlert = true
        }
    }
}

struct MenuIconButton: View {
    let title: String
    let icon: String
    let color: Color
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                    .frame(width: 70, height: 70)
                    .background(disabled ? Color.gray : color)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(disabled ? .secondary : .primary)
            }
        }
        .disabled(disabled)
    }
}

struct PlayerView: View {
    let videoURL: URL
    
    var body: some View {
        VideoPlayer(player: AVPlayer(url: videoURL))
            .ignoresSafeArea()
    }
}
