//
//  LocationManager.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import Foundation
import CoreLocation
import Observation

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var userLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var errorMessage: String?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
        
        // If already authorized, get location immediately
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
    
    func requestLocation() {
        print("📍 LocationManager: Requesting location, current status: \(authorizationStatus.rawValue)")
        
        switch authorizationStatus {
        case .notDetermined:
            print("📍 LocationManager: Requesting authorization")
            manager.requestWhenInUseAuthorization()
            // Location will be requested in locationManagerDidChangeAuthorization
            
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 LocationManager: Already authorized, requesting location")
            manager.requestLocation()
            
        case .denied, .restricted:
            print("📍 LocationManager: Location access denied or restricted")
            errorMessage = "Location access denied. Please enable in Settings."
            
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            print("📍 LocationManager: Got location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            userLocation = location
            errorMessage = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 LocationManager: Error - \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        
        // If it's a "location unknown" error, try again
        if let clError = error as? CLError, clError.code == .locationUnknown {
            print("📍 LocationManager: Location unknown, will retry")
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        print("📍 LocationManager: Authorization changed to: \(authorizationStatus.rawValue)")
        
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            print("📍 LocationManager: Now authorized, requesting location")
            manager.requestLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            errorMessage = "Location access denied. Please enable in Settings."
        }
    }
}
