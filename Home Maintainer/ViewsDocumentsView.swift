//
//  ViewsDocumentsView.swift
//  Home Maintainer
//

import SwiftUI
import SwiftData

// MARK: - Search Result Model

private enum DocumentSearchHit: Identifiable {
    case home(HomeDocument, sectionName: String)
    case appliance(ApplianceDocument, Appliance)
    case project(ProjectDocument, RepairProject)

    var id: UUID {
        switch self {
        case .home(let d, _): return d.id
        case .appliance(let d, _): return d.id
        case .project(let d, _): return d.id
        }
    }

    var displayTitle: String {
        switch self {
        case .home(let d, _): return d.title.isEmpty ? (d.attachmentName ?? "Untitled") : d.title
        case .appliance(let d, _): return d.displayName
        case .project(let d, _): return d.displayName
        }
    }

    var contextLabel: String {
        switch self {
        case .home(_, let section): return section
        case .appliance(_, let a): return a.name
        case .project(_, let p): return p.title
        }
    }

    var systemImage: String {
        switch self {
        case .home(let d, _): return d.systemImage
        case .appliance(let d, _): return d.systemImage
        case .project(let d, _): return d.systemImage
        }
    }
}

// MARK: - Root Documents View

struct DocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeManager.self) private var homeManager
    @Query(sort: \DocumentSection.createdAt) private var allSections: [DocumentSection]
    @Query(sort: \Appliance.name) private var allAppliances: [Appliance]
    @Query(sort: \RepairProject.title) private var allProjects: [RepairProject]
    @Query(sort: \MaintenanceTask.name) private var allTasks: [MaintenanceTask]
    @Query private var allHomeDocuments: [HomeDocument]
    @State private var showingAddSection = false
    @State private var showingHomePicker = false
    @State private var searchText = ""

    private var sections: [DocumentSection] {
        guard let home = homeManager.currentHome else { return [] }
        return allSections.filter { $0.homeIDString == home.id.uuidString }
    }

    private var appliancesWithDocuments: [Appliance] {
        guard let home = homeManager.currentHome else { return [] }
        return allAppliances.filter {
            $0.homeIDString == home.id.uuidString &&
            (!($0.documents ?? []).isEmpty || !($0.homeDocuments ?? []).isEmpty)
        }
    }

    private var homeDocuments: [HomeDocument] {
        guard let home = homeManager.currentHome else { return [] }
        return allHomeDocuments.filter { $0.homeIDString == home.id.uuidString }
    }

    private var projectsWithDocuments: [RepairProject] {
        guard let home = homeManager.currentHome else { return [] }
        let linkedProjectIDs = Set(homeDocuments.flatMap { $0.linkedProjectIDs })
        return allProjects.filter {
            $0.homeIDString == home.id.uuidString &&
            (!($0.projectDocuments ?? []).isEmpty || linkedProjectIDs.contains($0.id))
        }
    }

    private var tasksWithLinkedDocuments: [MaintenanceTask] {
        guard let home = homeManager.currentHome else { return [] }
        let linkedTaskIDs = Set(homeDocuments.flatMap { $0.linkedTaskIDs })
        return allTasks.filter { $0.homeIDString == home.id.uuidString && linkedTaskIDs.contains($0.id) }
    }

    private var searchResults: [DocumentSearchHit] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        var results: [DocumentSearchHit] = []
        var seenIDs = Set<UUID>()

        // Search HomeDocuments within user sections
        for section in sections {
            let sectionMatches = section.name.lowercased().contains(query)
            for doc in (section.documents ?? []) {
                guard !seenIDs.contains(doc.id) else { continue }
                let titleMatches = doc.title.lowercased().contains(query)
                let fileMatches = (doc.attachmentName ?? "").lowercased().contains(query)
                if sectionMatches || titleMatches || fileMatches {
                    results.append(.home(doc, sectionName: section.name))
                    seenIDs.insert(doc.id)
                }
            }
        }

        // Search ApplianceDocuments and linked HomeDocuments, deduplicated by ID
        for appliance in appliancesWithDocuments {
            let applianceMatches = appliance.name.lowercased().contains(query)
            for doc in (appliance.documents ?? []) {
                guard !seenIDs.contains(doc.id) else { continue }
                let displayMatches = doc.displayName.lowercased().contains(query)
                let fileMatches = doc.name.lowercased().contains(query)
                if applianceMatches || displayMatches || fileMatches {
                    results.append(.appliance(doc, appliance))
                    seenIDs.insert(doc.id)
                }
            }
            // HomeDocuments linked to this appliance (section cleared, so not found via sections loop)
            for doc in (appliance.homeDocuments ?? []) {
                guard !seenIDs.contains(doc.id) else { continue }
                let displayTitle = doc.title.isEmpty ? (doc.attachmentName ?? "") : doc.title
                let titleMatches = displayTitle.lowercased().contains(query)
                let fileMatches = (doc.attachmentName ?? "").lowercased().contains(query)
                if applianceMatches || titleMatches || fileMatches {
                    results.append(.home(doc, sectionName: appliance.name))
                    seenIDs.insert(doc.id)
                }
            }
        }

        // Search ProjectDocuments
        for project in projectsWithDocuments {
            let projectMatches = project.title.lowercased().contains(query)
            for doc in (project.projectDocuments ?? []) {
                guard !seenIDs.contains(doc.id) else { continue }
                let displayMatches = doc.displayName.lowercased().contains(query)
                let fileMatches = doc.name.lowercased().contains(query)
                if projectMatches || displayMatches || fileMatches {
                    results.append(.project(doc, project))
                    seenIDs.insert(doc.id)
                }
            }
        }

        return results
    }

    var body: some View {
        Group {
            if homeManager.currentHome == nil {
                ContentUnavailableView {
                    Label("No Home Selected", systemImage: "house")
                } description: {
                    Text("Create or select a home to manage documents.")
                } actions: {
                    Button("Select Home") { showingHomePicker = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if !searchText.isEmpty {
                searchResultsList
            } else if sections.isEmpty && appliancesWithDocuments.isEmpty && projectsWithDocuments.isEmpty && tasksWithLinkedDocuments.isEmpty {
                ContentUnavailableView {
                    Label("No Documents", systemImage: "folder")
                } description: {
                    Text("Tap + to create a section and start organizing your home documents.")
                } actions: {
                    Button("Add Section") { showingAddSection = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    // Auto-generated Appliances folder
                    if !appliancesWithDocuments.isEmpty {
                        NavigationLink(destination: AppliancesFolderView(appliances: appliancesWithDocuments)) {
                            FolderRow(name: "Appliances", systemImage: "refrigerator",
                                      count: appliancesWithDocuments.reduce(0) {
                                          $0 + ($1.documents?.count ?? 0) + ($1.homeDocuments?.count ?? 0)
                                      })
                        }
                    }

                    // Auto-generated Tasks folder
                    if !tasksWithLinkedDocuments.isEmpty {
                        NavigationLink(destination: TasksFolderView(tasks: tasksWithLinkedDocuments)) {
                            let count = homeDocuments.filter { !$0.linkedTaskIDs.isEmpty }.count
                            FolderRow(name: "Tasks", systemImage: "checklist", count: count)
                        }
                    }

                    // Auto-generated Projects folder
                    if !projectsWithDocuments.isEmpty {
                        let projectDocCount = projectsWithDocuments.reduce(0) { $0 + ($1.projectDocuments?.count ?? 0) }
                        let homeDocProjectCount = homeDocuments.filter { !$0.linkedProjectIDs.isEmpty }.count
                        NavigationLink(destination: ProjectsFolderView(projects: projectsWithDocuments)) {
                            FolderRow(name: "Projects", systemImage: "hammer",
                                      count: projectDocCount + homeDocProjectCount)
                        }
                    }

                    // User-created section folders
                    ForEach(sections) { section in
                        let sectionIDStr = section.id.uuidString
                        // Use scalar-only filter — accessing section?.id in-memory crashes on shared-store docs.
                        let count = allHomeDocuments.filter { $0.sectionIDString == sectionIDStr }.count
                        NavigationLink(destination: DocumentSectionFolderView(section: section, home: homeManager.currentHome)) {
                            FolderRow(name: section.name, systemImage: "folder.fill", count: count)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { sections[$0] }.forEach { modelContext.delete($0) }
                    }
                }
            }
        }
        .navigationTitle("Documents")
        .searchable(text: $searchText, prompt: "Search documents")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HomePickerButton(showingPicker: $showingHomePicker)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSection = true } label: {
                    Label("Add Section", systemImage: "plus")
                }
                .disabled(homeManager.currentHome == nil)
            }
        }
        .sheet(isPresented: $showingAddSection) {
            AddDocumentSectionView(home: homeManager.currentHome)
        }
        .sheet(isPresented: $showingHomePicker) {
            HomePickerView()
        }
    }

    private var searchResultsList: some View {
        Group {
            if searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(searchResults) { hit in
                    NavigationLink {
                        switch hit {
                        case .home(let doc, _):
                            HomeDocumentDetailView(document: doc)
                        case .appliance(let doc, let appliance):
                            ApplianceDocumentsFolderView(appliance: appliance, highlightDocumentID: doc.id)
                        case .project(let doc, let project):
                            ProjectDocumentsFolderView(project: project, highlightDocumentID: doc.id)
                        }
                    } label: {
                        DocumentRowView(
                            name: hit.displayTitle,
                            systemImage: hit.systemImage,
                            subtitle: hit.contextLabel
                        )
                    }
                }
            }
        }
    }
}

