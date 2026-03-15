//
//  RepairProjectDetailView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct RepairProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var providers: [ServiceProvider]
    @Bindable var project: RepairProject
    
    @State private var isEditing = false
    @State private var showingAddContact = false
    @State private var showingAddQuote = false
    @State private var showingAddInvoice = false
    
    var body: some View {
        List {
            Section("Project Details") {
                LabeledContent("Title", value: project.title)
                LabeledContent("Description", value: project.projectDescription)
                LabeledContent("Category", value: project.category.rawValue)
                
                Picker("Priority", selection: $project.priority) {
                    ForEach(ProjectPriority.allCases, id: \.self) { priority in
                        HStack {
                            Image(systemName: priority.systemImage)
                                .foregroundStyle(priority.color)
                            Text(priority.displayName)
                        }
                        .tag(priority)
                    }
                }
                
                Picker("Status", selection: $project.status) {
                    ForEach(ProjectStatus.allCases, id: \.self) { status in
                        Label(status.rawValue, systemImage: status.systemImage)
                            .tag(status)
                    }
                }
                
                if let startDate = project.startDate {
                    LabeledContent("Start Date") {
                        Text(startDate, format: .dateTime.month().day().year())
                    }
                }
                
                if let completionDate = project.completionDate {
                    LabeledContent("Completion Date") {
                        Text(completionDate, format: .dateTime.month().day().year())
                    }
                }
            }
            
            Section {
                if let hiredProvider = project.hiredProvider {
                    LabeledContent("Hired Provider") {
                        NavigationLink(destination: ServiceProviderDetailView(provider: hiredProvider)) {
                            Text(hiredProvider.name)
                        }
                    }
                } else {
                    Menu {
                        ForEach(providers.sorted(by: { $0.name < $1.name })) { provider in
                            Button(provider.name) {
                                project.hiredProvider = provider
                            }
                        }
                    } label: {
                        Label("Select Hired Provider", systemImage: "person.badge.plus")
                    }
                }
            } header: {
                Text("Hired Provider")
            }
            
            Section {
                ForEach(project.contacts ?? []) { contact in
                    ContactRowView(contact: contact)
                }
                
                Button {
                    showingAddContact = true
                } label: {
                    Label("Add Contact Record", systemImage: "plus.circle")
                }
            } header: {
                HStack {
                    Text("Contacts")
                    Spacer()
                    Text("\((project.contacts ?? []).count)")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                ForEach(project.quotes ?? []) { quote in
                    QuoteRowView(quote: quote)
                }
                
                Button {
                    showingAddQuote = true
                } label: {
                    Label("Add Quote", systemImage: "plus.circle")
                }
            } header: {
                HStack {
                    Text("Quotes")
                    Spacer()
                    if let quotes = project.quotes, !quotes.isEmpty {
                        Text("\(quotes.count) • Total: \(project.totalQuotedAmount, format: .currency(code: "USD"))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Invoice") {
                if let invoice = project.invoice {
                    InvoiceRowView(invoice: invoice)
                } else {
                    Button {
                        showingAddInvoice = true
                    } label: {
                        Label("Add Invoice", systemImage: "plus.circle")
                    }
                }
            }
            
            if !project.notes.isEmpty {
                Section("Notes") {
                    Text(project.notes)
                }
            }
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditRepairProjectView(project: project)
        }
        .sheet(isPresented: $showingAddContact) {
            AddProjectContactView(project: project)
        }
        .sheet(isPresented: $showingAddQuote) {
            AddQuoteView(project: project)
        }
        .sheet(isPresented: $showingAddInvoice) {
            AddInvoiceView(project: project)
        }
    }
}

struct ContactRowView: View {
    let contact: ProjectContact
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let provider = contact.provider {
                HStack {
                    Text(provider.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if contact.wasHired {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            HStack {
                Text(contact.contactDate, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(contact.method.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !contact.notes.isEmpty {
                Text(contact.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct QuoteRowView: View {
    let quote: Quote
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let provider = quote.provider {
                    Text(provider.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Text(quote.amount, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(quote.wasAccepted ? .green : .primary)
            }
            
            HStack {
                Text(quote.quoteDate, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if quote.wasAccepted {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Accepted")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            if !quote.details.isEmpty {
                Text(quote.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InvoiceRowView: View {
    let invoice: Invoice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let provider = invoice.provider {
                    Text(provider.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Text(invoice.amount, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            HStack {
                Text(invoice.invoiceDate, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if invoice.isPaid {
                    Text("Paid")
                        .font(.caption)
                        .foregroundStyle(.green)
                    
                    if let paidDate = invoice.paidDate {
                        Text(paidDate, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Unpaid")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            if !invoice.details.isEmpty {
                Text(invoice.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EditRepairProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: RepairProject
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Project Information") {
                    TextField("Title", text: $project.title)
                    TextField("Description", text: $project.projectDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Details") {
                    Picker("Category", selection: $project.category) {
                        ForEach(ServiceCategory.allCases, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                    
                    Picker("Priority", selection: $project.priority) {
                        ForEach(ProjectPriority.allCases, id: \.self) { priority in
                            HStack {
                                Image(systemName: priority.systemImage)
                                    .foregroundStyle(priority.color)
                                Text(priority.displayName)
                            }
                            .tag(priority)
                        }
                    }
                    
                    Picker("Status", selection: $project.status) {
                        ForEach(ProjectStatus.allCases, id: \.self) { status in
                            Label(status.rawValue, systemImage: status.systemImage)
                                .tag(status)
                        }
                    }
                }
                
                Section("Dates") {
                    DatePicker(
                        "Start Date",
                        selection: Binding(
                            get: { project.startDate ?? Date() },
                            set: { project.startDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    
                    DatePicker(
                        "Completion Date",
                        selection: Binding(
                            get: { project.completionDate ?? Date() },
                            set: { project.completionDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }
                
                Section("Notes") {
                    TextField("Notes", text: $project.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RepairProject.self, configurations: config)
    
    let project = RepairProject(
        title: "Fix Leaking Pipe",
        description: "Bathroom sink has a leak",
        category: .plumber
    )
    container.mainContext.insert(project)
    
    return NavigationStack {
        RepairProjectDetailView(project: project)
    }
    .modelContainer(container)
}
