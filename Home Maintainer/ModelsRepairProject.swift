//
//  RepairProject.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class RepairProject {
    var id: UUID
    var title: String
    var projectDescription: String
    var category: ServiceCategory
    var status: ProjectStatus
    var priority: ProjectPriority
    var contacts: [ProjectContact]?
    var quotes: [Quote]?
    @Relationship(deleteRule: .cascade, inverse: \ProductLink.project)
    var products: [ProductLink]?
    var invoice: Invoice?
    var hiredProvider: ServiceProvider?
    var startDate: Date?
    var completionDate: Date?
    var notes: String
    var createdAt: Date
    var home: Home?

    init(title: String, description: String, category: ServiceCategory, priority: ProjectPriority = .medium) {
        self.id = UUID()
        self.title = title
        self.projectDescription = description
        self.category = category
        self.status = .planning
        self.priority = priority
        self.notes = ""
        self.createdAt = Date()
    }
    
    var totalQuotedAmount: Double {
        quotes?.reduce(0) { $0 + $1.amount } ?? 0
    }
}

enum ProjectPriority: Int, Codable, CaseIterable, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
    
    var systemImage: String {
        switch self {
        case .low: return "arrow.down.circle"
        case .medium: return "minus.circle"
        case .high: return "exclamationmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    static func < (lhs: ProjectPriority, rhs: ProjectPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ProjectStatus: String, Codable, CaseIterable {
    case planning = "Planning"
    case requestingQuotes = "Requesting Quotes"
    case reviewingQuotes = "Reviewing Quotes"
    case hired = "Hired"
    case inProgress = "In Progress"
    case completed = "Completed"
    case cancelled = "Cancelled"
    
    var systemImage: String {
        switch self {
        case .planning: return "lightbulb"
        case .requestingQuotes: return "envelope"
        case .reviewingQuotes: return "doc.text.magnifyingglass"
        case .hired: return "checkmark.circle"
        case .inProgress: return "hammer"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }
}

@Model
final class ProjectContact {
    var id: UUID
    var project: RepairProject?
    var provider: ServiceProvider?
    var contactDate: Date
    var method: ContactMethod
    var notes: String
    var wasHired: Bool
    
    init(project: RepairProject, provider: ServiceProvider, contactDate: Date = Date(), method: ContactMethod = .phone, notes: String = "") {
        self.id = UUID()
        self.project = project
        self.provider = provider
        self.contactDate = contactDate
        self.method = method
        self.notes = notes
        self.wasHired = false
    }
}

enum ContactMethod: String, Codable, CaseIterable {
    case phone = "Phone"
    case email = "Email"
    case inPerson = "In Person"
    case website = "Website"
    case other = "Other"
}

@Model
final class Quote {
    var id: UUID
    var project: RepairProject?
    var provider: ServiceProvider?
    var amount: Double
    var quoteDate: Date
    var validUntil: Date?
    var details: String
    var wasAccepted: Bool
    
    init(project: RepairProject, provider: ServiceProvider, amount: Double, quoteDate: Date = Date()) {
        self.id = UUID()
        self.project = project
        self.provider = provider
        self.amount = amount
        self.quoteDate = quoteDate
        self.details = ""
        self.wasAccepted = false
    }
}

@Model
final class Invoice {
    var id: UUID
    var project: RepairProject?
    var provider: ServiceProvider?
    var amount: Double
    var invoiceDate: Date
    var dueDate: Date?
    var paidDate: Date?
    var isPaid: Bool
    var details: String
    
    init(project: RepairProject, provider: ServiceProvider, amount: Double, invoiceDate: Date = Date()) {
        self.id = UUID()
        self.project = project
        self.provider = provider
        self.amount = amount
        self.invoiceDate = invoiceDate
        self.isPaid = false
        self.details = ""
    }
}
