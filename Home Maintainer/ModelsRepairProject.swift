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
    var id: UUID = UUID()
    var title: String = ""
    var projectDescription: String = ""
    var category: ServiceCategory = ServiceCategory.other
    var status: ProjectStatus = ProjectStatus.planning
    var priority: ProjectPriority = ProjectPriority.medium
    @Relationship(deleteRule: .cascade, inverse: \ProjectContact.project)
    var contacts: [ProjectContact]?
    @Relationship(deleteRule: .cascade, inverse: \Quote.project)
    var quotes: [Quote]?
    @Relationship(deleteRule: .cascade, inverse: \ProductLink.project)
    var products: [ProductLink]?
    @Relationship(deleteRule: .cascade, inverse: \Invoice.project)
    var invoice: Invoice?
    var hiredProvider: ServiceProvider?
    var startDate: Date?
    var completionDate: Date?
    var notes: String = ""
    var projectDocuments: [ProjectDocument]?
    var createdAt: Date = Date()
    var home: Home?
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceTask.sourceProject)
    var subTasks: [MaintenanceTask]?
    var workDates: [ProjectWorkDate]?
    var totalCost: Double?

    init(title: String, description: String, category: ServiceCategory, priority: ProjectPriority = .medium) {
        self.id = UUID()
        self.title = title
        self.projectDescription = description
        self.category = category
        self.status = .planning
        self.priority = priority
        self.notes = ""
        self.projectDocuments = []
        self.createdAt = Date()
    }

    func addDocument(name: String, data: Data, contentType: String, title: String = "") {
        let document = ProjectDocument(name: name, data: data, contentType: contentType, title: title)
        if projectDocuments == nil { projectDocuments = [] }
        projectDocuments?.append(document)
    }

    func removeDocument(_ document: ProjectDocument) {
        projectDocuments?.removeAll { $0.id == document.id }
    }

    var totalQuotedAmount: Double {
        quotes?.reduce(0) { $0 + $1.amount } ?? 0
    }

    func addWorkDate(label: String, scheduledDate: Date, durationDays: Int = 0, durationMinutes: Int = 0) {
        let workDate = ProjectWorkDate(label: label, scheduledDate: scheduledDate, durationDays: durationDays, durationMinutes: durationMinutes)
        if workDates == nil { workDates = [] }
        workDates?.append(workDate)
    }

    func removeWorkDate(_ workDate: ProjectWorkDate) {
        workDates?.removeAll { $0.id == workDate.id }
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
    var id: UUID = UUID()
    var project: RepairProject?
    var provider: ServiceProvider?
    var contactDate: Date = Date()
    var method: ContactMethod = ContactMethod.phone
    var notes: String = ""
    var wasHired: Bool = false

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
    var id: UUID = UUID()
    var project: RepairProject?
    var provider: ServiceProvider?
    var amount: Double = 0
    var quoteDate: Date = Date()
    var validUntil: Date?
    var details: String = ""
    var wasAccepted: Bool = false

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

struct ProjectDocument: Codable, Identifiable {
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
        if contentType.contains("pdf") { return "pdf" }
        else if contentType.contains("word") { return "doc" }
        else if contentType.contains("text") { return "txt" }
        else { return "file" }
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

struct ProjectWorkDate: Codable, Identifiable {
    let id: UUID
    var label: String
    var scheduledDate: Date
    var durationDays: Int    // multi-day projects (e.g. pool removal)
    var durationMinutes: Int // hours + minutes encoded as total minutes

    enum CodingKeys: String, CodingKey {
        case id, label, scheduledDate, durationDays, durationMinutes
    }

    init(label: String = "", scheduledDate: Date = Date(), durationDays: Int = 0, durationMinutes: Int = 0) {
        self.id = UUID()
        self.label = label
        self.scheduledDate = scheduledDate
        self.durationDays = durationDays
        self.durationMinutes = durationMinutes
    }

    // Backward-compat: old records lack durationDays
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        scheduledDate = try c.decode(Date.self, forKey: .scheduledDate)
        durationDays = (try? c.decode(Int.self, forKey: .durationDays)) ?? 0
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
    }

    var formattedDuration: String? {
        let hours = durationMinutes / 60
        let mins = durationMinutes % 60
        guard durationDays > 0 || hours > 0 || mins > 0 else { return nil }

        var parts: [String] = []
        if durationDays > 0 { parts.append("\(durationDays)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if mins > 0 { parts.append("\(mins)m") }
        return parts.joined(separator: " ")
    }
}

@Model
final class Invoice {
    var id: UUID = UUID()
    var project: RepairProject?
    var provider: ServiceProvider?
    var amount: Double = 0
    var invoiceDate: Date = Date()
    var dueDate: Date?
    var paidDate: Date?
    var isPaid: Bool = false
    var details: String = ""

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
