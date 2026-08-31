//
//  MaintenanceTaskDetailView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import CoreData

struct MaintenanceTaskDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(NavigationCoordinator.self) private var coordinator
    @Environment(CloudSharingService.self) private var cloudSharingService
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var allAppliances: FetchedResults<Appliance>
    @FetchRequest(sortDescriptors: []) private var allHomeDocuments: FetchedResults<HomeDocument>
    var task: MaintenanceTask
    @State private var showingCloseSheet = false
    @State private var showingCloseOccurrenceSheet = false
    @State private var showingAppliancePicker = false
    @State private var showingEditTask = false
    @State private var editingRecord: MaintenanceRecord?
    @State private var productEditorTarget: ProductEditorTarget?
    @State private var showingTaskDocumentPicker = false
    @State private var selectedTaskDocument: TaskDocument?
    @State private var selectedLinkedHomeDocument: HomeDocument?
    @State private var sharedTaskDocuments: [TaskDocument] = []

    // Use the scalar mirror — accessing task.sourceProject directly on a shared-store
    // object triggers ModelContext.fulfill which crashes.
    private var isProjectSubTask: Bool { task.sourceProjectIDString != nil }

    // True when this task lives in the shared CloudKit store. Relationship properties
    // (appliance, records, products, sourceProject object) cannot be accessed on such
    // objects — only scalar properties and Codable blobs are safe.
    private var isSharedTask: Bool {
        cloudSharingService.isInSharedStore(entityName: "MaintenanceTask", id: task.id)
    }

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
            // Shared-store tasks must be handled first — accessing any relationship
            // property (appliance, records, products, sourceProject object) on a
            // shared-store object crashes via ModelContext.fulfill.
            if isSharedTask {
                sharedTaskSections
            } else if isProjectSubTask {
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
            EditMaintenanceTaskView(task: task, isSharedTask: isSharedTask)
        }
        .sheet(isPresented: $showingCloseSheet) {
            CloseTaskSheet(task: task, isPermanent: true)
        }
        .sheet(isPresented: $showingCloseOccurrenceSheet) {
            CloseTaskSheet(task: task, isPermanent: false)
        }
        .sheet(isPresented: $showingAppliancePicker) {
            SelectApplianceView(task: task, allAppliances: Array(allAppliances))
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
                try? viewContext.save()
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
        .task(id: task.id) {
            // Fetch taskDocuments for shared-store tasks via CoreData viewContext to
            // bypass ModelContext.fulfill, which crashes for shared-store objects.
            if isSharedTask {
                sharedTaskDocuments = cloudSharingService.fetchTaskDocuments(for: task.id)
            }
        }
    }

    // MARK: - Shared-store task view (scalars only — no @Relationship or Codable transformable reads)

    @ViewBuilder
    private var sharedTaskSections: some View {
        Section("Details") {
            LabeledContent("Name", value: task.name)
            if !task.taskDescription.isEmpty {
                LabeledContent("Description", value: task.taskDescription)
            }
            if !task.room.isEmpty {
                LabeledContent("Room", value: task.room)
            }
            LabeledContent("Frequency", value: task.frequencyDisplayName)
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
            }
        }

        Section {
            if task.isActive {
                Button { showingCloseSheet = true } label: {
                    Label("Close Task", systemImage: "checkmark.circle")
                }
                if isRepeating {
                    Button { showingCloseOccurrenceSheet = true } label: {
                        Label("Close Task Occurrence", systemImage: "checkmark.circle.badge.xmark")
                    }
                }
            } else {
                Button { sharedReopenTask() } label: {
                    Label("Reopen Task", systemImage: "arrow.uturn.backward.circle")
                }
            }
        }

        if !sharedTaskDocuments.isEmpty {
            Section("Documents") {
                ForEach(sharedTaskDocuments) { document in
                    Button {
                        selectedTaskDocument = document
                    } label: {
                        HStack {
                            Image(systemName: document.systemImage).foregroundStyle(.blue)
                            Text(document.displayName).font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Reopens a shared-store task using only safe scalar writes.
    /// Cannot call task.reopen() because it reads task.frequency (Codable transformable — crashes for shared-store objects).
    private func sharedReopenTask() {
        task.isActive = true
        task.lastCompleted = nil
        // updateFrequency reads self.lastCompleted (safe Date?) and sets scalar properties only.
        // We pass task.safeFrequency (decoded from frequencyEncoded string) to avoid
        // reading task.frequency (Codable transformable — crashes for shared-store objects).
        task.updateFrequency(task.safeFrequency)
        try? viewContext.save()
        cloudSharingService.insertMaintenanceRecord(
            taskID: task.id,
            completedDate: Date(),
            notes: "Task reopened",
            action: .reopened
        )
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
            products: task.productArray,
            detach: { $0.task = nil },
            onAdd: { productEditorTarget = .add },
            onEdit: { productEditorTarget = .edit($0) }
        )

        Section {
            let isDone = task.lastCompleted != nil
            if isDone {
                Button {
                    task.lastCompleted = nil
                    try? viewContext.save()
                } label: {
                    Label("Reopen Task", systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                Button {
                    task.lastCompleted = Date()
                    try? viewContext.save()
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

        let records = task.recordArray
        if !records.isEmpty {
            Section("History") {
                ForEach(records) { record in
                    Button {
                        editingRecord = record
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.completedDate, format: .dateTime.month().day().year().hour().minute())
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(record.taskAction.rawValue)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(record.taskAction.badgeColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(record.taskAction.badgeColor.opacity(0.15))
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
            products: task.productArray,
            detach: { $0.task = nil },
            onAdd: { productEditorTarget = .add },
            onEdit: { productEditorTarget = .edit($0) }
        )

        Section {
            ForEach(task.taskDocuments) { document in
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
                let docs = task.taskDocuments
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
            Toggle("Active", isOn: Binding(
                get: { task.isActive },
                set: { task.isActive = $0; try? viewContext.save() }
            ))
        }
    }

    private func reopenTask() {
        task.reopen()
        MaintenanceRecord.make(task: task, completedDate: Date(), notes: "Task reopened", action: .reopened, in: viewContext)
        try? viewContext.save()
    }
}

// MARK: - Close Task Sheet (handles both permanent close and occurrence close)

struct CloseTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(CloudSharingService.self) private var cloudSharingService
    let task: MaintenanceTask
    let isPermanent: Bool

    @State private var completionDate = Date()
    @State private var notes = ""

    private var isSharedTask: Bool {
        cloudSharingService.isInSharedStore(entityName: "MaintenanceTask", id: task.id)
    }

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
        let action: TaskAction = isPermanent ? .closed : .occurrenceClosed

        if isPermanent {
            task.isActive = false
            task.lastCompleted = completionDate
        } else {
            // Cannot call task.markCompleted() for shared-store tasks — it reads
            // task.frequency (Codable transformable) which crashes via ModelContext.fulfill.
            // Use safe scalar writes and safeFrequency (decoded from frequencyEncoded) instead.
            task.lastCompleted = completionDate
            task.nextDue = task.safeFrequency.nextDue(from: completionDate)
        }

        if isSharedTask {
            // Insert the record into the shared CloudKit zone so all participants see it.
            cloudSharingService.insertMaintenanceRecord(
                taskID: task.id,
                completedDate: completionDate,
                notes: notes,
                action: action
            )
        } else {
            MaintenanceRecord.make(task: task, completedDate: completionDate, notes: notes, action: action, in: viewContext)
        }
        try? viewContext.save()
        dismiss()
    }
}

// MARK: - Supporting Views

struct SelectApplianceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    let task: MaintenanceTask
    let allAppliances: [Appliance]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        task.appliance = nil
                        try? viewContext.save()
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
                                try? viewContext.save()
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
    @Environment(\.managedObjectContext) private var viewContext
    let record: MaintenanceRecord
    @State private var notes: String
    @FocusState private var isFocused: Bool

    init(record: MaintenanceRecord) {
        self.record = record
        _notes = State(initialValue: record.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Date") {
                        Text(record.completedDate, format: .dateTime.month().day().year().hour().minute())
                    }
                    LabeledContent("Action") {
                        Text(record.taskAction.rawValue)
                            .foregroundStyle(record.taskAction == .closed ? .green : .orange)
                    }
                }

                Section("Notes") {
                    TextField("Add notes about this completion...", text: $notes, axis: .vertical)
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
                    Button("Done") {
                        record.notes = notes
                        try? viewContext.save()
                        dismiss()
                    }
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
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var appliances: FetchedResults<Appliance>
    let task: MaintenanceTask
    let isSharedTask: Bool

    @State private var name: String
    @State private var description: String
    @State private var room: String
    @State private var selectedFrequency: TaskFrequency
    @State private var selectedAppliance: Appliance?

    let predefinedFrequencies: [TaskFrequency] = [
        .once, .daily, .weekly, .biweekly, .monthly, .quarterly, .biannually, .annually
    ]

    init(task: MaintenanceTask, isSharedTask: Bool) {
        self.task = task
        self.isSharedTask = isSharedTask
        _name = State(initialValue: task.name)
        _description = State(initialValue: task.taskDescription)
        _room = State(initialValue: task.room)
        _selectedFrequency = State(initialValue: task.safeFrequency)
        // task.appliance is a @Relationship — accessing it on a shared-store object
        // crashes via ModelContext.fulfill. Skip it; appliance links aren't editable
        // for shared tasks.
        _selectedAppliance = State(initialValue: isSharedTask ? nil : task.appliance)
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

                if !isSharedTask {
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
        // Skip appliance assignment for shared-store tasks — setting a @Relationship
        // triggers the inverse update which accesses the shared-store object and crashes.
        if !isSharedTask {
            task.appliance = selectedAppliance
        }
        if task.safeFrequency != selectedFrequency {
            task.updateFrequency(selectedFrequency)
        }
        try? viewContext.save()
    }
}

#Preview {
    Text("Preview unavailable")
}
