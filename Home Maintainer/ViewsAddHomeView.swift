//
//  ViewsAddHomeView.swift
//  Home Maintainer
//

import SwiftUI
import CoreData

struct AddHomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HomeManager.self) private var homeManager
    @Environment(AuthService.self) private var authService

    @State private var homeName = ""
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Home Name", text: $homeName)
                        .autocorrectionDisabled()
                    TextField("Address (optional)", text: $address)
                        .autocorrectionDisabled()
                } header: {
                    Text("Home Details")
                } footer: {
                    Text("Give your home a name like \"Oak Street House\" or \"Main Apartment\".")
                }

                Section {
                    HStack {
                        Text(authService.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Owner")
                } footer: {
                    Text("Linked to your Apple ID. Shown to anyone you share this home with.")
                }
            }
            .navigationTitle("New Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveHome()
                    }
                    .disabled(homeName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveHome() {
        let home = Home.make(
            name: homeName.trimmingCharacters(in: .whitespaces),
            ownerName: authService.displayName,
            address: address.trimmingCharacters(in: .whitespaces),
            isLocallyCreated: true,
            in: viewContext
        )
        try? viewContext.save()
        homeManager.select(home)
        dismiss()
    }
}
