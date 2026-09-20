//
//  GeminiService.swift
//  Home Maintainer
//
//  Calls Gemini directly from the device via Firebase AI Logic — no custom Cloud Function
//  proxies chat content, so hAIndyman conversations and memory never transit our backend.
//  Quota enforcement stays server-side (checkQuota/reportUsage), but is content-blind: those
//  functions only ever see token counts, never prompts or responses.
//

import Foundation
import UIKit
import CoreData
import FirebaseAI
import FirebaseFunctions
import FirebaseRemoteConfig

@Observable
class GeminiService {
    let isConfigured = true

    private let functions = Functions.functions()

    // Model name is resolved from Remote Config so Google deprecating a model doesn't require
    // an app update — just changing the "gemini_model_name" value in the Firebase console.
    // This constant is only the fallback used before Remote Config has fetched/activated, or if
    // fetching fails (e.g. offline): keep it pointed at the current stable model, not a
    // "-latest" alias — Google explicitly advises against those, since they can silently swap to
    // a preview/experimental release with only 2 weeks' notice.
    private static let fallbackModelName = "gemini-3.8-flash"

    private static let remoteConfig: RemoteConfig = {
        let rc = RemoteConfig.remoteConfig()
        rc.setDefaults(["gemini_model_name": fallbackModelName as NSObject])
        return rc
    }()

    private static func resolvedModelName() async -> String {
        _ = try? await remoteConfig.fetchAndActivate()
        let value = remoteConfig["gemini_model_name"].stringValue
        return value.isEmpty ? fallbackModelName : value
    }

    // A max-output ceiling plus a per-image constant, used only to produce a conservative
    // pre-flight token estimate for checkQuota — the real cost is trued up via reportUsage
    // once the actual response comes back with usageMetadata.
    private static let maxOutputTokenEstimate = 2048
    private static let perImageTokenEstimate = 260
    private static let memorySynthesisTokenEstimate = 800

    private var viewContext: NSManagedObjectContext? { CloudSharingService.shared?.viewContext }

    // MARK: - Public API

    func sendMessage(
        _ message: String,
        images: [Data] = [],
        context: String = "",
        onToolCall: ((ToolCall) async -> String)? = nil
    ) async throws -> String {
        let fullText: String
        if !context.isEmpty {
            fullText = "Context about this home: \(context)\n\n\(message.isEmpty ? "What do you see in this image?" : message)"
        } else {
            fullText = message.isEmpty ? "What do you see in this image?" : message
        }

        var userParts: [any Part] = [TextPart(fullText)]
        for imageData in images {
            let resized = resizeImage(imageData, maxDimension: 1024)
            userParts.append(InlineDataPart(data: resized, mimeType: "image/jpeg"))
        }

        let estimatedTokens = estimateTokens(text: fullText, imageCount: images.count)
            + Self.memorySynthesisTokenEstimate
        try await checkQuota(estimatedTokens: estimatedTokens)

        let memory = currentMemoryText()
        let model = await Self.makeChatModel(memory: memory)
        var history: [ModelContent] = [ModelContent(role: "user", parts: userParts)]
        var totalTokensUsed = 0

        while true {
            let response = try await model.generateContent(history)
            totalTokensUsed += response.usageMetadata?.totalTokenCount ?? 0

            guard let modelTurn = response.candidates.first?.content else {
                throw GeminiError.noContent
            }
            history.append(ModelContent(role: "model", parts: modelTurn.parts))

            let functionCalls = response.functionCalls
            if functionCalls.isEmpty {
                guard let text = response.text, !text.isEmpty else { throw GeminiError.noContent }
                await finishExchange(
                    memory: memory, userMessage: message, assistantResponse: text,
                    tokensSoFar: totalTokensUsed, reservedAmount: estimatedTokens
                )
                return text
            }

            guard let onToolCall else { break }

            var responseParts: [any Part] = []
            for fc in functionCalls {
                let argsString = (try? JSONEncoder().encode(fc.args))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                let toolCall = ToolCall(
                    id: fc.functionId ?? UUID().uuidString,
                    type: "function",
                    function: .init(name: fc.name, arguments: argsString)
                )
                let toolResult = await onToolCall(toolCall)
                responseParts.append(FunctionResponsePart(
                    name: fc.name, response: ["result": .string(toolResult)], functionId: fc.functionId
                ))
            }
            history.append(ModelContent(role: "user", parts: responseParts))
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

        let estimatedTokens = estimateTokens(text: prompt, imageCount: 0)
        try await checkQuota(estimatedTokens: estimatedTokens)

        let model = FirebaseAI.firebaseAI(backend: .googleAI())
            .generativeModel(modelName: await Self.resolvedModelName())
        let response = try await model.generateContent(prompt)
        let tokensUsed = response.usageMetadata?.totalTokenCount ?? 0
        await reportUsage(actualTokens: tokensUsed, reservedAmount: estimatedTokens)

        guard let text = response.text, !text.isEmpty else { throw GeminiError.noContent }

        let jsonText = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonData = jsonText.data(using: .utf8),
           let suggestions = try? JSONDecoder().decode([TaskSuggestion].self, from: jsonData),
           !suggestions.isEmpty {
            return suggestions
        }

        throw GeminiError.noContent
    }

    // MARK: - Model construction

    private static func makeChatModel(memory: String) async -> GenerativeModel {
        let systemInstruction = memory.isEmpty
            ? Self.systemPrompt
            : "\(Self.systemPrompt)\n\nWhat you remember about this user:\n\(memory)"
        return FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
            modelName: await Self.resolvedModelName(),
            tools: [Self.tool],
            systemInstruction: ModelContent(role: "system", parts: [TextPart(systemInstruction)])
        )
    }

