//
//  AddServiceProviderView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import CoreData

struct AddServiceProviderView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudSharingService.self) private var cloudSharingService

    let home: Home?

    init(home: Home? = nil) {
        self.home = home
    }

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
        let isSharedHome = home.map {
            cloudSharingService.isInSharedStore(entityName: "Home", id: $0.id)
        } ?? false
        let isOwnedSharedHome = !isSharedHome && (home.map {
            cloudSharingService.isOwnedAndShared(homeID: $0.id)
        } ?? false)

        if isSharedHome, let home {
            addProviderToSharedStore(home: home)
        } else if isOwnedSharedHome, let home {
            addProviderToOwnedSharedStore(home: home)
        } else {
            addProviderToPrivateStore()
        }
        dismiss()
    }

    private func addProviderToSharedStore(home: Home) {
        let homeIDStr = home.id.uuidString
        do {
            let homeObj = cloudSharingService.findHomeManagedObject(id: home.id)
            try cloudSharingService.insertIntoSharedStore(entityName: "ServiceProvider") { obj in
                obj.setValue(UUID(), forKey: "id")
                obj.setValue(name, forKey: "name")
                obj.setValue(category.rawValue, forKey: "categoryRaw")
                obj.setValue(phoneNumber, forKey: "phoneNumber")
                obj.setValue(email, forKey: "email")
                obj.setValue(address, forKey: "address")
                obj.setValue(website, forKey: "website")
                obj.setValue(notes, forKey: "notes")
                obj.setValue(isFavorite, forKey: "isFavorite")
                obj.setValue(Int32(rating), forKey: "rating")
                obj.setValue(Date(), forKey: "createdAt")
                obj.setValue(homeIDStr, forKey: "homeIDString")
                obj.setValue(homeObj, forKey: "home")
            }
            try cloudSharingService.saveSharedContext()
        } catch {
            print("[AddServiceProvider] Shared store insert failed: \(error)")
        }
    }

    private func addProviderToOwnedSharedStore(home: Home) {
        let homeIDStr = home.id.uuidString
        do {
            let homeObj = cloudSharingService.findHomeManagedObject(id: home.id)
            try cloudSharingService.insertLinkedToHome(entityName: "ServiceProvider") { obj in
                obj.setValue(UUID(), forKey: "id")
                obj.setValue(name, forKey: "name")
                obj.setValue(category.rawValue, forKey: "categoryRaw")
                obj.setValue(phoneNumber, forKey: "phoneNumber")
                obj.setValue(email, forKey: "email")
                obj.setValue(address, forKey: "address")
                obj.setValue(website, forKey: "website")
                obj.setValue(notes, forKey: "notes")
                obj.setValue(isFavorite, forKey: "isFavorite")
                obj.setValue(Int32(rating), forKey: "rating")
                obj.setValue(Date(), forKey: "createdAt")
                obj.setValue(homeIDStr, forKey: "homeIDString")
                obj.setValue(homeObj, forKey: "home")
            }
            try cloudSharingService.saveSharedContext()
        } catch {
            NSLog("[AddServiceProvider] Owner-shared insert failed: \(error)")
        }
    }

    private func addProviderToPrivateStore() {
        let provider = ServiceProvider.make(
            name: name,
            category: category,
            phoneNumber: phoneNumber,
            email: email,
            in: viewContext
        )
        provider.address = address
        provider.website = website
        provider.notes = notes
        provider.isFavorite = isFavorite
        provider.rating = Int32(rating)
        if let home, !cloudSharingService.isInSharedStore(entityName: "Home", id: home.id) {
            provider.home = home
        }
        provider.homeIDString = home?.id.uuidString
        try? viewContext.save()
    }
}

#Preview { Text("Preview unavailable") }
