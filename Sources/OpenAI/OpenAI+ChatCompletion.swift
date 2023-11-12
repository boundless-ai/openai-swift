import Foundation
import CoreGraphics
import ImageIO
import CoreServices

extension OpenAI {
    public struct Message: Equatable, Codable, Hashable {
        public enum Role: String, Equatable, Codable, Hashable {
            case system
            case user
            case assistant
        }

        public enum ContentBlock: Codable, Equatable, Hashable {
            case text(String)
            case image(CGImage)

            enum CodingKeys: CodingKey {
                case type, text, image_url
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let textValue = try? container.decode(String.self, forKey: .text) {
                    self = .text(textValue)
                } else if let imageDataString = try? container.decode(String.self, forKey: .image_url)
                    .replacingOccurrences(of: "data:image/jpeg;base64,", with: ""),
                          let imageData = Data(base64Encoded: imageDataString),
                          let dataProvider = CGDataProvider(data: imageData as CFData),
                          let image = CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                    self = .image(image)
                } else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode enum."))
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let textValue):
                    try container.encode("text", forKey: .type)
                    try container.encode(textValue, forKey: .text)
                case .image(let cgImage):
                    try container.encode("image_url", forKey: .type)

                    let mutableData = CFDataCreateMutable(nil, 0)!
                    let destination = CGImageDestinationCreateWithData(mutableData, kUTTypeJPEG, 1, nil)!
                    CGImageDestinationAddImage(destination, cgImage, nil)
                    CGImageDestinationFinalize(destination)
                    let jpegData = mutableData as Data

                    try container.encode("data:image/jpeg;base64,\(jpegData.base64EncodedString())", forKey: .image_url)
                }
            }
        }


        public var role: Role
        public var content: [ContentBlock]

        public init(role: Role, content: [ContentBlock]) {
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

        if case let .text(content) = completionResponse.choices[0].message.content[0] {
            return content
        } else {
            throw Errors.noChoices
        }
    }

    // MARK: - Streaming completion

    public func completeChatStreaming(_ completionRequest: ChatCompletionRequest, apiURL url: URL = URL(string: "https://api.openai.com/v1/chat/completions")!) throws -> AsyncThrowingStream<Message, Error> {
        var cr = completionRequest
        cr.stream = true
        let request = try createChatRequest(completionRequest: cr, apiURL: url)

        return AsyncThrowingStream { continuation in
            let src = EventSource(urlRequest: request)

            var message = Message(role: .assistant, content: [.text("")])

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
                    if case let .text(currentContent) = message.content[0],
                       let deltaContent = delta.content {
                       message.content = [.text(currentContent + deltaContent)]
                    }

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

        if let data = request.httpBody,
         let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }

        return request
    }
}