private struct FolderRow: View {
    let name: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                Text("\(count) \(count == 1 ? "document" : "documents")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - User Section Folder

struct DocumentSectionFolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var section: DocumentSection
    let home: Home?
    @State private var showingAddDocument = false
    @Query private var documents: [HomeDocument]

    init(section: DocumentSection, home: Home?) {
        self.section = section
        self.home = home
        let sectionIDStr = section.id.uuidString
        let sectionID = section.id
        // Match by sectionIDString scalar (new docs) OR by the section relationship (pre-existing docs).
        // Both comparisons are evaluated at SQL level by #Predicate — safe for shared-store objects.
        _documents = Query(
            filter: #Predicate<HomeDocument> { doc in
                doc.sectionIDString == sectionIDStr || doc.section?.id == sectionID
            },
            sort: \HomeDocument.createdAt
        )
    }

    var body: some View {
        List {
            ForEach(documents) { document in
                NavigationLink(destination: HomeDocumentDetailView(document: document)) {
                    DocumentRowView(name: document.title.isEmpty ? "Untitled Document" : document.title,
                                    systemImage: document.systemImage,
                                    subtitle: document.attachmentName)
                }
            }
            .onDelete { offsets in
                offsets.map { documents[$0] }.forEach { modelContext.delete($0) }
            }

            Button {
                showingAddDocument = true
            } label: {
                Label("Add Document", systemImage: "plus.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .navigationTitle(section.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddDocument) {
            AddHomeDocumentView(section: section, home: home)
        }
    }
}

// MARK: - Appliances Folder (top-level, each appliance is its own sub-folder)

struct AppliancesFolderView: View {
    let appliances: [Appliance]

    var body: some View {
        List {
            ForEach(appliances) { appliance in
                if !appliance.isDeleted {
                    NavigationLink(destination: ApplianceDocumentsFolderView(appliance: appliance)) {
                        HStack(spacing: 14) {
                            ApplianceIconView(appliance: appliance, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appliance.name)
                                    .font(.body)
                                let count = (appliance.documents?.count ?? 0) + (appliance.homeDocuments?.count ?? 0)
                                Text("\(count) \(count == 1 ? "document" : "documents")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Appliances")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Single Appliance Documents Folder

struct ApplianceDocumentsFolderView: View {
    @Environment(NavigationCoordinator.self) private var coordinator
    let appliance: Appliance
    var highlightDocumentID: UUID? = nil
    @State private var selectedDocument: ApplianceDocument?
    @State private var selectedHomeDocument: HomeDocument?

    private var documents: [ApplianceDocument] {
        appliance.documents ?? []
    }

    private var linkedHomeDocuments: [HomeDocument] {
        (appliance.homeDocuments ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        List {
            if documents.isEmpty && linkedHomeDocuments.isEmpty {
                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc",
                    description: Text("Documents added to this appliance will appear here.")
                )
            } else {
                ForEach(documents) { document in
                    Button {
                        selectedDocument = document
                    } label: {
                        DocumentRowView(name: document.displayName,
                                        systemImage: document.systemImage,
                                        subtitle: document.displayName == document.name ? nil : document.name)
                    }
                    .foregroundStyle(.primary)
                }

                ForEach(linkedHomeDocuments) { doc in
                    Button {
                        selectedHomeDocument = doc
                    } label: {
                        DocumentRowView(
                            name: doc.title.isEmpty ? (doc.attachmentName ?? "Untitled") : doc.title,
                            systemImage: doc.systemImage,
                            subtitle: doc.title.isEmpty ? nil : doc.attachmentName
                        )
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section {
                Button {
                    coordinator.selectedTab = "appliances"
                    coordinator.pendingAppliance = appliance
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Take me to this appliance")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationTitle(appliance.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = highlightDocumentID, selectedDocument == nil {
                selectedDocument = documents.first { $0.id == id }
            }
        }
        .sheet(item: $selectedDocument) { document in
            DocumentViewer(document: document)
        }
        .sheet(item: $selectedHomeDocument) { doc in
            GenericDocumentViewer(
                name: doc.attachmentName ?? doc.title,
                data: doc.attachmentData ?? Data(),
                contentType: doc.attachmentContentType ?? ""
            )
        }
    }
}

// MARK: - Shared Row View

struct DocumentRowView: View {
    let name: String
    let systemImage: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Tasks Folder (top-level, each task is its own sub-folder)

struct TasksFolderView: View {
    let tasks: [MaintenanceTask]
    @Query private var allHomeDocuments: [HomeDocument]

    var body: some View {
        List {
            ForEach(tasks) { task in
                if !task.isDeleted {
                    let docs = allHomeDocuments.filter { $0.linkedTaskIDs.contains(task.id) }
                    NavigationLink(destination: TaskDocumentsFolderView(task: task)) {
                        HStack(spacing: 14) {
                            Image(systemName: "checklist")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.name)
                                    .font(.body)
                                let count = docs.count
                                Text("\(count) \(count == 1 ? "document" : "documents")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Single Task Documents Folder

struct TaskDocumentsFolderView: View {
    @Environment(NavigationCoordinator.self) private var coordinator
    let task: MaintenanceTask
    @Query private var allHomeDocuments: [HomeDocument]
    @State private var selectedHomeDocument: HomeDocument?

    private var linkedDocuments: [HomeDocument] {
        allHomeDocuments
            .filter { $0.linkedTaskIDs.contains(task.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        List {
            if linkedDocuments.isEmpty {
                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc",
                    description: Text("Documents linked to this task will appear here.")
                )
            } else {
                ForEach(linkedDocuments) { doc in
                    Button {
                        selectedHomeDocument = doc
                    } label: {
                        DocumentRowView(
                            name: doc.title.isEmpty ? (doc.attachmentName ?? "Untitled") : doc.title,
                            systemImage: doc.systemImage,
                            subtitle: doc.title.isEmpty ? nil : doc.attachmentName
                        )
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section {
                Button {
                    coordinator.selectedTab = "tasks"
                    coordinator.pendingTask = task
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Take me to this task")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationTitle(task.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedHomeDocument) { doc in
            GenericDocumentViewer(
                name: doc.attachmentName ?? doc.title,
                data: doc.attachmentData ?? Data(),
                contentType: doc.attachmentContentType ?? ""
            )
        }
    }
}

// MARK: - Projects Folder (top-level, each project is its own sub-folder)

struct ProjectsFolderView: View {
    let projects: [RepairProject]
    @Query private var allHomeDocuments: [HomeDocument]

    var body: some View {
        List {
            ForEach(projects) { project in
                if !project.isDeleted {
                    NavigationLink(destination: ProjectDocumentsFolderView(project: project)) {
                        HStack(spacing: 14) {
                            Image(systemName: "hammer")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title)
                                    .font(.body)
                                let projDocs = project.projectDocuments?.count ?? 0
                                let homeDocs = allHomeDocuments.filter { $0.linkedProjectIDs.contains(project.id) }.count
                                let count = projDocs + homeDocs
                                Text("\(count) \(count == 1 ? "document" : "documents")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Single Project Documents Folder

struct ProjectDocumentsFolderView: View {
    @Environment(NavigationCoordinator.self) private var coordinator
    let project: RepairProject
    var highlightDocumentID: UUID? = nil
    @Query private var allHomeDocuments: [HomeDocument]
    @State private var selectedDocument: ProjectDocument?
    @State private var selectedHomeDocument: HomeDocument?

    private var documents: [ProjectDocument] {
        project.projectDocuments ?? []
    }

    private var linkedHomeDocuments: [HomeDocument] {
        allHomeDocuments
            .filter { $0.linkedProjectIDs.contains(project.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var isEmpty: Bool {
        documents.isEmpty && linkedHomeDocuments.isEmpty
    }

    var body: some View {
        List {
            if isEmpty {
                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc",
                    description: Text("Documents added to this project will appear here.")
                )
            } else {
                ForEach(documents) { document in
                    Button {
                        selectedDocument = document
                    } label: {
                        DocumentRowView(name: document.displayName,
                                        systemImage: document.systemImage,
                                        subtitle: document.displayName == document.name ? nil : document.name)
                    }
                    .foregroundStyle(.primary)
                }

                ForEach(linkedHomeDocuments) { doc in
                    Button {
                        selectedHomeDocument = doc
                    } label: {
                        DocumentRowView(
                            name: doc.title.isEmpty ? (doc.attachmentName ?? "Untitled") : doc.title,
                            systemImage: doc.systemImage,
                            subtitle: doc.title.isEmpty ? nil : doc.attachmentName
                        )
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section {
                Button {
                    coordinator.selectedTab = "projects"
                    coordinator.pendingProject = project
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Take me to this project")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = highlightDocumentID, selectedDocument == nil {
                selectedDocument = documents.first { $0.id == id }
            }
        }
        .sheet(item: $selectedDocument) { document in
            GenericDocumentViewer(name: document.name, data: document.data, contentType: document.contentType)
        }
        .sheet(item: $selectedHomeDocument) { doc in
            GenericDocumentViewer(
                name: doc.attachmentName ?? doc.title,
                data: doc.attachmentData ?? Data(),
                contentType: doc.attachmentContentType ?? ""
            )
        }
    }
}

// MARK: - Add Section Sheet

struct AddDocumentSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudSharingService.self) private var cloudSharingService
    let home: Home?

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Section Name (e.g. Warranties, Manuals)", text: $name)
                }
            }
            .navigationTitle("New Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let section = DocumentSection(name: name.trimmingCharacters(in: .whitespaces))
                        if let home, !cloudSharingService.isInSharedStore(entityName: "Home", id: home.id) {
                            section.home = home
                        }
                        section.homeIDString = home?.id.uuidString
                        modelContext.insert(section)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DocumentsView()
    }
    .modelContainer(for: [DocumentSection.self, HomeDocument.self, Appliance.self], inMemory: true)
    .environment(HomeManager())
    .environment(NavigationCoordinator())
}
