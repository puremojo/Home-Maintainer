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

    func addWorkDateEvent(workDate: ProjectWorkDate, projectTitle: String, homeName: String) async {
        guard await requestAccess() else { return }

        let event = EKEvent(eventStore: store)
        let base = workDate.label.isEmpty ? projectTitle : "\(workDate.label) — \(projectTitle)"
        event.title = "\(base) (\(homeName))"
        event.startDate = workDate.scheduledDate
        event.endDate = endDate(for: workDate)
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -86400)) // 1 day before

        try? store.save(event, span: .thisEvent)
    }

    // Takes plain values rather than the MaintenanceTask itself — task is an NSManagedObject
    // tied to a main-queue-confined context, and requestAccess() below may resume its
    // continuation off the main thread, so any CoreData property reads need to happen before
    // this call, not after.
    //
    // Creates a new calendar event the first time (existingIdentifier is nil), or updates the
    // same event in place on every subsequent call (e.g. after the task is renamed or its
    // frequency changes) so the calendar never drifts from the task's current name/date —
    // rather than leaving a stale duplicate behind. Returns the event identifier to persist
    // back onto the task (nil if no event exists/was created, e.g. a .once task with no due
    // date, or if calendar access was denied).
    // homeName is always included in the title (not just when ambiguous) so tasks from
    // different homes landing on the same calendar day are still easy to tell apart at a glance.
    @discardableResult
    func syncTaskEvent(
        existingIdentifier: String?,
        name: String,
        nextDue: Date?,
        frequency: TaskFrequency,
        homeName: String
    ) async -> String? {
        guard await requestAccess() else { return existingIdentifier }

        guard let nextDue else {
            // No due date (e.g. switched to .once) — remove any event that previously existed.
            if let existingIdentifier, let stale = store.event(withIdentifier: existingIdentifier) {
                try? store.remove(stale, span: .thisEvent)
            }
            return nil
        }

        let event = existingIdentifier.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        event.title = "\(name) (\(homeName))"
        event.startDate = Calendar.current.startOfDay(for: nextDue)
        event.endDate = Calendar.current.startOfDay(for: nextDue)
        event.isAllDay = true
        if event.calendar == nil {
            event.calendar = store.defaultCalendarForNewEvents
        }

        event.recurrenceRules = recurrenceRule(for: frequency).map { [$0] }

        if event.alarms?.isEmpty != false {
            event.addAlarm(EKAlarm(relativeOffset: -86400)) // 1 day before
        }

        guard (try? store.save(event, span: .thisEvent)) != nil else { return existingIdentifier }
        return event.eventIdentifier
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
