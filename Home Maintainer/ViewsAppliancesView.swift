//
//  AppliancesView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct AppliancesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Appliance.name) private var appliances: [Appliance]
    @State private var showingAddAppliance = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(appliances) { appliance in
                    NavigationLink(destination: ApplianceDetailView(appliance: appliance)) {
                        ApplianceRow(appliance: appliance)
                    }
                }
                .onDelete(perform: deleteAppliances)
                
                if appliances.isEmpty {
                    ContentUnavailableView(
                        "No Appliances",
                        systemImage: "refrigerator",
                        description: Text("Add your appliances to track their maintenance")
                    )
                }
            }
            .navigationTitle("Appliances")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddAppliance = true
                    } label: {
                        Label("Add Appliance", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAppliance) {
                AddApplianceView()
            }
        }
    }
    
    private func deleteAppliances(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(appliances[index])
        }
    }
}

struct ApplianceRow: View {
    let appliance: Appliance
    
    var body: some View {
        HStack {
            Image(systemName: appliance.type.systemImage)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(appliance.name)
                    .font(.headline)
                
                HStack {
                    Text(appliance.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !appliance.manufacturer.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(appliance.manufacturer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    AppliancesView()
        .modelContainer(for: Appliance.self, inMemory: true)
}
