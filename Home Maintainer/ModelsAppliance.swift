//
//  Appliance.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import SwiftData

@Model
final class Appliance {
    var id: UUID = UUID()
    var name: String = ""
    var type: ApplianceType = ApplianceType.other
    var manufacturer: String = ""
    var modelNumber: String = ""
    var purchaseDate: Date?
    var warrantyExpiration: Date?
    var notes: String = ""
    var room: String = ""
    var createdAt: Date = Date()
    var documents: [ApplianceDocument]?
    @Relationship(deleteRule: .cascade, inverse: \AppliancePhoto.appliance)
    var photos: [AppliancePhoto]?
    @Relationship(deleteRule: .nullify, inverse: \HomeDocument.linkedAppliance)
    var homeDocuments: [HomeDocument]?
    @Relationship(inverse: \MaintenanceTask.appliance)
    var maintenanceTasks: [MaintenanceTask]?
    var home: Home?
    // Scalar mirror of home?.id.uuidString — safe to compare without triggering
    // ModelContext.fulfill on shared-store objects.
    var homeIDString: String? = nil

    init(name: String, type: ApplianceType, manufacturer: String = "", modelNumber: String = "") {
        self.id = UUID()
        self.name = name
        self.type = type
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
        self.notes = ""
        self.createdAt = Date()
        self.documents = []
        self.photos = []
    }

    func addDocument(name: String, data: Data, contentType: String, title: String = "") {
        let document = ApplianceDocument(name: name, data: data, contentType: contentType, title: title)
        if documents == nil {
            documents = []
        }
        documents?.append(document)
    }

    func removeDocument(_ document: ApplianceDocument) {
        documents?.removeAll { $0.id == document.id }
    }

    func addPhoto(data: Data) {
        let photo = AppliancePhoto(imageData: data)
        if photos == nil {
            photos = []
        }
        photos?.append(photo)
    }

    /// The image data for the appliance's primary picture (the earliest one
    /// added), used in place of the type icon wherever the appliance is listed.
    var primaryPhotoData: Data? {
        photos?.sorted(by: { $0.createdAt < $1.createdAt }).first?.imageData
    }
}

/// A picture attached to an appliance. Stored as its own model so images use
/// SwiftData's external storage and can grow independently of the appliance row.
@Model
final class AppliancePhoto {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date = Date()
    var appliance: Appliance?

    init(imageData: Data? = nil) {
        self.id = UUID()
        self.imageData = imageData
        self.createdAt = Date()
    }
}

struct ApplianceDocument: Codable, Identifiable {
    let id: UUID
    let name: String        // actual file name
    var title: String       // user-provided display title (empty = use name)
    let data: Data
    let contentType: String
    let dateAdded: Date

    init(name: String, data: Data, contentType: String, title: String = "") {
        self.id = UUID()
        self.name = name
        self.title = title
        self.data = data
        self.contentType = contentType
        self.dateAdded = Date()
    }

    // Backward-compat: old records lack `title`
    enum CodingKeys: String, CodingKey {
        case id, name, title, data, contentType, dateAdded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        data = try c.decode(Data.self, forKey: .data)
        contentType = try c.decode(String.self, forKey: .contentType)
        dateAdded = try c.decode(Date.self, forKey: .dateAdded)
    }

    var displayName: String { title.isEmpty ? name : title }

    var fileExtension: String {
        if contentType.contains("pdf") {
            return "pdf"
        } else if contentType.contains("word") {
            return "doc"
        } else if contentType.contains("text") {
            return "txt"
        } else {
            return "file"
        }
    }

    var systemImage: String {
        switch fileExtension {
        case "pdf":
            return "doc.fill"
        case "doc":
            return "doc.text.fill"
        case "txt":
            return "doc.plaintext.fill"
        default:
            return "doc.fill"
        }
    }
}

enum ApplianceType: String, Codable, CaseIterable {
    case refrigerator = "Refrigerator"
    case dishwasher = "Dishwasher"
    case washer = "Washer"
    case dryer = "Dryer"
    case oven = "Oven"
    case microwave = "Microwave"
    case hvac = "HVAC System"
    case waterHeater = "Water Heater"
    case garbageDisposal = "Garbage Disposal"
    case other = "Other"

    var systemImage: String {
        switch self {
        case .refrigerator: return "refrigerator"
        case .dishwasher: return "dishwasher"
        case .washer: return "washer"
        case .dryer: return "dryer"
        case .oven: return "oven"
        case .microwave: return "microwave"
        case .hvac: return "fan.ceiling"
        case .waterHeater: return "water.waves"
        case .garbageDisposal: return "trash"
        case .other: return "wrench.and.screwdriver"
        }
    }
}
