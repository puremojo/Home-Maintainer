//
//  LocalBusinessSearchService.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import MapKit
import CoreLocation

@Observable
class LocalBusinessSearchService {
    var searchResults: [ServiceCategory: [MKMapItem]] = [:]
    var isSearching = false
    
    func searchForLocalBusinesses(category: ServiceCategory, near location: CLLocation) async {
        isSearching = true
        defer { isSearching = false }
        
        let searchQuery = searchQueryForCategory(category)
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 16000, // ~10 miles
            longitudinalMeters: 16000
        )
        request.resultTypes = .pointOfInterest
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            await MainActor.run {
                searchResults[category] = response.mapItems
            }
        } catch {
            print("Search error for \(category.rawValue): \(error.localizedDescription)")
            await MainActor.run {
                searchResults[category] = []
            }
        }
    }
    
    func searchMultipleCategories(categories: [ServiceCategory], near location: CLLocation) async {
        await withTaskGroup(of: Void.self) { group in
            for category in categories {
                group.addTask {
                    await self.searchForLocalBusinesses(category: category, near: location)
                }
            }
        }
    }
    
    private func searchQueryForCategory(_ category: ServiceCategory) -> String {
        switch category {
        case .electrician:
            return "electrician"
        case .plumber:
            return "plumber"
        case .generalContractor:
            return "general contractor"
        case .roofer:
            return "roofer"
        case .hvac:
            return "HVAC contractor"
        case .carpenter:
            return "carpenter"
        case .painter:
            return "painter"
        case .landscaper:
            return "landscaper"
        case .handyman:
            return "handyman"
        case .appliance:
            return "appliance repair"
        case .other:
            return "home repair"
        }
    }
}

struct SuggestedBusiness: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
    let category: ServiceCategory
    
    var name: String {
        mapItem.name ?? "Unknown Business"
    }
    
    var phoneNumber: String? {
        mapItem.phoneNumber
    }
    
    var address: String {
        let placemark = mapItem.placemark
        var components: [String] = []
        
        if let street = placemark.thoroughfare {
            components.append(street)
        }
        if let city = placemark.locality {
            components.append(city)
        }
        if let state = placemark.administrativeArea {
            components.append(state)
        }
        if let zip = placemark.postalCode {
            components.append(zip)
        }
        
        return components.joined(separator: ", ")
    }
    
    var distance: CLLocationDistance? {
        guard let location = mapItem.placemark.location else { return nil }
        return location.distance(from: location)
    }
    
    // Get rating from MKMapItem if available (iOS 16.0+)
    var rating: Double? {
        // MapKit provides ratings through the mapItem
        return nil // MapKit doesn't directly expose ratings in MKMapItem, but sorts by relevance
    }
}

