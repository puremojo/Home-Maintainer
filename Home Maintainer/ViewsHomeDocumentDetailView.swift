//
//  ViewsHomeDocumentDetailView.swift
//  Home Maintainer
//

import SwiftUI
import SwiftData
import PDFKit
import VisionKit

// MARK: - Document Text Extraction

/// Extracts readable text from a document's raw data.
/// Returns nil for binary formats that aren't PDF or plain text.
func extractDocumentText(data: Data, contentType: String) -> String? {
    let ct = contentType.lowercased()
    if ct.contains("pdf") || ct == "pdf" {
        return PDFDocument(data: data)?.string
    } else if ct.contains("text") || ct == "txt" || ct == "plain" {
        return String(data: data, encoding: .utf8)
    }
    return nil
}

// MARK: - Detail View

struct HomeDocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeManager.self) private var homeManager
    @Environment(CloudSharingService.self) private var cloudSharingService
    @Query(sort: \MaintenanceTask.name) private var allTasks: [MaintenanceTask]
    @Query(sort: \Appliance.name) private var allAppliances: [Appliance]
    @Query(sort: \RepairProject.title) private var allProjects: [RepairProject]
    @Bindable var document: HomeDocument

    @State private var showingDocumentPicker = false
    @State private var showingAttachment = false
    @State private var showingTaskPicker = false
    @State private var showingProjectPicker = false
    @State private var showingAppliancePicker = false
    @State private var showingScanner = false

    private var homeTasks: [MaintenanceTask] {
        guard let home = homeManager.currentHome else { return [] }
        return allTasks.filter { $0.homeIDString == home.id.uuidString }
    }

    private var homeAppliances: [Appliance] {
        guard let home = homeManager.currentHome else { return [] }
        return allAppliances.filter { $0.homeIDString == home.id.uuidString }
    }

    private var homeProjects: [RepairProject] {
        guard let home = homeManager.currentHome else { return [] }
        return allProjects.filter { $0.homeIDString == home.id.uuidString }
    }

    private var linkedTasks: [MaintenanceTask] {
        homeTasks.filter { document.linkedTaskIDs.contains($0.id) }
    }

    private var linkedProjects: [RepairProject] {
        homeProjects.filter { document.linkedProjectIDs.contains($0.id) }
    }

    private var applianceBinding: Binding<Appliance?> {
        Binding(
            get: { document.linkedAppliance },
            set: { newValue in
                document.linkedAppliance = newValue
                if newValue != nil {
                    document.section = nil
                }
            }
        )
    }

    var body: some View {
        List {
            Section("Title") {
                TextField("Document Title", text: $document.title)
            }

            Section {
                if let attachmentName = document.attachmentName, let data = document.attachmentData {
                    Button {
                        showingAttachment = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: document.systemImage)
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(attachmentName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                HStack {
                                    Text(document.fileExtension.uppercased())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "eye")
                                .foregroundStyle(.blue)
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            document.attachmentData = nil
                            document.attachmentName = nil
                            document.attachmentContentType = nil
                        }
                    }
                }

                Button {
                    showingDocumentPicker = true
                } label: {
                    Label(
                        document.attachmentData == nil ? "Attach File" : "Replace Attachment",
                        systemImage: "paperclip"
                    )
                }
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        showingScanner = true
                    } label: {
                        Label(
                            document.attachmentData == nil ? "Scan Document" : "Re-scan Document",
                            systemImage: "doc.viewfinder"
                        )
                    }
                }
            } header: {
                Text("Attachment")
            } footer: {
                if document.attachmentData == nil {
                    Text("Attach a PDF, Word document, or text file. Tap to view once attached.")
                }
            }

            Section {
                if let appliance = document.linkedAppliance {
                    NavigationLink(destination: ApplianceDetailView(appliance: appliance)) {
                        ApplianceRow(appliance: appliance)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            document.linkedAppliance = nil
                        }
                    }
                }

                Button {
                    showingAppliancePicker = true
                } label: {
                    Label(
                        document.linkedAppliance == nil ? "Link Appliance" : "Change Appliance",
                        systemImage: "plus"
                    )
                }
            } header: {
                Text("Linked Appliance")
            }

            Section {
                ForEach(linkedTasks) { task in
                    NavigationLink(destination: MaintenanceTaskDetailView(task: task)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.name)
                                .font(.subheadline)
                            Text(task.frequencyDisplayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let idsToRemove = offsets.map { linkedTasks[$0].id }
                    document.linkedTaskIDs.removeAll { idsToRemove.contains($0) }
                }

                Button {
                    showingTaskPicker = true
                } label: {
                    Label("Link Task", systemImage: "plus")
                }
            } header: {
                Text("Linked Tasks")
            }

            Section {
                ForEach(linkedProjects) { project in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.title)
                            .font(.subheadline)
                        Text(project.status.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    let idsToRemove = offsets.map { linkedProjects[$0].id }
                    document.linkedProjectIDs.removeAll { idsToRemove.contains($0) }
                }

                Button {
                    showingProjectPicker = true
                } label: {
                    Label("Link Project", systemImage: "plus")
                }
            } header: {
                Text("Linked Projects")
            }
        }
        .navigationTitle(document.title.isEmpty ? "Document" : document.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { url, name in
                addAttachment(from: url, name: name)
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView { images in
                if let pdfData = scannedImagesToPDF(images) {
                    document.attachmentData = pdfData
                    document.attachmentName = "Scanned Document.pdf"
                    document.attachmentContentType = "pdf"
                }
                showingScanner = false
            } onCancel: {
                showingScanner = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingAttachment) {
            if let name = document.attachmentName, let data = document.attachmentData, let contentType = document.attachmentContentType {
                GenericDocumentViewer(name: name, data: data, contentType: contentType)
            }
        }
        .sheet(isPresented: $showingTaskPicker) {
            SelectTasksForDocumentView(selectedTaskIDs: $document.linkedTaskIDs, tasks: homeTasks)
        }
        .sheet(isPresented: $showingProjectPicker) {
            SelectProjectsForDocumentView(selectedProjectIDs: $document.linkedProjectIDs, projects: homeProjects)
        }
        .sheet(isPresented: $showingAppliancePicker) {
            SelectApplianceForDocumentView(selectedAppliance: applianceBinding, appliances: homeAppliances)
        }
    }

    private func addAttachment(from url: URL, name: String) {
        guard let data = try? Data(contentsOf: url) else { return }
        document.attachmentData = data
        document.attachmentName = name
        document.attachmentContentType = url.pathExtension
    }
}

