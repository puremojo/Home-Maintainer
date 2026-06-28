//
//  AddMaintenanceTaskView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct AddMaintenanceTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Appliance.name) private var appliances: [Appliance]
    
    @State private var name = ""
    @State private var description = ""
    @State private var selectedFrequency: TaskFrequency = .monthly
    @State private var selectedAppliance: Appliance?
    @State private var customDays = 30
    @State private var productDrafts: [ProductDraft] = []
    
    let predefinedFrequencies: [TaskFrequency] = [
        .daily, .weekly, .biweekly, .monthly, .quarterly, .biannually, .annually
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Task Information") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
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
        let task = MaintenanceTask(
            name: name,
            description: description,
            frequency: selectedFrequency,
            appliance: selectedAppliance
        )
        modelContext.insert(task)

        for draft in productDrafts where !draft.isEmpty {
            let product = ProductLink(name: draft.name, urlString: draft.urlString, imageData: draft.imageData)
            product.task = task
            modelContext.insert(product)
        }

        dismiss()
    }
}

#Preview {
    AddMaintenanceTaskView()
        .modelContainer(for: MaintenanceTask.self, inMemory: true)
}
