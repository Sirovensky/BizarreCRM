// §57.1 FieldServiceMapView — MKMapView wrapped as UIViewRepresentable.
// Displays today's appointment pins with custom annotation + ETA chip.
// A11y: annotations have accessibilityLabel set per pin.
// Reduce Motion: pan/zoom animations muted when accessibility reduces motion.
//
// UIKit dependency: MapKit/MKMapView is UIKit-based; this file is iOS-only.
// For macOS (Designed for iPad) MapKit is still available via Catalyst.

import SwiftUI
import MapKit
import CoreLocation
import Networking

#if canImport(UIKit)
import UIKit

// MARK: - AppointmentAnnotation

public final class AppointmentAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let title: String?
    public let subtitle: String?
    public let appointmentId: Int64
    public let etaMinutes: Int?

    public init(
        appointmentId: Int64,
        coordinate: CLLocationCoordinate2D,
        title: String?,
        etaMinutes: Int?
    ) {
        self.appointmentId = appointmentId
        self.coordinate = coordinate
        self.title = title
        self.etaMinutes = etaMinutes
        self.subtitle = etaMinutes.map { "\($0) min" }
    }
}

// MARK: - FieldServiceMapView

/// §57.1 — MapKit map showing today's appointments as pins with ETA chips.
///
/// iPhone + iPad: fills available space. iPad uses in NavigationSplitView detail.
public struct FieldServiceMapView: UIViewRepresentable {

    public let annotations: [AppointmentAnnotation]
    public let reduceMotion: Bool
    public var onAnnotationTapped: ((Int64) -> Void)?

    public init(
        annotations: [AppointmentAnnotation],
        reduceMotion: Bool = false,
        onAnnotationTapped: ((Int64) -> Void)? = nil
    ) {
        self.annotations = annotations
        self.reduceMotion = reduceMotion
        self.onAnnotationTapped = onAnnotationTapped
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.delegate = context.coordinator
        map.register(
            ETAAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: ETAAnnotationView.reuseID
        )
        return map
    }

    public func updateUIView(_ map: MKMapView, context: Context) {
        let existing = map.annotations.compactMap { $0 as? AppointmentAnnotation }
        let existingIds = Set(existing.map(\.appointmentId))
        let newIds = Set(annotations.map(\.appointmentId))

        let toRemove = existing.filter { !newIds.contains($0.appointmentId) }
        let toAdd = annotations.filter { !existingIds.contains($0.appointmentId) }

        map.removeAnnotations(toRemove)
        map.addAnnotations(toAdd)

        if !annotations.isEmpty {
            let coords = annotations.map(\.coordinate)
            let region = regionFitting(coords)
            if reduceMotion {
                map.region = region
            } else {
                map.setRegion(region, animated: true)
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onAnnotationTapped: onAnnotationTapped)
    }

    // MARK: - Helpers

    private func regionFitting(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.33, longitude: -122.03),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        return MKCoordinateRegion(
            MKMapRect(coords.map { MKMapPoint($0) })
                .insetBy(dx: -8000, dy: -8000)
        )
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, MKMapViewDelegate, @unchecked Sendable {
        var onAnnotationTapped: ((Int64) -> Void)?

        init(onAnnotationTapped: ((Int64) -> Void)?) {
            self.onAnnotationTapped = onAnnotationTapped
        }

        public func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            guard let appt = annotation as? AppointmentAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: ETAAnnotationView.reuseID,
                for: appt
            ) as? ETAAnnotationView
            view?.configure(with: appt)
            return view
        }

        public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let appt = view.annotation as? AppointmentAnnotation else { return }
            onAnnotationTapped?(appt.appointmentId)
        }
    }
}

// MARK: - ETAAnnotationView

/// Custom annotation view: orange dot + ETA chip label.
/// A11y: `accessibilityLabel` set to appointment title + ETA.
final class ETAAnnotationView: MKAnnotationView {
    static let reuseID = "ETAAnnotation"

    private let chipLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = UIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 1)
        l.layer.cornerRadius = 8
        l.clipsToBounds = true
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        backgroundColor = UIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 1)
        layer.cornerRadius = 10
        canShowCallout = true

        addSubview(chipLabel)
        NSLayoutConstraint.activate([
            chipLabel.topAnchor.constraint(equalTo: bottomAnchor, constant: 4),
            chipLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            chipLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            chipLabel.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func configure(with annotation: AppointmentAnnotation) {
        if let eta = annotation.etaMinutes {
            chipLabel.text = "  \(eta) min  "
            chipLabel.isHidden = false
        } else {
            chipLabel.isHidden = true
        }
        // A11y
        let etaStr = annotation.etaMinutes.map { ", \($0) minutes away" } ?? ""
        let label = (annotation.title ?? "Appointment") + etaStr
        accessibilityLabel = label
        isAccessibilityElement = true
    }
}

#else

// MARK: - Non-UIKit stub (macOS SPM build without Catalyst)

public struct AppointmentAnnotation: Identifiable, Sendable {
    public let id: Int64
    public var appointmentId: Int64 { id }
    public let title: String?
    public let etaMinutes: Int?

    public init(appointmentId: Int64,
                coordinate: (lat: Double, lon: Double) = (0, 0),
                title: String?,
                etaMinutes: Int?) {
        self.id = appointmentId
        self.title = title
        self.etaMinutes = etaMinutes
    }
}

public struct FieldServiceMapView: View {
    public let annotations: [AppointmentAnnotation]
    public init(annotations: [AppointmentAnnotation],
                reduceMotion: Bool = false,
                onAnnotationTapped: ((Int64) -> Void)? = nil) {
        self.annotations = annotations
    }
    public var body: some View { EmptyView() }
}

#endif