    private static let systemPrompt = """
    You are hAIndyman, a helpful AI assistant specialized in home maintenance. You help users with:
    - Creating and managing maintenance tasks
    - Appliance care and troubleshooting
    - Finding local service providers
    - Managing repair projects
    - General home improvement advice
    - Analyzing images of appliances, repairs, or maintenance issues

    When users send images, analyze them and provide helpful advice about what you see.
    When users ask you to create tasks, add appliances, or make changes, use the available tools to actually perform these actions.

    Be concise, practical, and friendly.
    """

    private static let tool: Tool = .functionDeclarations([
        FunctionDeclaration(
            name: "create_maintenance_task",
            description: "Create a new maintenance task in the user's home maintenance app",
            parameters: [
                "name": .string(description: "The name of the task (e.g., 'Change HVAC Filter')"),
                "description": .string(description: "Description of what needs to be done"),
                "frequency": .enumeration(
                    values: ["daily", "weekly", "biweekly", "monthly", "quarterly", "biannually", "annually"],
                    description: "How often the task should be performed"
                ),
            ]
        ),
        FunctionDeclaration(
            name: "create_appliance",
            description: "Add a new appliance to track in the user's home",
            parameters: [
                "name": .string(description: "Name of the appliance (e.g., 'Kitchen Refrigerator')"),
                "type": .enumeration(
                    values: ["refrigerator", "dishwasher", "washer", "dryer", "oven", "microwave",
                             "hvac", "waterHeater", "garbageDisposal", "other"],
                    description: "Type of appliance"
                ),
                "manufacturer": .string(description: "Manufacturer name"),
            ],
            optionalParameters: ["manufacturer"]
        ),
        FunctionDeclaration(
            name: "search_local_providers",
            description: "Search for local service providers near the user (plumbers, electricians, etc.)",
            parameters: [
                "category": .enumeration(
                    values: ["electrician", "plumber", "generalContractor", "roofer", "hvac", "carpenter",
                             "painter", "landscaper", "handyman", "appliance"],
                    description: "Type of service provider to search for"
                ),
            ]
        ),
        FunctionDeclaration(
            name: "save_search_result",
            description: "Save a specific numbered result from the most recent search_local_providers call to the user's saved providers. Use this (not add_service_provider) whenever the user asks to add a result by number from a local search.",
            parameters: [
                "resultNumber": .integer(description: "The result number to save (1, 2, 3… as listed in the search output)"),
            ]
        ),
        FunctionDeclaration(
            name: "add_service_provider",
            description: "Add a service provider by name/details when NOT coming from a local search result. Include ALL known details — phone, address, website, and rating.",
            parameters: [
                "name": .string(description: "Business name"),
                "category": .enumeration(
                    values: ["electrician", "plumber", "generalContractor", "roofer", "hvac", "carpenter",
                             "painter", "landscaper", "handyman", "appliance"],
                    description: "Type of service"
                ),
                "phoneNumber": .string(description: "Phone number"),
                "address": .string(description: "Full street address"),
                "website": .string(description: "Website URL"),
                "rating": .double(description: "Google rating (e.g. 4.7)"),
            ],
            optionalParameters: ["phoneNumber", "address", "website", "rating"]
        ),
        FunctionDeclaration(
            name: "create_repair_project",
            description: "Create a new repair or home improvement project to track",
            parameters: [
                "title": .string(description: "Project title (e.g., 'Bathroom Renovation', 'Roof Repair')"),
                "description": .string(description: "Description of the work needed"),
                "category": .enumeration(
                    values: ["electrician", "plumber", "generalContractor", "roofer", "hvac", "carpenter",
                             "painter", "landscaper", "handyman", "appliance", "other"],
                    description: "Type of work"
                ),
                "priority": .enumeration(values: ["low", "medium", "high"], description: "How urgently the project needs to be done"),
            ],
            optionalParameters: ["priority"]
        ),
    ])

