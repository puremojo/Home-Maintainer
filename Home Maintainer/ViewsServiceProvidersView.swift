//
//  ServiceProvidersView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct ServiceProvidersView: View {
    var body: some View {
        NavigationStack {
            ServiceProvidersContent()
        }
    }
}

struct ServiceProvidersContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeManager.self) private var homeManager
    @Environment(LocationManager.self) private var locationManager
    @Environment(LocalBusinessSearchService.self) private var searchService
    @Query(sort: \ServiceProvider.name) private var allProviders: [ServiceProvider]
    @State private var showingAddProvider = false
    @State private var showingHomePicker = false
    @State private var selectedCategory: ServiceCategory?
    @State private var suggestionCategory: ServiceCategory?

    let suggestedCategories: [ServiceCategory] = [.plumber, .electrician, .roofer]

    private var providers: [ServiceProvider] {
        guard let home = homeManager.currentHome else { return [] }
        return allProviders.filter { $0.home?.id == home.id }
    }

    var filteredProviders: [ServiceProvider] {
        if let category = selectedCategory {
            return providers.filter { $0.category == category }
        }
        return providers
    }

    var providersByCategory: [ServiceCategory: [ServiceProvider]] {
        let grouped = Dictionary(grouping: filteredProviders, by: { $0.category })
        return grouped.mapValues { providers in
            providers.sorted { provider1, provider2 in
                if provider1.isFavorite != provider2.isFavorite {
                    return provider1.isFavorite
                }
                return provider1.name < provider2.name
            }
        }
    }

    var body: some View {
        Group {
            if homeManager.currentHome == nil {
                ContentUnavailableView {
                    Label("No Home Selected", systemImage: "house")
                } description: {
                    Text("Create or select a home to manage service providers.")
                } actions: {
                    Button("Select Home") { showingHomePicker = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    if selectedCategory == nil && providers.isEmpty {
                        Section {
                            ContentUnavailableView(
                                "No Service Providers",
                                systemImage: "person.2",
                                description: Text("Get started by finding local businesses or add your own")
                            )
                        }
                    }

                    if selectedCategory == nil {
                        Section("Find Local Businesses") {
                            ForEach(suggestedCategories, id: \.self) { category in
                                Button {
                                    suggestionCategory = category
                                } label: {
                                    HStack {
                                        Image(systemName: category.systemImage)
                                            .font(.title3)
                                            .foregroundStyle(.blue)
                                            .frame(width: 30)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(category.rawValue)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text("Find local \(category.rawValue.lowercased())s near you")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if !providers.isEmpty {
                        ForEach(Array(providersByCategory.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { category in
                            Section(category.rawValue) {
                                ForEach(providersByCategory[category] ?? []) { provider in
                                    NavigationLink(destination: ServiceProviderDetailView(provider: provider)) {
                                        ServiceProviderRow(provider: provider)
                                    }
                                }
                                .onDelete { offsets in
                                    deleteProviders(at: offsets, in: category)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Service Providers")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HomePickerButton(showingPicker: $showingHomePicker)
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("All Categories") { selectedCategory = nil }
                    Divider()
                    ForEach(ServiceCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) { selectedCategory = category }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddProvider = true
                } label: {
                    Label("Add Provider", systemImage: "plus")
                }
                .disabled(homeManager.currentHome == nil)
            }
        }
        .sheet(isPresented: $showingAddProvider) {
            AddServiceProviderView(home: homeManager.currentHome)
        }
        .sheet(isPresented: $showingHomePicker) {
            HomePickerView()
        }
        .sheet(item: $suggestionCategory) { category in
            ServiceProviderSuggestionsView(category: category)
        }
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestLocation()
            }
        }
    }

    private func deleteProviders(at offsets: IndexSet, in category: ServiceCategory) {
        let providersInCategory = providersByCategory[category] ?? []
        for index in offsets {
            modelContext.delete(providersInCategory[index])
        }
    }
}

struct ServiceProviderRow: View {
    let provider: ServiceProvider
    
    var body: some View {
        HStack {
            Image(systemName: provider.category.systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(provider.name)
                        .font(.headline)
                    
                    if provider.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                
                if !provider.phoneNumber.isEmpty {
                    Text(provider.phoneNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if provider.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < provider.rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ServiceProvidersView()
        .environment(LocationManager())
        .environment(LocalBusinessSearchService())
        .modelContainer(for: ServiceProvider.self, inMemory: true)
}
