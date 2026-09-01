//
//  AddInvoiceView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import CoreData

struct AddInvoiceView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var providers: FetchedResults<ServiceProvider>

    let project: RepairProject

    @State private var selectedProvider: ServiceProvider?
    @State private var amount: Double = 0
    @State private var invoiceDate = Date()
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var isPaid = false
    @State private var paidDate = Date()
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Service Provider", selection: $selectedProvider) {
                        Text("Select Provider").tag(nil as ServiceProvider?)

                        if let hiredProvider = project.hiredProvider {
                            Text("\(hiredProvider.name) (Hired)").tag(hiredProvider as ServiceProvider?)
                        }

                        ForEach(providers.sorted(by: { $0.name < $1.name })) { provider in
                            if provider.id != project.hiredProvider?.id {
                                Text(provider.name).tag(provider as ServiceProvider?)
                            }
                        }
                    }
                }

                Section("Invoice Details") {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("Invoice Date", selection: $invoiceDate, displayedComponents: .date)

                    Toggle("Due Date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Payment Status") {
                    Toggle("Paid", isOn: $isPaid)

                    if isPaid {
                        DatePicker("Paid Date", selection: $paidDate, displayedComponents: .date)
                    }
                }

                Section("Details") {
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addInvoice()
                    }
                    .disabled(selectedProvider == nil || amount <= 0)
                }
            }
            .onAppear {
                // Pre-select the hired provider if available
                if selectedProvider == nil, let hiredProvider = project.hiredProvider {
                    selectedProvider = hiredProvider
                }
            }
        }
    }

    private func addInvoice() {
        guard let provider = selectedProvider else { return }

        let invoice = Invoice.make(project: project, provider: provider, amount: amount, in: viewContext)
        invoice.invoiceDate = invoiceDate

        if hasDueDate {
            invoice.dueDate = dueDate
        }

        invoice.isPaid = isPaid

        if isPaid {
            invoice.paidDate = paidDate
        }

        invoice.details = details

        project.invoice = invoice

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

    return AddInvoiceView(project: project)
        .environment(\.managedObjectContext, container.viewContext)
}
