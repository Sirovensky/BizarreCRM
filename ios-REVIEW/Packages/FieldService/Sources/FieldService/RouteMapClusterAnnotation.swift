// §57.1 RouteMapClusterAnnotation — MKClusterAnnotationView for grouping
// nearby appointment pins on the route map.
//
// When multiple `AppointmentAnnotation` pins are close together MapKit
// automatically merges them into an `MKClusterAnnotation`.  This view renders
// the cluster as an orange circle badge with a count label so the dispatcher
// or tech can still see how many jobs are in the area.
//
// Registration: call `FieldServiceMapView.registerClusterView(on:)` from
// `makeUIView` after the map is created.
//
// A11y: cluster is a single accessibility element labelled
// "N appointments in this area".

import MapKit
import UIKit

#if canImport(UIKit)

// MARK: - RouteMapClusterAnnotationView

public final class RouteMapClusterAnnotationView: MKAnnotationView {

    public static let reuseID = "RouteMapCluster"

    // MARK: - UI

    private let circleView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 1) // bizarreOrange
        v.layer.borderColor = UIColor.white.cgColor
        v.layer.borderWidth = 2
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let countLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Init

    override public init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Layout

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        circleView.layer.cornerRadius = 18

        addSubview(circleView)
        circleView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 36),
            circleView.heightAnchor.constraint(equalToConstant: 36),

            countLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
        ])

        displayPriority = .defaultHigh
        collisionMode  = .circle
    }

    // MARK: - Cluster update

    override public func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let count = cluster.memberAnnotations.count
        countLabel.text = count < 100 ? "\(count)" : "99+"

        // Scale circle slightly for large clusters
        let side: CGFloat = count > 9 ? 44 : 36
        frame = CGRect(x: 0, y: 0, width: side, height: side)
        circleView.layer.cornerRadius = side / 2

        // A11y
        isAccessibilityElement = true
        accessibilityLabel = "\(count) appointments in this area"
        accessibilityHint = "Double-tap to zoom in and see individual jobs"
    }
}

// MARK: - FieldServiceMapView registration helper

public extension FieldServiceMapView {
    /// Register the cluster annotation view class on a freshly-created MKMapView.
    /// Call this inside `makeUIView(context:)` after `map.register(ETAAnnotationView…)`.
    static func registerClusterView(on map: MKMapView) {
        map.register(
            RouteMapClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
    }
}

#endif
