//
//  ModelsRepairProject.swift
//  Home Maintainer
//

import Foundation
import CoreData
import SwiftUI

// MARK: - RepairProject

@objc(RepairProject)
public final class RepairProject: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var projectDescription: String
    @NSManaged private var categoryRaw: String
    @NSManaged private var statusRaw: String
    @NSManaged private var priorityRaw: Int32
    @NSManaged public var startDate: Date?
    @NSManaged public var completionDate: Date?
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date
    @NSManaged public var homeIDString: String?
    @NSManaged public var totalCost: Double
    @NSManaged private var projectDocumentsJSON: String?
    @NSManaged private var workDatesJSON: String?

    // Relationships
    @NSManaged public var home: Home?
    @NSManaged public var hiredProvider: ServiceProvider?
    @NSManaged public var contacts: NSSet?
    @NSManaged public var quotes: NSSet?
    @NSManaged public var products: NSSet?
    @NSManaged public var invoice: Invoice?
    @NSManaged public var subTasks: NSSet?

    // MARK: - Enum properties

    var category: ServiceCategory {
        get { ServiceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .planning }
        set { statusRaw = newValue.rawValue }
    }

    var priority: ProjectPriority {
        get { ProjectPriority(rawValue: Int(priorityRaw)) ?? .medium }
        set { priorityRaw = Int32(newValue.rawValue) }
    }

    // MARK: - JSON-backed array attributes

    var projectDocuments: [ProjectDocument] {
        get { jsonDecode(from: projectDocumentsJSON) ?? [] }
        set { projectDocumentsJSON = jsonEncode(newValue) }
    }

    func addDocument(name: String, data: Data, contentType: String, title: String = "") {
        var docs = projectDocuments
        docs.append(ProjectDocument(name: name, data: data, contentType: contentType, title: title))
        projectDocuments = docs
    }

    func removeDocument(_ document: ProjectDocument) {
        projectDocuments = projectDocuments.filter { $0.id != document.id }
    }

    var workDates: [ProjectWorkDate] {
        get { jsonDecode(from: workDatesJSON) ?? [] }
        set { workDatesJSON = jsonEncode(newValue) }
    }

    func addWorkDate(label: String, scheduledDate: Date, durationDays: Int = 0, durationMinutes: Int = 0) {
        var dates = workDates
        dates.append(ProjectWorkDate(label: label, scheduledDate: scheduledDate, durationDays: durationDays, durationMinutes: durationMinutes))
        workDates = dates
    }

    func removeWorkDate(_ workDate: ProjectWorkDate) {
        workDates = workDates.filter { $0.id != workDate.id }
    }

    // MARK: - Typed relationship helpers

    var contactArray: [ProjectContact] {
        (contacts as? Set<ProjectContact>)?.sorted { $0.contactDate > $1.contactDate } ?? []
    }

    var quoteArray: [Quote] {
        (quotes as? Set<Quote>)?.sorted { $0.quoteDate > $1.quoteDate } ?? []
    }

    var productArray: [ProductLink] {
        (products as? Set<ProductLink>)?.sorted { $0.createdAt < $1.createdAt } ?? []
    }

    var subTaskArray: [MaintenanceTask] {
        (subTasks as? Set<MaintenanceTask>)?.sorted { $0.name < $1.name } ?? []
    }

    var totalQuotedAmount: Double {
        quoteArray.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Convenience factory

    @discardableResult
    static func make(
        title: String,
        description: String = "",
        category: ServiceCategory,
        priority: ProjectPriority = .medium,
        in context: NSManagedObjectContext
    ) -> RepairProject {
        let project = RepairProject(context: context)
        project.id = UUID()
        project.title = title
        project.projectDescription = description
        project.categoryRaw = category.rawValue
        project.statusRaw = ProjectStatus.planning.rawValue
        project.priorityRaw = Int32(priority.rawValue)
        project.notes = ""
        project.createdAt = Date()
        return project
    }
}

// MARK: - ProjectContact

@objc(ProjectContact)
public final class ProjectContact: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var contactDate: Date
    @NSManaged private var methodRaw: String
    @NSManaged public var notes: String
    @NSManaged public var wasHired: Bool
    @NSManaged public var project: RepairProject?
    @NSManaged public var provider: ServiceProvider?

    var method: ContactMethod {
        get { ContactMethod(rawValue: methodRaw) ?? .phone }
        set { methodRaw = newValue.rawValue }
    }

    @discardableResult
    static func make(
        project: RepairProject,
        provider: ServiceProvider,
        method: ContactMethod = .phone,
        notes: String = "",
        in context: NSManagedObjectContext
    ) -> ProjectContact {
        let contact = ProjectContact(context: context)
        contact.id = UUID()
        contact.project = project
        contact.provider = provider
        contact.contactDate = Date()
        contact.methodRaw = method.rawValue
        contact.notes = notes
        contact.wasHired = false
        return contact
    }
}

// MARK: - Quote

@objc(Quote)
public final class Quote: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var amount: Double
    @NSManaged public var quoteDate: Date
    @NSManaged public var validUntil: Date?
    @NSManaged public var details: String
    @NSManaged public var wasAccepted: Bool
    @NSManaged public var project: RepairProject?
    @NSManaged public var provider: ServiceProvider?

    @discardableResult
    static func make(
        project: RepairProject,
        provider: ServiceProvider,
        amount: Double,
        in context: NSManagedObjectContext
    ) -> Quote {
        let quote = Quote(context: context)
        quote.id = UUID()
        quote.project = project
        quote.provider = provider
        quote.amount = amount
        quote.quoteDate = Date()
        quote.details = ""
        quote.wasAccepted = false
        return quote
    }
}

// MARK: - Invoice

@objc(Invoice)
public final class Invoice: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var amount: Double
    @NSManaged public var invoiceDate: Date
    @NSManaged public var dueDate: Date?
    @NSManaged public var paidDate: Date?
    @NSManaged public var isPaid: Bool
    @NSManaged public var details: String
    @NSManaged public var project: RepairProject?
    @NSManaged public var provider: ServiceProvider?

    @discardableResult
    static func make(
        project: RepairProject,
        provider: ServiceProvider,
        amount: Double,
        in context: NSManagedObjectContext
    ) -> Invoice {
        let invoice = Invoice(context: context)
        invoice.id = UUID()
        invoice.project = project
        invoice.provider = provider
        invoice.amount = amount
        invoice.invoiceDate = Date()
        invoice.isPaid = false
        invoice.details = ""
        return invoice
    }
}

// MARK: - Enums

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
        case .planning:         return "lightbulb"
        case .requestingQuotes: return "envelope"
        case .reviewingQuotes:  return "doc.text.magnifyingglass"
        case .hired:            return "checkmark.circle"
        case .inProgress:       return "hammer"
        case .completed:        return "checkmark.circle.fill"
        case .cancelled:        return "xmark.circle"
        }
    }
}

enum ContactMethod: String, Codable, CaseIterable {
    case phone = "Phone"
    case email = "Email"
    case inPerson = "In Person"
    case website = "Website"
    case other = "Other"
}

// MARK: - Codable value types

struct ProjectDocument: Codable, Identifiable {
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

struct ProjectWorkDate: Codable, Identifiable {
    let id: UUID
    var label: String
    var scheduledDate: Date
    var durationDays: Int
    var durationMinutes: Int

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
