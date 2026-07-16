//
//  ProductLink.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import SwiftData

/// A named link to a product (e.g. "Shock": https://...) that can be attached
/// to a maintenance task or a repair project.
@Model
final class ProductLink {
    var id: UUID = UUID()
    var name: String = ""
    var urlString: String = ""
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date = Date()

    // Back-references. A product link belongs to either a task or a project.
    var task: MaintenanceTask?
    var project: RepairProject?

    init(name: String = "", urlString: String = "", imageData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.urlString = urlString
        self.imageData = imageData
        self.createdAt = Date()
    }

    /// A best-effort URL built from the entered string, adding a scheme if missing.
    var url: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }
}
