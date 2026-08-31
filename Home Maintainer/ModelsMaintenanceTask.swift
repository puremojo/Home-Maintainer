//
//  ModelsMaintenanceTask.swift
//  Home Maintainer
//

import Foundation
import CoreData
import SwiftUI

// MARK: - MaintenanceTask

@objc(MaintenanceTask)
public final class MaintenanceTask: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var taskDescription: String
    @NSManaged public var room: String
    @NSManaged public var frequencyEncoded: String
    @NSManaged public var lastCompleted: Date?
    @NSManaged public var nextDue: Date?
    @NSManaged public var isActive: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var homeIDString: String?
    @NSManaged public var sourceProjectIDString: String?
    @NSManaged private var taskDocumentsJSON: String?

    // Relationships
    @NSManaged public var home: Home?
    @NSManaged public var appliance: Appliance?
    @NSManaged public var records: NSSet?
    @NSManaged public var products: NSSet?
    @NSManaged public var sourceProject: RepairProject?

    // MARK: - Frequency (computed, backed by frequencyEncoded)

    var frequency: TaskFrequency {
        get { TaskFrequency.from(encoded: frequencyEncoded) }
        set { frequencyEncoded = newValue.encoded }
    }

    var safeFrequency: TaskFrequency { frequency }
    var frequencyDisplayName: String { frequency.displayName }

    // MARK: - Task documents (JSON-backed [TaskDocument])

    var taskDocuments: [TaskDocument] {
        get { jsonDecode(from: taskDocumentsJSON) ?? [] }
        set { taskDocumentsJSON = jsonEncode(newValue) }
    }

    func addDocument(name: String, data: Data, contentType: String, title: String = "") {
        var docs = taskDocuments
        docs.append(TaskDocument(name: name, data: data, contentType: contentType, title: title))
        taskDocuments = docs
    }

    func removeDocument(_ document: TaskDocument) {
        taskDocuments = taskDocuments.filter { $0.id != document.id }
    }

    // MARK: - Computed state

    var isOverdue: Bool {
        guard let nextDue else { return false }
        return nextDue < Date()
    }

    var isCompletedForCurrentCycle: Bool {
        guard lastCompleted != nil, let nextDue else { return false }
        return nextDue > Date()
    }

    // MARK: - Actions

    func markCompleted(on date: Date = Date()) {
        lastCompleted = date
        nextDue = frequency.nextDue(from: date)
        isActive = true
    }

    func reopen() {
        isActive = true
        lastCompleted = nil
        updateFrequency(frequency)
    }

    func updateFrequency(_ newFrequency: TaskFrequency) {
        frequency = newFrequency
        let base = lastCompleted ?? Date()
        nextDue = newFrequency.nextDue(from: base)
    }

    // MARK: - Typed relationship helpers

    var recordArray: [MaintenanceRecord] {
        (records as? Set<MaintenanceRecord>)?.sorted { $0.completedDate > $1.completedDate } ?? []
    }

    var productArray: [ProductLink] {
        (products as? Set<ProductLink>)?.sorted { $0.createdAt < $1.createdAt } ?? []
    }

    // MARK: - Convenience factory

    @discardableResult
    static func make(
        name: String,
        description: String = "",
        frequency: TaskFrequency = .monthly,
        room: String = "",
        appliance: Appliance? = nil,
        in context: NSManagedObjectContext
    ) -> MaintenanceTask {
        let task = MaintenanceTask(context: context)
        task.id = UUID()
        task.name = name
        task.taskDescription = description
        task.room = room
        task.frequencyEncoded = frequency.encoded
        task.appliance = appliance
        task.isActive = true
        task.createdAt = Date()
        task.nextDue = frequency.nextDue(from: Date())
        return task
    }
}

// MARK: - MaintenanceRecord

@objc(MaintenanceRecord)
public final class MaintenanceRecord: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var completedDate: Date
    @NSManaged public var notes: String
    /// Stores TaskAction.rawValue
    @NSManaged public var action: String
    @NSManaged public var task: MaintenanceTask?

    var taskAction: TaskAction {
        get { TaskAction(rawValue: action) ?? .closed }
        set { action = newValue.rawValue }
    }

    @discardableResult
    static func make(
        task: MaintenanceTask,
        completedDate: Date = Date(),
        notes: String = "",
        action: TaskAction = .closed,
        in context: NSManagedObjectContext
    ) -> MaintenanceRecord {
        let record = MaintenanceRecord(context: context)
        record.id = UUID()
        record.task = task
        record.completedDate = completedDate
        record.notes = notes
        record.action = action.rawValue
        return record
    }
}

// MARK: - TaskFrequency

enum TaskFrequency: Codable, Hashable, Equatable {
    case once
    case daily
    case weekly
    case biweekly
    case monthly
    case quarterly
    case biannually
    case annually
    case custom(days: Int)

    var displayName: String {
        switch self {
        case .once: return "Never"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 Weeks"
        case .monthly: return "Monthly"
        case .quarterly: return "Every 3 Months"
        case .biannually: return "Every 6 Months"
        case .annually: return "Annually"
        case .custom(let days): return "Every \(days) days"
        }
    }

    var encoded: String {
        switch self {
        case .once: return "once"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .biweekly: return "biweekly"
        case .monthly: return "monthly"
        case .quarterly: return "quarterly"
        case .biannually: return "biannually"
        case .annually: return "annually"
        case .custom(let days): return "custom:\(days)"
        }
    }

    func nextDue(from date: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .once:             return nil
        case .daily:            return cal.date(byAdding: .day,        value: 1,    to: date)
        case .weekly:           return cal.date(byAdding: .weekOfYear, value: 1,    to: date)
        case .biweekly:         return cal.date(byAdding: .weekOfYear, value: 2,    to: date)
        case .monthly:          return cal.date(byAdding: .month,      value: 1,    to: date)
        case .quarterly:        return cal.date(byAdding: .month,      value: 3,    to: date)
        case .biannually:       return cal.date(byAdding: .month,      value: 6,    to: date)
        case .annually:         return cal.date(byAdding: .year,       value: 1,    to: date)
        case .custom(let days): return cal.date(byAdding: .day,        value: days, to: date)
        }
    }

    static func from(encoded: String) -> TaskFrequency {
        switch encoded {
        case "once":       return .once
        case "daily":      return .daily
        case "weekly":     return .weekly
        case "biweekly":   return .biweekly
        case "monthly":    return .monthly
        case "quarterly":  return .quarterly
        case "biannually": return .biannually
        case "annually":   return .annually
        default:
            if encoded.hasPrefix("custom:"), let days = Int(encoded.dropFirst(7)) {
                return .custom(days: days)
            }
            return .monthly
        }
    }
}

// MARK: - TaskAction

enum TaskAction: String, Codable {
    case closed = "Closed"
    case occurrenceClosed = "Occurrence Closed"
    case reopened = "Reopened"

    var badgeColor: Color {
        switch self {
        case .closed: return .green
        case .occurrenceClosed: return .blue
        case .reopened: return .orange
        }
    }
}

// MARK: - TaskDocument (Codable value type — not a Core Data entity)

struct TaskDocument: Codable, Identifiable {
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

// MARK: - JSON helpers (module-internal)

func jsonDecode<T: Decodable>(from json: String?) -> T? {
    guard let json, let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

func jsonEncode<T: Encodable>(_ value: T) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}
