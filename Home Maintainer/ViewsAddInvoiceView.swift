//
//  AddInvoiceView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct AddInvoiceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var providers: [ServiceProvider]
    
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
        
        let invoice = Invoice(
            project: project,
            provider: provider,
            amount: amount,
            invoiceDate: invoiceDate
        )
        
        if hasDueDate {
            invoice.dueDate = dueDate
        }
        
        invoice.isPaid = isPaid
        
        if isPaid {
            invoice.paidDate = paidDate
        }
        
        invoice.details = details
        
        project.invoice = invoice
        
        modelContext.insert(invoice)
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RepairProject.self, ServiceProvider.self, configurations: config)
    
    let project = RepairProject(title: "Test", description: "Test", category: .plumber)
    container.mainContext.insert(project)
    
    return AddInvoiceView(project: project)
        .modelContainer(container)
}