// MARK: - Add Document Sheet

struct AddHomeDocumentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HomeManager.self) private var homeManager
    @Environment(CloudSharingService.self) private var cloudSharingService
    @Query(sort: \MaintenanceTask.name) private var allTasks: [MaintenanceTask]
    @Query(sort: \Appliance.name) private var allAppliances: [Appliance]
    @Query(sort: \RepairProject.title) private var allProjects: [RepairProject]

    let section: DocumentSection
    let home: Home?

    @State private var title = ""
    @State private var attachmentData: Data?
    @State private var attachmentName: String?
    @State private var attachmentContentType: String?
    @State private var linkedAppliance: Appliance?
    @State private var linkedTaskIDs: [UUID] = []
    @State private var linkedProjectIDs: [UUID] = []
    @State private var showingDocumentPicker = false
    @State private var showingScanner = false
    @State private var showingTaskPicker = false
    @State private var showingProjectPicker = false
    @State private var showingAppliancePicker = false

    private var homeTasks: [MaintenanceTask] {
        guard let home else { return [] }
        return allTasks.filter { $0.homeIDString == home.id.uuidString }
    }

    private var homeAppliances: [Appliance] {
        guard let home else { return [] }
        return allAppliances.filter { $0.homeIDString == home.id.uuidString }
    }

    private var homeProjects: [RepairProject] {
        guard let home else { return [] }
        return allProjects.filter { $0.homeIDString == home.id.uuidString }
    }

    private var linkedTasks: [MaintenanceTask] {
        homeTasks.filter { linkedTaskIDs.contains($0.id) }
    }

    private var linkedProjectsList: [RepairProject] {
        homeProjects.filter { linkedProjectIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Document Title", text: $title)
                }

                Section {
                    if let name = attachmentName {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.blue)
                            Text(name)
                            Spacer()
                            Button(role: .destructive) {
                                attachmentData = nil
                                attachmentName = nil
                                attachmentContentType = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        showingDocumentPicker = true
                    } label: {
                        Label(attachmentData == nil ? "Attach File" : "Replace Attachment", systemImage: "paperclip")
                    }
                    if VNDocumentCameraViewController.isSupported {
                        Button {
                            showingScanner = true
                        } label: {
                            Label(attachmentData == nil ? "Scan Document" : "Re-scan Document", systemImage: "doc.viewfinder")
                        }
                    }
                } header: {
                    Text("Attachment")
                }

                Section("Linked Appliance") {
                    if let appliance = linkedAppliance {
                        HStack {
                            ApplianceIconView(appliance: appliance, size: 30)
                            Text(appliance.name)
                            Spacer()
                            Button(role: .destructive) {
                                linkedAppliance = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        showingAppliancePicker = true
                    } label: {
                        Label(linkedAppliance == nil ? "Link Appliance" : "Change Appliance", systemImage: "plus")
                    }
                }

                Section("Linked Tasks") {
                    ForEach(linkedTasks) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.name).font(.subheadline)
                                Text(task.frequencyDisplayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                linkedTaskIDs.removeAll { $0 == task.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        showingTaskPicker = true
                    } label: {
                        Label("Link Task", systemImage: "plus")
                    }
                }

                Section("Linked Projects") {
                    ForEach(linkedProjectsList) { project in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title).font(.subheadline)
                                Text(project.status.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                linkedProjectIDs.removeAll { $0 == project.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        showingProjectPicker = true
                    } label: {
                        Label("Link Project", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker { url, name in
                    guard let data = try? Data(contentsOf: url) else { return }
                    attachmentData = data
                    attachmentName = name
                    attachmentContentType = url.pathExtension
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView { images in
                    if let pdfData = scannedImagesToPDF(images) {
                        attachmentData = pdfData
                        attachmentName = "Scanned Document.pdf"
                        attachmentContentType = "pdf"
                    }
                    showingScanner = false
                } onCancel: {
                    showingScanner = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingTaskPicker) {
                SelectTasksForDocumentView(selectedTaskIDs: $linkedTaskIDs, tasks: homeTasks)
            }
            .sheet(isPresented: $showingProjectPicker) {
                SelectProjectsForDocumentView(selectedProjectIDs: $linkedProjectIDs, projects: homeProjects)
            }
            .sheet(isPresented: $showingAppliancePicker) {
                SelectApplianceForDocumentView(selectedAppliance: $linkedAppliance, appliances: homeAppliances)
            }
        }
    }

    private func save() {
        let doc = HomeDocument(title: title.trimmingCharacters(in: .whitespaces))
        doc.attachmentData = attachmentData
        doc.attachmentName = attachmentName
        doc.attachmentContentType = attachmentContentType
        doc.linkedTaskIDs = linkedTaskIDs
        doc.linkedProjectIDs = linkedProjectIDs
        // Scalar mirrors — always safe to set regardless of store.
        doc.homeIDString = home?.id.uuidString
        if linkedAppliance == nil {
            doc.sectionIDString = section.id.uuidString
        }
        // Relationship assignments trigger inverse @Relationship updates on shared-store objects — crash.
        // Guard each relationship individually based on the target object's store.
        if let home, !cloudSharingService.isInSharedStore(entityName: "Home", id: home.id) {
            doc.home = home
        }
        let sectionInShared = cloudSharingService.isInSharedStore(entityName: "DocumentSection", id: section.id)
        if !sectionInShared, linkedAppliance == nil {
            doc.section = section
        }
        if let appliance = linkedAppliance,
           !cloudSharingService.isInSharedStore(entityName: "Appliance", id: appliance.id) {
            doc.linkedAppliance = appliance
        }
        modelContext.insert(doc)
        dismiss()
    }
}

// MARK: - Task Picker (multi-select)

struct SelectTasksForDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTaskIDs: [UUID]
    let tasks: [MaintenanceTask]

    var body: some View {
        NavigationStack {
            Group {
                if tasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Add maintenance tasks first.")
                    )
                } else {
                    List {
                        ForEach(tasks) { task in
                            Button {
                                if selectedTaskIDs.contains(task.id) {
                                    selectedTaskIDs.removeAll { $0 == task.id }
                                } else {
                                    selectedTaskIDs.append(task.id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(task.frequencyDisplayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedTaskIDs.contains(task.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Project Picker (multi-select)

struct SelectProjectsForDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedProjectIDs: [UUID]
    let projects: [RepairProject]

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "hammer",
                        description: Text("Add repair projects first.")
                    )
                } else {
                    List {
                        ForEach(projects) { project in
                            Button {
                                if selectedProjectIDs.contains(project.id) {
                                    selectedProjectIDs.removeAll { $0 == project.id }
                                } else {
                                    selectedProjectIDs.append(project.id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(project.status.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedProjectIDs.contains(project.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Appliance Picker (single-select)

struct SelectApplianceForDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedAppliance: Appliance?
    let appliances: [Appliance]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedAppliance = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("None")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedAppliance == nil {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                }

                if !appliances.isEmpty {
                    Section("Appliances") {
                        ForEach(appliances) { appliance in
                            Button {
                                selectedAppliance = appliance
                                dismiss()
                            } label: {
                                HStack {
                                    ApplianceIconView(appliance: appliance, size: 30)
                                    Text(appliance.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedAppliance?.id == appliance.id {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Text("No appliances added yet.")
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

// MARK: - Generic Document Viewer

struct GenericDocumentViewer: View {
    let name: String
    let data: Data
    let contentType: String
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?

    private var fileExtension: String {
        if contentType.contains("pdf") || contentType == "pdf" { return "pdf" }
        if contentType.contains("word") || contentType.contains("doc") || contentType == "doc" || contentType == "docx" { return "doc" }
        if contentType.contains("text") || contentType == "txt" { return "txt" }
        return contentType.isEmpty ? "file" : contentType
    }

    var body: some View {
        NavigationStack {
            Group {
                if fileExtension == "pdf" {
                    PDFViewWrapper(data: data)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: fileExtension == "txt" ? "doc.plaintext.fill" : "doc.text.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)

                            VStack(alignment: .leading, spacing: 8) {
                                infoRow(label: "File Name", value: name)
                                infoRow(label: "File Type", value: fileExtension.uppercased())
                                infoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                            }
                            .padding(.horizontal)

                            if fileExtension == "txt", let content = String(data: data, encoding: .utf8) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Content")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal)
                                    Text(content)
                                        .font(.system(.body, design: .monospaced))
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                        .padding(.horizontal)
                                }
                            }

                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { shareDocument() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: Binding(
                get: { shareURL.map { ShareItem(url: $0) } },
                set: { shareURL = $0?.url }
            )) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private func shareDocument() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: tempURL)
        shareURL = tempURL
    }
}
