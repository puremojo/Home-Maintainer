//
//  MaintenanceTask.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class MaintenanceTask {
    var id: UUID = UUID()
    var name: String = ""
    var taskDescription: String = ""
    var room: String = ""
    var frequency: TaskFrequency = TaskFrequency.monthly
    var lastCompleted: Date?
    var nextDue: Date?
    var isActive: Bool = true
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceRecord.task)
    var records: [MaintenanceRecord]?
    var appliance: Appliance?
    @Relationship(deleteRule: .cascade, inverse: \ProductLink.task)
    var products: [ProductLink]?
    var taskDocuments: [TaskDocument]?
    var createdAt: Date = Date()
    var home: Home?
    var sourceProject: RepairProject?

    init(name: String, description: String, frequency: TaskFrequency, appliance: Appliance? = nil, room: String = "") {
        self.id = UUID()
        self.name = name
        self.taskDescription = description
        self.room = room
        self.frequency = frequency
        self.appliance = appliance
        self.isActive = true
        self.createdAt = Date()
        self.lastCompleted = nil
        self.taskDocuments = []
        self.nextDue = calculateNextDue(from: Date(), frequency: frequency)
    }

    func addDocument(name: String, data: Data, contentType: String, title: String = "") {
        let document = TaskDocument(name: name, data: data, contentType: contentType, title: title)
        if taskDocuments == nil { taskDocuments = [] }
        taskDocuments?.append(document)
    }

    func removeDocument(_ document: TaskDocument) {
        taskDocuments?.removeAll { $0.id == document.id }
    }

    func markCompleted(on date: Date = Date()) {
        self.lastCompleted = date
        self.nextDue = calculateNextDue(from: date, frequency: frequency)
    }

    func reopen() {
        self.isActive = true
        self.lastCompleted = nil
        self.updateFrequency(self.frequency)
    }

    /// Updates the frequency and recomputes the next due date based on the new
    /// schedule (from the last completion if available, otherwise from now).
    func updateFrequency(_ newFrequency: TaskFrequency) {
        self.frequency = newFrequency
        let base = lastCompleted ?? Date()
        self.nextDue = calculateNextDue(from: base, frequency: newFrequency)
    }

    private func calculateNextDue(from date: Date, frequency: TaskFrequency) -> Date? {
        let calendar = Calendar.current

        switch frequency {
        case .once:
            // A one-time task never repeats, so there is no next due date.
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date)
        case .biannually:
            return calendar.date(byAdding: .month, value: 6, to: date)
        case .annually:
            return calendar.date(byAdding: .year, value: 1, to: date)
        case .custom(let days):
            return calendar.date(byAdding: .day, value: days, to: date)
        }
    }

    var isOverdue: Bool {
        guard let nextDue = nextDue else { return false }
        return nextDue < Date()
    }

    // Check if task is completed and not yet due again
    var isCompletedForCurrentCycle: Bool {
        guard let lastCompleted = lastCompleted,
              let nextDue = nextDue else {
            return false
        }

        // If we've completed it and the next due date hasn't passed yet
        return nextDue > Date()
    }
}

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
}

@Model
final class MaintenanceRecord {
    var id: UUID = UUID()
    var task: MaintenanceTask?
    var completedDate: Date = Date()
    var notes: String = ""
    var action: TaskAction = TaskAction.closed

    init(task: MaintenanceTask, completedDate: Date = Date(), notes: String = "", action: TaskAction = .closed) {
        self.id = UUID()
        self.task = task
        self.completedDate = completedDate
        self.notes = notes
        self.action = action
    }
}

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

struct TaskDocument: Codable, Identifiable {
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
