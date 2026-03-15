//
//  AddApplianceView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct AddApplianceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var type: ApplianceType = .refrigerator
    @State private var manufacturer = ""
    @State private var modelNumber = ""
    @State private var purchaseDate: Date?
    @State private var warrantyExpiration: Date?
    @State private var notes = ""
    @State private var hasPurchaseDate = false
    @State private var hasWarranty = false
    
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
        
        modelContext.insert(appliance)
        dismiss()
    }
}

#Preview {
    AddApplianceView()
        .modelContainer(for: Appliance.self, inMemory: true)
}
