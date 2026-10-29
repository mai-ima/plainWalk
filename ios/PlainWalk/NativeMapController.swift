import UIKit
import MapKit

final class NativeMapController: UIViewController, MKMapViewDelegate {
    private let map = MKMapView()
    private let points: [[String: Any]]
    private let satellite: Bool
    init(points: [[String: Any]], satellite: Bool) { self.points = points; self.satellite = satellite; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        map.frame = view.bounds; map.autoresizingMask = [.flexibleWidth, .flexibleHeight]; map.delegate = self
        map.showsBuildings = true; map.isPitchEnabled = true; map.showsCompass = true
        if satellite { map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic) }
        else { let configuration = MKStandardMapConfiguration(elevationStyle: .realistic); configuration.pointOfInterestFilter = .excludingAll; map.preferredConfiguration = configuration }
        view.addSubview(map)
        let close = UIButton(type: .system); close.setTitle("閉じる", for: .normal)
        close.backgroundColor = .secondarySystemBackground; close.layer.cornerRadius = 18
        close.addTarget(self, action: #selector(dismissMap), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(close)
        NSLayoutConstraint.activate([close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18), close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 15), close.widthAnchor.constraint(equalToConstant: 70), close.heightAnchor.constraint(equalToConstant: 38)])
        var segment: [CLLocationCoordinate2D] = []; var rect = MKMapRect.null
        func addSegment() { if segment.count > 1 { let line = MKPolyline(coordinates: segment, count: segment.count); map.addOverlay(line); rect = rect.union(line.boundingMapRect) }; segment = [] }
        for point in points {
            guard let lat = point["lat"] as? Double, let lon = point["lon"] as? Double, abs(lat) <= 85, abs(lon) <= 180 else { continue }
            if point["break"] as? Bool == true { addSegment() }
            segment.append(.init(latitude: lat, longitude: lon))
        }
        addSegment()
        if !rect.isNull { map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 100, left: 45, bottom: 120, right: 45), animated: false) }
        else { map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76), latitudinalMeters: 1000, longitudinalMeters: 1000), animated: false) }
        let camera = map.camera; camera.pitch = 55; map.setCamera(camera, animated: false)
    }
    @objc private func dismissMap() { dismiss(animated: true) }
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: line); renderer.strokeColor = .label; renderer.lineWidth = 3; renderer.lineJoin = .round; renderer.lineCap = .round; return renderer
    }
}
