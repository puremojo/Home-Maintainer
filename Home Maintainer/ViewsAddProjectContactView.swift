//
//  AddProjectContactView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import CoreData

struct AddProjectContactView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var providers: FetchedResults<ServiceProvider>

    let project: RepairProject

    @State private var selectedProvider: ServiceProvider?
    @State private var contactDate = Date()
    @State private var method: ContactMethod = .phone
    @State private var notes = ""
    @State private var wasHired = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Service Provider", selection: $selectedProvider) {
                        Text("Select Provider").tag(nil as ServiceProvider?)
                        ForEach(providers.sorted(by: { $0.name < $1.name })) { provider in
                            Text(provider.name).tag(provider as ServiceProvider?)
                        }
                    }
                }

                Section("Contact Details") {
                    DatePicker("Contact Date", selection: $contactDate, displayedComponents: .date)

                    Picker("Method", selection: $method) {
                        ForEach(ContactMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }

                    Toggle("Was Hired", isOn: $wasHired)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addContact()
                    }
                    .disabled(selectedProvider == nil)
                }
            }
        }
    }

    private func addContact() {
        guard let provider = selectedProvider else { return }

        let contact = ProjectContact.make(project: project, provider: provider, method: method, notes: notes, in: viewContext)
        contact.contactDate = contactDate
        contact.wasHired = wasHired

        if wasHired {
            project.hiredProvider = provider
        }

        try? viewContext.save()
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

    let project = RepairProject.make(title: "Test", description: "Test", category: .plumber, in: container.viewContext)
    try? container.viewContext.save()

    return AddProjectContactView(project: project)
        .environment(\.managedObjectContext, container.viewContext)
}
