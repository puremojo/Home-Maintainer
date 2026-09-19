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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addTask() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addTask() {
        let task = MaintenanceTask.make(
            name: name,
            description: description,
            frequency: selectedFrequency,
            room: room,
            appliance: selectedAppliance,
            in: viewContext
        )
        task.home = home
        task.homeIDString = home?.id.uuidString

        for draft in productDrafts where !draft.isEmpty {
            let product = ProductLink.make(name: draft.name, urlString: draft.urlString,
                                           imageData: draft.imageData, in: viewContext)
            product.task = task
        }

        try? viewContext.save()

        Task { await CalendarService.shared.addTaskEvent(task: task) }
        dismiss()
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
}
