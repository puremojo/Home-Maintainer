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
    
    var activeTasks: [MaintenanceTask] {
        tasks.filter { $0.isActive }
    }
    
    var overdueTasks: [MaintenanceTask] {
        activeTasks.filter { $0.isOverdue }
    }
    
    var upcomingTasks: [MaintenanceTask] {
        activeTasks.filter { !$0.isOverdue }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if !overdueTasks.isEmpty {
                    Section("Overdue") {
                        ForEach(overdueTasks) { task in
                            NavigationLink(destination: MaintenanceTaskDetailView(task: task)) {
                                TaskRow(task: task)
                            }
                        }
                    }
                }
                
                if !upcomingTasks.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcomingTasks) { task in
                            NavigationLink(destination: MaintenanceTaskDetailView(task: task)) {
                                TaskRow(task: task)
                            }
                        }
                    }
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
