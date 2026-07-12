//
//  ViewsAddHomeView.swift
//  Home Maintainer
//

import SwiftUI
import SwiftData

struct AddHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HomeManager.self) private var homeManager

    @State private var homeName = ""
    @State private var address = ""
    @State private var ownerName = UIDevice.current.name

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
                    TextField("Your Name", text: $ownerName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Owner")
                } footer: {
                    Text("Your name is shown to anyone you share this home with.")
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
        let home = Home(
            name: homeName.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            ownerName: ownerName.trimmingCharacters(in: .whitespaces),
            isLocallyCreated: true
        )
        modelContext.insert(home)
        try? modelContext.save()
        homeManager.select(home)
        dismiss()
    }
}
