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
    // This should be phased out
    enum Errors: Error {
        case noChoices
        case invalidResponse(String)
        case noApiKey
    }

    public enum APIError: Int, Error {
        case invalidAPIKey = 401
        case rateLimited = 429
        case serverError = 500
        case engineOverload = 503
    }
}

