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
    @Environment(HomeManager.self) private var homeManager
    @Environment(NavigationCoordinator.self) private var coordinator
    @Query(sort: \Appliance.name) private var allAppliances: [Appliance]
    @State private var showingAddAppliance = false
    @State private var showingHomePicker = false
    @State private var navigationTarget: Appliance? = nil

    private var appliances: [Appliance] {
        guard let home = homeManager.currentHome else { return [] }
        return allAppliances.filter { !$0.isDeleted && $0.home?.id == home.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if homeManager.currentHome == nil {
                    ContentUnavailableView {
                        Label("No Home Selected", systemImage: "house")
                    } description: {
                        Text("Create or select a home to manage appliances.")
                    } actions: {
                        Button("Select Home") { showingHomePicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
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
                }
            }
            .navigationTitle("Appliances")
            .navigationDestination(item: $navigationTarget) { appliance in
                ApplianceDetailView(appliance: appliance)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomePickerButton(showingPicker: $showingHomePicker)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddAppliance = true
                    } label: {
                        Label("Add Appliance", systemImage: "plus")
                    }
                    .disabled(homeManager.currentHome == nil)
                }
            }
            .sheet(isPresented: $showingAddAppliance) {
                AddApplianceView(home: homeManager.currentHome)
            }
            .sheet(isPresented: $showingHomePicker) {
                HomePickerView()
            }
            .onAppear { handlePendingNavigation() }
            .onChange(of: coordinator.pendingAppliance) { _, _ in handlePendingNavigation() }
        }
    }

    private func handlePendingNavigation() {
        if let appliance = coordinator.pendingAppliance {
            navigationTarget = appliance
            coordinator.pendingAppliance = nil
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
        if appliance.isDeleted {
            EmptyView()
        } else {
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
}

#Preview {
    AppliancesView()
        .modelContainer(for: Appliance.self, inMemory: true)
        .environment(NavigationCoordinator())
        .environment(HomeManager())
}
