//
//  ProductLink.swift
//  Home Maintainer
//

import Foundation
import CoreData

/// A named link to a product (e.g. "Shock": https://...) that can be attached
/// to a maintenance task or a repair project.
@objc(ProductLink)
public final class ProductLink: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var urlString: String
    @NSManaged public var imageData: Data?
    @NSManaged public var createdAt: Date
    @NSManaged public var task: MaintenanceTask?
    @NSManaged public var project: RepairProject?

    /// A best-effort URL built from the entered string, adding a scheme if missing.
    var url: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://\(trimmed)")
    }

    @discardableResult
    static func make(name: String = "", urlString: String = "", imageData: Data? = nil, in context: NSManagedObjectContext) -> ProductLink {
        let link = ProductLink(context: context)
        link.id = UUID()
        link.name = name
        link.urlString = urlString
        link.imageData = imageData
        link.createdAt = Date()
        return link
    }
}
