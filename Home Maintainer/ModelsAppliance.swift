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
    var id: UUID
    var name: String
    var type: ApplianceType
    var manufacturer: String
    var modelNumber: String
    var purchaseDate: Date?
    var warrantyExpiration: Date?
    var notes: String
    var createdAt: Date
    var documents: [ApplianceDocument]?
    
    init(name: String, type: ApplianceType, manufacturer: String = "", modelNumber: String = "") {
        self.id = UUID()
        self.name = name
        self.type = type
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
        self.notes = ""
        self.createdAt = Date()
        self.documents = []
    }
    
    func addDocument(name: String, data: Data, contentType: String) {
        let document = ApplianceDocument(name: name, data: data, contentType: contentType)
        if documents == nil {
            documents = []
        }
        documents?.append(document)
    }
    
    func removeDocument(_ document: ApplianceDocument) {
        documents?.removeAll { $0.id == document.id }
    }
}

struct ApplianceDocument: Codable, Identifiable {
    let id: UUID
    let name: String
    let data: Data
    let contentType: String
    let dateAdded: Date
    
    init(name: String, data: Data, contentType: String) {
        self.id = UUID()
        self.name = name
        self.data = data
        self.contentType = contentType
        self.dateAdded = Date()
    }
    
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
