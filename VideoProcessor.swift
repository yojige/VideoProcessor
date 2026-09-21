import Foundation
import AVFoundation
import CoreImage
import Photos
import UIKit

final class VideoProcessor {
    static let shared = VideoProcessor()
    private let ciContext = CIContext()

    private func createGreenBackground(extent: CGRect) -> CIImage {
        let greenColor = CIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        return CIImage(color: greenColor).cropped(to: extent)
    }

    /// 動画トラックの preferredTransform から回転角 (0, 90, 180, 270) と正しい正立サイズを算出
    func getFixedVideoSize(asset: AVAsset) async -> (CGSize, Int) {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return (CGSize(width: 1920, height: 1080), 0)
        }
        let naturalSize = (try? await track.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
        let t = (try? await track.load(.preferredTransform)) ?? .identity

        var degrees = 0
        if t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0 {
            degrees = 90
        } else if t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0 {
            degrees = 270
        } else if t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0 {
            degrees = 0
        } else if t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0 {
            degrees = 180
        } else {
            // その他のケース（アークタンジェントから判定）
            let angle = atan2(t.b, t.a)
            degrees = Int(round(angle * 180 / .pi))
            if degrees < 0 { degrees += 360 }
        }

        if degrees == 90 || degrees == 270 {
            return (CGSize(width: naturalSize.height, height: naturalSize.width), degrees)
        } else {
            return (naturalSize, degrees)
        }
    }

    /// sourceImage を確実に正立させて (0, 0) 起点に補正する
    private func makeOrientedImage(source: CIImage, degrees: Int, targetSize: CGSize) -> CIImage {
        // すでに sourceImage が正立解像度と一致している場合はそのまま利用
        if abs(source.extent.width - targetSize.width) < 2 && abs(source.extent.height - targetSize.height) < 2 {
            let offset = CGAffineTransform(translationX: -source.extent.origin.x, y: -source.extent.origin.y)
            return source.transformed(by: offset)
        }

        var transform = CGAffineTransform.identity
        switch degrees {
        case 90:
            transform = transform.translatedBy(x: targetSize.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case 180:
            transform = transform.translatedBy(x: targetSize.width, y: targetSize.height)
            transform = transform.rotated(by: .pi)
        case 270:
            transform = transform.translatedBy(x: 0, y: targetSize.height)
            transform = transform.rotated(by: -.pi / 2)
        default:
            break
        }

        let oriented = source.transformed(by: transform)
        let originFix = CGAffineTransform(translationX: -oriented.extent.origin.x, y: -oriented.extent.origin.y)
        return oriented.transformed(by: originFix)
    }

    /// プレビュー用に動画の先頭1フレームを取得
    func extractFirstFrame(asset: AVAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        do {
            let imageRef = try generator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: imageRef)
        } catch {
            return nil
        }
    }

    /// 1) 射影変換（余白はグリーンバック）
    func applyPerspectiveTransform(
        asset: AVAsset,
        inputTopLeft: CGPoint,
        inputTopRight: CGPoint,
        inputBottomRight: CGPoint,
        inputBottomLeft: CGPoint,
        targetSize: CGSize,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task {
            let (_, degrees) = await getFixedVideoSize(asset: asset)

            let composition = AVMutableVideoComposition(asset: asset) { request in
                // 正立した基準フレーム画像を生成
                let baseImage = self.makeOrientedImage(source: request.sourceImage, degrees: degrees, targetSize: targetSize)

                let filter = CIFilter(name: "CIPerspectiveTransform")!
                filter.setValue(baseImage, forKey: kCIInputImageKey)
                filter.setValue(CIVector(cgPoint: inputTopLeft), forKey: "inputTopLeft")
                filter.setValue(CIVector(cgPoint: inputTopRight), forKey: "inputTopRight")
                filter.setValue(CIVector(cgPoint: inputBottomRight), forKey: "inputBottomRight")
                filter.setValue(CIVector(cgPoint: inputBottomLeft), forKey: "inputBottomLeft")

                let transformed = filter.outputImage ?? baseImage
                let background = self.createGreenBackground(extent: CGRect(origin: .zero, size: targetSize))
                let finalImage = transformed.composited(over: background).cropped(to: CGRect(origin: .zero, size: targetSize))

                request.finish(with: finalImage, context: self.ciContext)
            }

            composition.renderSize = targetSize
            composition.frameDuration = CMTime(value: 1, timescale: 30)

            self.exportVideo(asset: asset, videoComposition: composition, completion: completion)
        }
    }

