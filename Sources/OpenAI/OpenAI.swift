import Foundation

public struct OpenAI {
    var apiKey: String
    var orgId: String?

    public init(apiKey: String, orgId: String? = nil) {
        self.apiKey = apiKey
        self.orgId = orgId
    }
}

extension OpenAI {
    enum Errors: Error {
        case noChoices
        case invalidResponse(String)
        case noApiKey
    }
}

