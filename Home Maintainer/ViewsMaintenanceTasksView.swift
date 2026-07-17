//
//  MaintenanceTasksView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

// MARK: - Outer shell (navigation, toolbar, sheets)

struct MaintenanceTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeManager.self) private var homeManager
    @Environment(NavigationCoordinator.self) private var coordinator
    @State private var navigationTarget: MaintenanceTask? = nil
    @State private var showingAddTask = false
    @State private var showingHomePicker = false
    @AppStorage("taskSortOption") private var sortOption: TaskSortOption = .upNext

    private var navTitle: String {
        sortOption == .fromProjects ? "Project Sub Tasks" : "Maintenance Tasks"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let home = homeManager.currentHome {
                    // HomeTasksList builds its @Query predicate from homeID in init so the
                    // filter runs at the SQLite level — no SwiftData relationship faulting.
                    HomeTasksList(home: home, sortOption: sortOption)
                } else {
                    noHomeView
                }
            }
            .navigationTitle(navTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomePickerButton(showingPicker: $showingHomePicker)
                }
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
                    .disabled(homeManager.currentHome == nil || sortOption == .fromProjects)
                }
            }
            .navigationDestination(item: $navigationTarget) { task in
                MaintenanceTaskDetailView(task: task)
            }
            .onAppear { handlePendingNavigation() }
            .onChange(of: coordinator.pendingTask) { _, _ in handlePendingNavigation() }
            .sheet(isPresented: $showingAddTask) {
                AddMaintenanceTaskView(home: homeManager.currentHome)
            }
            .sheet(isPresented: $showingHomePicker) {
                HomePickerView()
            }
        }
    }

    private func handlePendingNavigation() {
        if let task = coordinator.pendingTask {
            navigationTarget = task
            coordinator.pendingTask = nil
        }
    }

    private var noHomeView: some View {
        ContentUnavailableView {
            Label("No Home Selected", systemImage: "house")
        } description: {
            Text("Create or select a home to manage tasks.")
        } actions: {
            Button("Select Home") { showingHomePicker = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Inner list (owns @Query with SQL predicate)

// Splitting into a child view is the SwiftUI pattern for dynamic @Query predicates.
// The predicate `task.home?.id == homeID` is compiled by #Predicate into a CoreData
// keypath expression evaluated at the SQLite level — it never calls ModelContext.fulfill,
// so it is safe for tasks in the dynamically-added CloudKit shared store.
private struct HomeTasksList: View {
    let home: Home
    let sortOption: TaskSortOption
    @Query private var homeTasks: [MaintenanceTask]

    init(home: Home, sortOption: TaskSortOption) {
        self.home = home
        self.sortOption = sortOption
        let homeID = home.id
        _homeTasks = Query(
            filter: #Predicate<MaintenanceTask> { task in
                task.home?.id == homeID
            },
            sort: \MaintenanceTask.nextDue
        )
    }

    // Regular maintenance tasks (not from projects).
    // isDeleted guard short-circuits before the sourceProject relationship fault fires.
    private var tasks: [MaintenanceTask] {
        homeTasks.filter { !$0.isDeleted && $0.sourceProject == nil }
    }

    // Project sub-tasks only
    private var projectSubTasks: [MaintenanceTask] {
        homeTasks.filter { !$0.isDeleted && $0.sourceProject != nil }
    }

    var activeTasks: [MaintenanceTask] {
        tasks.filter { $0.isActive }
    }

    var closedTasks: [MaintenanceTask] {
        tasks.filter { !$0.isActive }.sorted { $0.name < $1.name }
    }

    var overdueTasks: [MaintenanceTask] {
        activeTasks.filter { $0.isOverdue }
    }

    var upcomingTasks: [MaintenanceTask] {
        activeTasks.filter { !$0.isOverdue }
    }

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

    var tasksByFrequency: [(frequency: TaskFrequency, tasks: [MaintenanceTask])] {
        let groups = Dictionary(grouping: activeTasks) { $0.safeFrequency }
        return groups
            .map { (frequency: $0.key, tasks: $0.value.sorted { ($0.nextDue ?? .distantFuture) < ($1.nextDue ?? .distantFuture) }) }
            .sorted { $0.frequency.sortOrder < $1.frequency.sortOrder }
    }

    var projectSubTasksByProject: [(projectTitle: String, tasks: [MaintenanceTask])] {
        let groups = Dictionary(grouping: projectSubTasks) { task in
            task.sourceProject?.title ?? "Unknown Project"
        }
        return groups
            .map { (projectTitle: $0.key, tasks: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.projectTitle.localizedCaseInsensitiveCompare($1.projectTitle) == .orderedAscending }
    }

    var body: some View {
        List {
            switch sortOption {
            case .upNext:
                upNextSections
                if activeTasks.isEmpty && closedTasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Add your first maintenance task to get started")
                    )
                }
                closedTasksSection
            case .room:
                roomSections
                if activeTasks.isEmpty && closedTasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Add your first maintenance task to get started")
                    )
                }
                closedTasksSection
            case .frequency:
                frequencySections
                if activeTasks.isEmpty && closedTasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Add your first maintenance task to get started")
                    )
                }
                closedTasksSection
            case .fromProjects:
                fromProjectsSections
                if projectSubTasks.isEmpty {
                    ContentUnavailableView(
                        "No Project Sub Tasks",
                        systemImage: "checklist.checked",
                        description: Text("There are no project sub tasks created")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var closedTasksSection: some View {
        if !closedTasks.isEmpty {
            Section {
                NavigationLink(destination: ClosedTasksView(tasks: closedTasks)) {
                    Label("Closed Tasks (\(closedTasks.count))", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                }
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

    @ViewBuilder
    private var fromProjectsSections: some View {
        ForEach(projectSubTasksByProject, id: \.projectTitle) { group in
            Section(group.projectTitle) {
                ForEach(group.tasks) { task in
                    NavigationLink(destination: MaintenanceTaskDetailView(task: task)) {
                        ProjectSubTaskRow(task: task)
                    }
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
    case fromProjects = "From Projects"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .upNext: return "calendar"
        case .room: return "door.left.hand.open"
        case .frequency: return "repeat"
        case .fromProjects: return "hammer"
        }
    }
}

extension TaskFrequency {
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

    var isCompletedForCurrentCycle: Bool {
        guard let _ = task.lastCompleted, let nextDue = task.nextDue else { return false }
        return nextDue > Date()
    }

    var body: some View {
        if task.isDeleted {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.name)
                        .font(.headline)

                    if isCompletedForCurrentCycle {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                HStack {
                    Text(task.frequencyDisplayName)
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
}

// Row used in the "From Projects" sort view — strikes through when closed
struct ProjectSubTaskRow: View {
    let task: MaintenanceTask

    var isDone: Bool { task.lastCompleted != nil }

    var body: some View {
        if task.isDeleted {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.name)
                        .font(.headline)
                        .strikethrough(isDone, color: .gray)
                        .foregroundStyle(isDone ? .secondary : .primary)

                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let lastCompleted = task.lastCompleted {
                    Text("Closed \(lastCompleted, format: .dateTime.month().day().year())")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

struct ClosedTasksView: View {
    let tasks: [MaintenanceTask]

    var body: some View {
        List {
            ForEach(tasks) { task in
                NavigationLink(destination: MaintenanceTaskDetailView(task: task)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.name)
                            .font(.headline)
                            .strikethrough(true, color: .gray)
                            .foregroundStyle(.secondary)

                        if let lastCompleted = task.lastCompleted {
                            Text("Closed \(lastCompleted, format: .dateTime.month().day().year())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Closed Tasks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    MaintenanceTasksView()
        .modelContainer(for: [MaintenanceTask.self, MaintenanceRecord.self], inMemory: true)
}
