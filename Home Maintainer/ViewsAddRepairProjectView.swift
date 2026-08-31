//
//  AddRepairProjectView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct AddRepairProjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudSharingService.self) private var cloudSharingService

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
                                Image(systemName: priority.systemImage)
                                    .foregroundStyle(priority.color)
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addProject()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func addProject() {
        let isSharedHome = home.map {
            cloudSharingService.isInSharedStore(entityName: "Home", id: $0.id)
        } ?? false
        let isOwnedSharedHome = !isSharedHome && (home.map {
            cloudSharingService.isOwnedAndShared(homeID: $0.id)
        } ?? false)

        if isSharedHome, let home {
            addProjectToSharedStore(home: home)
        } else if isOwnedSharedHome, let home {
            addProjectToOwnedSharedStore(home: home)
        } else {
            addProjectToPrivateStore()
        }
        dismiss()
    }

    private func addProjectToSharedStore(home: Home) {
        let homeIDStr = home.id.uuidString
        do {
            let homeObj = cloudSharingService.findHomeManagedObject(id: home.id)
            let projectObj = try cloudSharingService.insertIntoSharedStore(entityName: "RepairProject") { obj in
                obj.setValue(UUID(), forKey: "id")
                obj.setValue(title, forKey: "title")
                obj.setValue(description, forKey: "projectDescription")
                obj.setValue(category.rawValue, forKey: "category")
                obj.setValue(status.rawValue, forKey: "status")
                obj.setValue(priority.rawValue, forKey: "priority")
                obj.setValue(notes, forKey: "notes")
                obj.setValue(Date(), forKey: "createdAt")
                obj.setValue(homeIDStr, forKey: "homeIDString")
                obj.setValue(homeObj, forKey: "home")
            }
            for draft in productDrafts where !draft.isEmpty {
                try cloudSharingService.insertIntoSharedStore(entityName: "ProductLink") { obj in
                    obj.setValue(UUID(), forKey: "id")
                    obj.setValue(draft.name, forKey: "name")
                    obj.setValue(draft.urlString, forKey: "urlString")
                    obj.setValue(draft.imageData, forKey: "imageData")
                    obj.setValue(Date(), forKey: "createdAt")
                    obj.setValue(projectObj, forKey: "project")
                }
            }
            try cloudSharingService.saveSharedContext()
        } catch {
            print("[AddRepairProject] Shared store insert failed: \(error)")
        }
    }

    private func addProjectToOwnedSharedStore(home: Home) {
        let homeIDStr = home.id.uuidString
        do {
            let homeObj = cloudSharingService.findHomeManagedObject(id: home.id)
            let projectObj = try cloudSharingService.insertLinkedToHome(entityName: "RepairProject") { obj in
                obj.setValue(UUID(), forKey: "id")
                obj.setValue(title, forKey: "title")
                obj.setValue(description, forKey: "projectDescription")
                obj.setValue(category.rawValue, forKey: "category")
                obj.setValue(status.rawValue, forKey: "status")
                obj.setValue(priority.rawValue, forKey: "priority")
                obj.setValue(notes, forKey: "notes")
                obj.setValue(Date(), forKey: "createdAt")
                obj.setValue(homeIDStr, forKey: "homeIDString")
                obj.setValue(homeObj, forKey: "home")
            }
            for draft in productDrafts where !draft.isEmpty {
                try cloudSharingService.insertLinkedToHome(entityName: "ProductLink") { obj in
                    obj.setValue(UUID(), forKey: "id")
                    obj.setValue(draft.name, forKey: "name")
                    obj.setValue(draft.urlString, forKey: "urlString")
                    obj.setValue(draft.imageData, forKey: "imageData")
                    obj.setValue(Date(), forKey: "createdAt")
                    obj.setValue(projectObj, forKey: "project")
                }
            }
            try cloudSharingService.saveSharedContext()
        } catch {
            NSLog("[AddRepairProject] Owner-shared insert failed: \(error)")
        }
    }

    private func addProjectToPrivateStore() {
        let project = RepairProject(
            title: title,
            description: description,
            category: category,
            priority: priority
        )
        project.status = status
        project.notes = notes
        if let home, !cloudSharingService.isInSharedStore(entityName: "Home", id: home.id) {
            project.home = home
        }
        project.homeIDString = home?.id.uuidString
        modelContext.insert(project)
        for draft in productDrafts where !draft.isEmpty {
            let product = ProductLink(name: draft.name, urlString: draft.urlString, imageData: draft.imageData)
            product.project = project
            modelContext.insert(product)
        }
    }
}

#Preview {
    AddRepairProjectView()
        .modelContainer(for: RepairProject.self, inMemory: true)
}
