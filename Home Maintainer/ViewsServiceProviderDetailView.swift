//
//  ServiceProviderDetailView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import CoreData

// MARK: - Provider Detail

struct ServiceProviderDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    var provider: ServiceProvider
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)]) private var allProjects: FetchedResults<RepairProject>

    @State private var isEditing = false

    private var linkedProjects: [RepairProject] {
        allProjects
            .filter { $0.hiredProvider?.id == provider.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var cleanPhone: String {
        provider.phoneNumber.filter { "0123456789+".contains($0) }
    }

    var body: some View {
        List {
            // MARK: Information
            Section("Information") {
                LabeledContent("Category", value: provider.category.rawValue)

                if let type = provider.primaryGoogleType {
                    LabeledContent("Type", value: type)
                }

                if provider.googleRating > 0 {
                    LabeledContent("Google Rating") {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                            Text(String(format: "%.1f", provider.googleRating))
                                .font(.subheadline)
                        }
                    }
                }

                if let price = provider.displayPriceLevel {
                    LabeledContent("Price Level", value: price)
                }

                if provider.rating > 0 {
                    LabeledContent("My Rating") {
                        HStack(spacing: 2) {
                            ForEach(0..<5) { i in
                                Image(systemName: i < Int(provider.rating) ? "star.fill" : "star")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
            }

            // MARK: Contact
            Section("Contact") {
                if !provider.phoneNumber.isEmpty, let url = URL(string: "tel:\(cleanPhone)") {
                    LabeledContent("Phone") {
                        Link(provider.phoneNumber, destination: url)
                            .foregroundStyle(.blue)
                    }
                } else {
                    LabeledContent("Phone") {
                        Text("Tap Edit to add")
                            .foregroundStyle(.secondary)
                    }
                }

                if !provider.email.isEmpty, let url = URL(string: "mailto:\(provider.email)") {
                    LabeledContent("Email") {
                        Link(provider.email, destination: url)
                            .foregroundStyle(.blue)
                    }
                }

                if !provider.address.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Address")
                        if let encoded = provider.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let mapsURL = URL(string: "maps://?q=\(encoded)") {
                            Link(destination: mapsURL) {
                                Text(provider.address)
                            }
                            .foregroundStyle(.blue)
                        } else {
                            Text(provider.address)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !provider.website.isEmpty {
                    let urlString = provider.website.hasPrefix("http") ? provider.website : "https://\(provider.website)"
                    if let url = URL(string: urlString) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Website")
                            Link(provider.website, destination: url)
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                        }
                    }
                }
            }

            // MARK: Hours
            if let hours = provider.weekdayHours, !hours.isEmpty {
                Section("Hours") {
                    ForEach(hours, id: \.self) { day in
                        Text(day)
                            .font(.subheadline)
                    }
                }
            }

            // MARK: Notes
            Section("Notes") {
                TextField("Add notes…", text: Binding(
                    get: { provider.notes },
                    set: { provider.notes = $0; try? viewContext.save() }
                ), axis: .vertical)
                    .lineLimit(3...10)
            }

            // MARK: Favorite
            Section {
                Toggle("Favorite", isOn: Binding(
                    get: { provider.isFavorite },
                    set: { provider.isFavorite = $0; try? viewContext.save() }
                ))
            }

            // MARK: Linked Projects
            if !linkedProjects.isEmpty {
                Section {
                    ForEach(linkedProjects) { project in
                        NavigationLink(destination: RepairProjectDetailView(project: project)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                HStack(spacing: 4) {
                                    Text(project.status.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(project.createdAt, format: .dateTime.month().day().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Projects")
                } footer: {
                    Text("Projects where this provider was hired, sorted by most recent")
                }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditServiceProviderView(provider: provider)
        }
    }
}

// MARK: - Edit Provider

struct EditServiceProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    var provider: ServiceProvider

    @State private var name: String
    @State private var category: ServiceCategory
    @State private var phoneNumber: String
    @State private var email: String
    @State private var address: String
    @State private var website: String
    @State private var notes: String
    @State private var isFavorite: Bool
    @State private var rating: Int

    init(provider: ServiceProvider) {
        self.provider = provider
        _name = State(initialValue: provider.name)
        _category = State(initialValue: provider.category)
        _phoneNumber = State(initialValue: provider.phoneNumber)
        _email = State(initialValue: provider.email)
        _address = State(initialValue: provider.address)
        _website = State(initialValue: provider.website)
        _notes = State(initialValue: provider.notes)
        _isFavorite = State(initialValue: provider.isFavorite)
        _rating = State(initialValue: Int(provider.rating))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(ServiceCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage)
                                .tag(cat)
                        }
                    }
                }

                Section("Contact Information") {
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Address", text: $address)
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                Section("My Rating") {
                    HStack {
                        Text("Rating")
                        Spacer()
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .foregroundStyle(.yellow)
                                .onTapGesture { rating = star }
                        }
                        if rating > 0 {
                            Button {
                                rating = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Toggle("Favorite", isOn: $isFavorite)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        provider.name = name
                        provider.category = category
                        provider.phoneNumber = phoneNumber
                        provider.email = email
                        provider.address = address
                        provider.website = website
                        provider.notes = notes
                        provider.isFavorite = isFavorite
                        provider.rating = Int32(rating)
                        try? viewContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Provider Picker Sheet
// Used by RepairProjectDetailView to select a hired provider.

struct ProviderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var allProviders: FetchedResults<ServiceProvider>

    let home: Home?
    let onSelect: (ServiceProvider) -> Void

    private var providers: [ServiceProvider] {
        guard let home else { return [] }
        return allProviders.filter { $0.homeIDString == home.id.uuidString }
    }

    private var providersByCategory: [ServiceCategory: [ServiceProvider]] {
        Dictionary(grouping: providers, by: { $0.category })
            .mapValues { list in
                list.sorted { p1, p2 in
                    if p1.isFavorite != p2.isFavorite { return p1.isFavorite }
                    return p1.name < p2.name
                }
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if providers.isEmpty {
                    ContentUnavailableView(
                        "No Providers",
                        systemImage: "person.2",
                        description: Text("Add providers in the Service Providers tab first.")
                    )
                } else {
                    List {
                        let sortedCategories = providersByCategory.keys.sorted { $0.rawValue < $1.rawValue }
                        ForEach(sortedCategories, id: \.self) { category in
                            Section(category.rawValue) {
                                ForEach(providersByCategory[category] ?? []) { provider in
                                    Button {
                                        onSelect(provider)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: category.systemImage)
                                                .foregroundStyle(.blue)
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 4) {
                                                    Text(provider.name)
                                                        .font(.headline)
                                                        .foregroundStyle(.primary)
                                                    if provider.isFavorite {
                                                        Image(systemName: "star.fill")
                                                            .font(.caption2)
                                                            .foregroundStyle(.yellow)
                                                    }
                                                }
                                                if !provider.phoneNumber.isEmpty {
                                                    Text(provider.phoneNumber)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                if !provider.address.isEmpty {
                                                    Text(provider.address)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
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
    let ctx = container.viewContext

    let provider = ServiceProvider(context: ctx)
    provider.id = UUID()
    provider.name = "ABC Plumbing"
    provider.category = .plumber
    provider.phoneNumber = "(555) 123-4567"
    provider.email = ""
    provider.address = ""
    provider.website = ""
    provider.notes = ""
    provider.googleRating = 4.7
    provider.googlePriceLevel = "PRICE_LEVEL_MODERATE"
    provider.weekdayHours = ["Monday: 8:00 AM – 5:00 PM", "Tuesday: 8:00 AM – 5:00 PM"]
    try? ctx.save()

    return NavigationStack {
        ServiceProviderDetailView(provider: provider)
    }
    .environment(\.managedObjectContext, ctx)
}
