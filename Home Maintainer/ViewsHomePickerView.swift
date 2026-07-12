//
//  ViewsHomePickerView.swift
//  Home Maintainer
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Custom UTI

extension UTType {
    static let homeMaintainer = UTType(exportedAs: "com.estrados.home-maintainer-data")
}

// MARK: - Home Picker Sheet

struct HomePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HomeManager.self) private var homeManager
    @Query(sort: \Home.createdDate) private var homes: [Home]

    @State private var showingAddHome = false
    @State private var showingImport = false
    @State private var importError: String?
    @State private var showingImportError = false
    @State private var homeToShare: Home?
    @State private var shareURL: URL?
    @State private var shareItem: HomeSharingItem?
    @State private var homeToDelete: Home?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                if homes.isEmpty {
                    emptyState
                } else {
                    ForEach(homes) { home in
                        HomeRow(
                            home: home,
                            isSelected: homeManager.currentHome?.id == home.id,
                            isOwner: homeManager.isCurrentUserOwner(of: home),
                            onSelect: {
                                homeManager.select(home)
                                dismiss()
                            },
                            onShare: { shareHome(home) },
                            onDelete: {
                                homeToDelete = home
                                showingDeleteConfirmation = true
                            }
                        )
                    }
                }

                importButton
            }
            .navigationTitle("Your Homes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddHome = true
                    } label: {
                        Label("Add Home", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddHome) {
                AddHomeView()
            }
            .fileImporter(
                isPresented: $showingImport,
                allowedContentTypes: [.homeMaintainer, .json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
            .sheet(item: $shareItem) { item in
                ActivityView(activityItems: [item.url])
                    .ignoresSafeArea()
            }
            .confirmationDialog(
                "Delete \"\(homeToDelete?.name ?? "")\"?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Home & All Data", role: .destructive) {
                    if let home = homeToDelete { deleteHome(home) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All tasks, appliances, providers, and projects in this home will be permanently deleted.")
            }
            .alert("Import Failed", isPresented: $showingImportError) {
                Button("OK") {}
            } message: {
                Text(importError ?? "The file could not be imported.")
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Homes Yet", systemImage: "house")
        } description: {
            Text("Tap + to create your first home.")
        }
    }

    private var importButton: some View {
        Section {
            Button {
                showingImport = true
            } label: {
                Label("Import Shared Home", systemImage: "square.and.arrow.down")
            }
        } footer: {
            Text("Import a home that was shared with you as a .homemaintainer file.")
        }
    }

    // MARK: - Actions

    private func shareHome(_ home: Home) {
        do {
            let data = try HomeExportService.export(home: home)
            let url = try HomeExportService.writeTempFile(data: data, homeName: home.name)
            shareItem = HomeSharingItem(url: url)
        } catch {
            importError = "Could not export home: \(error.localizedDescription)"
            showingImportError = true
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                importError = "Permission denied for the selected file."
                showingImportError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let home = try HomeExportService.importHome(from: data, into: modelContext)
            homeManager.select(home)
            dismiss()
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }

    private func deleteHome(_ home: Home) {
        if homeManager.currentHome?.id == home.id {
            homeManager.clearSelection()
            let remaining = homes.filter { $0.id != home.id }
            if let next = remaining.first {
                homeManager.select(next)
            }
        }
        modelContext.delete(home)
        try? modelContext.save()
    }
}

// MARK: - Home Row

private struct HomeRow: View {
    let home: Home
    let isSelected: Bool
    let isOwner: Bool
    let onSelect: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "house.fill" : "house")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(home.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !home.address.isEmpty {
                        Text(home.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ownerBadge
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private var ownerBadge: some View {
        if !home.ownerName.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text(isOwner ? "You (Owner)" : home.ownerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Home Picker Toolbar Button (used by every tab)

struct HomePickerButton: View {
    @Environment(HomeManager.self) private var homeManager
    @Binding var showingPicker: Bool

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.subheadline)
                Text(homeManager.currentHome?.name ?? "Select Home")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Helpers

struct HomeSharingItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Import Confirmation (opened via file tap)

struct ImportHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HomeManager.self) private var homeManager

    let url: URL

    @State private var snapshot: HomeExportData?
    @State private var importData: Data?
    @State private var loadError: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    confirmView(snapshot: snapshot)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Cannot Read File", systemImage: "doc.badge.exclamationmark")
                    } description: {
                        Text(loadError)
                    }
                } else {
                    ProgressView("Reading file…")
                }
            }
            .navigationTitle("Import Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        homeManager.pendingImportURL = nil
                        dismiss()
                    }
                }
            }
        }
        .task { loadSnapshot() }
    }

    @ViewBuilder
    private func confirmView(snapshot: HomeExportData) -> some View {
        Form {
            Section("Home Details") {
                LabeledContent("Name", value: snapshot.home.name)
                if !snapshot.home.address.isEmpty {
                    LabeledContent("Address", value: snapshot.home.address)
                }
                if !snapshot.home.ownerName.isEmpty {
                    LabeledContent("Owner", value: snapshot.home.ownerName)
                }
            }

            Section("Contents") {
                LabeledContent("Tasks", value: "\(snapshot.tasks.count)")
                LabeledContent("Appliances", value: "\(snapshot.appliances.count)")
                LabeledContent("Service Providers", value: "\(snapshot.serviceProviders.count)")
                LabeledContent("Projects", value: "\(snapshot.projects.count)")
            }

            Section {
                Button {
                    performImport()
                } label: {
                    if isImporting {
                        HStack {
                            ProgressView()
                            Text("Importing…")
                        }
                    } else {
                        Label("Import Home", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isImporting)
            } footer: {
                Text("This will add the home to your app. The original owner's data will not be modified.")
            }
        }
    }

    private func loadSnapshot() {
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            importData = data
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(HomeExportData.self, from: data)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func performImport() {
        guard let data = importData else { return }
        isImporting = true
        do {
            let home = try HomeExportService.importHome(from: data, into: modelContext)
            homeManager.select(home)
            homeManager.pendingImportURL = nil
            dismiss()
        } catch {
            loadError = error.localizedDescription
            isImporting = false
        }
    }
}
