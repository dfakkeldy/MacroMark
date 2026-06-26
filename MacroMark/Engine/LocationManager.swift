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
    private var isRequestingLocation = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func getCurrentLocation() async -> CLLocation? {
        guard !isRequestingLocation else { return nil }
        isRequestingLocation = true
        defer { isRequestingLocation = false }

        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                self.authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

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
        // Read the Sendable status on the delegate thread; never capture the
        // non-Sendable `manager` in the main-actor closure (that would let a
        // task-isolated reference race against later nonisolated uses).
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status != .notDetermined {
                authContinuation?.resume()
                authContinuation = nil
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            #if DEBUG
            print("Location request failed: \(error)")
            #endif
            activeContinuation?.resume(returning: nil)
            activeContinuation = nil
        }
    }
}
