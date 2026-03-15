//
//  ServiceProviderDetailView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct ServiceProviderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var provider: ServiceProvider
    @State private var isEditing = false
    
    var body: some View {
        List {
            Section("Information") {
                LabeledContent("Name", value: provider.name)
                LabeledContent("Category", value: provider.category.rawValue)
                
                if provider.rating > 0 {
                    LabeledContent("Rating") {
                        HStack(spacing: 2) {
                            ForEach(0..<5) { index in
                                Image(systemName: index < provider.rating ? "star.fill" : "star")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
            }
            
            Section("Contact") {
                if !provider.phoneNumber.isEmpty {
                    Link(destination: URL(string: "tel:\(provider.phoneNumber)")!) {
                        LabeledContent("Phone", value: provider.phoneNumber)
                    }
                }
                
                if !provider.email.isEmpty {
                    Link(destination: URL(string: "mailto:\(provider.email)")!) {
                        LabeledContent("Email", value: provider.email)
                    }
                }
                
                if !provider.address.isEmpty {
                    LabeledContent("Address", value: provider.address)
                }
                
                if !provider.website.isEmpty {
                    Link(destination: URL(string: provider.website.hasPrefix("http") ? provider.website : "https://\(provider.website)")!) {
                        LabeledContent("Website", value: provider.website)
                    }
                }
            }
            
            if !provider.notes.isEmpty {
                Section("Notes") {
                    Text(provider.notes)
                }
            }
            
            Section {
                Toggle("Favorite", isOn: $provider.isFavorite)
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditServiceProviderView(provider: provider)
        }
    }
}

struct EditServiceProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var provider: ServiceProvider
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $provider.name)
                    Picker("Category", selection: $provider.category) {
                        ForEach(ServiceCategory.allCases, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                }
                
                Section("Contact Information") {
                    TextField("Phone Number", text: $provider.phoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $provider.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Address", text: $provider.address)
                    TextField("Website", text: $provider.website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                
                Section("Rating") {
                    HStack {
                        Text("Rating")
                        Spacer()
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= provider.rating ? "star.fill" : "star")
                                .foregroundStyle(.yellow)
                                .onTapGesture {
                                    provider.rating = star
                                }
                        }
                        if provider.rating > 0 {
                            Button {
                                provider.rating = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Section {
                    Toggle("Favorite", isOn: $provider.isFavorite)
                }
                
                Section("Notes") {
                    TextField("Notes", text: $provider.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Provider")
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
    let container = try! ModelContainer(for: ServiceProvider.self, configurations: config)
    
    let provider = ServiceProvider(
        name: "ABC Plumbing",
        category: .plumber,
        phoneNumber: "(555) 123-4567",
        email: "info@abcplumbing.com"
    )
    provider.rating = 4
    container.mainContext.insert(provider)
    
    return NavigationStack {
        ServiceProviderDetailView(provider: provider)
    }
    .modelContainer(container)
}
