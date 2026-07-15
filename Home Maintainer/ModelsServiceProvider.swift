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
    var rating: Int // 0-5 stars (user's personal rating)
    var createdAt: Date
    var home: Home?
    // Google Places data (populated when added via search)
    var googlePlaceID: String?
    var googleRating: Double?
    var googlePriceLevel: String?
    var weekdayHours: [String]?
    var businessTypes: [String]?

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

    var displayPriceLevel: String? {
        switch googlePriceLevel {
        case "PRICE_LEVEL_INEXPENSIVE": return "$"
        case "PRICE_LEVEL_MODERATE": return "$$"
        case "PRICE_LEVEL_EXPENSIVE": return "$$$"
        case "PRICE_LEVEL_VERY_EXPENSIVE": return "$$$$"
        default: return nil
        }
    }

    var primaryGoogleType: String? {
        guard let types = businessTypes else { return nil }
        let skip = Set(["point_of_interest", "establishment", "local_government_office", "store", "food", "health"])
        return types.first { !skip.contains($0) }
            .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
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

    // Text query for Google Places text search
    var searchQuery: String {
        switch self {
        case .electrician: return "electrician"
        case .plumber: return "plumber"
        case .generalContractor: return "general contractor"
        case .roofer: return "roofing contractor"
        case .hvac: return "HVAC contractor"
        case .carpenter: return "carpenter"
        case .painter: return "house painter"
        case .landscaper: return "landscaping service"
        case .handyman: return "handyman"
        case .appliance: return "appliance repair"
        case .other: return "home repair"
        }
    }

    static func fromGoogleTypes(_ types: [String]) -> ServiceCategory {
        if types.contains("electrician") { return .electrician }
        if types.contains("plumber") { return .plumber }
        if types.contains("roofing_contractor") { return .roofer }
        if types.contains("hvac_contractor") { return .hvac }
        if types.contains("carpenter") { return .carpenter }
        if types.contains("painter") { return .painter }
        if types.contains("landscaper") || types.contains("landscaping_service") { return .landscaper }
        if types.contains("handyman") { return .handyman }
        if types.contains("appliance_repair_service") { return .appliance }
        if types.contains("general_contractor") { return .generalContractor }
        return .other
    }
}
