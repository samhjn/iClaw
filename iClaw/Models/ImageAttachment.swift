import Foundation
import UIKit

struct ImageAttachment: Codable, Identifiable {
    let id: UUID
    let imageData: Data
    let mimeType: String
    let width: Int
    let height: Int

    var base64DataURI: String {
        "data:\(mimeType);base64,\(imageData.base64EncodedString())"
    }

    var uiImage: UIImage? {
        UIImage(data: imageData)
    }

    /// Compress and resize a UIImage into an ImageAttachment.
    /// Max dimension is capped at `maxDimension` pixels; JPEG quality at `quality`.
    static func from(image: UIImage, maxDimension: CGFloat = 1024, quality: CGFloat = 0.75) -> ImageAttachment? {
        let resized = resize(image: image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
        return ImageAttachment(
            id: UUID(),
            imageData: data,
            mimeType: "image/jpeg",
            width: Int(resized.size.width * resized.scale),
            height: Int(resized.size.height * resized.scale)
        )
    }

    private static func resize(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }

        let ratio = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
