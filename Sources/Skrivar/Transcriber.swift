import Foundation

/// Calls ElevenLabs Scribe v2 REST API for speech-to-text transcription.
enum Transcriber {
    private static let globalEndpoint = "https://api.elevenlabs.io/v1/speech-to-text"
    private static let euEndpoint = "https://api.eu.residency.elevenlabs.io/v1/speech-to-text"

    /// Pick the correct endpoint based on the API key.
    private static func endpoint(for apiKey: String) -> String {
        apiKey.contains("residency_eu") ? euEndpoint : globalEndpoint
    }

    /// Transcribe WAV audio data to text.
    static func transcribe(
        wavData: Data,
        apiKey: String,
        languageCode: String = ""
    ) async throws -> String {
        let boundary = UUID().uuidString
        let url = endpoint(for: apiKey)

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        // Build multipart body
        var body = Data()

        // File field
        body.appendMultipart(boundary: boundary, name: "file",
                             filename: "recording.wav",
                             contentType: "audio/wav", data: wavData)

        // model_id field
        body.appendMultipart(boundary: boundary, name: "model_id", value: "scribe_v2")

        // Optional language_code field
        if !languageCode.isEmpty {
            body.appendMultipart(boundary: boundary, name: "language_code",
                                 value: languageCode)
        }

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriberError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriberError.apiError(
                statusCode: httpResponse.statusCode, message: errorBody
            )
        }

        // Parse JSON response
        let result = try JSONDecoder().decode(ScribeResponse.self, from: data)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Models

struct ScribeResponse: Decodable {
    let text: String
    let languageCode: String?
    let languageProbability: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case languageProbability = "language_probability"
    }
}

// MARK: - Errors

enum TranscriberError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let code, let message):
            return "API error \(code): \(message)"
        }
    }
}

// MARK: - Data Multipart Helpers

extension Data {
    mutating func appendMultipart(
        boundary: String, name: String, value: String
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(
        boundary: String, name: String, filename: String,
        contentType: String, data fileData: Data
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
