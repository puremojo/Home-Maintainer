//
//  AddServiceProviderView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct AddServiceProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var category: ServiceCategory = .generalContractor
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var address = ""
    @State private var website = ""
    @State private var notes = ""
    @State private var isFavorite = false
    @State private var rating = 0
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(ServiceCategory.allCases, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category)
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
                
                Section("Rating") {
                    HStack {
                        Text("Rating")
                        Spacer()
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .foregroundStyle(.yellow)
                                .onTapGesture {
                                    rating = star
                                }
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
            .navigationTitle("New Service Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addProvider()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func addProvider() {
        let provider = ServiceProvider(
            name: name,
            category: category,
            phoneNumber: phoneNumber,
            email: email
        )
        
        provider.address = address
        provider.website = website
        provider.notes = notes
        provider.isFavorite = isFavorite
        provider.rating = rating
        
        modelContext.insert(provider)
        dismiss()
    }
}

#Preview {
    AddServiceProviderView()
        .modelContainer(for: ServiceProvider.self, inMemory: true)
}
