//
//  ModelsChatConversation.swift
//  Home Maintainer
//

import Foundation
import CoreData
import UIKit

// MARK: - ChatConversation

@objc(ChatConversation)
public final class ChatConversation: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var createdAt: Date
    @NSManaged public var lastMessageAt: Date
    /// Plain UUID attribute (not a relationship) so ChatConversation stays outside
    /// the CloudKit zone share when a Home is shared with other users.
    @NSManaged public var homeID: UUID?
    @NSManaged public var messages: NSSet?

    var messageArray: [ChatMessageData] {
        (messages as? Set<ChatMessageData>)?.sorted { $0.timestamp < $1.timestamp } ?? []
    }

    func addMessage(role: MessageRole, content: String, imageData: [Data] = [], in context: NSManagedObjectContext) {
        let message = ChatMessageData(context: context)
        message.id = UUID()
        message.role = role.rawValue
        message.content = content
        message.timestamp = Date()
        message.conversation = self

        for data in imageData {
            let imageRecord = ChatImageData(context: context)
            imageRecord.id = UUID()
            imageRecord.imageData = data
            imageRecord.message = message
        }

        lastMessageAt = Date()
        if title == "New Chat", role == .user, !content.isEmpty {
            title = String(content.prefix(50))
        }
    }

    @discardableResult
    static func make(title: String = "New Chat", homeID: UUID? = nil, in context: NSManagedObjectContext) -> ChatConversation {
        let conv = ChatConversation(context: context)
        conv.id = UUID()
        conv.title = title
        conv.createdAt = Date()
        conv.lastMessageAt = Date()
        conv.homeID = homeID
        return conv
    }
}

// MARK: - ChatMessageData

@objc(ChatMessageData)
public final class ChatMessageData: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var role: String
    @NSManaged public var content: String
    @NSManaged public var timestamp: Date
    @NSManaged public var conversation: ChatConversation?
    @NSManaged public var imageRecords: NSSet?

    var messageRole: MessageRole {
        MessageRole(rawValue: role) ?? .user
    }

    var imageRecordArray: [ChatImageData] {
        (imageRecords as? Set<ChatImageData>)?.sorted { ($0.message?.timestamp ?? Date()) < ($1.message?.timestamp ?? Date()) } ?? []
    }

    var images: [UIImage] {
        imageRecordArray.compactMap { $0.imageData.flatMap { UIImage(data: $0) } }
    }

    func addImage(_ image: ChatImageData) {
        let mutable = NSMutableSet(set: imageRecords ?? NSSet())
        mutable.add(image)
        imageRecords = mutable
    }
}

// MARK: - ChatImageData

@objc(ChatImageData)
public final class ChatImageData: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var imageData: Data?
    @NSManaged public var message: ChatMessageData?
}

// MARK: - MessageRole

enum MessageRole: String, Codable {
    case user
    case assistant
}
