//
//  AddRepairProjectView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import CoreData

struct AddRepairProjectView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let home: Home?

    init(home: Home? = nil) {
        self.home = home
    }

    @State private var title = ""
    @State private var description = ""
    @State private var category: ServiceCategory = .generalContractor
    @State private var status: ProjectStatus = .planning
    @State private var priority: ProjectPriority = .medium
    @State private var notes = ""
    @State private var productDrafts: [ProductDraft] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Information") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(ServiceCategory.allCases, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }

                    Picker("Priority", selection: $priority) {
                        ForEach(ProjectPriority.allCases, id: \.self) { priority in
                            HStack {
                                Image(systemName: priority.systemImage).foregroundStyle(priority.color)
                                Text(priority.displayName)
                            }
                            .tag(priority)
                        }
                    }

                    Picker("Status", selection: $status) {
                        ForEach(ProjectStatus.allCases, id: \.self) { status in
                            Label(status.rawValue, systemImage: status.systemImage)
                                .tag(status)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                DraftProductsSection(drafts: $productDrafts)
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addProject() }
                        .disabled(title.isEmpty)
                }
            }
        }
    }

    private func addProject() {
        let project = RepairProject.make(
            title: title,
            description: description,
            category: category,
            priority: priority,
            in: viewContext
        )
        project.status = status
        project.notes = notes
        project.home = home
        project.homeIDString = home?.id.uuidString

        for draft in productDrafts where !draft.isEmpty {
            let product = ProductLink.make(name: draft.name, urlString: draft.urlString,
                                           imageData: draft.imageData, in: viewContext)
            product.project = project
        }

        try? viewContext.save()
        dismiss()
    }
}

#Preview { Text("Preview unavailable") }
