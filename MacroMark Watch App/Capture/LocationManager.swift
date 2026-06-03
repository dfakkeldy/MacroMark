import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    private var activeContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<Void, Never>?
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    func getCurrentLocation() async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                self.authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        
        // If not authorized after requesting, return nil
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            self.activeContinuation = continuation
            manager.requestLocation()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.first {
                activeContinuation?.resume(returning: location)
                activeContinuation = nil
            }
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus != .notDetermined {
                authContinuation?.resume()
                authContinuation = nil
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("Location request failed: \(error)")
            activeContinuation?.resume(returning: nil)
            activeContinuation = nil
        }
    }
}
