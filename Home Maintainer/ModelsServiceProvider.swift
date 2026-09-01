//
//  ModelsServiceProvider.swift
//  Home Maintainer
//

import Foundation
import CoreData

// MARK: - ServiceProvider

@objc(ServiceProvider)
public final class ServiceProvider: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged private var categoryRaw: String
    @NSManaged public var phoneNumber: String
    @NSManaged public var email: String
    @NSManaged public var address: String
    @NSManaged public var website: String
    @NSManaged public var notes: String
    @NSManaged public var isFavorite: Bool
    @NSManaged public var rating: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var homeIDString: String?
    @NSManaged public var googlePlaceID: String?
    @NSManaged public var googleRating: Double
    @NSManaged public var googlePriceLevel: String?
    @NSManaged private var weekdayHoursJSON: String?
    @NSManaged private var businessTypesJSON: String?

    // Relationships
    @NSManaged public var home: Home?
    @NSManaged public var invoices: NSSet?
    @NSManaged public var projectContacts: NSSet?
    @NSManaged public var quotes: NSSet?
    @NSManaged public var hiredProjects: NSSet?

    // MARK: - Category (enum backed by categoryRaw)

    var category: ServiceCategory {
        get { ServiceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    // MARK: - Array attributes (JSON-backed)

    var weekdayHours: [String]? {
        get { jsonDecode(from: weekdayHoursJSON) }
        set { weekdayHoursJSON = newValue.flatMap { jsonEncode($0) } }
    }

    var businessTypes: [String]? {
        get { jsonDecode(from: businessTypesJSON) }
        set { businessTypesJSON = newValue.flatMap { jsonEncode($0) } }
    }

    // MARK: - Computed

    var displayPriceLevel: String? {
        switch googlePriceLevel {
        case "PRICE_LEVEL_INEXPENSIVE": return "$"
        case "PRICE_LEVEL_MODERATE":    return "$$"
        case "PRICE_LEVEL_EXPENSIVE":   return "$$$"
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

    // MARK: - Convenience factory

    @discardableResult
    static func make(
        name: String,
        category: ServiceCategory,
        phoneNumber: String = "",
        email: String = "",
        in context: NSManagedObjectContext
    ) -> ServiceProvider {
        let provider = ServiceProvider(context: context)
        provider.id = UUID()
        provider.name = name
        provider.categoryRaw = category.rawValue
        provider.phoneNumber = phoneNumber
        provider.email = email
        provider.address = ""
        provider.website = ""
        provider.notes = ""
        provider.isFavorite = false
        provider.rating = 0
        provider.createdAt = Date()
        return provider
    }
}

// MARK: - ServiceCategory

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

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .electrician:       return "bolt.fill"
        case .plumber:           return "drop.fill"
        case .generalContractor: return "hammer.fill"
        case .roofer:            return "house.fill"
        case .hvac:              return "fan.fill"
        case .carpenter:         return "ruler.fill"
        case .painter:           return "paintbrush.fill"
        case .landscaper:        return "leaf.fill"
        case .handyman:          return "wrench.and.screwdriver.fill"
        case .appliance:         return "refrigerator.fill"
        case .other:             return "person.fill"
        }
    }

    var searchQuery: String {
        switch self {
        case .electrician:       return "electrician"
        case .plumber:           return "plumber"
        case .generalContractor: return "general contractor"
        case .roofer:            return "roofing contractor"
        case .hvac:              return "HVAC contractor"
        case .carpenter:         return "carpenter"
        case .painter:           return "house painter"
        case .landscaper:        return "landscaping service"
        case .handyman:          return "handyman"
        case .appliance:         return "appliance repair"
        case .other:             return "home repair"
        }
    }

    static func fromGoogleTypes(_ types: [String]) -> ServiceCategory {
        if types.contains("electrician")            { return .electrician }
        if types.contains("plumber")                { return .plumber }
        if types.contains("roofing_contractor")     { return .roofer }
        if types.contains("hvac_contractor")        { return .hvac }
        if types.contains("carpenter")              { return .carpenter }
        if types.contains("painter")                { return .painter }
        if types.contains("landscaper") || types.contains("landscaping_service") { return .landscaper }
        if types.contains("handyman")               { return .handyman }
        if types.contains("appliance_repair_service") { return .appliance }
        if types.contains("general_contractor")     { return .generalContractor }
        return .other
    }
}
