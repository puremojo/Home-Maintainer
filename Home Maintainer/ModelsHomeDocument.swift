//
//  ModelsHomeDocument.swift
//  Home Maintainer
//

import Foundation
import CoreData

// MARK: - DocumentSection

@objc(DocumentSection)
public final class DocumentSection: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var sortOrder: Int32
    @NSManaged public var homeIDString: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var home: Home?
    @NSManaged public var documents: NSSet?

    var documentArray: [HomeDocument] {
        (documents as? Set<HomeDocument>)?.sorted { $0.createdAt < $1.createdAt } ?? []
    }

    @discardableResult
    static func make(name: String, sortOrder: Int = 0, in context: NSManagedObjectContext) -> DocumentSection {
        let section = DocumentSection(context: context)
        section.id = UUID()
        section.name = name
        section.sortOrder = Int32(sortOrder)
        section.createdAt = Date()
        return section
    }
}

// MARK: - HomeDocument

@objc(HomeDocument)
public final class HomeDocument: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var attachmentData: Data?
    @NSManaged public var attachmentName: String?
    @NSManaged public var attachmentContentType: String?
    @NSManaged private var linkedTaskIDsJSON: String?
    @NSManaged private var linkedProjectIDsJSON: String?
    @NSManaged public var homeIDString: String?
    @NSManaged public var sectionIDString: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var linkedAppliance: Appliance?
    @NSManaged public var section: DocumentSection?
    @NSManaged public var home: Home?

    // MARK: - JSON-backed UUID arrays

    var linkedTaskIDs: [UUID] {
        get { jsonDecode(from: linkedTaskIDsJSON) ?? [] }
        set { linkedTaskIDsJSON = jsonEncode(newValue) }
    }

    var linkedProjectIDs: [UUID] {
        get { jsonDecode(from: linkedProjectIDsJSON) ?? [] }
        set { linkedProjectIDsJSON = jsonEncode(newValue) }
    }

    // MARK: - Computed

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

    // MARK: - Convenience factory

    @discardableResult
    static func make(title: String, in context: NSManagedObjectContext) -> HomeDocument {
        let doc = HomeDocument(context: context)
        doc.id = UUID()
        doc.title = title
        doc.createdAt = Date()
        return doc
    }
}
