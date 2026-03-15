//
//  ServiceProvider.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import SwiftData

@Model
final class ServiceProvider {
    var id: UUID
    var name: String
    var category: ServiceCategory
    var phoneNumber: String
    var email: String
    var address: String
    var website: String
    var notes: String
    var isFavorite: Bool
    var rating: Int // 0-5 stars
    var createdAt: Date
    
    init(name: String, category: ServiceCategory, phoneNumber: String = "", email: String = "") {
        self.id = UUID()
        self.name = name
        self.category = category
        self.phoneNumber = phoneNumber
        self.email = email
        self.address = ""
        self.website = ""
        self.notes = ""
        self.isFavorite = false
        self.rating = 0
        self.createdAt = Date()
    }
}

enum ServiceCategory: String, Codable, CaseIterable, Identifiable {
    case electrician = "Electrician"
    case plumber = "Plumber"
    case generalContractor = "General Contractor"
    case roofer = "Roofer"
    case hvac = "HVAC Specialist"
    case carpenter = "Carpenter"
    case painter = "Painter"
    case landscaper = "Landscaper"
    case handyman = "Handyman"
    case appliance = "Appliance Repair"
    case other = "Other"
    
    var id: String { self.rawValue }
    
    var systemImage: String {
        switch self {
        case .electrician: return "bolt.fill"
        case .plumber: return "drop.fill"
        case .generalContractor: return "hammer.fill"
        case .roofer: return "house.fill"
        case .hvac: return "fan.fill"
        case .carpenter: return "ruler.fill"
        case .painter: return "paintbrush.fill"
        case .landscaper: return "leaf.fill"
        case .handyman: return "wrench.and.screwdriver.fill"
        case .appliance: return "refrigerator.fill"
        case .other: return "person.fill"
        }
    }
}
