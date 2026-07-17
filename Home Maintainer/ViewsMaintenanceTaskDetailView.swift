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
    @Environment(NavigationCoordinator.self) private var coordinator
    @Query private var allAppliances: [Appliance]
    @Query private var allHomeDocuments: [HomeDocument]
    @Bindable var task: MaintenanceTask
    @State private var showingCloseSheet = false
    @State private var showingCloseOccurrenceSheet = false
    @State private var showingAppliancePicker = false
    @State private var showingEditTask = false
    @State private var editingRecord: MaintenanceRecord?
    @State private var productEditorTarget: ProductEditorTarget?
    @State private var showingTaskDocumentPicker = false
    @State private var selectedTaskDocument: TaskDocument?
    @State private var selectedLinkedHomeDocument: HomeDocument?

    private var isProjectSubTask: Bool { task.sourceProject != nil }

    private var isRepeating: Bool {
        if case .once = task.safeFrequency { return false }
        return true
    }

    private var linkedHomeDocuments: [HomeDocument] {
        allHomeDocuments
            .filter { $0.linkedTaskIDs.contains(task.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var isCompletedForCurrentCycle: Bool {
        guard let _ = task.lastCompleted, let nextDue = task.nextDue else { return false }
        return nextDue > Date()
    }

    var body: some View {
        List {
            if isProjectSubTask {
                subTaskSections
            } else {
                maintenanceTaskSections
            }
        }
        .navigationTitle(task.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isProjectSubTask {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEditTask = true }
                }
            }
        }
        .sheet(isPresented: $showingEditTask) {
            EditMaintenanceTaskView(task: task)
        }
        .sheet(isPresented: $showingCloseSheet) {
            CloseTaskSheet(task: task, isPermanent: true, modelContext: modelContext)
        }
        .sheet(isPresented: $showingCloseOccurrenceSheet) {
            CloseTaskSheet(task: task, isPermanent: false, modelContext: modelContext)
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
        .sheet(isPresented: $showingTaskDocumentPicker) {
            AddDocumentSheet { title, fileName, data, contentType in
                task.addDocument(name: fileName, data: data, contentType: contentType, title: title)
            }
        }
        .sheet(item: $selectedTaskDocument) { doc in
            GenericDocumentViewer(name: doc.name, data: doc.data, contentType: doc.contentType)
        }
        .sheet(item: $selectedLinkedHomeDocument) { doc in
            GenericDocumentViewer(
                name: doc.attachmentName ?? doc.title,
                data: doc.attachmentData ?? Data(),
                contentType: doc.attachmentContentType ?? ""
            )
        }
    }

    // MARK: - Sub-task view (name, description, products only)

    @ViewBuilder
    private var subTaskSections: some View {
        Section("Details") {
            LabeledContent("Name", value: task.name)
            if !task.taskDescription.isEmpty {
                LabeledContent("Description", value: task.taskDescription)
            }
        }

        LiveProductsSection(
            products: task.products ?? [],
            detach: { $0.task = nil },
            onAdd: { productEditorTarget = .add },
            onEdit: { productEditorTarget = .edit($0) }
        )

        Section {
            let isDone = task.lastCompleted != nil
            if isDone {
                Button {
                    task.lastCompleted = nil
                } label: {
                    Label("Reopen Task", systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                Button {
                    task.lastCompleted = Date()
                } label: {
                    Label("Close Task", systemImage: "checkmark.circle")
                }
            }
        }

        if let project = task.sourceProject {
            Section {
                Button {
                    coordinator.pendingProject = project
                    coordinator.selectedTab = "projects"
                } label: {
                    Label("Take me to this project", systemImage: "arrow.right.circle")
                }
            } header: {
                Text("Source Project: \(project.title)")
            }
        }
    }

    // MARK: - Regular maintenance task view

    @ViewBuilder
    private var maintenanceTaskSections: some View {
        Section("Details") {
            LabeledContent("Name", value: task.name)
            LabeledContent("Description", value: task.taskDescription)
            if !task.room.isEmpty {
                LabeledContent("Room", value: task.room)
            }
            LabeledContent("Frequency", value: task.frequencyDisplayName)

            LabeledContent("Linked Appliance") {
                Button {
                    showingAppliancePicker = true
                } label: {
                    HStack {
                        if let appliance = task.appliance {
                            ApplianceIconView(appliance: appliance, size: 30)
                            Text(appliance.name)
                        } else {
                            Text("None").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

            if !task.isActive {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox.fill").foregroundStyle(.secondary)
                        Text("Closed Task").foregroundStyle(.secondary)
                    }
                }
            } else if isCompletedForCurrentCycle, let lastCompleted = task.lastCompleted, let nextDue = task.nextDue {
                LabeledContent("Status") {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Occurrence closed \(lastCompleted, format: .dateTime.month().day().year())")
                                .foregroundStyle(.green)
                        }
                        Text("Next due \(nextDue, format: .dateTime.month().day().year())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        // Action buttons
        Section {
            if task.isActive {
                Button {
                    showingCloseSheet = true
                } label: {
                    Label("Close Task", systemImage: "checkmark.circle")
                }

                if isRepeating {
                    Button {
                        showingCloseOccurrenceSheet = true
                    } label: {
                        Label("Close Task Occurrence", systemImage: "checkmark.circle.badge.xmark")
                    }
                }
            } else {
                Button {
                    reopenTask()
                } label: {
                    Label("Reopen Task", systemImage: "arrow.uturn.backward.circle")
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
                                    .foregroundStyle(record.action.badgeColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(record.action.badgeColor.opacity(0.15))
                                    )
                            }

                            if !record.notes.isEmpty {
                                LinkedText(text: record.notes)
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
            ForEach(task.taskDocuments ?? []) { document in
                Button {
                    selectedTaskDocument = document
                } label: {
                    HStack {
                        Image(systemName: document.systemImage).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            HStack {
                                Text(document.fileExtension.uppercased())
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text("•").font(.caption2).foregroundStyle(.secondary)
                                Text(document.dateAdded, format: .dateTime.month().day().year())
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text("•").font(.caption2).foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(document.data.count), countStyle: .file))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let docs = task.taskDocuments ?? []
                for index in offsets { task.removeDocument(docs[index]) }
            }

            ForEach(linkedHomeDocuments) { doc in
                Button {
                    selectedLinkedHomeDocument = doc
                } label: {
                    DocumentRowView(
                        name: doc.title.isEmpty ? (doc.attachmentName ?? "Untitled") : doc.title,
                        systemImage: doc.systemImage,
                        subtitle: doc.title.isEmpty ? nil : doc.attachmentName
                    )
                }
                .foregroundStyle(.primary)
            }

            Button {
                showingTaskDocumentPicker = true
            } label: {
                Label("Add Document", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Documents")
        } footer: {
            Text("Attach files related to this task.")
        }

        Section {
            Toggle("Active", isOn: $task.isActive)
        }
    }

    private func reopenTask() {
        task.reopen()
        let record = MaintenanceRecord(task: task, completedDate: Date(), notes: "Task reopened", action: .reopened)
        modelContext.insert(record)
    }
}

// MARK: - Close Task Sheet (handles both permanent close and occurrence close)

struct CloseTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: MaintenanceTask
    let isPermanent: Bool
    let modelContext: ModelContext

    @State private var completionDate = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $completionDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isPermanent ? "Close Task" : "Close Occurrence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { complete() }
                }
            }
        }
    }

    private func complete() {
        if isPermanent {
            task.isActive = false
            task.lastCompleted = completionDate
        } else {
            task.markCompleted(on: completionDate)
        }
        let action: TaskAction = isPermanent ? .closed : .occurrenceClosed
        let record = MaintenanceRecord(task: task, completedDate: completionDate, notes: notes, action: action)
        modelContext.insert(record)
        dismiss()
    }
}

// MARK: - Supporting Views

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
                                Image(systemName: "checkmark").foregroundStyle(.blue)
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
                                    ApplianceIconView(appliance: appliance, size: 30)
                                    Text(appliance.name)
                                    Spacer()
                                    if task.appliance?.id == appliance.id {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
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
                    Button("Cancel") { dismiss() }
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isFocused = true }
            }
        }
    }
}

struct EditMaintenanceTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Appliance.name) private var appliances: [Appliance]
    @Bindable var task: MaintenanceTask

    @State private var name: String
    @State private var description: String
    @State private var room: String
    @State private var selectedFrequency: TaskFrequency
    @State private var selectedAppliance: Appliance?

    let predefinedFrequencies: [TaskFrequency] = [
        .once, .daily, .weekly, .biweekly, .monthly, .quarterly, .biannually, .annually
    ]

    init(task: MaintenanceTask) {
        self.task = task
        _name = State(initialValue: task.name)
        _description = State(initialValue: task.taskDescription)
        _room = State(initialValue: task.room)
        _selectedFrequency = State(initialValue: task.safeFrequency)
        _selectedAppliance = State(initialValue: task.appliance)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Information") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                RoomFieldSection(room: $room)

                Section("Frequency") {
                    Picker("Repeat", selection: $selectedFrequency) {
                        ForEach(predefinedFrequencies, id: \.displayName) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                }

                Section("Link to Appliance") {
                    Picker("Appliance", selection: $selectedAppliance) {
                        Text("None").tag(nil as Appliance?)
                        ForEach(appliances) { appliance in
                            HStack {
                                Image(systemName: appliance.type.systemImage)
                                Text(appliance.name)
                            }
                            .tag(appliance as Appliance?)
                        }
                    }
                    .disabled(appliances.isEmpty)

                    if appliances.isEmpty {
                        Text("No appliances added yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func saveChanges() {
        task.name = name
        task.taskDescription = description
        task.room = room
        task.appliance = selectedAppliance
        if task.safeFrequency != selectedFrequency {
            task.updateFrequency(selectedFrequency)
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
