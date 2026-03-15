//
//  ServiceProviderSuggestionsView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData
import MapKit

struct ServiceProviderSuggestionsView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(LocalBusinessSearchService.self) private var searchService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let category: ServiceCategory
    
    @State private var hasSearched = false
    
    var suggestions: [SuggestedBusiness] {
        guard let mapItems = searchService.searchResults[category] else { return [] }
        let businesses = mapItems.map { SuggestedBusiness(mapItem: $0, category: category) }
        
        // Sort by distance if we have user location
        if let userLocation = locationManager.userLocation {
            return businesses.sorted { business1, business2 in
                guard let loc1 = business1.mapItem.placemark.location,
                      let loc2 = business2.mapItem.placemark.location else {
                    return false
                }
                let dist1 = userLocation.distance(from: loc1)
                let dist2 = userLocation.distance(from: loc2)
                return dist1 < dist2
            }
        }
        
        return businesses
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                    ContentUnavailableView(
                        "Location Access Needed",
                        systemImage: "location.slash",
                        description: Text("Please enable location access in Settings to find local \(category.rawValue.lowercased())s")
                    )
                } else if !hasSearched {
                    VStack(spacing: 20) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        Text("Find Local \(category.rawValue)s")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("We'll search for local businesses near you")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            searchForBusinesses()
                        } label: {
                            Label("Search Near Me", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }
                    .padding()
                } else if searchService.isSearching {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Searching for local \(category.rawValue.lowercased())s...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if suggestions.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No local \(category.rawValue.lowercased())s found nearby")
                    )
                } else {
                    List {
                        Section {
                            ForEach(suggestions) { business in
                                SuggestedBusinessRow(
                                    business: business,
                                    userLocation: locationManager.userLocation
                                )
                            }
                        } header: {
                            Text("Found \(suggestions.count) local \(category.rawValue.lowercased())\(suggestions.count == 1 ? "" : "s") • Sorted by distance")
                        }
                    }
                }
            }
            .navigationTitle("Find \(category.rawValue)s")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if hasSearched && !searchService.isSearching {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            searchForBusinesses()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear {
                print("🔍 SuggestionsView appeared for category: \(category.rawValue)")
                print("🔍 Current auth status: \(locationManager.authorizationStatus.rawValue)")
                print("🔍 Has location: \(locationManager.userLocation != nil)")
                
                // Automatically start searching when view appears
                searchForBusinesses()
            }
        }
    }
    
    private func searchForBusinesses() {
        print("🔍 Search button tapped")
        print("🔍 Auth status: \(locationManager.authorizationStatus.rawValue)")
        print("🔍 Has location: \(locationManager.userLocation != nil)")
        
        // Request location if we don't have permission yet
        if locationManager.authorizationStatus == .notDetermined {
            print("🔍 Requesting location permission")
            locationManager.requestLocation()
            // Wait for location and retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("🔍 Retrying after permission request")
                self.searchForBusinesses()
            }
            return
        }
        
        // Check if we have location
        if let location = locationManager.userLocation {
            print("🔍 Have location, performing search")
            performSearch(at: location)
        } else {
            print("🔍 Don't have location yet, requesting")
            // Request location update
            locationManager.requestLocation()
            // Wait a bit and try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let location = self.locationManager.userLocation {
                    print("🔍 Got location after waiting, performing search")
                    self.performSearch(at: location)
                } else {
                    print("🔍 Still no location after waiting")
                    print("🔍 Error: \(self.locationManager.errorMessage ?? "no error")")
                }
            }
        }
    }
    
    private func performSearch(at location: CLLocation) {
        print("🔍 Performing search at location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        hasSearched = true
        Task {
            await searchService.searchForLocalBusinesses(category: category, near: location)
            await MainActor.run {
                print("🔍 Search completed, found \(suggestions.count) results")
            }
        }
    }
}

struct SuggestedBusinessRow: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allProviders: [ServiceProvider]
    
    let business: SuggestedBusiness
    let userLocation: CLLocation?
    
    @State private var showingAddConfirmation = false
    
    // Check if this business is already in saved providers
    var isAlreadyAdded: Bool {
        allProviders.contains { provider in
            // Match by name and category (could also match by phone if available)
            provider.name.lowercased() == business.name.lowercased() &&
            provider.category == business.category
        }
    }
    
    var distanceText: String? {
        guard let userLocation = userLocation,
              let businessLocation = business.mapItem.placemark.location else {
            return nil
        }
        
        let distance = userLocation.distance(from: businessLocation)
        let miles = distance / 1609.34 // Convert meters to miles
        
        if miles < 0.1 {
            return "nearby"
        } else if miles < 1 {
            return String(format: "%.1f mi", miles)
        } else {
            return String(format: "%.0f mi", miles)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(business.name)
                        .font(.headline)
                    
                    if let distance = distanceText {
                        Label(distance, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !business.address.isEmpty {
                        Text(business.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    if let phone = business.phoneNumber {
                        Text(phone)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                
                Spacer()
                
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
                    Button {
                        showingAddConfirmation = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Add \(business.name) to your providers?",
            isPresented: $showingAddConfirmation
        ) {
            Button("Add Provider") {
                addProvider()
            }
            
            Button("Cancel", role: .cancel) { }
        }
    }
    
    private func addProvider() {
        let provider = ServiceProvider(
            name: business.name,
            category: business.category,
            phoneNumber: business.phoneNumber ?? "",
            email: ""
        )
        
        provider.address = business.address
        
        modelContext.insert(provider)
    }
}

#Preview {
    ServiceProviderSuggestionsView(category: .plumber)
        .environment(LocationManager())
        .environment(LocalBusinessSearchService())
        .modelContainer(for: ServiceProvider.self, inMemory: true)
}