    // MARK: - Memory (client-side synthesis, stored in CoreData → synced via CloudKit's personal zone)

    private func currentMemoryText() -> String {
        guard let ctx = viewContext else { return "" }
        return ctx.performAndWait { UserMemory.fetchOrCreate(in: ctx).content ?? "" }
    }

    private func saveMemory(_ text: String) {
        guard let ctx = viewContext else { return }
        ctx.performAndWait {
            let memory = UserMemory.fetchOrCreate(in: ctx)
            memory.content = text
            memory.updatedAt = Date()
            try? ctx.save()
        }
    }

    /// Regenerates the memory summary and reports final token usage. Runs after the main
    /// response is already available, so a failure here never blocks returning the chat reply.
    private func finishExchange(
        memory: String, userMessage: String, assistantResponse: String,
        tokensSoFar: Int, reservedAmount: Int
    ) async {
        var totalTokens = tokensSoFar
        if let (newMemory, memoryTokens) = await synthesizeMemory(
            current: memory, userMessage: userMessage, assistantResponse: assistantResponse
        ) {
            totalTokens += memoryTokens
            saveMemory(newMemory)
        }
        await reportUsage(actualTokens: totalTokens, reservedAmount: reservedAmount)
    }

    private func synthesizeMemory(
        current: String, userMessage: String, assistantResponse: String
    ) async -> (memory: String, tokensUsed: Int)? {
        guard !userMessage.isEmpty || !assistantResponse.isEmpty else { return nil }

        let prompt = """
        You are a memory extraction assistant. Extract personal facts about the user worth remembering for future home maintenance conversations.

        Current memory: "\(current.isEmpty ? "none" : current)"

        New exchange:
        User: "\(String(userMessage.prefix(400)))"
        Assistant: "\(String(assistantResponse.prefix(400)))"

        Extract any NEW facts about: user's name, home type/age, location, family, appliances owned, recurring issues, or preferences relevant to home maintenance.

        Reply ONLY with a concise updated memory (under 500 characters). If nothing new, reply with the current memory unchanged. No explanations or greetings.
        """

        let model = FirebaseAI.firebaseAI(backend: .googleAI())
            .generativeModel(modelName: await Self.resolvedModelName())
        guard let response = try? await model.generateContent(prompt) else { return nil }
        let tokensUsed = response.usageMetadata?.totalTokenCount ?? 0
        guard let text = response.text else { return (current, tokensUsed) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != current else { return (current, tokensUsed) }
        return (trimmed, tokensUsed)
    }

    // MARK: - Quota (content-blind — these functions only ever see token counts)

    private func estimateTokens(text: String, imageCount: Int) -> Int {
        (text.count / 4) + (imageCount * Self.perImageTokenEstimate) + Self.maxOutputTokenEstimate
    }

    private func checkQuota(estimatedTokens: Int) async throws {
        let callable = functions.httpsCallable("checkQuota")
        do {
            _ = try await callable.call(["estimatedTokens": estimatedTokens])
        } catch let error as NSError {
            if error.domain == "com.firebase.functions" && error.code == 8 {
                throw GeminiError.quotaExceeded
            }
            throw error
        }
    }

    private func reportUsage(actualTokens: Int, reservedAmount: Int) async {
        let callable = functions.httpsCallable("reportUsage")
        _ = try? await callable.call(["actualTokens": actualTokens, "reservedAmount": reservedAmount])
    }

    // MARK: - Image helpers

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
