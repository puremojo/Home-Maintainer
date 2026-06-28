//
//  MaintenanceTask.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import SwiftData

@Model
final class MaintenanceTask {
    var id: UUID
    var name: String
    var taskDescription: String
    var room: String = ""
    var frequency: TaskFrequency
    var lastCompleted: Date?
    var nextDue: Date?
    var isActive: Bool
    var records: [MaintenanceRecord]?
    var appliance: Appliance?
    @Relationship(deleteRule: .cascade, inverse: \ProductLink.task)
    var products: [ProductLink]?
    var createdAt: Date
    
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
        self.nextDue = calculateNextDue(from: Date(), frequency: frequency)
    }
    
    func markCompleted(on date: Date = Date()) {
        self.lastCompleted = date
        self.nextDue = calculateNextDue(from: date, frequency: frequency)
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
        case .once: return "Once"
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
    var id: UUID
    var task: MaintenanceTask?
    var completedDate: Date
    var notes: String
    var action: TaskAction
    
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
    case reopened = "Reopened"
}

