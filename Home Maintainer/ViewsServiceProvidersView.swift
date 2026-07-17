//
//  ServiceProvidersView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

// MARK: - Sort Mode

enum ProviderSortMode: String, CaseIterable {
    case byCategory = "Sort by Category"
    case favoritesFirst = "Favorites First"
}

// MARK: - Root View

struct ServiceProvidersView: View {
    var body: some View {
        NavigationStack {
            ServiceProvidersContent()
        }
    }
}

// MARK: - Content

struct ServiceProvidersContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeManager.self) private var homeManager
    @Environment(LocationManager.self) private var locationManager
    @Query(sort: \ServiceProvider.name) private var allProviders: [ServiceProvider]

    @State private var showingAddProvider = false
    @State private var showingHomePicker = false
    @State private var showingFindBusinesses = false
    @State private var sortMode: ProviderSortMode = .byCategory
    @State private var searchText = ""

    private var providers: [ServiceProvider] {
        guard let home = homeManager.currentHome else { return [] }
        return allProviders.filter { !$0.isDeleted && $0.home?.id == home.id }
    }

    private var filteredProviders: [ServiceProvider] {
        guard !searchText.isEmpty else { return providers }
        let q = searchText.lowercased()
        return providers.filter {
            $0.name.lowercased().contains(q) ||
            $0.category.rawValue.lowercased().contains(q) ||
            $0.address.lowercased().contains(q) ||
            $0.phoneNumber.contains(q)
        }
    }

    private var providersByCategory: [ServiceCategory: [ServiceProvider]] {
        Dictionary(grouping: filteredProviders, by: { $0.category })
            .mapValues { $0.sorted { p1, p2 in
                if p1.isFavorite != p2.isFavorite { return p1.isFavorite }
                return p1.name < p2.name
            }}
    }

    private var favorites: [ServiceProvider] {
        filteredProviders.filter { $0.isFavorite }.sorted { $0.name < $1.name }
    }

    private var nonFavoritesByCategory: [ServiceCategory: [ServiceProvider]] {
        Dictionary(grouping: filteredProviders.filter { !$0.isFavorite }, by: { $0.category })
            .mapValues { $0.sorted { $0.name < $1.name } }
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
                listContent
            }
        }
        .navigationTitle("Service Providers")
        .searchable(text: $searchText, prompt: "Search providers")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HomePickerButton(showingPicker: $showingHomePicker)
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(ProviderSortMode.allCases, id: \.self) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            if sortMode == mode {
                                Label(mode.rawValue, systemImage: "checkmark")
                            } else {
                                Text(mode.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingFindBusinesses = true
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddProvider = true
                } label: {
                    Label("Add", systemImage: "plus")
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
        .sheet(isPresented: $showingFindBusinesses) {
            FindBusinessesView()
        }
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestLocation()
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if filteredProviders.isEmpty {
            if !searchText.isEmpty {
                List { }.overlay(ContentUnavailableView.search(text: searchText))
            } else {
                List {
                    ContentUnavailableView(
                        "No Service Providers",
                        systemImage: "person.2",
                        description: Text("Tap the search icon to find local businesses, or + to add manually.")
                    )
                }
            }
        } else {
            List {
                switch sortMode {
                case .byCategory:
                    byCategoryRows
                case .favoritesFirst:
                    favoritesFirstRows
                }
            }
            .navigationDestination(for: ServiceProvider.self) { provider in
                ServiceProviderDetailView(provider: provider)
            }
        }
    }

    @ViewBuilder
    private var byCategoryRows: some View {
        let sortedCategories = providersByCategory.keys.sorted { $0.rawValue < $1.rawValue }
        ForEach(sortedCategories, id: \.self) { category in
            Section(category.rawValue) {
                ForEach(providersByCategory[category] ?? []) { provider in
                    ServiceProviderRow(provider: provider)
                }
                .onDelete { offsets in
                    deleteProviders(at: offsets, from: providersByCategory[category] ?? [])
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesFirstRows: some View {
        if !favorites.isEmpty {
            Section("Favorites") {
                ForEach(favorites) { provider in
                    ServiceProviderRow(provider: provider)
                }
            }
        }
        let sortedCategories = nonFavoritesByCategory.keys.sorted { $0.rawValue < $1.rawValue }
        ForEach(sortedCategories, id: \.self) { category in
            Section(category.rawValue) {
                ForEach(nonFavoritesByCategory[category] ?? []) { provider in
                    ServiceProviderRow(provider: provider)
                }
                .onDelete { offsets in
                    deleteProviders(at: offsets, from: nonFavoritesByCategory[category] ?? [])
                }
            }
        }
    }

    private func deleteProviders(at offsets: IndexSet, from list: [ServiceProvider]) {
        for index in offsets {
            modelContext.delete(list[index])
        }
    }
}

// MARK: - Provider Row
// Name tap → navigates to detail. Phone number is a tappable Link that opens the iOS call prompt.

struct ServiceProviderRow: View {
    let provider: ServiceProvider

    private var cleanPhone: String {
        provider.phoneNumber.filter { "0123456789+".contains($0) }
    }

    var body: some View {
        if provider.isDeleted {
            EmptyView()
        } else {
            HStack(alignment: .center, spacing: 0) {
                // NavigationLink wraps icon + name only
                NavigationLink(value: provider) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: provider.category.systemImage)
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(provider.name)
                                    .font(.headline)
                                if provider.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                }
                            }
                            if let rating = provider.googleRating {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", rating))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Phone sits outside the NavigationLink so it gets its own tap target
                if !provider.phoneNumber.isEmpty, let url = URL(string: "tel:\(cleanPhone)") {
                    Link(provider.phoneNumber, destination: url)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.leading, 8)
                }
            }
        }
    }
}

#Preview {
    ServiceProvidersView()
        .environment(LocationManager())
        .environment(LocalBusinessSearchService())
        .environment(HomeManager())
        .modelContainer(for: ServiceProvider.self, inMemory: true)
}
