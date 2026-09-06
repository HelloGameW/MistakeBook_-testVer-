import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Contracts

enum NetworkSupport {
    static func endpointURL(_ configuration: ModelAPIConfiguration) throws -> URL {
        let base = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: base),
              let scheme = components.scheme?.lowercased(), scheme == "https",
              components.host != nil, components.user == nil, components.password == nil else { throw AppError(code: .invalidConfiguration) }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = configuration.endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpoint].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url, !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              configuration.timeoutSeconds.isFinite, configuration.timeoutSeconds > 0 else { throw AppError(code: .invalidConfiguration) }
        return url
    }

    static func checkedData(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw AppError(code: .networkUnavailable, isRetryable: true) }
            switch http.statusCode {
            case 200..<300: return data
            case 401, 403: throw AppError(code: .authenticationFailed)
            case 429: throw AppError(code: .rateLimited, isRetryable: true)
            case 400..<500: throw AppError(code: .invalidConfiguration)
            default: throw AppError(code: .networkUnavailable, isRetryable: true)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            default: throw AppError(code: .networkUnavailable, isRetryable: true)
            }
        } catch {
            throw AppError(code: .networkUnavailable, isRetryable: true)
        }
    }

    static func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        // Form decoders interpret a literal plus as a space, corrupting base64 images.
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
}

struct OpenAICompatibleClient: Sendable {
    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: MessageContent?
                let reasoningContent: String?

                enum CodingKeys: String, CodingKey { case content, reasoningContent = "reasoning_content" }
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private enum MessageContent: Decodable {
        case text(String)
        case parts([Part])

        struct Part: Decodable {
            let text: String?
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .text(value)
            } else {
                self = .parts(try container.decode([Part].self))
            }
        }

        var text: String {
            switch self {
            case .text(let value): value
            case .parts(let values): values.compactMap(\.text).joined()
            }
        }
    }

    func requestJSON(prompt: String, imageDataURI: String? = nil,
                     configuration: ModelAPIConfiguration, apiKey: String) async throws -> Data {
        let endpoint = try NetworkSupport.endpointURL(configuration)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AppError(code: .authenticationFailed) }

        let content: Any
        if let imageDataURI {
            content = [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": imageDataURI]]
            ]
        } else {
            content = prompt
        }
        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [["role": "user", "content": content]],
            "response_format": ["type": "json_object"],
            "max_tokens": 8192,
            "temperature": 0.1
        ]
        var requestBody = body
        if configuration.isDeepSeek {
            // DeepSeek V4 enables thinking by default. Structured extraction is
            // more reliable and cheaper with thinking explicitly disabled.
            requestBody["thinking"] = ["type": "disabled"]
        }
        let encoded = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = encoded
        let data = try await NetworkSupport.checkedData(for: request)
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let message = response.choices.first?.message else {
            throw AppError(code: .invalidModelOutput)
        }
        let contentText = message.content?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (contentText?.isEmpty == false ? contentText : nil) ?? message.reasoningContent
        guard let text, let json = Self.extractJSONObject(from: text) else {
            throw AppError(code: .invalidModelOutput)
        }
        return json
    }

    static func extractJSONObject(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        let withoutFence = trimmed
            .replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = withoutFence.firstIndex(of: "{"),
              let end = withoutFence.lastIndex(of: "}"), start <= end else { return nil }
        let data = Data(withoutFence[start...end].utf8)
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
        return data
    }
}
