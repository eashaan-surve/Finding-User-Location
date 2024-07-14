//
//  ViewController.swift
//  Finding User Location
//
//  Created by Chiraag Nadig on 7/7/20.
//  Copyright © 2020 Chiraag Nadig. All rights reserved.
//

import UIKit
import CoreLocation
import MapKit
import FirebaseCore
import FirebaseFirestore



class CustomAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var useUserLocationStyle: Bool
    
    init(coordinate: CLLocationCoordinate2D, title: String?, useUserLocationStyle: Bool) {
        self.coordinate = coordinate
        self.title = title
        self.useUserLocationStyle = useUserLocationStyle
    }
}

@available(iOS 14.0, *)
class ViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    @IBOutlet var map: MKMapView!
    
    var locationManager = CLLocationManager()
    var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        map.delegate = self
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        FirebaseApp.configure()
        let db = Firestore.firestore()
        
        guard let userLocation = locations.first else { return }
        let latitude = userLocation.coordinate.latitude
        let longitude = userLocation.coordinate.longitude
        let latDelta: CLLocationDegrees = 0.05
        let lonDelta: CLLocationDegrees = 0.05
        let span: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        let location: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region: MKCoordinateRegion = MKCoordinateRegion(center: location, span: span)
        
        DispatchQueue.main.async {
            self.map.showsUserLocation = true
            self.map.setRegion(region, animated: true)
        }

            Task {
                await self.handleFirestoreOperations(latitude: latitude, longitude: longitude, db: db)
            }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let customAnnotation = annotation as? CustomAnnotation else {
            return nil
        }
        
        if customAnnotation.useUserLocationStyle {
            let annotationView = MKUserLocationView(annotation: annotation, reuseIdentifier: "userStyleLocation")
            annotationView.canShowCallout = true
            return annotationView
        }
        
        return nil
    }
    
    func handleFirestoreOperations(latitude: CLLocationDegrees, longitude: CLLocationDegrees, db: Firestore) async {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { timer in
            Task {
                do {
                    try await db.collection("location").document("User1").setData([
                        "latitude": latitude,
                        "longitude": longitude
                    ])
                    print("Document successfully written!")
                } catch {
                    print("Error writing document: \(error)")
                }

            }
            let x = 1
            if x == 10 {
                timer.invalidate()
            }
        }

        let docRef = db.collection("location").document("User2")
        var dataDescription: [String: Any]? = nil
        
        do {
            let document = try await docRef.getDocument()
            if document.exists {
                dataDescription = document.data()
                print("Document data: \(dataDescription)")
            } else {
                print("Document does not exist")
            }
        } catch {
            print("Error getting document: \(error)")
        }
        
        if let data = dataDescription {
            if let latitude = data["latitude"] as? Double, let longitude = data["longitude"] as? Double {
                let latDelta: CLLocationDegrees = 0.05
                let lonDelta: CLLocationDegrees = 0.05
                let span2: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
                let location2: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                let region2: MKCoordinateRegion = MKCoordinateRegion(center: location2, span: span2)
                
                DispatchQueue.main.async {
                    self.addAnnotationAtLocation(location: location2)
                    self.updateMapRegionToShowAllAnnotations()
                }
            }
            else {
                    print("Latitude or longitude not found or not of expected type")
                }
            } else {
                print("No document data available")
            }
    }

    func addAnnotationAtLocation(location: CLLocationCoordinate2D) {
        let annotation = CustomAnnotation(coordinate: location, title: "Second Location", useUserLocationStyle: true)
        self.map.addAnnotation(annotation)
    }
    
    func updateMapRegionToShowAllAnnotations() {
        var annotations = map.annotations
        if map.userLocation.location != nil {
            annotations.append(map.userLocation)
        }
        map.showAnnotations(annotations, animated: true)
    }
}
