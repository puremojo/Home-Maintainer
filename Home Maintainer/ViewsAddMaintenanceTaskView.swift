//
//  AddMaintenanceTaskView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import CoreData

struct AddMaintenanceTaskView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudSharingService.self) private var cloudSharingService
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var appliances: FetchedResults<Appliance>

    let home: Home?

    @State private var name = ""
    @State private var description = ""
    @State private var selectedFrequency: TaskFrequency = .once
    @State private var selectedAppliance: Appliance?
    @State private var customDays = 30
    @State private var productDrafts: [ProductDraft] = []
    @State private var room = ""

    init(home: Home? = nil) {
        self.home = home
    }

    let predefinedFrequencies: [TaskFrequency] = [
        .once, .daily, .weekly, .biweekly, .monthly, .quarterly, .biannually, .annually
    ]

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

                DraftProductsSection(drafts: $productDrafts)
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addTask()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addTask() {
        let isSharedHome = home.map {
            cloudSharingService.isInSharedStore(entityName: "Home", id: $0.id)
        } ?? false

        if isSharedHome, let home {
            addTaskToSharedStore(home: home)
        } else if let home {
            addTaskToOwnedSharedStore(home: home)
        } else {
            addTaskToPrivateStore()
        }
        dismiss()
    }

    private func addTaskToSharedStore(home: Home) {
        let freq = selectedFrequency
        let homeIDStr = home.id.uuidString
        do {
            let homeObj = cloudSharingService.findHomeManagedObject(id: home.id)
            NSLog("[AddMaintenanceTask] SHARED path — homeID=\(homeIDStr) homeObjFound=\(homeObj != nil)")
            let taskObj = try cloudSharingService.insertIntoSharedStore(entityName: "MaintenanceTask") { obj in
                let taskID = UUID()
                obj.setValue(taskID, forKey: "id")
                obj.setValue(name, forKey: "name")
                obj.setValue(description, forKey: "taskDescription")
                obj.setValue(room, forKey: "room")
                obj.setValue(freq.encoded, forKey: "frequencyEncoded")
                obj.setValue(true, forKey: "isActive")
                obj.setValue(Date(), forKey: "createdAt")
                obj.setValue(freq.nextDue(from: Date()), forKey: "nextDue")
                obj.setValue(homeIDStr, forKey: "homeIDString")
                obj.setValue(homeObj, forKey: "home")
                NSLog("[AddMaintenanceTask] SHARED insert — task '\(name)' id=\(taskID) homeIDString=\(homeIDStr)")
            }
            var allObjects: [NSManagedObject] = [taskObj]
            for draft in productDrafts where !draft.isEmpty {
                let linkObj = try cloudSharingService.insertIntoSharedStore(entityName: "ProductLink") { obj in
                    obj.setValue(UUID(), forKey: "id")
                    obj.setValue(draft.name, forKey: "name")
                    obj.setValue(draft.urlString, forKey: "urlString")
                    obj.setValue(draft.imageData, forKey: "imageData")
                    obj.setValue(Date(), forKey: "createdAt")
                    obj.setValue(taskObj, forKey: "task")
                }
                allObjects.append(linkObj)
            }
            cloudSharingService.addObjectsToHomeShare(objects: allObjects, homeID: home.id)
        } catch {
            NSLog("[AddMaintenanceTask] Shared store insert failed: \(error)")
        }
    }

    private func addTaskToOwnedSharedStore(home: Home) {
        let freq = selectedFrequency
        let homeIDStr = home.id.uuidString
        do {
            let taskObj = try cloudSharingService.insertLinkedToHome(entityName: "MaintenanceTask") { obj in
                let taskID = UUID()
                obj.setValue(taskID, forKey: "id")
                obj.setValue(name, forKey: "name")
                obj.setValue(description, forKey: "taskDescription")
                obj.setValue(room, forKey: "room")
                obj.setValue(freq.encoded, forKey: "frequencyEncoded")
                obj.setValue(true, forKey: "isActive")
                obj.setValue(Date(), forKey: "createdAt")
                obj.setValue(freq.nextDue(from: Date()), forKey: "nextDue")
                obj.setValue(homeIDStr, forKey: "homeIDString")
                NSLog("[AddMaintenanceTask] OWNER-SHARED insert — task '\(name)' id=\(taskID) homeIDString=\(homeIDStr)")
            }
            var allObjects: [NSManagedObject] = [taskObj]
            for draft in productDrafts where !draft.isEmpty {
                let linkObj = try cloudSharingService.insertLinkedToHome(entityName: "ProductLink") { obj in
                    obj.setValue(UUID(), forKey: "id")
                    obj.setValue(draft.name, forKey: "name")
                    obj.setValue(draft.urlString, forKey: "urlString")
                    obj.setValue(draft.imageData, forKey: "imageData")
                    obj.setValue(Date(), forKey: "createdAt")
                    obj.setValue(taskObj, forKey: "task")
                }
                allObjects.append(linkObj)
            }
            cloudSharingService.addObjectsToOwnerShare(objects: allObjects, homeID: home.id)
        } catch {
            NSLog("[AddMaintenanceTask] Owner-shared insert failed: \(error)")
        }
    }

    private func addTaskToPrivateStore() {
        let task = MaintenanceTask.make(
            name: name,
            description: description,
            frequency: selectedFrequency,
            room: room,
            appliance: selectedAppliance,
            in: viewContext
        )
        if let home, !cloudSharingService.isInSharedStore(entityName: "Home", id: home.id) {
            task.home = home
        }
        task.homeIDString = home?.id.uuidString
        NSLog("[AddMaintenanceTask] PRIVATE path — task '\(task.name)' id=\(task.id) homeIDString=\(task.homeIDString ?? "nil") homeRelSet=\(task.home != nil)")

        for draft in productDrafts where !draft.isEmpty {
            let product = ProductLink.make(name: draft.name, urlString: draft.urlString, imageData: draft.imageData, in: viewContext)
            product.task = task
        }

        try? viewContext.save()

        Task {
            await CalendarService.shared.addTaskEvent(task: task)
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
    return AddMaintenanceTaskView()
        .environment(\.managedObjectContext, container.viewContext)
        .environment(CloudSharingService(container: NSPersistentCloudKitContainer(name: "preview", managedObjectModel: model)))
}
