//
//  ServiceProviderSuggestionsView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData
import CoreLocation

// MARK: - Find Businesses Modal

struct FindBusinessesView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(LocalBusinessSearchService.self) private var searchService
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeManager.self) private var homeManager
    @Environment(\.dismiss) private var dismiss

    var initialCategory: ServiceCategory?

    @State private var searchText = ""
    @State private var radiusMiles: Double = 10
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?

    private var sortedResults: [GooglePlaceResult] {
        let items = searchService.textSearchResults
        guard let loc = locationManager.userLocation else { return items }
        return items.sorted {
            let d1 = $0.distanceFrom(loc) ?? .greatestFiniteMagnitude
            let d2 = $1.distanceFrom(loc) ?? .greatestFiniteMagnitude
            return d1 < d2
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                    ContentUnavailableView(
                        "Location Access Needed",
                        systemImage: "location.slash",
                        description: Text("Enable location access in Settings to find local businesses near you.")
                    )
                } else if !hasSearched {
                    initialStateView
                } else if searchService.isSearching {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Searching Google Places…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = searchService.searchError {
                    ContentUnavailableView(
                        "Search Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if sortedResults.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No businesses found for \"\(searchText)\". Try a different search.")
                    )
                } else {
                    resultsList
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "location.circle")
                        .foregroundStyle(.secondary)
                    Slider(value: $radiusMiles, in: 5...50, step: 5)
                    Text("\(Int(radiusMiles)) mi")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Find Businesses")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search (e.g., plumbers, roofers)"
            )
            .onSubmit(of: .search) { performSearch() }
            .onChange(of: searchText) { _, new in
                if new.isEmpty {
                    hasSearched = false
                    searchService.textSearchResults = []
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if hasSearched && !searchService.isSearching {
                    ToolbarItem(placement: .primaryAction) {
                        Button { performSearch() } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear {
                if let category = initialCategory {
                    searchText = category.searchQuery
                    performSearch()
                }
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestLocation()
                }
            }
        }
    }

    private var initialStateView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    Text("Find Local Businesses")
                        .font(.title2.weight(.semibold))
                    Text("Type in the search bar above, or tap a category below")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ServiceCategory.allCases.filter { $0 != .other }) { category in
                        Button {
                            searchText = category.searchQuery
                            performSearch()
                        } label: {
                            HStack {
                                Image(systemName: category.systemImage)
                                    .foregroundStyle(.blue)
                                    .frame(width: 20)
                                Text(category.rawValue)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
    }

    private var resultsList: some View {
        List {
            Section {
                ForEach(sortedResults) { place in
                    GooglePlaceRow(place: place, userLocation: locationManager.userLocation, home: homeManager.currentHome)
                }
            } header: {
                Text("\(sortedResults.count) result\(sortedResults.count == 1 ? "" : "s") • Sorted by distance")
            }
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        hasSearched = true
        searchTask?.cancel()
        searchTask = Task {
            await searchService.textSearch(query: query, near: locationManager.userLocation, radiusMiles: radiusMiles)
        }
    }
}

// MARK: - Google Place Row

struct GooglePlaceRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudSharingService.self) private var cloudSharingService
    @Query private var allProviders: [ServiceProvider]

    let place: GooglePlaceResult
    let userLocation: CLLocation?
    let home: Home?

    private var isAlreadyAdded: Bool {
        allProviders.contains { $0.googlePlaceID == place.id || $0.name.lowercased() == place.name.lowercased() }
    }

    private var distanceText: String? {
        guard let userLocation, let dist = place.distanceFrom(userLocation) else { return nil }
        let miles = dist / 1609.34
        if miles < 0.1 { return "nearby" }
        if miles < 1 { return String(format: "%.1f mi", miles) }
        return String(format: "%.0f mi", miles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.headline)

                    // Rating / price / type row
                    HStack(spacing: 8) {
                        if let rating = place.rating {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.caption)
                                if let count = place.userRatingCount {
                                    Text("(\(count))")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        if let price = place.displayPriceLevel {
                            Text(price)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let type = place.primaryTypeDisplay {
                            Text(type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let dist = distanceText {
                        Label(dist, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !place.address.isEmpty {
                        if let mapsURL = place.mapsURL {
                            Link(destination: mapsURL) {
                                Text(place.address)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .lineLimit(2)
                            }
                        } else {
                            Text(place.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    if let phone = place.phoneNumber,
                       let url = URL(string: "tel:\(phone.filter { "0123456789+".contains($0) })") {
                        Link(phone, destination: url)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if let website = place.website, let url = URL(string: website) {
                        Link(website, destination: url)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isAlreadyAdded {
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text("Added")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button { addProvider() } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Today's hours
            if let hours = place.weekdayDescriptions, !hours.isEmpty {
                let todayIdx = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
                if todayIdx < hours.count {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(hours[todayIdx])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func addProvider() {
        let provider = ServiceProvider(
            name: place.name,
            category: place.category,
            phoneNumber: place.phoneNumber ?? "",
            email: ""
        )
        provider.address = place.address
        provider.website = place.website ?? ""
        provider.googlePlaceID = place.id
        provider.googleRating = place.rating
        provider.googlePriceLevel = place.priceLevel
        provider.weekdayHours = place.weekdayDescriptions
        provider.businessTypes = place.types.isEmpty ? nil : place.types
        if let home, !cloudSharingService.isInSharedStore(entityName: "Home", id: home.id) {
            provider.home = home
        }
        provider.homeIDString = home?.id.uuidString
        modelContext.insert(provider)
    }
}

// Backward-compat alias — ServiceProvidersView still references this name
typealias ServiceProviderSuggestionsView = FindBusinessesView

#Preview {
    FindBusinessesView()
        .environment(LocationManager())
        .environment(LocalBusinessSearchService())
        .environment(HomeManager())
        .modelContainer(for: ServiceProvider.self, inMemory: true)
}
