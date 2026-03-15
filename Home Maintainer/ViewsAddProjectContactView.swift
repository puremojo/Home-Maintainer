//
//  AddProjectContactView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct AddProjectContactView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var providers: [ServiceProvider]
    
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
        
        let contact = ProjectContact(
            project: project,
            provider: provider,
            contactDate: contactDate,
            method: method,
            notes: notes
        )
        contact.wasHired = wasHired
        
        if wasHired {
            project.hiredProvider = provider
        }
        
        modelContext.insert(contact)
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RepairProject.self, ServiceProvider.self, configurations: config)
    
    let project = RepairProject(title: "Test", description: "Test", category: .plumber)
    container.mainContext.insert(project)
    
    return AddProjectContactView(project: project)
        .modelContainer(container)
}
