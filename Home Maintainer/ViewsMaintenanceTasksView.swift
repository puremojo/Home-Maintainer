//
//  MaintenanceTasksView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct MaintenanceTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MaintenanceTask.nextDue) private var tasks: [MaintenanceTask]
    @State private var showingAddTask = false
    @AppStorage("taskSortOption") private var sortOption: TaskSortOption = .upNext

    var activeTasks: [MaintenanceTask] {
        tasks.filter { $0.isActive }
    }

    var overdueTasks: [MaintenanceTask] {
        activeTasks.filter { $0.isOverdue }
    }

    var upcomingTasks: [MaintenanceTask] {
        activeTasks.filter { !$0.isOverdue }
    }

    /// Tasks grouped into sections by room, with empty rooms gathered under
    /// "No Room" and shown last.
    var tasksByRoom: [(room: String, tasks: [MaintenanceTask])] {
        let groups = Dictionary(grouping: activeTasks) { task in
            task.room.trimmingCharacters(in: .whitespaces).isEmpty ? "No Room" : task.room
        }
        return groups
            .map { (room: $0.key, tasks: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                if lhs.room == "No Room" { return false }
                if rhs.room == "No Room" { return true }
                return lhs.room.localizedCaseInsensitiveCompare(rhs.room) == .orderedAscending
            }
    }

    /// Tasks grouped into sections by frequency, ordered from most to least
    /// frequent.
    var tasksByFrequency: [(frequency: TaskFrequency, tasks: [MaintenanceTask])] {
        let groups = Dictionary(grouping: activeTasks) { $0.frequency }
        return groups
            .map { (frequency: $0.key, tasks: $0.value.sorted { ($0.nextDue ?? .distantFuture) < ($1.nextDue ?? .distantFuture) }) }
            .sorted { $0.frequency.sortOrder < $1.frequency.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                switch sortOption {
                case .upNext:
                    upNextSections
                case .room:
                    roomSections
                case .frequency:
                    frequencySections
                }

                if activeTasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Add your first maintenance task to get started")
                    )
                }
            }
            .navigationTitle("Maintenance Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort By", selection: $sortOption) {
                            ForEach(TaskSortOption.allCases) { option in
                                Label(option.rawValue, systemImage: option.systemImage).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTask = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                AddMaintenanceTaskView()
            }
        }
    }

    @ViewBuilder
    private var upNextSections: some View {
        if !overdueTasks.isEmpty {
            Section("Overdue") {
                ForEach(overdueTasks) { task in
                    taskLink(task)
                }
            }
        }

        if !upcomingTasks.isEmpty {
            Section("Upcoming") {
                ForEach(upcomingTasks) { task in
                    taskLink(task)
                }
            }
        }
    }

    @ViewBuilder
    private var roomSections: some View {
        ForEach(tasksByRoom, id: \.room) { group in
            Section(group.room) {
                ForEach(group.tasks) { task in
                    taskLink(task)
                }
            }
        }
    }

    @ViewBuilder
    private var frequencySections: some View {
        ForEach(tasksByFrequency, id: \.frequency) { group in
            Section(group.frequency.displayName) {
                ForEach(group.tasks) { task in
                    taskLink(task)
                }
            }
        }
    }

    private func taskLink(_ task: MaintenanceTask) -> some View {
        NavigationLink(destination: MaintenanceTaskDetailView(task: task)) {
            TaskRow(task: task)
        }
    }
}

enum TaskSortOption: String, CaseIterable, Identifiable {
    case upNext = "Up Next"
    case room = "Room"
    case frequency = "Frequency"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .upNext: return "calendar"
        case .room: return "door.left.hand.open"
        case .frequency: return "repeat"
        }
    }
}

extension TaskFrequency {
    /// Relative ordering used when sorting frequency groups (most frequent first).
    var sortOrder: Int {
        switch self {
        case .once: return 0
        case .daily: return 1
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        case .quarterly: return 90
        case .biannually: return 180
        case .annually: return 365
        case .custom(let days): return days
        }
    }
}

struct TaskRow: View {
    let task: MaintenanceTask
    
    // Check if task is completed and not yet due again
    var isCompletedForCurrentCycle: Bool {
        guard let lastCompleted = task.lastCompleted,
              let nextDue = task.nextDue else {
            return false
        }
        
        // If we've completed it and the next due date hasn't passed yet
        return nextDue > Date()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.name)
                    .font(.headline)
                    .strikethrough(isCompletedForCurrentCycle, color: .gray)
                    .foregroundStyle(isCompletedForCurrentCycle ? .secondary : .primary)
                
                if isCompletedForCurrentCycle {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            HStack {
                Text(task.frequency.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let nextDue = task.nextDue {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Due \(nextDue, format: .dateTime.month().day())")
                        .font(.caption)
                        .foregroundStyle(task.isOverdue ? .red : .secondary)
                }
                
                if let lastCompleted = task.lastCompleted, isCompletedForCurrentCycle {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Done \(lastCompleted, format: .dateTime.month().day())")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

#Preview {
    MaintenanceTasksView()
        .modelContainer(for: [MaintenanceTask.self, MaintenanceRecord.self], inMemory: true)
}
