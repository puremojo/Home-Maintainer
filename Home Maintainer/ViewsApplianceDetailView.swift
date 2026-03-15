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

struct ApplianceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [MaintenanceTask]
    @Bindable var appliance: Appliance
    @State private var isEditing = false
    @State private var showingDocumentPicker = false
    @State private var selectedDocument: ApplianceDocument?
    
    // Get tasks linked to this appliance
    var linkedTasks: [MaintenanceTask] {
        allTasks.filter { $0.appliance?.id == appliance.id }
    }
    
    var body: some View {
        List {
            Section("Information") {
                LabeledContent("Name", value: appliance.name)
                LabeledContent("Type", value: appliance.type.rawValue)
                
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
                    Text(appliance.notes)
                }
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
                                Text(document.name)
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
                
                Button {
                    showingDocumentPicker = true
                } label: {
                    Label("Add Document", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Documents")
            } footer: {
                Text("Attach user manuals, warranty documents, or other files related to this appliance.")
            }
            
            if !linkedTasks.isEmpty {
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
                                }
                            }
                        }
                    }
                }
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
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { url, name in
                addDocument(from: url, name: name)
            }
        }
        .sheet(item: $selectedDocument) { document in
            DocumentViewer(document: document)
        }
    }
    
    private func deleteDocuments(offsets: IndexSet) {
        guard let documents = appliance.documents else { return }
        for index in offsets {
            appliance.removeDocument(documents[index])
        }
    }
    
    private func addDocument(from url: URL, name: String) {
        do {
            let data = try Data(contentsOf: url)
            let contentType = url.pathExtension
            appliance.addDocument(name: name, data: data, contentType: contentType)
        } catch {
            print("Error loading document: \(error)")
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
            .navigationTitle(document.name)
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