    /// 2) 回転変換
    enum RotationAxis {
        case vertical
        case horizontal
    }

    func applyAxisRotation(
        asset: AVAsset,
        axis: RotationAxis,
        axisPosition: CGFloat,
        duration: Double,
        targetSize: CGSize,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task {
            let (_, degrees) = await getFixedVideoSize(asset: asset)

            let composition = AVMutableVideoComposition(asset: asset) { request in
                let baseImage = self.makeOrientedImage(source: request.sourceImage, degrees: degrees, targetSize: targetSize)
                let timeSec = CMTimeGetSeconds(request.compositionTime)

                let progress = (duration > 0) ? (timeSec / duration) : 0.0
                let angle = progress * 2.0 * .pi

                let width = targetSize.width
                let height = targetSize.height

                var rotTransform = CGAffineTransform.identity
                if axis == .vertical {
                    let pivotX = width * axisPosition
                    rotTransform = rotTransform.translatedBy(x: pivotX, y: 0)
                    rotTransform = rotTransform.scaledBy(x: cos(angle), y: 1.0)
                    rotTransform = rotTransform.translatedBy(x: -pivotX, y: 0)
                } else {
                    let pivotY = height * axisPosition
                    rotTransform = rotTransform.translatedBy(x: 0, y: pivotY)
                    rotTransform = rotTransform.scaledBy(x: 1.0, y: cos(angle))
                    rotTransform = rotTransform.translatedBy(x: 0, y: -pivotY)
                }

                let transformed = baseImage.transformed(by: rotTransform)
                let background = self.createGreenBackground(extent: CGRect(origin: .zero, size: targetSize))
                let finalImage = transformed.composited(over: background).cropped(to: CGRect(origin: .zero, size: targetSize))

                request.finish(with: finalImage, context: self.ciContext)
            }

            composition.renderSize = targetSize
            composition.frameDuration = CMTime(value: 1, timescale: 30)

            self.exportVideo(asset: asset, videoComposition: composition, completion: completion)
        }
    }

    /// 3) サイズ変更
    func applyResize(
        asset: AVAsset,
        newSize: CGSize,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task {
            let (fixedSize, degrees) = await getFixedVideoSize(asset: asset)

            let composition = AVMutableVideoComposition(asset: asset) { request in
                let baseImage = self.makeOrientedImage(source: request.sourceImage, degrees: degrees, targetSize: fixedSize)
                let extent = baseImage.extent

                let scaleX = newSize.width / extent.width
                let scaleY = newSize.height / extent.height
                let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)

                let finalImage = baseImage.transformed(by: scaleTransform)
                    .cropped(to: CGRect(origin: .zero, size: newSize))

                request.finish(with: finalImage, context: self.ciContext)
            }

            composition.renderSize = newSize
            composition.frameDuration = CMTime(value: 1, timescale: 30)

            self.exportVideo(asset: asset, videoComposition: composition, completion: completion)
        }
    }

    private func exportVideo(
        asset: AVAsset,
        videoComposition: AVVideoComposition,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AVAssetExportSession"])))
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed {
                    completion(.success(outputURL))
                } else {
                    completion(.failure(exportSession.error ?? NSError(domain: "ExportError", code: -2, userInfo: nil)))
                }
            }
        }
    }

    func saveToPhotoLibrary(videoURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(false, NSError(domain: "PermissionDenied", code: 403, userInfo: [NSLocalizedDescriptionKey: "Photo library permission not granted"]))
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                DispatchQueue.main.async {
                    completion(success, error)
                }
            }
        }
    }
}
