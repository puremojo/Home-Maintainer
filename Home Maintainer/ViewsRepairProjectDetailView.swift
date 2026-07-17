//
//  RepairProjectDetailView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct RepairProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var providers: [ServiceProvider]
    @Query private var allHomeDocuments: [HomeDocument]
    @Bindable var project: RepairProject

    @State private var isEditing = false
    @State private var showingAddContact = false
    @State private var showingAddQuote = false
    @State private var showingAddInvoice = false
    @State private var productEditorTarget: ProductEditorTarget?
    @State private var showingProjectDocumentPicker = false
    @State private var selectedProjectDocument: ProjectDocument?
    @State private var selectedLinkedHomeDocument: HomeDocument?
    @State private var showingAddSubTask = false
    @State private var showingAddWorkDate = false
    @State private var showingProviderPicker = false

    private var linkedHomeDocuments: [HomeDocument] {
        allHomeDocuments
            .filter { $0.linkedProjectIDs.contains(project.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var sortedSubTasks: [MaintenanceTask] {
        (project.subTasks ?? []).sorted { $0.name < $1.name }
    }

    private var sortedWorkDates: [ProjectWorkDate] {
        (project.workDates ?? []).sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var body: some View {
        List {
            Section("Project Details") {
                LabeledContent("Title", value: project.title)
                LabeledContent("Description", value: project.projectDescription)
                LabeledContent("Category", value: project.category.rawValue)

                Picker("Priority", selection: $project.priority) {
                    ForEach(ProjectPriority.allCases, id: \.self) { priority in
                        HStack {
                            Image(systemName: priority.systemImage)
                                .foregroundStyle(priority.color)
                            Text(priority.displayName)
                        }
                        .tag(priority)
                    }
                }

                Picker("Status", selection: $project.status) {
                    ForEach(ProjectStatus.allCases, id: \.self) { status in
                        Label(status.rawValue, systemImage: status.systemImage)
                            .tag(status)
                    }
                }

                if let totalCost = project.totalCost {
                    LabeledContent("Total Cost") {
                        Text(totalCost, format: .currency(code: "USD"))
                    }
                }

                if let startDate = project.startDate {
                    LabeledContent("Start Date") {
                        Text(startDate, format: .dateTime.month().day().year())
                    }
                }

                if let completionDate = project.completionDate {
                    LabeledContent("Completion Date") {
                        Text(completionDate, format: .dateTime.month().day().year())
                    }
                }
            }

            // Sub Tasks — shown right after Status
            Section {
                ForEach(sortedSubTasks) { subTask in
                    NavigationLink(destination: MaintenanceTaskDetailView(task: subTask)) {
                        SubTaskRowView(task: subTask)
                    }
                }
                .onDelete { offsets in
                    let tasks = sortedSubTasks
                    for index in offsets {
                        modelContext.delete(tasks[index])
                    }
                }

                Button {
                    showingAddSubTask = true
                } label: {
                    Label("Add Sub Task", systemImage: "plus.circle")
                }
            } header: {
                HStack {
                    Text("Sub Tasks")
                    Spacer()
                    Text("\(sortedSubTasks.count)")
                        .foregroundStyle(.secondary)
                }
            }

            // Work Dates
            Section {
                ForEach(sortedWorkDates) { workDate in
                    WorkDateRowView(workDate: workDate)
                }
                .onDelete { offsets in
                    let dates = sortedWorkDates
                    for index in offsets {
                        project.removeWorkDate(dates[index])
                    }
                }

                Button {
                    showingAddWorkDate = true
                } label: {
                    Label("Add Work Date", systemImage: "calendar.badge.plus")
                }
            } header: {
                Text("Work Dates")
            }

            Section {
                if let hp = project.hiredProvider {
                    let cleanPhone = hp.phoneNumber.filter { "0123456789+".contains($0) }
                    NavigationLink(destination: ServiceProviderDetailView(provider: hp)) {
                        HStack(spacing: 10) {
                            Image(systemName: hp.category.systemImage)
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hp.name).font(.headline)
                                if !hp.phoneNumber.isEmpty {
                                    Text(hp.phoneNumber).font(.caption).foregroundStyle(.secondary)
                                }
                                if !hp.address.isEmpty {
                                    Text(hp.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                    if !hp.phoneNumber.isEmpty, let url = URL(string: "tel:\(cleanPhone)") {
                        LabeledContent("Call") {
                            Link(hp.phoneNumber, destination: url).foregroundStyle(.blue)
                        }
                    }
                    if !hp.website.isEmpty {
                        let urlStr = hp.website.hasPrefix("http") ? hp.website : "https://\(hp.website)"
                        if let url = URL(string: urlStr) {
                            LabeledContent("Website") {
                                Link(hp.website, destination: url).foregroundStyle(.blue).lineLimit(1)
                            }
                        }
                    }
                    if let rating = hp.googleRating {
                        LabeledContent("Rating") {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                                Text(String(format: "%.1f", rating))
                            }
                        }
                    }
                    Button("Change Provider", role: .destructive) {
                        project.hiredProvider = nil
                    }
                } else {
                    Button {
                        showingProviderPicker = true
                    } label: {
                        Label("Select Hired Provider", systemImage: "person.badge.plus")
                    }
                }
            } header: {
                Text("Hired Provider")
            }

            Section {
                ForEach(project.contacts ?? []) { contact in
                    ContactRowView(contact: contact)
                }

                Button {
                    showingAddContact = true
                } label: {
                    Label("Add Contact Record", systemImage: "plus.circle")
                }
            } header: {
                HStack {
                    Text("Contacts")
                    Spacer()
                    Text("\((project.contacts ?? []).count)")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(project.quotes ?? []) { quote in
                    QuoteRowView(quote: quote)
                }

                Button {
                    showingAddQuote = true
                } label: {
                    Label("Add Quote", systemImage: "plus.circle")
                }
            } header: {
                HStack {
                    Text("Quotes")
                    Spacer()
                    if let quotes = project.quotes, !quotes.isEmpty {
                        Text("\(quotes.count) • Total: \(project.totalQuotedAmount, format: .currency(code: "USD"))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("0")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Invoice") {
                if let invoice = project.invoice {
                    InvoiceRowView(invoice: invoice)
                } else {
                    Button {
                        showingAddInvoice = true
                    } label: {
                        Label("Add Invoice", systemImage: "plus.circle")
                    }
                }
            }

            LiveProductsSection(
                products: project.products ?? [],
                detach: { $0.project = nil },
                onAdd: { productEditorTarget = .add },
                onEdit: { productEditorTarget = .edit($0) }
            )

            Section {
                ForEach(project.projectDocuments ?? []) { document in
                    Button {
                        selectedProjectDocument = document
                    } label: {
                        HStack {
                            Image(systemName: document.systemImage)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                HStack {
                                    Text(document.fileExtension.uppercased())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(document.dateAdded, format: .dateTime.month().day().year())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(document.data.count), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let docs = project.projectDocuments ?? []
                    for index in offsets {
                        project.removeDocument(docs[index])
                    }
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
                    showingProjectDocumentPicker = true
                } label: {
                    Label("Add Document", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Documents")
            } footer: {
                Text("Attach files related to this project.")
            }

            if !project.notes.isEmpty {
                Section("Notes") {
                    LinkedText(text: project.notes)
                }
            }
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditRepairProjectView(project: project)
        }
        .sheet(isPresented: $showingAddSubTask) {
            AddProjectSubTaskView(project: project)
        }
        .sheet(isPresented: $showingAddWorkDate) {
            AddWorkDateView(project: project)
        }
        .sheet(isPresented: $showingAddContact) {
            AddProjectContactView(project: project)
        }
        .sheet(isPresented: $showingAddQuote) {
            AddQuoteView(project: project)
        }
        .sheet(isPresented: $showingAddInvoice) {
            AddInvoiceView(project: project)
        }
        .sheet(item: $productEditorTarget) { target in
            ProductEditorSheet(target: target, attach: { $0.project = project })
        }
        .sheet(isPresented: $showingProjectDocumentPicker) {
            AddDocumentSheet { title, fileName, data, contentType in
                project.addDocument(name: fileName, data: data, contentType: contentType, title: title)
            }
        }
        .sheet(item: $selectedProjectDocument) { doc in
            GenericDocumentViewer(name: doc.name, data: doc.data, contentType: doc.contentType)
        }
        .sheet(item: $selectedLinkedHomeDocument) { doc in
            GenericDocumentViewer(
                name: doc.attachmentName ?? doc.title,
                data: doc.attachmentData ?? Data(),
                contentType: doc.attachmentContentType ?? ""
            )
        }
        .sheet(isPresented: $showingProviderPicker) {
            ProviderPickerSheet(home: project.home) { provider in
                project.hiredProvider = provider
            }
        }
    }
}

struct SubTaskRowView: View {
    let task: MaintenanceTask

    var isDone: Bool { task.lastCompleted != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(isDone, color: .gray)
                    .foregroundStyle(isDone ? .secondary : .primary)

                Spacer()

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
        }
    }
}

struct WorkDateRowView: View {
    let workDate: ProjectWorkDate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !workDate.label.isEmpty {
                Text(workDate.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack {
                Text(workDate.scheduledDate, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let duration = workDate.formattedDuration {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ContactRowView: View {
    let contact: ProjectContact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let provider = contact.provider {
                HStack {
                    Text(provider.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if contact.wasHired {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            HStack {
                Text(contact.contactDate, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(contact.method.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !contact.notes.isEmpty {
                LinkedText(text: contact.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct QuoteRowView: View {
    let quote: Quote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let provider = quote.provider {
                    Text(provider.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                Text(quote.amount, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(quote.wasAccepted ? .green : .primary)
            }

            HStack {
                Text(quote.quoteDate, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if quote.wasAccepted {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Accepted")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if !quote.details.isEmpty {
                Text(quote.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InvoiceRowView: View {
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let provider = invoice.provider {
                    Text(provider.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                Text(invoice.amount, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            HStack {
                Text(invoice.invoiceDate, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if invoice.isPaid {
                    Text("Paid")
                        .font(.caption)
                        .foregroundStyle(.green)

                    if let paidDate = invoice.paidDate {
                        Text(paidDate, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Unpaid")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !invoice.details.isEmpty {
                Text(invoice.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Add Sub Task

struct AddProjectSubTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: RepairProject

    @State private var name = ""
    @State private var taskDescription = ""
    @State private var productDrafts: [ProductDraft] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Information") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $taskDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                DraftProductsSection(drafts: $productDrafts)
            }
            .navigationTitle("New Sub Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSubTask()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addSubTask() {
        let task = MaintenanceTask(
            name: name,
            description: taskDescription,
            frequency: .once
        )
        task.home = project.home
        task.homeIDString = project.homeIDString
        task.sourceProject = project
        task.sourceProjectIDString = project.id.uuidString
        modelContext.insert(task)

        for draft in productDrafts where !draft.isEmpty {
            let product = ProductLink(name: draft.name, urlString: draft.urlString, imageData: draft.imageData)
            product.task = task
            modelContext.insert(product)
        }

        dismiss()
    }
}

// MARK: - Add Work Date

struct AddWorkDateView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var project: RepairProject

    @State private var label = ""
    @State private var scheduledDate = Date()
    @State private var hasDuration = false
    @State private var durationDays = 0
    @State private var durationHours = 0
    @State private var durationMinutes = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Work Date") {
                    TextField("Label (e.g. Scheduled Installation)", text: $label)
                    DatePicker("Date & Time", selection: $scheduledDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Duration") {
                    Toggle("Set Duration", isOn: $hasDuration)

                    if hasDuration {
                        Stepper("Days: \(durationDays)", value: $durationDays, in: 0...365)
                        Stepper("Hours: \(durationHours)", value: $durationHours, in: 0...23)
                        Stepper("Minutes: \(durationMinutes)", value: $durationMinutes, in: 0...55, step: 5)
                    }
                }
            }
            .navigationTitle("Add Work Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addWorkDate() }
                }
            }
        }
    }

    private func addWorkDate() {
        let days = hasDuration ? durationDays : 0
        let totalMinutes = hasDuration ? (durationHours * 60 + durationMinutes) : 0
        let workDate = ProjectWorkDate(
            label: label,
            scheduledDate: scheduledDate,
            durationDays: days,
            durationMinutes: totalMinutes
        )

        if project.workDates == nil { project.workDates = [] }
        project.workDates?.append(workDate)

        let title = project.title
        Task {
            await CalendarService.shared.addWorkDateEvent(workDate: workDate, projectTitle: title)
        }

        dismiss()
    }
}

// MARK: - Edit Project

struct EditRepairProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: RepairProject

    @State private var totalCostText = ""

    init(project: RepairProject) {
        self.project = project
        _totalCostText = State(initialValue: project.totalCost.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Information") {
                    TextField("Title", text: $project.title)
                    TextField("Description", text: $project.projectDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Details") {
                    Picker("Category", selection: $project.category) {
                        ForEach(ServiceCategory.allCases, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }

                    Picker("Priority", selection: $project.priority) {
                        ForEach(ProjectPriority.allCases, id: \.self) { priority in
                            HStack {
                                Image(systemName: priority.systemImage)
                                    .foregroundStyle(priority.color)
                                Text(priority.displayName)
                            }
                            .tag(priority)
                        }
                    }

                    Picker("Status", selection: $project.status) {
                        ForEach(ProjectStatus.allCases, id: \.self) { status in
                            Label(status.rawValue, systemImage: status.systemImage)
                                .tag(status)
                        }
                    }
                }

                Section("Cost") {
                    HStack {
                        Text("Total Cost")
                        Spacer()
                        TextField("$0.00", text: $totalCostText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Dates") {
                    DatePicker(
                        "Start Date",
                        selection: Binding(
                            get: { project.startDate ?? Date() },
                            set: { project.startDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    DatePicker(
                        "Completion Date",
                        selection: Binding(
                            get: { project.completionDate ?? Date() },
                            set: { project.completionDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }

                Section("Notes") {
                    TextField("Notes", text: $project.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        project.totalCost = Double(totalCostText)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RepairProject.self, configurations: config)

    let project = RepairProject(
        title: "Fix Leaking Pipe",
        description: "Bathroom sink has a leak",
        category: .plumber
    )
    container.mainContext.insert(project)

    return NavigationStack {
        RepairProjectDetailView(project: project)
    }
    .modelContainer(container)
}
