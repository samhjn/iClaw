import Foundation
import UIKit

// MARK: - Request / Response Models

struct ImageGenerationRequest: Encodable {
    let model: String
    let prompt: String
    var n: Int?
    var size: String?
    var quality: String?
    var responseFormat: String?

    enum CodingKeys: String, CodingKey {
        case model, prompt, n, size, quality
        case responseFormat = "response_format"
    }
}

struct ImageGenerationResponse: Decodable {
    let data: [ImageData]

    struct ImageData: Decodable {
        let url: String?
        let b64Json: String?
        let revisedPrompt: String?

        enum CodingKeys: String, CodingKey {
            case url
            case b64Json = "b64_json"
            case revisedPrompt = "revised_prompt"
        }
    }
}

enum ImageGenerationError: LocalizedError {
    case noProviderConfigured
    case invalidURL(String)
    case apiError(statusCode: Int, message: String)
    case noImageReturned
    case invalidImageData
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No image generation provider configured."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .noImageReturned:
            return "No image returned by the API."
        case .invalidImageData:
            return "Invalid image data received."
        case .downloadFailed(let url):
            return "Failed to download image from: \(url)"
        }
    }
}

// MARK: - Service

final class ImageGenerationService: @unchecked Sendable {
    private let provider: LLMProvider
    private let modelName: String

    init(provider: LLMProvider, modelName: String? = nil) {
        self.provider = provider
        self.modelName = modelName ?? provider.modelName
    }

    /// Generate images, routing to the correct API based on model capabilities.
    func generate(
        prompt: String,
        n: Int = 1,
        size: String? = nil,
        quality: String? = nil,
        agentId: UUID
    ) async throws -> (images: [ImageAttachment], revisedPrompt: String?) {
        let caps = provider.capabilities(for: modelName)

        switch caps.imageGenerationMode {
        case .dedicatedAPI:
            return try await callDedicatedAPI(
                prompt: prompt, n: n, size: size, quality: quality, agentId: agentId
            )
        case .chatInline:
            return try await callChatInline(
                prompt: prompt, agentId: agentId
            )
        case .none:
            throw ImageGenerationError.noProviderConfigured
        }
    }

    // MARK: - Dedicated /images/generations API

    private func callDedicatedAPI(
        prompt: String, n: Int, size: String?, quality: String?, agentId: UUID
    ) async throws -> (images: [ImageAttachment], revisedPrompt: String?) {
        let body = ImageGenerationRequest(
            model: modelName,
            prompt: prompt,
            n: n,
            size: size,
            quality: quality,
            responseFormat: "b64_json"
        )

        let endpoint = buildEndpoint("/images/generations")
        guard let url = URL(string: endpoint) else {
            throw ImageGenerationError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("iClaw/1.0 (https://iclaw.shadow.mov)", forHTTPHeaderField: "User-Agent")
        if !provider.apiKey.isEmpty {
            request.addValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageGenerationError.apiError(statusCode: 0, message: "Invalid response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ImageGenerationError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let decoded = try JSONDecoder().decode(ImageGenerationResponse.self, from: data)
        guard !decoded.data.isEmpty else {
            throw ImageGenerationError.noImageReturned
        }

        var attachments: [ImageAttachment] = []
        var revisedPrompt: String?

        for item in decoded.data {
            if revisedPrompt == nil { revisedPrompt = item.revisedPrompt }

            if let b64 = item.b64Json, let imageData = Data(base64Encoded: b64) {
                if let attachment = createAttachment(from: imageData, mimeType: "image/png", agentId: agentId) {
                    attachments.append(attachment)
                }
            } else if let urlStr = item.url {
                if let imageData = try? await downloadImage(from: urlStr) {
                    let mimeType = urlStr.contains(".png") ? "image/png" : "image/jpeg"
                    if let attachment = createAttachment(from: imageData, mimeType: mimeType, agentId: agentId) {
                        attachments.append(attachment)
                    }
                }
            }
        }

        guard !attachments.isEmpty else {
            throw ImageGenerationError.invalidImageData
        }

        return (attachments, revisedPrompt)
    }

    // MARK: - Chat Inline (modalities)

    private func callChatInline(
        prompt: String, agentId: UUID
    ) async throws -> (images: [ImageAttachment], revisedPrompt: String?) {
        let service = LLMService(provider: provider, modelNameOverride: modelName)
        let messages = [LLMChatMessage.user(prompt)]
        let response = try await service.chatCompletion(messages: messages, tools: nil)

        guard let message = response.choices.first?.message else {
            throw ImageGenerationError.noImageReturned
        }

        var attachments: [ImageAttachment] = []

        // Extract inline images from content (markdown image syntax with data URIs)
        if let content = message.content {
            let pattern = #"!\[.*?\]\((data:image\/[^;]+;base64,[A-Za-z0-9+/=]+)\)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: content) {
                        let dataURI = String(content[range])
                        if let attachment = ImageAttachment.from(base64DataURI: dataURI, agentId: agentId) {
                            attachments.append(attachment)
                        }
                    }
                }
            }
        }

        // Also check contentParts for imageURL parts
        if let parts = message.contentParts {
            for part in parts {
                if case .imageURL(let url, _) = part {
                    if url.hasPrefix("data:") {
                        if let attachment = ImageAttachment.from(base64DataURI: url, agentId: agentId) {
                            attachments.append(attachment)
                        }
                    } else if let imageData = try? await downloadImage(from: url) {
                        let mimeType = url.contains(".png") ? "image/png" : "image/jpeg"
                        if let attachment = createAttachment(from: imageData, mimeType: mimeType, agentId: agentId) {
                            attachments.append(attachment)
                        }
                    }
                }
            }
        }

        guard !attachments.isEmpty else {
            throw ImageGenerationError.noImageReturned
        }

        // Extract text content as revised prompt
        let textContent = message.content?.replacingOccurrences(
            of: #"!\[.*?\]\(data:image\/[^)]+\)"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return (attachments, textContent?.isEmpty == false ? textContent : nil)
    }

    // MARK: - Helpers

    private func buildEndpoint(_ path: String) -> String {
        let base = provider.endpoint
        if base.hasSuffix("/") {
            return base + path.dropFirst() // remove leading /
        }
        return base + path
    }

    private func createAttachment(from imageData: Data, mimeType: String, agentId: UUID) -> ImageAttachment? {
        guard let image = UIImage(data: imageData) else { return nil }
        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)
        let thumbnail = ImageAttachment.generateThumbnail(from: image)
        let ref = AgentFileManager.shared.saveImage(imageData, mimeType: mimeType, agentId: agentId)

        return ImageAttachment(
            id: UUID(),
            imageData: thumbnail,
            mimeType: mimeType,
            width: w,
            height: h,
            fileReference: ref
        )
    }

    private func downloadImage(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw ImageGenerationError.downloadFailed(urlString)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ImageGenerationError.downloadFailed(urlString)
        }
        return data
    }
}
