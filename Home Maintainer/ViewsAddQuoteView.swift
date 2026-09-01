//
//  AddQuoteView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import CoreData

struct AddQuoteView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var providers: FetchedResults<ServiceProvider>

    let project: RepairProject

    @State private var selectedProvider: ServiceProvider?
    @State private var amount: Double = 0
    @State private var quoteDate = Date()
    @State private var hasValidUntil = false
    @State private var validUntil = Date()
    @State private var details = ""
    @State private var wasAccepted = false

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

                Section("Quote Details") {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("Quote Date", selection: $quoteDate, displayedComponents: .date)

                    Toggle("Valid Until Date", isOn: $hasValidUntil)

                    if hasValidUntil {
                        DatePicker("Valid Until", selection: $validUntil, displayedComponents: .date)
                    }

                    Toggle("Accepted", isOn: $wasAccepted)
                }

                Section("Details") {
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addQuote()
                    }
                    .disabled(selectedProvider == nil || amount <= 0)
                }
            }
        }
    }

    private func addQuote() {
        guard let provider = selectedProvider else { return }

        let quote = Quote.make(project: project, provider: provider, amount: amount, in: viewContext)
        quote.quoteDate = quoteDate

        if hasValidUntil {
            quote.validUntil = validUntil
        }

        quote.details = details
        quote.wasAccepted = wasAccepted

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

    return AddQuoteView(project: project)
        .environment(\.managedObjectContext, container.viewContext)
}
