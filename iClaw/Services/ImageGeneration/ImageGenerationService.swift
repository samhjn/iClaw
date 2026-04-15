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
        case .dashScope:
            return try await callDashScopeAPI(
                prompt: prompt, n: n, size: size, agentId: agentId
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

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(body)
        let request = try APIRequestBuilder.jsonPOST(
            base: provider.endpoint,
            path: "/images/generations",
            apiKey: provider.apiKey,
            style: provider.apiStyle,
            body: bodyData
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        do {
            try APIRequestBuilder.validate(data: data, response: response)
        } catch let error as APIRequestError {
            throw ImageGenerationError.apiError(
                statusCode: error.statusCode ?? 0,
                message: error.messageBody ?? "Unknown error"
            )
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

    // MARK: - DashScope Async Task API (wan2.7-image series)

    private func callDashScopeAPI(
        prompt: String, n: Int, size: String?, agentId: UUID
    ) async throws -> (images: [ImageAttachment], revisedPrompt: String?) {
        let taskId = try await dashScopeSubmitTask(prompt: prompt, n: n, size: size)
        let imageURLs = try await dashScopePollUntilDone(taskId: taskId)

        var attachments: [ImageAttachment] = []
        for urlStr in imageURLs {
            try Task.checkCancellation()
            if let imageData = try? await downloadImage(from: urlStr) {
                let mimeType = urlStr.lowercased().contains(".png") ? "image/png" : "image/jpeg"
                if let attachment = createAttachment(from: imageData, mimeType: mimeType, agentId: agentId) {
                    attachments.append(attachment)
                }
            }
        }

        guard !attachments.isEmpty else {
            throw ImageGenerationError.invalidImageData
        }
        return (attachments, nil)
    }

    /// Submit an image generation task to DashScope and return the task ID.
    private func dashScopeSubmitTask(prompt: String, n: Int, size: String?) async throws -> String {
        let baseURL = provider.endpoint.hasSuffix("/")
            ? String(provider.endpoint.dropLast()) : provider.endpoint
        let urlStr = "\(baseURL)/services/aigc/image-generation/generation"
        guard let url = URL(string: urlStr) else {
            throw ImageGenerationError.invalidURL(urlStr)
        }

        let dsSize = mapDashScopeSize(size)

        var parameters: [String: Any] = [
            "n": min(max(n, 1), 4),
            "watermark": false,
        ]
        if let dsSize { parameters["size"] = dsSize }

        let body: [String: Any] = [
            "model": modelName,
            "input": [
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["text": prompt]
                        ]
                    ]
                ]
            ],
            "parameters": parameters,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        APIRequestBuilder.applyCommonHeaders(to: &request)
        APIRequestBuilder.applyBearerAuth(to: &request, apiKey: provider.apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        do {
            try APIRequestBuilder.validate(data: data, response: response)
        } catch let error as APIRequestError {
            throw ImageGenerationError.apiError(
                statusCode: error.statusCode ?? 0,
                message: error.messageBody ?? "Unknown error"
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let taskId = output["task_id"] as? String else {
            // Check for error response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["code"] as? String {
                let message = json["message"] as? String ?? code
                throw ImageGenerationError.apiError(statusCode: 0, message: message)
            }
            throw ImageGenerationError.apiError(statusCode: 0, message: "No task_id in DashScope response")
        }

        return taskId
    }

    /// Poll DashScope task until completion, returning image URLs.
    private func dashScopePollUntilDone(taskId: String) async throws -> [String] {
        let baseURL = provider.endpoint.hasSuffix("/")
            ? String(provider.endpoint.dropLast()) : provider.endpoint
        let urlStr = "\(baseURL)/tasks/\(taskId)"
        guard let url = URL(string: urlStr) else {
            throw ImageGenerationError.invalidURL(urlStr)
        }

        let maxAttempts = 120 // up to ~4 minutes with 2s interval
        for _ in 0..<maxAttempts {
            try Task.checkCancellation()

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            APIRequestBuilder.applyCommonHeaders(to: &request)
            APIRequestBuilder.applyBearerAuth(to: &request, apiKey: provider.apiKey)

            let (data, response) = try await URLSession.shared.data(for: request)

            do {
                try APIRequestBuilder.validate(data: data, response: response)
            } catch let error as APIRequestError {
                throw ImageGenerationError.apiError(
                    statusCode: error.statusCode ?? 0,
                    message: error.messageBody ?? "Unknown error"
                )
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["output"] as? [String: Any] else {
                throw ImageGenerationError.apiError(statusCode: 0, message: "Invalid DashScope poll response")
            }

            let status = (output["task_status"] as? String)?.uppercased() ?? ""

            switch status {
            case "SUCCEEDED":
                return extractDashScopeImageURLs(from: output)
            case "FAILED":
                let reason = output["message"] as? String
                    ?? (json["message"] as? String) ?? "Image generation failed"
                throw ImageGenerationError.apiError(statusCode: 0, message: reason)
            case "CANCELED":
                throw ImageGenerationError.apiError(statusCode: 0, message: "Task was canceled")
            default:
                // PENDING, RUNNING – wait and retry
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        throw ImageGenerationError.apiError(statusCode: 0, message: "DashScope image generation timed out")
    }

    /// Extract image URLs from DashScope task output.
    private func extractDashScopeImageURLs(from output: [String: Any]) -> [String] {
        guard let choices = output["choices"] as? [[String: Any]] else { return [] }
        var urls: [String] = []
        for choice in choices {
            guard let message = choice["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }
            for item in content {
                if let imageURL = item["image"] as? String {
                    urls.append(imageURL)
                }
            }
        }
        return urls
    }

    /// Map standard size strings to DashScope format.
    private func mapDashScopeSize(_ size: String?) -> String? {
        guard let size, !size.isEmpty else { return "2K" }
        let s = size.lowercased()
        // Already in DashScope format
        if s == "1k" || s == "2k" || s == "4k" { return size.uppercased() }
        // WxH pixel format (e.g. "1024x1024") → convert to DashScope "W*H" format
        if s.contains("x") {
            return s.replacingOccurrences(of: "x", with: "*")
        }
        // Already DashScope W*H format
        if s.contains("*") { return size }
        return size
    }

    // MARK: - Helpers

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
