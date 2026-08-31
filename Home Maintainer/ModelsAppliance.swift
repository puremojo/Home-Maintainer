//
//  ModelsAppliance.swift
//  Home Maintainer
//

import Foundation
import CoreData

// MARK: - Appliance

@objc(Appliance)
public final class Appliance: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged private var typeRaw: String
    @NSManaged public var manufacturer: String
    @NSManaged public var modelNumber: String
    @NSManaged public var purchaseDate: Date?
    @NSManaged public var warrantyExpiration: Date?
    @NSManaged public var notes: String
    @NSManaged public var room: String
    @NSManaged public var createdAt: Date
    @NSManaged public var homeIDString: String?
    @NSManaged private var documentsJSON: String?

    // Relationships
    @NSManaged public var home: Home?
    @NSManaged public var photos: NSSet?
    @NSManaged public var maintenanceTasks: NSSet?
    @NSManaged public var homeDocuments: NSSet?

    // MARK: - Type (enum backed by typeRaw String)

    var type: ApplianceType {
        get { ApplianceType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    // MARK: - Documents (JSON-backed [ApplianceDocument])

    var documents: [ApplianceDocument] {
        get { jsonDecode(from: documentsJSON) ?? [] }
        set { documentsJSON = jsonEncode(newValue) }
    }

    func addDocument(name: String, data: Data, contentType: String, title: String = "") {
        var docs = documents
        docs.append(ApplianceDocument(name: name, data: data, contentType: contentType, title: title))
        documents = docs
    }

    func removeDocument(_ document: ApplianceDocument) {
        documents = documents.filter { $0.id != document.id }
    }

    // MARK: - Photos

    var photoArray: [AppliancePhoto] {
        (photos as? Set<AppliancePhoto>)?.sorted { $0.createdAt < $1.createdAt } ?? []
    }

    func addPhoto(data: Data, in context: NSManagedObjectContext) {
        let photo = AppliancePhoto(context: context)
        photo.id = UUID()
        photo.imageData = data
        photo.createdAt = Date()
        photo.appliance = self
    }

    var primaryPhotoData: Data? {
        photoArray.first?.imageData
    }

    // MARK: - Convenience factory

    @discardableResult
    static func make(
        name: String,
        type: ApplianceType,
        manufacturer: String = "",
        modelNumber: String = "",
        in context: NSManagedObjectContext
    ) -> Appliance {
        let appliance = Appliance(context: context)
        appliance.id = UUID()
        appliance.name = name
        appliance.typeRaw = type.rawValue
        appliance.manufacturer = manufacturer
        appliance.modelNumber = modelNumber
        appliance.notes = ""
        appliance.room = ""
        appliance.createdAt = Date()
        return appliance
    }
}

// MARK: - AppliancePhoto

@objc(AppliancePhoto)
public final class AppliancePhoto: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var imageData: Data?
    @NSManaged public var createdAt: Date
    @NSManaged public var appliance: Appliance?
}

// MARK: - ApplianceDocument (Codable value type)

struct ApplianceDocument: Codable, Identifiable {
    let id: UUID
    let name: String
    var title: String
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
        if contentType.contains("pdf") { return "pdf" }
        if contentType.contains("word") || contentType.contains("doc") { return "doc" }
        if contentType.contains("text") { return "txt" }
        return "file"
    }

    var systemImage: String {
        switch fileExtension {
        case "pdf": return "doc.fill"
        case "doc": return "doc.text.fill"
        case "txt": return "doc.plaintext.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - ApplianceType

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
