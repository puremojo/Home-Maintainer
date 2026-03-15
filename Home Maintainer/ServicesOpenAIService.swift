//
//  OpenAIService.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import Security

@Observable
class OpenAIService {
    private let keychainKey = "openai_api_key"
    
    // HARDCODED API KEY - Just for you!
    var apiKey: String? = "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"  // ← Paste your key here
    
    var isConfigured: Bool {
        apiKey != nil && !apiKey!.isEmpty && apiKey != "YOUR_API_KEY_HERE"
    }
    
    init() {
        // No need to load from keychain anymore
    }
    
    // Save API key to Keychain
    func saveAPIKey(_ key: String) {
        apiKey = key
        
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data
        ]
        
        // Delete old key first
        SecItemDelete(query as CFDictionary)
        
        // Add new key
        SecItemAdd(query as CFDictionary, nil)
    }
    
    // Load API key from Keychain
    private func loadAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            apiKey = key
        }
    }
    
    // Delete API key
    func deleteAPIKey() {
        apiKey = nil
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // Send chat message
    func sendMessage(_ message: String, images: [Data] = [], context: String = "", onToolCall: ((ToolCall) async -> String)? = nil) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemMessage = """
        You are a helpful AI assistant specialized in home maintenance. You help users with:
        - Creating and managing maintenance tasks
        - Appliance care and troubleshooting
        - Finding local service providers
        - Managing repair projects
        - General home improvement advice
        - Analyzing images of appliances, repairs, or maintenance issues
        
        When users send images, analyze them and provide helpful advice about what you see.
        When users ask you to create tasks, add appliances, or make changes, use the available tools to actually perform these actions.
        
        Be concise, practical, and friendly.
        \(context.isEmpty ? "" : "\n\nContext about the user's home: \(context)")
        """
        
        // Build user message with optional images
        var userMessageContent: [[String: Any]] = [
            ["type": "text", "text": message]
        ]
        
        // Add images if provided
        for imageData in images {
            let base64Image = imageData.base64EncodedString()
            userMessageContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64Image)"
                ]
            ])
        }
        
        var body: [String: Any] = [
            "model": images.isEmpty ? "gpt-4o-mini" : "gpt-4o", // Use gpt-4o for vision
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": userMessageContent]
            ],
            "temperature": 0.7,
            "max_tokens": 1000 // More tokens for image analysis
        ]
        
        // Add function definitions if tool calling is enabled
        if onToolCall != nil {
            body["tools"] = [
                [
                    "type": "function",
                    "function": [
                        "name": "create_maintenance_task",
                        "description": "Create a new maintenance task in the user's home maintenance app",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "name": [
                                    "type": "string",
                                    "description": "The name of the task (e.g., 'Change HVAC Filter')"
                                ],
                                "description": [
                                    "type": "string",
                                    "description": "Description of what needs to be done"
                                ],
                                "frequency": [
                                    "type": "string",
                                    "enum": ["daily", "weekly", "biweekly", "monthly", "quarterly", "biannually", "annually"],
                                    "description": "How often the task should be performed"
                                ]
                            ],
                            "required": ["name", "description", "frequency"]
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "create_appliance",
                        "description": "Add a new appliance to track in the user's home",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "name": [
                                    "type": "string",
                                    "description": "Name of the appliance (e.g., 'Kitchen Refrigerator')"
                                ],
                                "type": [
                                    "type": "string",
                                    "enum": ["refrigerator", "dishwasher", "washer", "dryer", "oven", "microwave", "hvac", "waterHeater", "garbageDisposal", "other"],
                                    "description": "Type of appliance"
                                ],
                                "manufacturer": [
                                    "type": "string",
                                    "description": "Manufacturer name (optional)"
                                ]
                            ],
                            "required": ["name", "type"]
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "search_local_providers",
                        "description": "Search for local service providers near the user (plumbers, electricians, etc.)",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "category": [
                                    "type": "string",
                                    "enum": ["electrician", "plumber", "generalContractor", "roofer", "hvac", "carpenter", "painter", "landscaper", "handyman", "appliance"],
                                    "description": "Type of service provider to search for"
                                ]
                            ],
                            "required": ["category"]
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "add_service_provider",
                        "description": "Add a service provider to the user's saved list",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "name": [
                                    "type": "string",
                                    "description": "Business name"
                                ],
                                "category": [
                                    "type": "string",
                                    "enum": ["electrician", "plumber", "generalContractor", "roofer", "hvac", "carpenter", "painter", "landscaper", "handyman", "appliance"],
                                    "description": "Type of service"
                                ],
                                "phoneNumber": [
                                    "type": "string",
                                    "description": "Phone number (optional)"
                                ],
                                "address": [
                                    "type": "string",
                                    "description": "Address (optional)"
                                ]
                            ],
                            "required": ["name", "category"]
                        ]
                    ]
                ]
            ]
            body["tool_choice"] = "auto"
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let errorData = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(errorData.error.message)
            }
            throw OpenAIError.invalidResponse
        }
        
        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        
        guard let choice = chatResponse.choices.first else {
            throw OpenAIError.noContent
        }
        
        // Check if AI wants to call a function
        if let toolCalls = choice.message.toolCalls, !toolCalls.isEmpty, let onToolCall = onToolCall {
            var results: [String] = []
            
            for toolCall in toolCalls {
                let result = await onToolCall(toolCall)
                results.append(result)
            }
            
            // Return confirmation message
            return results.joined(separator: "\n")
        }
        
        // Regular text response
        guard let content = choice.message.content else {
            throw OpenAIError.noContent
        }
        
        return content
    }
}

// MARK: - Models

struct OpenAIChatResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String?
        let toolCalls: [ToolCall]?
        
        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }
}

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: FunctionCall
    
    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }
}

struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
    }
}

enum OpenAIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case noContent
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your OpenAI API key in settings."
        case .invalidResponse:
            return "Invalid response from OpenAI"
        case .apiError(let message):
            return message
        case .noContent:
            return "No response content received"
        }
    }
}
