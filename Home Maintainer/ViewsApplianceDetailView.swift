//
//  ApplianceDetailView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit
import PhotosUI
import VisionKit

struct ApplianceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(GeminiService.self) private var geminiService
    @Environment(HomeManager.self) private var homeManager
    @Query private var allTasks: [MaintenanceTask]
    @Bindable var appliance: Appliance
    @State private var isEditing = false
    @State private var showingAddDocument = false
    @State private var selectedDocument: ApplianceDocument?
    @State private var selectedHomeDocument: HomeDocument?
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var selectedPhoto: AppliancePhoto?
    @State private var isFetchingSuggestions = false
    @State private var suggestedTasks: [TaskSuggestion] = []
    @State private var showTaskSuggestions = false
    @State private var suggestionError: String?
    @State private var showSuggestionError = false
    
    // Get tasks linked to this appliance
    var linkedTasks: [MaintenanceTask] {
        allTasks.filter { $0.appliance?.id == appliance.id }
    }
    
    var body: some View {
        List {
            Section("Information") {
                LabeledContent("Name", value: appliance.name)
                LabeledContent("Type", value: appliance.type.rawValue)
                
                if !appliance.room.isEmpty {
                    LabeledContent("Room", value: appliance.room)
                }

                if !appliance.manufacturer.isEmpty {
                    LabeledContent("Manufacturer", value: appliance.manufacturer)
                }
                
                if !appliance.modelNumber.isEmpty {
                    LabeledContent("Model Number", value: appliance.modelNumber)
                }
                
                if let purchaseDate = appliance.purchaseDate {
                    LabeledContent("Purchase Date") {
                        Text(purchaseDate, format: .dateTime.month().day().year())
                    }
                }
                
                if let warrantyExpiration = appliance.warrantyExpiration {
                    LabeledContent("Warranty Expires") {
                        Text(warrantyExpiration, format: .dateTime.month().day().year())
                            .foregroundStyle(warrantyExpiration < Date() ? .red : .primary)
                    }
                }
            }
            
            if !appliance.notes.isEmpty {
                Section("Notes") {
                    LinkedText(text: appliance.notes)
                }
            }
            
            Section {
                if let photos = appliance.photos, !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(photos.sorted(by: { $0.createdAt < $1.createdAt })) { photo in
                                if let data = photo.imageData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .contentShape(RoundedRectangle(cornerRadius: 8))
                                        .onTapGesture {
                                            selectedPhoto = photo
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                deletePhoto(photo)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                PhotosPicker(selection: $photoPickerItems, matching: .images) {
                    Label("Add Pictures", systemImage: "photo.badge.plus")
                }
            } header: {
                Text("Pictures")
            } footer: {
                Text("Add photos of the appliance, its label, or model/serial number. Tap a photo to view it full screen; long-press to delete.")
            }

            Section {
                ForEach(appliance.documents ?? []) { document in
                    Button {
                        selectedDocument = document
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
                .onDelete(perform: deleteDocuments)

                // HomeDocuments linked from the Documents tab
                ForEach((appliance.homeDocuments ?? []).sorted { $0.createdAt < $1.createdAt }) { doc in
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

                Button {
                    showingAddDocument = true
                } label: {
                    Label("Add Document", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Documents")
            } footer: {
                Text("Attach user manuals, warranty documents, or other files related to this appliance.")
            }
            
            Section("Maintenance Tasks") {
                ForEach(linkedTasks) { task in
                    NavigationLink(destination: MaintenanceTaskDetailView(task: task)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(task.name)
                                    .font(.subheadline)
                                    .strikethrough(task.isCompletedForCurrentCycle, color: .gray)
                                    .foregroundStyle(task.isCompletedForCurrentCycle ? .secondary : .primary)

                                if task.isCompletedForCurrentCycle {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
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
                            }
                        }
                    }
                }

                Button {
                    fetchSuggestions()
                } label: {
                    if isFetchingSuggestions {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Fetching suggestions…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Add Suggested Tasks", systemImage: "sparkles")
                    }
                }
                .disabled(isFetchingSuggestions)
            }
        }
        .navigationTitle(appliance.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditApplianceView(appliance: appliance)
        }
        .sheet(isPresented: $showingAddDocument) {
            AddDocumentSheet { title, fileName, data, contentType in
                appliance.addDocument(name: fileName, data: data, contentType: contentType, title: title)
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
        .fullScreenCover(item: $selectedPhoto) { photo in
            if let data = photo.imageData, let uiImage = UIImage(data: data) {
                FullScreenImageView(uiImage: uiImage)
            }
        }
        .onChange(of: photoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        appliance.addPhoto(data: data)
                    }
                }
                photoPickerItems = []
            }
        }
        .sheet(isPresented: $showTaskSuggestions) {
            SuggestedTasksView(
                appliance: appliance,
                suggestions: suggestedTasks,
                onAdd: addSuggestedTasks
            )
        }
        .alert("Couldn't Get Suggestions", isPresented: $showSuggestionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(suggestionError ?? "An error occurred. Please try again.")
        }
    }

    private func deletePhoto(_ photo: AppliancePhoto) {
        appliance.photos?.removeAll { $0.id == photo.id }
        modelContext.delete(photo)
    }
    
    private func deleteDocuments(offsets: IndexSet) {
        guard let documents = appliance.documents else { return }
        for index in offsets {
            appliance.removeDocument(documents[index])
        }
    }
    
    private func fetchSuggestions() {
        isFetchingSuggestions = true
        Task {
            do {
                let suggestions = try await geminiService.suggestMaintenanceTasks(for: appliance)
                await MainActor.run {
                    suggestedTasks = suggestions
                    showTaskSuggestions = true
                    isFetchingSuggestions = false
                }
            } catch {
                await MainActor.run {
                    suggestionError = error.localizedDescription
                    showSuggestionError = true
                    isFetchingSuggestions = false
                }
            }
        }
    }

    private func addSuggestedTasks(_ tasks: [TaskSuggestion]) {
        for suggestion in tasks {
            let freq = TaskFrequency(fromString: suggestion.frequency) ?? .annually
            let task = MaintenanceTask(
                name: suggestion.name,
                description: suggestion.description,
                frequency: freq,
                appliance: appliance,
                room: appliance.room
            )
            task.home = homeManager.currentHome
            task.homeIDString = homeManager.currentHome?.id.uuidString
            modelContext.insert(task)

            for product in suggestion.products {
                let encoded = product.searchQuery
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? product.searchQuery
                let link = ProductLink(
                    name: product.name,
                    urlString: "https://www.amazon.com/s?k=\(encoded)"
                )
                link.task = task
                modelContext.insert(link)
            }
        }
    }
}

struct EditApplianceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var appliance: Appliance
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $appliance.name)
                    Picker("Type", selection: $appliance.type) {
                        ForEach(ApplianceType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                }
                
                Section("Details") {
                    TextField("Manufacturer", text: $appliance.manufacturer)
                    TextField("Model Number", text: $appliance.modelNumber)
                    TextField("Room", text: $appliance.room)
                }
                
                Section("Dates") {
                    DatePicker(
                        "Purchase Date",
                        selection: Binding(
                            get: { appliance.purchaseDate ?? Date() },
                            set: { appliance.purchaseDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    
                    DatePicker(
                        "Warranty Expires",
                        selection: Binding(
                            get: { appliance.warrantyExpiration ?? Date() },
                            set: { appliance.warrantyExpiration = $0 }
                        ),
                        displayedComponents: .date
                    )
                }
                
                Section("Notes") {
                    TextField("Notes", text: $appliance.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Appliance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Appliance.self, configurations: config)
    
    let appliance = Appliance(name: "Kitchen Fridge", type: .refrigerator, manufacturer: "Samsung", modelNumber: "RF28R7351SR")
    container.mainContext.insert(appliance)
    
    return NavigationStack {
        ApplianceDetailView(appliance: appliance)
    }
    .modelContainer(container)
}

// MARK: - Task Suggestions

extension TaskFrequency {
    init?(fromString string: String) {
        switch string.lowercased() {
        case "daily": self = .daily
        case "weekly": self = .weekly
        case "biweekly": self = .biweekly
        case "monthly": self = .monthly
        case "quarterly": self = .quarterly
        case "biannually": self = .biannually
        case "annually": self = .annually
        default: return nil
        }
    }
}

struct SuggestedTasksView: View {
    let appliance: Appliance
    let suggestions: [TaskSuggestion]
    let onAdd: ([TaskSuggestion]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndices: Set<Int>

    init(appliance: Appliance, suggestions: [TaskSuggestion], onAdd: @escaping ([TaskSuggestion]) -> Void) {
        self.appliance = appliance
        self.suggestions = suggestions
        self.onAdd = onAdd
        _selectedIndices = State(initialValue: Set(suggestions.indices))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("hAIndyman recommends these tasks for your \(appliance.type.rawValue). Select the ones you want to add.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        if selectedIndices.contains(index) {
                            selectedIndices.remove(index)
                        } else {
                            selectedIndices.insert(index)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedIndices.contains(index) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIndices.contains(index) ? .blue : .secondary)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                Text(suggestion.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 6) {
                                    Label(suggestion.frequency.capitalized, systemImage: "clock")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    if !suggestion.products.isEmpty {
                                        Text("·")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Label("\(suggestion.products.count) product\(suggestion.products.count == 1 ? "" : "s")", systemImage: "cart")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Suggested Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedIndices.count) Task\(selectedIndices.count == 1 ? "" : "s")") {
                        onAdd(selectedIndices.sorted().map { suggestions[$0] })
                        dismiss()
                    }
                    .disabled(selectedIndices.isEmpty)
                }
            }
        }
    }
}

// MARK: - Document Management

struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentPicked: (URL, String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .pdf,
            .plainText,
            .commaSeparatedText,
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "docx") ?? .data
        ])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let name = url.lastPathComponent
            parent.onDocumentPicked(url, name)
            parent.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

struct DocumentViewer: View {
    let document: ApplianceDocument
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?
    
    var body: some View {
        NavigationStack {
            VStack {
                if document.fileExtension == "pdf" {
                    PDFViewWrapper(data: document.data)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: document.systemImage)
                                .font(.system(size: 60))
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Document Name")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(document.name)
                                    .font(.headline)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("File Type")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(document.fileExtension.uppercased())
                                    .font(.subheadline)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Size")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(document.data.count), countStyle: .file))
                                    .font(.subheadline)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Date Added")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(document.dateAdded, format: .dateTime.month().day().year())
                                    .font(.subheadline)
                            }
                            
                            // Preview text content if it's a text file
                            if document.fileExtension == "txt",
                               let content = String(data: document.data, encoding: .utf8) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Content")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(content)
                                        .font(.system(.body, design: .monospaced))
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(document.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        shareDocument()
                    } label: {
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
    
    private func shareDocument() {
        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(document.name)
        do {
            try document.data.write(to: tempURL)
            shareURL = tempURL
        } catch {
            print("Error creating temporary file: \(error)")
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct PDFViewWrapper: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Document Scanner

/// Wraps VNDocumentCameraViewController so it can be presented in SwiftUI.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onScan(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}

/// Combines an array of scanned page images into a single PDF and returns the raw data.
func scannedImagesToPDF(_ images: [UIImage]) -> Data? {
    let pdf = PDFDocument()
    for (index, image) in images.enumerated() {
        guard let page = PDFPage(image: image) else { continue }
        pdf.insert(page, at: index)
    }
    return pdf.dataRepresentation()
}

// MARK: - Shared Add-Document Sheet

/// Reusable sheet that lets the user optionally name a document before attaching a file.
/// Used by both appliance and task detail views.
struct AddDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    // title, fileName, data, contentType
    let onAdd: (String, String, Data, String) -> Void

    @State private var title = ""
    @State private var pendingData: Data?
    @State private var pendingFileName: String?
    @State private var pendingContentType: String?
    @State private var showingPicker = false
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Document Title (optional)", text: $title)
                } footer: {
                    Text("If left blank, the file name will be used as the title.")
                }

                Section("File") {
                    if let fileName = pendingFileName {
                        HStack {
                            Image(systemName: "doc.fill").foregroundStyle(.blue)
                            Text(fileName).foregroundStyle(.primary)
                            Spacer()
                            Button(role: .destructive) {
                                pendingData = nil
                                pendingFileName = nil
                                pendingContentType = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        showingPicker = true
                    } label: {
                        Label(pendingData == nil ? "Choose File" : "Replace File", systemImage: "folder")
                    }
                    if VNDocumentCameraViewController.isSupported {
                        Button {
                            showingScanner = true
                        } label: {
                            Label(pendingData == nil ? "Scan Document" : "Re-scan Document", systemImage: "doc.viewfinder")
                        }
                    }
                }
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let data = pendingData, let fileName = pendingFileName, let ct = pendingContentType {
                            onAdd(title, fileName, data, ct)
                        }
                        dismiss()
                    }
                    .disabled(pendingData == nil)
                }
            }
            .sheet(isPresented: $showingPicker) {
                DocumentPicker { url, name in
                    guard let data = try? Data(contentsOf: url) else { return }
                    pendingData = data
                    pendingFileName = name
                    pendingContentType = url.pathExtension
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView { images in
                    if let pdfData = scannedImagesToPDF(images) {
                        pendingData = pdfData
                        pendingFileName = "Scanned Document.pdf"
                        pendingContentType = "pdf"
                    }
                    showingScanner = false
                } onCancel: {
                    showingScanner = false
                }
                .ignoresSafeArea()
            }
        }
    }
}

