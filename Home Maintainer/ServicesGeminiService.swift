//
//  GeminiService.swift
//  Home Maintainer
//

import Foundation
import UIKit
import FirebaseFunctions

@Observable
class GeminiService {
    let isConfigured = true

    private let functions = Functions.functions()

    func sendMessage(
        _ message: String,
        images: [Data] = [],
        context: String = "",
        onToolCall: ((ToolCall) async -> String)? = nil
    ) async throws -> String {
        var userParts: [[String: Any]] = []

        let fullText: String
        if !context.isEmpty {
            fullText = "Context about this home: \(context)\n\n\(message.isEmpty ? "What do you see in this image?" : message)"
        } else {
            fullText = message.isEmpty ? "What do you see in this image?" : message
        }
        userParts.append(["text": fullText])

        for imageData in images {
            let resized = resizeImage(imageData, maxDimension: 1024)
            userParts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": resized.base64EncodedString()
                ]
            ])
        }

        // History in Gemini REST API content format — stays on client for multi-turn function calls
        var history: [[String: Any]] = [["role": "user", "parts": userParts]]

        while true {
            let callable = functions.httpsCallable("geminiChat")
            let result: HTTPSCallableResult

            do {
                result = try await callable.call(["contents": history])
            } catch let error as NSError {
                if error.domain == "com.firebase.functions" && error.code == 8 {
                    throw GeminiError.quotaExceeded
                }
                throw error
            }

            guard
                let data = result.data as? [String: Any],
                let candidates = data["candidates"] as? [[String: Any]],
                let firstCandidate = candidates.first,
                let content = firstCandidate["content"] as? [String: Any],
                let parts = content["parts"] as? [[String: Any]]
            else {
                throw GeminiError.noContent
            }

            history.append(["role": "model", "parts": parts])

            let functionCalls: [(name: String, args: [String: Any])] = parts.compactMap { part in
                guard let fc = part["functionCall"] as? [String: Any],
                      let name = fc["name"] as? String,
                      let args = fc["args"] as? [String: Any]
                else { return nil }
                return (name: name, args: args)
            }

            if functionCalls.isEmpty {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                guard !text.isEmpty else { throw GeminiError.noContent }
                return text
            }

            guard let onToolCall else { break }

            var responseParts: [[String: Any]] = []
            for fc in functionCalls {
                let argsString = (try? JSONSerialization.data(withJSONObject: fc.args))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

                let toolCall = ToolCall(
                    id: UUID().uuidString,
                    type: "function",
                    function: .init(name: fc.name, arguments: argsString)
                )
                let toolResult = await onToolCall(toolCall)

                responseParts.append([
                    "functionResponse": [
                        "name": fc.name,
                        "response": ["result": toolResult]
                    ]
                ])
            }

            history.append(["role": "user", "parts": responseParts])
        }

        throw GeminiError.noContent
    }

    func suggestMaintenanceTasks(for appliance: Appliance) async throws -> [TaskSuggestion] {
        var descParts: [String] = []
        if !appliance.manufacturer.isEmpty { descParts.append(appliance.manufacturer) }
        descParts.append(appliance.type.rawValue)
        if !appliance.name.isEmpty { descParts.append("'\(appliance.name)'") }
        let applianceDesc = descParts.joined(separator: " ")

        let prompt = """
        Output a JSON array of routine maintenance recommendations for a \(applianceDesc). \
        Do NOT call any tools or functions — output raw JSON text only.

        The array must have 4–6 items. Each item must have exactly these keys:
        - "name": string
        - "description": string
        - "frequency": one of "daily","weekly","biweekly","monthly","quarterly","biannually","annually"
        - "products": array of {"name":string,"searchQuery":string} or empty array []

        Respond with only the JSON array, no markdown, no code fences, no explanation.
        """

        let contents: [[String: Any]] = [
            ["role": "user", "parts": [["text": prompt]]]
        ]

        let callable = functions.httpsCallable("geminiChat")
        let result: HTTPSCallableResult

        do {
            result = try await callable.call(["contents": contents])
        } catch let error as NSError {
            if error.domain == "com.firebase.functions" && error.code == 8 {
                throw GeminiError.quotaExceeded
            }
            throw error
        }

        guard
            let data = result.data as? [String: Any],
            let candidates = data["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let responseParts = content["parts"] as? [[String: Any]]
        else { throw GeminiError.noContent }

        let text = responseParts.compactMap { $0["text"] as? String }.joined()

        if !text.isEmpty {
            let jsonText = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let jsonData = jsonText.data(using: .utf8),
               let suggestions = try? JSONDecoder().decode([TaskSuggestion].self, from: jsonData),
               !suggestions.isEmpty {
                return suggestions
            }
        }

        // Fallback: model called tools instead of returning JSON — extract task args directly
        var suggestions: [TaskSuggestion] = []
        for part in responseParts {
            guard let fc = part["functionCall"] as? [String: Any],
                  let fcName = fc["name"] as? String,
                  fcName == "create_maintenance_task",
                  let args = fc["args"] as? [String: Any],
                  let taskName = args["name"] as? String,
                  let frequency = args["frequency"] as? String
            else { continue }
            let description = args["description"] as? String ?? ""
            suggestions.append(TaskSuggestion(name: taskName, description: description, frequency: frequency, products: []))
        }

        guard !suggestions.isEmpty else { throw GeminiError.noContent }
        return suggestions
    }

    private func resizeImage(_ data: Data, maxDimension: CGFloat) -> Data {
        guard let image = UIImage(data: data),
              max(image.size.width, image.size.height) > maxDimension else {
            return data
        }
        let scale = maxDimension / max(image.size.width, image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.7) ?? data
    }
}

// MARK: - Task Suggestion Types

struct TaskSuggestion: Codable, Identifiable {
    var id = UUID()
    let name: String
    let description: String
    let frequency: String
    let products: [SuggestedProduct]

    struct SuggestedProduct: Codable {
        let name: String
        let searchQuery: String

        private enum CodingKeys: String, CodingKey {
            case name, searchQuery, search_query
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            searchQuery = (try? c.decode(String.self, forKey: .searchQuery))
                ?? (try? c.decode(String.self, forKey: .search_query))
                ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(searchQuery, forKey: .searchQuery)
        }
    }

    init(name: String, description: String, frequency: String, products: [SuggestedProduct] = []) {
        self.name = name
        self.description = description
        self.frequency = frequency
        self.products = products
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, frequency, products
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        frequency = try c.decode(String.self, forKey: .frequency)
        products = (try? c.decode([SuggestedProduct].self, forKey: .products)) ?? []
    }
}

// MARK: - Shared Types

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: FunctionCall

    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }
}

enum GeminiError: LocalizedError {
    case notConfigured
    case noContent
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "hAIndyman is not configured. Please ensure Firebase is set up correctly."
        case .noContent:
            return "No response received. Please try again."
        case .quotaExceeded:
            return "Monthly message limit reached. Upgrade your plan to continue using hAIndyman."
        }
    }
}
