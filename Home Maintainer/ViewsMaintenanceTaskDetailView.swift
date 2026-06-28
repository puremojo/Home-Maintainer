//
//  MaintenanceTaskDetailView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct MaintenanceTaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allAppliances: [Appliance]
    @Bindable var task: MaintenanceTask
    @State private var showingCompleteSheet = false
    @State private var showingReopenConfirmation = false
    @State private var showingAppliancePicker = false
    @State private var editingRecord: MaintenanceRecord?
    @State private var productEditorTarget: ProductEditorTarget?
    
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
        List {
            Section("Details") {
                LabeledContent("Name", value: task.name)
                LabeledContent("Description", value: task.taskDescription)
                LabeledContent("Frequency", value: task.frequency.displayName)
                
                // Appliance link - editable
                LabeledContent("Linked Appliance") {
                    if let appliance = task.appliance {
                        Button {
                            showingAppliancePicker = true
                        } label: {
                            HStack {
                                Image(systemName: appliance.type.systemImage)
                                Text(appliance.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            showingAppliancePicker = true
                        } label: {
                            HStack {
                                Text("None")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                if let lastCompleted = task.lastCompleted {
                    LabeledContent("Last Closed") {
                        Text(lastCompleted, format: .dateTime.month().day().year())
                    }
                }
                
                if let nextDue = task.nextDue {
                    LabeledContent("Next Due") {
                        Text(nextDue, format: .dateTime.month().day().year())
                            .foregroundStyle(task.isOverdue ? .red : .primary)
                    }
                }
                
                if isCompletedForCurrentCycle {
                    LabeledContent("Status") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Closed")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            
            Section {
                if isCompletedForCurrentCycle {
                    Button(role: .destructive) {
                        showingReopenConfirmation = true
                    } label: {
                        Label("Mark as Open", systemImage: "arrow.uturn.backward.circle")
                    }
                } else {
                    Button {
                        showingCompleteSheet = true
                    } label: {
                        Label("Mark as Closed", systemImage: "checkmark.circle")
                    }
                }
            }
            
            if let records = task.records, !records.isEmpty {
                Section("History") {
                    ForEach(records.sorted(by: { $0.completedDate > $1.completedDate })) { record in
                        Button {
                            editingRecord = record
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.completedDate, format: .dateTime.month().day().year().hour().minute())
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                    
                                    Text(record.action.rawValue)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(record.action == .closed ? .green : .orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(record.action == .closed ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                        )
                                }
                                
                                if !record.notes.isEmpty {
                                    Text(record.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Tap to add notes")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .italic()
                                }
                            }
                        }
                    }
                }
            }
            
            LiveProductsSection(
                products: task.products ?? [],
                detach: { $0.task = nil },
                onAdd: { productEditorTarget = .add },
                onEdit: { productEditorTarget = .edit($0) }
            )

            Section {
                Toggle("Active", isOn: $task.isActive)
            }
        }
        .navigationTitle(task.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCompleteSheet) {
            CompleteTaskView(task: task)
        }
        .sheet(isPresented: $showingAppliancePicker) {
            SelectApplianceView(task: task, allAppliances: allAppliances)
        }
        .sheet(item: $editingRecord) { record in
            EditRecordNotesView(record: record)
        }
        .sheet(item: $productEditorTarget) { target in
            ProductEditorSheet(target: target, attach: { $0.task = task })
        }
        .confirmationDialog(
            "Reopen this task?",
            isPresented: $showingReopenConfirmation
        ) {
            Button("Mark as Open", role: .destructive) {
                reopenTask()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will mark the task as needing to be completed again.")
        }
    }
    
    private func reopenTask() {
        // Create a "reopened" record
        let record = MaintenanceRecord(
            task: task,
            completedDate: Date(),
            notes: "Task reopened",
            action: .reopened
        )
        modelContext.insert(record)
        
        // Set the next due date to today (or keep it if already overdue)
        if let nextDue = task.nextDue, nextDue > Date() {
            task.nextDue = Date()
        }
        // Clear the last completed date to make it appear incomplete
        task.lastCompleted = nil
    }
}

struct CompleteTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let task: MaintenanceTask
    
    @State private var completionDate = Date()
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Completion Date", selection: $completionDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Close Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        completeTask()
                    }
                }
            }
        }
    }
    
    private func completeTask() {
        task.markCompleted(on: completionDate)
        
        let record = MaintenanceRecord(
            task: task,
            completedDate: completionDate,
            notes: notes,
            action: .closed
        )
        modelContext.insert(record)
        
        dismiss()
    }
}

struct SelectApplianceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: MaintenanceTask
    let allAppliances: [Appliance]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        task.appliance = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("None")
                            Spacer()
                            if task.appliance == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                
                if !allAppliances.isEmpty {
                    Section("Appliances") {
                        ForEach(allAppliances) { appliance in
                            Button {
                                task.appliance = appliance
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: appliance.type.systemImage)
                                        .foregroundStyle(.blue)
                                        .frame(width: 30)
                                    Text(appliance.name)
                                    Spacer()
                                    if task.appliance?.id == appliance.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                } else {
                    Section {
                        Text("No appliances added yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Link Appliance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct EditRecordNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var record: MaintenanceRecord
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Date") {
                        Text(record.completedDate, format: .dateTime.month().day().year().hour().minute())
                    }
                    
                    LabeledContent("Action") {
                        Text(record.action.rawValue)
                            .foregroundStyle(record.action == .closed ? .green : .orange)
                    }
                }
                
                Section("Notes") {
                    TextField("Add notes about this completion...", text: $record.notes, axis: .vertical)
                        .lineLimit(3...10)
                        .focused($isFocused)
                }
            }
            .navigationTitle("Edit Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Small delay to allow the view to appear before showing keyboard
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: MaintenanceTask.self, configurations: config)
    
    let task = MaintenanceTask(name: "Change HVAC Filter", description: "Replace air filter", frequency: .monthly)
    container.mainContext.insert(task)
    
    return NavigationStack {
        MaintenanceTaskDetailView(task: task)
    }
    .modelContainer(container)
}
