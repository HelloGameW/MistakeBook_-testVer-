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
              configuration.timeoutSeconds > 0 else { throw AppError(code: .invalidConfiguration) }
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
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

struct OpenAICompatibleClient: Sendable {
    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
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
            "temperature": 0.1
        ]
        let encoded = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = encoded
        let data = try await NetworkSupport.checkedData(for: request)
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let text = response.choices.first?.message.content,
              let json = text.data(using: .utf8) else { throw AppError(code: .invalidModelOutput) }
        return json
    }
}
