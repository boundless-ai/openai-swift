import Foundation

extension OpenAI {
    public struct Message: Equatable, Codable, Hashable {
        public enum Role: String, Equatable, Codable, Hashable {
            case system
            case user
            case assistant
        }

        public var role: Role
        public var content: String

        public init(role: Role, content: String) {
            self.role = role
            self.content = content
        }
    }

    public struct ChatCompletionRequest: Codable {
        var messages: [Message]
        var model: String
        var max_tokens: Int = 1500
        var temperature: Double = 0.2
        var stream = false
        var stop: [String]?

        public init(messages: [Message], model: String = "gpt-3.5-turbo", max_tokens: Int = 1500, temperature: Double = 0.2, stop: [String]? = nil) {
            self.messages = messages
            self.model = model
            self.max_tokens = max_tokens
            self.temperature = temperature
            self.stop = stop
        }
    }

    // MARK: - Plain completion

    struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            var message: Message
        }
        var choices: [Choice]
    }

    public func completeChat(_ completionRequest: ChatCompletionRequest, apiURL url: URL = URL(string: "https://api.openai.com/v1/chat/completions")!) async throws -> String {
        let request = try createChatRequest(completionRequest: completionRequest, apiURL: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw Errors.invalidResponse(String(data: data, encoding: .utf8) ?? "<failed to decode response>")
        }
        let completionResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard completionResponse.choices.count > 0 else {
            throw Errors.noChoices
        }
        return completionResponse.choices[0].message.content
    }

    // MARK: - Streaming completion

    public func completeChatStreaming(_ completionRequest: ChatCompletionRequest, apiURL url: URL = URL(string: "https://api.openai.com/v1/chat/completions")!) throws -> AsyncThrowingStream<Message, Error> {
        var cr = completionRequest
        cr.stream = true
        let request = try createChatRequest(completionRequest: cr, apiURL: url)

        return AsyncThrowingStream { continuation in
            let src = EventSource(urlRequest: request)

            var message = Message(role: .assistant, content: "")

            src.onComplete { statusCode, reconnect, error in
                if let statusCode {
                    if let apiError = APIError(rawValue: statusCode) {
                        continuation.finish(throwing: apiError)
                    }

                    if statusCode != 200 {
                        continuation.finish(throwing: NSError(domain: "unknown error", code: statusCode))
                    }
                }

                continuation.finish(throwing: error)
            }

            src.onMessage { id, event, data in
                guard let data, data != "[DONE]" else { return }

                do {
                    let decoder = JSONDecoder()
                    let decoded = try decoder.decode(ChatCompletionStreamingResponse.self, from: Data(data.utf8))

                    guard let delta = decoded.choices.first?.delta else {
                        continuation.yield(with: .failure(Errors.noChoices))
                        return
                    }

                    message.role = delta.role ?? message.role
                    message.content += delta.content ?? ""
                    continuation.yield(message)
                } catch let error {
                    continuation.yield(with: .failure(error))
                }
            }

            src.connect()
        }
    }

    private struct ChatCompletionStreamingResponse: Codable {
        struct Choice: Codable {
            struct MessageDelta: Codable {
                var role: Message.Role?
                var content: String?
            }
            var delta: MessageDelta
        }
        var choices: [Choice]
    }

    private func decodeChatStreamingResponse(jsonStr: String) -> String? {
        guard let json = try? JSONDecoder().decode(ChatCompletionStreamingResponse.self, from: Data(jsonStr.utf8)) else {
            return nil
        }
        return json.choices.first?.delta.content
    }
    
    private func createChatRequest(completionRequest: ChatCompletionRequest, apiURL url: URL) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let orgId {
            request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
        }
        request.httpBody = try JSONEncoder().encode(completionRequest)
        return request
    }
}
