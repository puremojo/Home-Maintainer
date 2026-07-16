//
//  ChatConversation.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import SwiftData
import UIKit

@Model
final class ChatConversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var lastMessageAt: Date
    @Relationship(deleteRule: .cascade) var messages: [ChatMessageData]?
    /// UUID of the associated Home. Plain attribute (not a relationship) so this model
    /// stays outside the CloudKit zone share when a Home is shared with other users.
    var homeID: UUID?

    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.lastMessageAt = Date()
        self.messages = []
    }
    
    func addMessage(role: MessageRole, content: String, imageData: [Data] = []) {
        let message = ChatMessageData(role: role, content: content)
        
        // Save images separately
        for data in imageData {
            let imageRecord = ChatImageData(imageData: data)
            message.addImage(imageRecord)
        }
        
        if messages == nil {
            messages = []
        }
        messages?.append(message)
        lastMessageAt = Date()
        
        // Auto-generate title from first user message if still "New Chat"
        if title == "New Chat", role == .user, !content.isEmpty {
            title = String(content.prefix(50))
        }
    }
}

@Model
final class ChatMessageData {
    var id: UUID
    var role: String // Store as String instead of enum for SwiftData
    var content: String
    @Relationship(deleteRule: .cascade) var imageRecords: [ChatImageData]?
    var timestamp: Date
    var conversation: ChatConversation?
    
    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role.rawValue
        self.content = content
        self.timestamp = Date()
        self.imageRecords = []
    }
    
    func addImage(_ image: ChatImageData) {
        if imageRecords == nil {
            imageRecords = []
        }
        imageRecords?.append(image)
    }
    
    // Convert to UIImage array for display
    var images: [UIImage] {
        (imageRecords ?? []).compactMap { UIImage(data: $0.imageData) }
    }
    
    var messageRole: MessageRole {
        MessageRole(rawValue: role) ?? .user
    }
}

@Model
final class ChatImageData {
    var id: UUID
    @Attribute(.externalStorage) var imageData: Data
    var message: ChatMessageData?
    
    init(imageData: Data) {
        self.id = UUID()
        self.imageData = imageData
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
}
