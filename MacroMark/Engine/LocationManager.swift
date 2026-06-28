import Foundation
import CoreLocation
import Observation
import MacroMarkKit

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    private var activeContinuation: CheckedContinuation<CLLocation?, Never>?
    private var activeContinuationTimeout: ContinuationTimeout?
    private var activeLocationManager: CLLocationManager?
    private var activeLocationManagerID: ObjectIdentifier?
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var authContinuationTimeout: ContinuationTimeout?
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
                let timeout = ContinuationTimeout()
                self.authContinuation = continuation
                self.authContinuationTimeout = timeout
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    if await timeout.complete() {
                        self.authContinuation = nil
                        self.authContinuationTimeout = nil
                        continuation.resume()
                    }
                }
                manager.requestWhenInUseAuthorization()
            }
        }

        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let timeout = ContinuationTimeout()
            let requestManager = CLLocationManager()
            let requestID = ObjectIdentifier(requestManager)
            requestManager.delegate = self
            requestManager.desiredAccuracy = manager.desiredAccuracy
            self.activeContinuation = continuation
            self.activeContinuationTimeout = timeout
            self.activeLocationManager = requestManager
            self.activeLocationManagerID = requestID
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard self.activeLocationManagerID == requestID else { return }
                if await timeout.complete() {
                    self.clearActiveLocationRequest(id: requestID)
                    continuation.resume(returning: nil)
                }
            }
            requestManager.requestLocation()
        }
    }

    private func clearActiveLocationRequest(id: ObjectIdentifier) {
        guard activeLocationManagerID == id else { return }
        activeLocationManager?.delegate = nil
        activeLocationManager?.stopUpdatingLocation()
        activeContinuation = nil
        activeContinuationTimeout = nil
        activeLocationManager = nil
        activeLocationManagerID = nil
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let requestID = ObjectIdentifier(manager)
        let location = locations.first
        Task { @MainActor in
            guard activeLocationManagerID == requestID,
                  let continuation = activeContinuation,
                  let timeout = activeContinuationTimeout else {
                return
            }
            clearActiveLocationRequest(id: requestID)
            if await timeout.complete() {
                continuation.resume(returning: location)
            }
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the Sendable status on the delegate thread; never capture the
        // non-Sendable `manager` in the main-actor closure (that would let a
        // task-isolated reference race against later nonisolated uses).
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined,
                  let continuation = authContinuation,
                  let timeout = authContinuationTimeout
            else {
                return
            }
            authContinuation = nil
            authContinuationTimeout = nil
            if await timeout.complete() {
                continuation.resume()
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let requestID = ObjectIdentifier(manager)
        let errorDescription = String(describing: error)
        Task { @MainActor in
            #if DEBUG
            print("Location request failed: \(errorDescription)")
            #endif
            guard activeLocationManagerID == requestID,
                  let continuation = activeContinuation,
                  let timeout = activeContinuationTimeout else {
                return
            }
            clearActiveLocationRequest(id: requestID)
            if await timeout.complete() {
                continuation.resume(returning: nil)
            }
        }
    }
}
