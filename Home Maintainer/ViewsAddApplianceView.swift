//
//  AddApplianceView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddApplianceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let home: Home?

    init(home: Home? = nil) {
        self.home = home
    }

    @State private var name = ""
    @State private var type: ApplianceType = .refrigerator
    @State private var manufacturer = ""
    @State private var modelNumber = ""
    @State private var purchaseDate: Date?
    @State private var warrantyExpiration: Date?
    @State private var notes = ""
    @State private var hasPurchaseDate = false
    @State private var hasWarranty = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var photoData: [Data] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(ApplianceType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                }
                
                Section("Details") {
                    TextField("Manufacturer", text: $manufacturer)
                    TextField("Model Number", text: $modelNumber)
                }
                
                Section {
                    Toggle("Set Purchase Date", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("Purchase Date", selection: Binding(
                            get: { purchaseDate ?? Date() },
                            set: { purchaseDate = $0 }
                        ), displayedComponents: .date)
                    }
                }
                
                Section {
                    Toggle("Set Warranty Expiration", isOn: $hasWarranty)
                    if hasWarranty {
                        DatePicker("Warranty Expires", selection: Binding(
                            get: { warrantyExpiration ?? Date() },
                            set: { warrantyExpiration = $0 }
                        ), displayedComponents: .date)
                    }
                }
                
                Section {
                    if !photoData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(photoData.enumerated()), id: \.offset) { index, data in
                                    if let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    photoData.remove(at: index)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    PhotosPicker(selection: $photoPickerItems, matching: .images) {
                        Label("Add Pictures", systemImage: "photo.badge.plus")
                    }
                } header: {
                    Text("Pictures")
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Appliance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addAppliance()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onChange(of: photoPickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var loaded: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            loaded.append(data)
                        }
                    }
                    photoData.append(contentsOf: loaded)
                    photoPickerItems = []
                }
            }
        }
    }

    private func addAppliance() {
        let appliance = Appliance(
            name: name,
            type: type,
            manufacturer: manufacturer,
            modelNumber: modelNumber
        )
        
        if hasPurchaseDate {
            appliance.purchaseDate = purchaseDate
        }
        
        if hasWarranty {
            appliance.warrantyExpiration = warrantyExpiration
        }
        
        appliance.notes = notes
        appliance.home = home

        modelContext.insert(appliance)

        for data in photoData {
            appliance.addPhoto(data: data)
        }

        dismiss()
    }
}

#Preview {
    AddApplianceView()
        .modelContainer(for: Appliance.self, inMemory: true)
}
