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

/// Shows the appliance's primary photo as a thumbnail, falling back to the
/// type's SF Symbol icon when no photo has been added.
struct ApplianceIconView: View {
    let appliance: Appliance
    var size: CGFloat = 40

    var body: some View {
        if let data = appliance.primaryPhotoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: appliance.type.systemImage)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: size, height: size)
        }
    }
}

struct ApplianceRow: View {
    let appliance: Appliance

    var body: some View {
        HStack {
            ApplianceIconView(appliance: appliance)

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
