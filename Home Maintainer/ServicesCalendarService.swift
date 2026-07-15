//
//  CalendarService.swift
//  Home Maintainer
//

import EventKit
import Foundation

final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()

    private init() {}

    // MARK: - Public API

    func addWorkDateEvent(workDate: ProjectWorkDate, projectTitle: String) async {
        guard await requestAccess() else { return }

        let event = EKEvent(eventStore: store)
        event.title = workDate.label.isEmpty ? projectTitle : "\(workDate.label) — \(projectTitle)"
        event.startDate = workDate.scheduledDate
        event.endDate = endDate(for: workDate)
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -86400)) // 1 day before

        try? store.save(event, span: .thisEvent)
    }

    func addTaskEvent(task: MaintenanceTask) async {
        guard await requestAccess() else { return }
        guard let nextDue = task.nextDue else { return } // .once tasks have no due date

        let event = EKEvent(eventStore: store)
        event.title = task.name
        event.startDate = Calendar.current.startOfDay(for: nextDue)
        event.endDate = Calendar.current.startOfDay(for: nextDue)
        event.isAllDay = true
        event.calendar = store.defaultCalendarForNewEvents

        if let rule = recurrenceRule(for: task.frequency) {
            event.recurrenceRules = [rule]
        }

        event.addAlarm(EKAlarm(relativeOffset: -86400)) // 1 day before

        try? store.save(event, span: .thisEvent)
    }

    // MARK: - Private Helpers

    private func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess:
                return true
            case .notDetermined:
                return (try? await store.requestFullAccessToEvents()) ?? false
            default:
                return false
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized:
                return true
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    store.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            default:
                return false
            }
        }
    }

    private func endDate(for workDate: ProjectWorkDate) -> Date {
        let hasDuration = workDate.durationDays > 0 || workDate.durationMinutes > 0
        guard hasDuration else {
            return Calendar.current.date(byAdding: .hour, value: 1, to: workDate.scheduledDate) ?? workDate.scheduledDate
        }

        var result = workDate.scheduledDate
        if workDate.durationDays > 0 {
            result = Calendar.current.date(byAdding: .day, value: workDate.durationDays, to: result) ?? result
        }
        if workDate.durationMinutes > 0 {
            result = Calendar.current.date(byAdding: .minute, value: workDate.durationMinutes, to: result) ?? result
        }
        return result
    }

    private func recurrenceRule(for frequency: TaskFrequency) -> EKRecurrenceRule? {
        switch frequency {
        case .once:
            return nil
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .biweekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .quarterly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 3, end: nil)
        case .biannually:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 6, end: nil)
        case .annually:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        case .custom(let days):
            return EKRecurrenceRule(recurrenceWith: .daily, interval: max(1, days), end: nil)
        }
    }
}
