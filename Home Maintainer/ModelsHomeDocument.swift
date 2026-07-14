//
//  ModelsHomeDocument.swift
//  Home Maintainer
//

import Foundation
import SwiftData

@Model
final class DocumentSection {
    var id: UUID
    var name: String
    var sortOrder: Int
    var home: Home?
    @Relationship(deleteRule: .cascade, inverse: \HomeDocument.section)
    var documents: [HomeDocument]?
    var createdAt: Date

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.documents = []
    }
}

@Model
final class HomeDocument {
    var id: UUID
    var title: String
    @Attribute(.externalStorage) var attachmentData: Data?
    var attachmentName: String?
    var attachmentContentType: String?
    var linkedTaskIDs: [UUID]
    var linkedProjectIDs: [UUID] = []
    var linkedAppliance: Appliance?
    var section: DocumentSection?
    var home: Home?
    var createdAt: Date

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.linkedTaskIDs = []
        self.linkedProjectIDs = []
        self.createdAt = Date()
    }

    var fileExtension: String {
        guard let contentType = attachmentContentType else { return "file" }
        if contentType.contains("pdf") { return "pdf" }
        if contentType.contains("word") || contentType.contains("doc") { return "doc" }
        if contentType.contains("text") { return "txt" }
        return contentType.isEmpty ? "file" : String(contentType.prefix(4))
    }

    var systemImage: String {
        switch fileExtension {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "txt": return "doc.plaintext.fill"
        default: return "doc.fill"
        }
    }
}
