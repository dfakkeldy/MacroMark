import Foundation
@preconcurrency import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    private var activeContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var isRequestingLocation = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func getCurrentLocation() async -> CLLocation? {
        // Guard against re-entrant calls that would silently overwrite stored continuations.
        // A leaked continuation produces a runtime warning then crashes at deallocation.
        guard !isRequestingLocation else { return nil }
        isRequestingLocation = true
        defer { isRequestingLocation = false }

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
