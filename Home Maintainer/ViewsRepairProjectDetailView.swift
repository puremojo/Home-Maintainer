//
//  RepairProjectDetailView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import CoreData

struct RepairProjectDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var providers: FetchedResults<ServiceProvider>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)]) private var allHomeDocuments: FetchedResults<HomeDocument>
    var project: RepairProject

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
        project.subTaskArray
    }

    private var sortedWorkDates: [ProjectWorkDate] {
        project.workDates.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var body: some View {
        List {
            Section("Project Details") {
                LabeledContent("Title", value: project.title)
                LabeledContent("Description", value: project.projectDescription)
                LabeledContent("Category", value: project.category.rawValue)

                Picker("Priority", selection: Binding(
                    get: { project.priority },
                    set: { project.priority = $0; try? viewContext.save() }
                )) {
                    ForEach(ProjectPriority.allCases, id: \.self) { priority in
                        HStack {
                            Image(systemName: priority.systemImage)
                                .foregroundStyle(priority.color)
                            Text(priority.displayName)
                        }
                        .tag(priority)
                    }
                }

                Picker("Status", selection: Binding(
                    get: { project.status },
                    set: { project.status = $0; try? viewContext.save() }
                )) {
                    ForEach(ProjectStatus.allCases, id: \.self) { status in
                        Label(status.rawValue, systemImage: status.systemImage)
                            .tag(status)
                    }
                }

                if project.totalCost > 0 {
                    LabeledContent("Total Cost") {
                        Text(project.totalCost, format: .currency(code: "USD"))
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
                        viewContext.delete(tasks[index])
                    }
                    try? viewContext.save()
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
                    try? viewContext.save()
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
                    if hp.googleRating > 0 {
                        LabeledContent("Rating") {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                                Text(String(format: "%.1f", hp.googleRating))
                            }
                        }
                    }
                    Button("Change Provider", role: .destructive) {
                        project.hiredProvider = nil
                        try? viewContext.save()
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
                ForEach(project.contactArray) { contact in
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
                    Text("\(project.contactArray.count)")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(project.quoteArray) { quote in
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
                    let quotes = project.quoteArray
                    if !quotes.isEmpty {
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
                products: project.productArray,
                detach: { $0.project = nil },
                onAdd: { productEditorTarget = .add },
                onEdit: { productEditorTarget = .edit($0) }
            )

            Section {
                ForEach(project.projectDocuments) { document in
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
                    let docs = project.projectDocuments
                    for index in offsets {
                        project.removeDocument(docs[index])
                    }
                    try? viewContext.save()
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
                try? viewContext.save()
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
    @Environment(\.managedObjectContext) private var viewContext
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
        let task = MaintenanceTask.make(
            name: name,
            description: taskDescription,
            frequency: .once,
            in: viewContext
        )
        task.home = project.home
        task.homeIDString = project.homeIDString
        task.sourceProject = project
        task.sourceProjectIDString = project.id.uuidString

        for draft in productDrafts where !draft.isEmpty {
            let product = ProductLink.make(
                name: draft.name,
                urlString: draft.urlString,
                imageData: draft.imageData,
                in: viewContext
            )
            product.task = task
        }

        try? viewContext.save()
        dismiss()
    }
}

// MARK: - Add Work Date

struct AddWorkDateView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    var project: RepairProject

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
        project.addWorkDate(
            label: workDate.label,
            scheduledDate: workDate.scheduledDate,
            durationDays: days,
            durationMinutes: totalMinutes
        )
        try? viewContext.save()

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
    @Environment(\.managedObjectContext) private var viewContext
    var project: RepairProject

    @State private var title: String
    @State private var projectDescription: String
    @State private var notes: String
    @State private var category: ServiceCategory
    @State private var priority: ProjectPriority
    @State private var status: ProjectStatus
    @State private var startDate: Date
    @State private var completionDate: Date
    @State private var totalCostText: String

    init(project: RepairProject) {
        self.project = project
        _title = State(initialValue: project.title)
        _projectDescription = State(initialValue: project.projectDescription)
        _notes = State(initialValue: project.notes)
        _category = State(initialValue: project.category)
        _priority = State(initialValue: project.priority)
        _status = State(initialValue: project.status)
        _startDate = State(initialValue: project.startDate ?? Date())
        _completionDate = State(initialValue: project.completionDate ?? Date())
        _totalCostText = State(initialValue: project.totalCost > 0 ? String(project.totalCost) : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Information") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $projectDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(ServiceCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage)
                                .tag(cat)
                        }
                    }

                    Picker("Priority", selection: $priority) {
                        ForEach(ProjectPriority.allCases, id: \.self) { p in
                            HStack {
                                Image(systemName: p.systemImage)
                                    .foregroundStyle(p.color)
                                Text(p.displayName)
                            }
                            .tag(p)
                        }
                    }

                    Picker("Status", selection: $status) {
                        ForEach(ProjectStatus.allCases, id: \.self) { s in
                            Label(s.rawValue, systemImage: s.systemImage)
                                .tag(s)
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
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    DatePicker(
                        "Completion Date",
                        selection: $completionDate,
                        displayedComponents: .date
                    )
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        project.title = title
                        project.projectDescription = projectDescription
                        project.notes = notes
                        project.category = category
                        project.priority = priority
                        project.status = status
                        project.startDate = startDate
                        project.completionDate = completionDate
                        project.totalCost = Double(totalCostText) ?? 0
                        try? viewContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let model = AppDataModel.buildModel()
    let container = NSPersistentContainer(name: "Preview", managedObjectModel: model)
    let desc = NSPersistentStoreDescription()
    desc.type = NSInMemoryStoreType
    container.persistentStoreDescriptions = [desc]
    container.loadPersistentStores { _, _ in }
    let ctx = container.viewContext

    let project = RepairProject(context: ctx)
    project.id = UUID()
    project.title = "Fix Leaking Pipe"
    project.projectDescription = "Bathroom sink has a leak"
    project.category = .plumber
    project.priority = .medium
    project.status = .planning
    project.notes = ""
    project.createdAt = Date()
    try? ctx.save()

    return NavigationStack {
        RepairProjectDetailView(project: project)
    }
    .environment(\.managedObjectContext, ctx)
}
