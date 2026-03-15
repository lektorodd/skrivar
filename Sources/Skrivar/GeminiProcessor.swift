import Foundation
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "Gemini")

/// Token usage from a Gemini API call.
struct GeminiUsage {
    let promptTokens: Int
    let candidateTokens: Int
    let totalTokens: Int
}

/// Post-processes transcribed text using Gemini Flash API.
enum GeminiProcessor {
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    /// Polish/translate transcribed text using Gemini Flash.
    /// Returns the polished text and token usage.
    static func process(
        text: String,
        apiKey: String,
        targetLanguage: String
    ) async throws -> (text: String, usage: GeminiUsage) {
        guard !text.isEmpty else { return (text, GeminiUsage(promptTokens: 0, candidateTokens: 0, totalTokens: 0)) }

        let prompt = buildPrompt(text: text, targetLanguage: targetLanguage)

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 1024,
            ]
        ]

        let url = "\(endpoint)?key=\(apiKey)"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            logger.error("Gemini API error \(httpResponse.statusCode): \(errorBody)")
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let resultText = parts.first?["text"] as? String
        else {
            throw GeminiError.parseError
        }

        // Parse token usage
        var usage = GeminiUsage(promptTokens: 0, candidateTokens: 0, totalTokens: 0)
        if let usageMeta = json["usageMetadata"] as? [String: Any] {
            usage = GeminiUsage(
                promptTokens: usageMeta["promptTokenCount"] as? Int ?? 0,
                candidateTokens: usageMeta["candidatesTokenCount"] as? Int ?? 0,
                totalTokens: usageMeta["totalTokenCount"] as? Int ?? 0
            )
        }

        let cleaned = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Gemini processed: \(text.count)→\(cleaned.count) chars, \(usage.totalTokens) tokens")
        return (cleaned, usage)
    }

    /// targetLanguage is a plain name like "nynorsk", "bokmål", "english", or "same"
    private static func buildPrompt(text: String, targetLanguage: String) -> String {
        if targetLanguage == "same" {
            return """
            Du er ein språkassistent. Teksten under er transkribering frå tale. \
            Rett opp skrivefeil og gjer teksten meir lesbar. \
            Ikkje endre språket eller meininga. Berre gje den retta teksten, utan forklaring.

            Tekst: \(text)
            """
        }

        if targetLanguage == "nynorsk" {
            return """
            Du er ein nynorskekspert. Teksten under er transkribert frå tale og er sannsynlegvis på bokmål. \
            Du SKAL omsetje teksten til korrekt nynorsk. \
            Døme på endringar: «er»→«er» (men verbbøying: «snakker»→«snakkar»), \
            «jeg»→«eg», «ikke»→«ikkje», «hva»→«kva», «noe»→«noko», \
            «det»→«det», «har»→«har», «kan»→«kan», «vil»→«vil», \
            «dette»→«dette», «hvis»→«dersom», «også»→«òg», \
            «-ene»→«-ane/-ene», «-tion»→«-sjon». \
            Bruk korrekt nynorsk grammatikk og ordformer gjennomgåande. \
            Gje BERRE den omsette teksten, utan forklaring eller kommentarar.

            Tekst: \(text)
            """
        }

        return """
        Du er ein språkassistent. Teksten under er transkribering frå tale. \
        Omset teksten til korrekt \(targetLanguage). \
        Ikkje endre meininga. Gje BERRE den omsette teksten, utan forklaring eller ekstra tekst.

        Tekst: \(text)
        """
    }

    // MARK: - Long-form synthesis (Raw Dictation "Flash")

    /// Synthesize multiple raw dictation chunks into coherent, well-structured text.
    static func synthesize(
        chunks: [String],
        apiKey: String,
        targetLanguage: String
    ) async throws -> (text: String, usage: GeminiUsage) {
        guard !chunks.isEmpty else {
            return ("", GeminiUsage(promptTokens: 0, candidateTokens: 0, totalTokens: 0))
        }

        let prompt = buildSynthesisPrompt(chunks: chunks, targetLanguage: targetLanguage)

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 8192,
            ]
        ]

        let url = "\(endpoint)?key=\(apiKey)"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120  // Longer timeout for big synthesis

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            logger.error("Gemini synthesis error \(httpResponse.statusCode): \(errorBody)")
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let resultText = parts.first?["text"] as? String
        else {
            throw GeminiError.parseError
        }

        var usage = GeminiUsage(promptTokens: 0, candidateTokens: 0, totalTokens: 0)
        if let usageMeta = json["usageMetadata"] as? [String: Any] {
            usage = GeminiUsage(
                promptTokens: usageMeta["promptTokenCount"] as? Int ?? 0,
                candidateTokens: usageMeta["candidatesTokenCount"] as? Int ?? 0,
                totalTokens: usageMeta["totalTokenCount"] as? Int ?? 0
            )
        }

        let cleaned = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Gemini synthesis: \(chunks.count) chunks → \(cleaned.count) chars, \(usage.totalTokens) tokens")
        return (cleaned, usage)
    }

    private static func buildSynthesisPrompt(chunks: [String], targetLanguage: String) -> String {
        let numberedChunks = chunks.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n\n")

        let languageDirective: String
        if targetLanguage == "same" {
            languageDirective = "Skriv på same språk som talar brukar."
        } else if targetLanguage == "nynorsk" {
            languageDirective = "Skriv på korrekt nynorsk. Bruk nynorske ordformer og grammatikk gjennomgåande."
        } else {
            languageDirective = "Skriv på korrekt \(targetLanguage)."
        }

        return """
        Du er ein skriveassistent. Teksten under er ei rekkje med rå taleopptak frå ei \
        idémyldring- eller tenkjeøkt. Talaren tenkjer høgt — rekn med ufullstendige \
        setningar, rettingar, gjentakingar og lause tankar.

        Oppgåva di:
        1. Syntetiser dette til samanhengande, velstrukturert tekst som fangar ALLE ideane.
        2. Organiser logisk med avsnitt. Bruk overskrifter om det er naturleg.
        3. Fjern gjentakingar og fyllord, men ikkje mist nokon idé.
        4. \(languageDirective)
        5. Gje BERRE den syntetiserte teksten, utan forklaring eller kommentarar.

        Rå opptak:

        \(numberedChunks)
        """
    }
}

enum GeminiError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid Gemini response"
        case .apiError(let code, let msg): return "Gemini error \(code): \(msg)"
        case .parseError: return "Could not parse Gemini response"
        }
    }
}
