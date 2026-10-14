import Foundation
import CoreLocation
import Observation
import MacroMarkKit

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    private var pendingLocationContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var activeLocationTimeout: ContinuationTimeout?
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
        await withCheckedContinuation { continuation in
            pendingLocationContinuations.append(continuation)
            guard !isRequestingLocation else { return }
            isRequestingLocation = true
            Task { @MainActor in
                await beginLocationRequest()
            }
        }
    }

    private func beginLocationRequest() async {
        if manager.authorizationStatus == .notDetermined {
            await requestAuthorizationIfNeeded()
        }

        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            finishLocationRequest(returning: nil)
            return
        }

        let timeout = ContinuationTimeout()
        let requestManager = CLLocationManager()
        let requestID = ObjectIdentifier(requestManager)
        requestManager.delegate = self
        requestManager.desiredAccuracy = manager.desiredAccuracy
        activeLocationTimeout = timeout
        activeLocationManager = requestManager
        activeLocationManagerID = requestID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard self.activeLocationManagerID == requestID else { return }
            if await timeout.complete() {
                self.finishLocationRequest(returning: nil, id: requestID)
            }
        }
        requestManager.requestLocation()
    }

    private func requestAuthorizationIfNeeded() async {
        await withCheckedContinuation { continuation in
            let timeout = ContinuationTimeout()
            authContinuation = continuation
            authContinuationTimeout = timeout
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

    private func finishLocationRequest(returning location: CLLocation?, id: ObjectIdentifier? = nil) {
        if let id {
            guard activeLocationManagerID == id else { return }
        }
        activeLocationManager?.delegate = nil
        activeLocationManager?.stopUpdatingLocation()
        activeLocationTimeout = nil
        activeLocationManager = nil
        activeLocationManagerID = nil
        isRequestingLocation = false

        let continuations = pendingLocationContinuations
        pendingLocationContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let requestID = ObjectIdentifier(manager)
        let location = locations.first
        Task { @MainActor in
            guard activeLocationManagerID == requestID,
                  let timeout = activeLocationTimeout else {
                return
            }
            if await timeout.complete() {
                finishLocationRequest(returning: location, id: requestID)
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
                  let timeout = activeLocationTimeout else {
                return
            }
            if await timeout.complete() {
                finishLocationRequest(returning: nil, id: requestID)
            }
        }
    }
}
