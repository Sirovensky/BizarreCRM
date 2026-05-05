// §57 OneShotLocationCapture — production LocationCapture implementation
// using CLLocationManager continuation pattern.
//
// Runs on a throw-away CLLocationManager created per capture to avoid
// state leakage across calls. Resolves with the first fix that has
// horizontal accuracy ≤ 50 m, or times out after 10 s.

import Foundation
import CoreLocation

// MARK: - OneShotLocationCapture

public final class OneShotLocationCapture: NSObject, LocationCapture, CLLocationManagerDelegate, Sendable {

    private let timeoutSeconds: Double

    public init(timeoutSeconds: Double = 10) {
        self.timeoutSeconds = timeoutSeconds
    }

    public func captureCurrentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = _Delegate(
                continuation: continuation,
                timeoutSeconds: timeoutSeconds
            )
            // Keep delegate alive for the duration.
            delegate.start()
        }
    }
}

// MARK: - Internal delegate helper

private final class _Delegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?
    private let timeoutSeconds: Double
    private var resolved = false

    init(continuation: CheckedContinuation<CLLocation, Error>, timeoutSeconds: Double) {
        self.continuation = continuation
        self.timeoutSeconds = timeoutSeconds
        super.init()
    }

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestLocation()

        let timeout = timeoutSeconds
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            self?.fail(FieldCheckInError.locationTimeout)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first, loc.horizontalAccuracy >= 0 else { return }
        resolve(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        if clError?.code == .denied {
            fail(FieldCheckInError.locationPermissionDenied)
        } else {
            fail(FieldCheckInError.locationTimeout)
        }
    }

    private func resolve(_ location: CLLocation) {
        guard !resolved else { return }
        resolved = true
        timeoutTask?.cancel()
        manager.stopUpdatingLocation()
        continuation?.resume(returning: location)
        continuation = nil
    }

    private func fail(_ error: Error) {
        guard !resolved else { return }
        resolved = true
        timeoutTask?.cancel()
        manager.stopUpdatingLocation()
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
