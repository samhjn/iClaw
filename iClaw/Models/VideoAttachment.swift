import Foundation
import UIKit
import AVFoundation

struct VideoAttachment: Codable, Identifiable {
    let id: UUID
    /// Thumbnail image data (JPEG). Full video lives on disk via `fileReference`.
    let thumbnailData: Data
    let mimeType: String
    let width: Int
    let height: Int
    let duration: TimeInterval
    let fileSize: Int64

    /// When non-nil, the full video lives on disk at this reference
    /// (format: `agentfile://<agentId>/<filename>`).
    var fileReference: String?

    /// Base64 data URI of the full video (for API transmission).
    /// Returns nil if the file is missing or too large.
    var base64DataURI: String? {
        guard let data = resolvedVideoData else { return nil }
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    /// Load the full video data from disk.
    var resolvedVideoData: Data? {
        guard let fileReference else { return nil }
        guard let (agentId, filename) = AgentFileManager.parseFileReference(fileReference) else { return nil }
        let url = AgentFileManager.shared.fileURL(agentId: agentId, name: filename)
        return try? Data(contentsOf: url)
    }

    /// Whether the original file has been deleted by the user.
    var isFileDeleted: Bool {
        guard let fileReference else { return false }
        guard let (agentId, filename) = AgentFileManager.parseFileReference(fileReference) else { return true }
        return !AgentFileManager.shared.fileExists(agentId: agentId, name: filename)
    }

    /// Thumbnail as UIImage.
    var thumbnailImage: UIImage? {
        thumbnailData.isEmpty ? nil : UIImage(data: thumbnailData)
    }

    /// Human-readable duration string.
    var durationString: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Human-readable file size string.
    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    // MARK: - Factory Methods

    /// Create from an agentfile:// reference by extracting metadata from the video on disk.
    static func from(fileReference ref: String) -> VideoAttachment? {
        guard let (agentId, filename) = AgentFileManager.parseFileReference(ref) else { return nil }
        let url = AgentFileManager.shared.fileURL(agentId: agentId, name: filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else { return nil }

        var width = 0, height = 0
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            width = Int(abs(size.width))
            height = Int(abs(size.height))
        }

        let fileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        let thumbnail = generateThumbnail(from: url)
        let ext = (filename as NSString).pathExtension.lowercased()

        return VideoAttachment(
            id: UUID(),
            thumbnailData: thumbnail,
            mimeType: mimeTypeForExtension(ext),
            width: width,
            height: height,
            duration: duration,
            fileSize: fileSize,
            fileReference: ref
        )
    }

    /// Create from raw video data, saving to the agent's file folder.
    static func from(data: Data, filename: String, agentId: UUID) -> VideoAttachment? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return nil }

        do {
            try AgentFileManager.shared.writeFile(agentId: agentId, name: filename, data: data)
        } catch {
            return nil
        }

        let ref = AgentFileManager.makeFileReference(agentId: agentId, filename: filename)
        return from(fileReference: ref)
    }

    // MARK: - Supported Formats

    static let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "webm"
    ]

    // MARK: - Thumbnail

    static func generateThumbnail(from url: URL, maxDimension: CGFloat = 128) -> Data {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        let time = CMTime(seconds: min(1.0, CMTimeGetSeconds(asset.duration) / 2), preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return Data()
        }
        let image = UIImage(cgImage: cgImage)
        return image.jpegData(compressionQuality: 0.5) ?? Data()
    }

    // MARK: - MIME Types

    static func mimeTypeForExtension(_ ext: String) -> String {
        switch ext {
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        default: return "video/mp4"
        }
    }
}
