//
//  ServicesHomeManager.swift
//  Home Maintainer
//

import Foundation
import SwiftData

@Observable
final class HomeManager {
    var currentHome: Home?

    private let selectedHomeKey = "selectedHomeID"

    // MARK: - Selection

    func restoreSelection(from homes: [Home]) {
        let savedID = UserDefaults.standard.string(forKey: selectedHomeKey).flatMap { UUID(uuidString: $0) }
        if let id = savedID, let match = homes.first(where: { $0.id == id }) {
            currentHome = match
        } else if let first = homes.first {
            currentHome = first
            UserDefaults.standard.set(first.id.uuidString, forKey: selectedHomeKey)
        }
    }

    func select(_ home: Home) {
        currentHome = home
        UserDefaults.standard.set(home.id.uuidString, forKey: selectedHomeKey)
    }

    func clearSelection() {
        currentHome = nil
        UserDefaults.standard.removeObject(forKey: selectedHomeKey)
    }

    // MARK: - Owner detection

    /// A home is "yours" if it was created on this device, not imported from someone else.
    func isCurrentUserOwner(of home: Home) -> Bool {
        home.isLocallyCreated
    }

    // MARK: - File-open import coordination

    /// Set when the app is opened via a .homemaintainer file tap.
    /// Observed by ContentView to present the import confirmation sheet.
    var pendingImportURL: URL?
}
