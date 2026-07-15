//
//  LocalBusinessSearchService.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//
//  Proxies Google Places API via Firebase Cloud Function ("placesSearch").
//  The API key lives in Firebase Secret Manager — never in the app bundle.
//

import Foundation
import CoreLocation
import FirebaseFunctions

// MARK: - Google Place Result

struct GooglePlaceResult: Identifiable {
    let id: String
    let name: String
    let address: String
    let phoneNumber: String?
    let website: String?
    let rating: Double?
    let userRatingCount: Int?
    let priceLevel: String?
    let types: [String]
    let weekdayDescriptions: [String]?
    let latitude: Double?
    let longitude: Double?
    var category: ServiceCategory

    var displayPriceLevel: String? {
        switch priceLevel {
        case "PRICE_LEVEL_INEXPENSIVE": return "$"
        case "PRICE_LEVEL_MODERATE": return "$$"
        case "PRICE_LEVEL_EXPENSIVE": return "$$$"
        case "PRICE_LEVEL_VERY_EXPENSIVE": return "$$$$"
        default: return nil
        }
    }

    var location: CLLocation? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }

    func distanceFrom(_ userLocation: CLLocation) -> CLLocationDistance? {
        location?.distance(from: userLocation)
    }

    var mapsURL: URL? {
        if let lat = latitude, let lon = longitude {
            let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "maps://?ll=\(lat),\(lon)&q=\(q)")
        } else if !address.isEmpty,
                  let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "maps://?q=\(encoded)")
        }
        return nil
    }

    var primaryTypeDisplay: String? {
        let skip = Set(["point_of_interest", "establishment", "local_government_office", "store", "food", "health"])
        return types.first { !skip.contains($0) }
            .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
    }
}

// MARK: - API Decodable Types

private struct PlacesResponse: Decodable {
    let places: [PlaceData]?
}

private struct PlaceData: Decodable {
    let id: String?
    let displayName: DisplayName?
    let formattedAddress: String?
    let nationalPhoneNumber: String?
    let websiteUri: String?
    let rating: Double?
    let userRatingCount: Int?
    let priceLevel: String?
    let types: [String]?
    let regularOpeningHours: OpeningHours?
    let location: PlaceLocation?
}

private struct DisplayName: Decodable {
    let text: String?
}

private struct OpeningHours: Decodable {
    let weekdayDescriptions: [String]?
}

private struct PlaceLocation: Decodable {
    let latitude: Double?
    let longitude: Double?
}

// MARK: - Service

@Observable
class LocalBusinessSearchService {
    var searchResults: [ServiceCategory: [GooglePlaceResult]] = [:]
    var textSearchResults: [GooglePlaceResult] = []
    var isSearching = false
    var searchError: String?

    // Category-based search (used by category quick-chips in FindBusinessesView)
    func searchForLocalBusinesses(category: ServiceCategory, near location: CLLocation) async {
        await MainActor.run { isSearching = true; searchError = nil }
        let raw = await performSearch(query: category.searchQuery, near: location)
        let tagged = raw.map { place -> GooglePlaceResult in var p = place; p.category = category; return p }
        await MainActor.run {
            searchResults[category] = tagged
            isSearching = false
        }
    }

    // Free-form text search (used by the search bar and hAIndyman)
    func textSearch(query: String, near location: CLLocation?, radiusMiles: Double = 10) async {
        await MainActor.run { isSearching = true; searchError = nil; textSearchResults = [] }
        let results = await performSearch(query: query, near: location, radiusMeters: radiusMiles * 1609.34)
        await MainActor.run {
            textSearchResults = results
            isSearching = false
        }
    }

    private func performSearch(query: String, near location: CLLocation?, radiusMeters: Double = 16093.4) async -> [GooglePlaceResult] {
        let callable = Functions.functions().httpsCallable("placesSearch")
        var params: [String: Any] = ["query": query]
        if let loc = location {
            params["latitude"] = loc.coordinate.latitude
            params["longitude"] = loc.coordinate.longitude
            params["radius"] = radiusMeters
        }

        do {
            let result = try await callable.call(params)
            // Re-encode the response dict back to JSON so we can reuse our Decodable types
            guard let responseDict = result.data as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: responseDict) else {
                return []
            }
            let response = try JSONDecoder().decode(PlacesResponse.self, from: jsonData)
            return (response.places ?? []).compactMap { place -> GooglePlaceResult? in
                guard let id = place.id, let name = place.displayName?.text else { return nil }
                let types = place.types ?? []
                return GooglePlaceResult(
                    id: id,
                    name: name,
                    address: place.formattedAddress ?? "",
                    phoneNumber: place.nationalPhoneNumber,
                    website: place.websiteUri,
                    rating: place.rating,
                    userRatingCount: place.userRatingCount,
                    priceLevel: place.priceLevel,
                    types: types,
                    weekdayDescriptions: place.regularOpeningHours?.weekdayDescriptions,
                    latitude: place.location?.latitude,
                    longitude: place.location?.longitude,
                    category: ServiceCategory.fromGoogleTypes(types)
                )
            }
        } catch {
            await MainActor.run { searchError = error.localizedDescription }
            return []
        }
    }
}
