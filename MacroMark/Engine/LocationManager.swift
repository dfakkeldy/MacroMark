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
    // Monotonic per-request tokens. A timeout may only resume the continuation if
    // its request is still the current one. Cancelling a timeout is not enough:
    // `Task.cancel()` only throws at the `Task.sleep` suspension point, so the
    // body still runs afterward — and a presence-only check ("is some continuation
    // pending?") could let a stale timeout resume a *later* request's continuation.
    // Comparing the token (identity) keeps each request isolated.
    private var locationGeneration = 0
    private var authGeneration = 0
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
                self.authGeneration += 1
                let generation = self.authGeneration
                manager.requestWhenInUseAuthorization()
                // Don't wait forever if the authorization callback never fires.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    guard self.authGeneration == generation, let pending = self.authContinuation else { return }
                    self.authContinuation = nil
                    pending.resume()
                }
            }
        }

        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.activeContinuation = continuation
            self.locationGeneration += 1
            let generation = self.locationGeneration
            manager.requestLocation()
            // Bounded wait: if no location/error callback arrives, resume nil so
            // `{location}` expansion (and WAL replay) can't hang forever.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard self.locationGeneration == generation, let pending = self.activeContinuation else { return }
                self.activeContinuation = nil
                pending.resume(returning: nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.first {
                // Advance the token so the pending timeout for this request no-ops.
                locationGeneration += 1
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
                authGeneration += 1
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
            locationGeneration += 1
            activeContinuation?.resume(returning: nil)
            activeContinuation = nil
        }
    }
}
