import SwiftUI
import PhotosUI
import AVKit

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedURL: URL?
    @Binding var isLoading: Bool
    var onLoaded: (URL) -> Void
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        init(_ parent: VideoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()

            guard let itemProvider = results.first?.itemProvider,
                  itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                return
            }

            // 読み込み開始インジケータを即座に表示
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }

            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                guard let url = url else {
                    DispatchQueue.main.async {
                        self.parent.isLoading = false
                    }
                    return
                }

                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tempURL)
                try? FileManager.default.copyItem(at: url, to: tempURL)

                DispatchQueue.main.async {
                    self.parent.selectedURL = tempURL
                    self.parent.onLoaded(tempURL)
                }
            }
        }
    }
}
