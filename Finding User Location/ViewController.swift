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
import SwiftUI



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
    var currentUserLocation: CLLocationCoordinate2D?
    var currentDriverLocation: CLLocationCoordinate2D?
    var writeTimer: Timer?
    var readTimer: Timer?
    var isOperationActive = true

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
        self.currentUserLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let span: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        let region: MKCoordinateRegion = MKCoordinateRegion(center: self.currentUserLocation!, span: span)
        
        DispatchQueue.main.async {
            self.map.showsUserLocation = true
            self.map.setRegion(region, animated: true)
        }

            Task {
                self.handleFirestoreOperations(latitude: latitude, longitude: longitude, db: db)
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

        func handleFirestoreOperations(latitude: CLLocationDegrees, longitude: CLLocationDegrees, db: Firestore) {
            Task {
                await startWriteOperation(latitude: latitude, longitude: longitude, db: db)
            }
            
            Task {
                await startReadOperation(db: db)
            }
            
        }
        
        func startWriteOperation(latitude: CLLocationDegrees, longitude: CLLocationDegrees, db: Firestore) async {
            while isOperationActive {
                await writeLocationToFirestore(latitude: latitude, longitude: longitude, db: db)
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
        }
        
        func startReadOperation(db: Firestore) async {
            while isOperationActive {
                await readLocationFromFirestore(db: db)
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
        }
        
        func writeLocationToFirestore(latitude: CLLocationDegrees, longitude: CLLocationDegrees, db: Firestore) async {
            do {
                try await db.collection("location").document("User1").setData([
                    "latitude": latitude,
                    "longitude": longitude
                ])
                print("Document successfully written!")
                await MainActor.run {
                    self.currentUserLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                }
            } catch {
                print("Error writing document: \(error)")
            }
        }
        
        func readLocationFromFirestore(db: Firestore) async {
            do {
                let docRef = db.collection("location").document("User2")
                let document = try await docRef.getDocument()
                if let data = document.data(),
                   let latitude = data["latitude"] as? Double,
                   let longitude = data["longitude"] as? Double {
                    await MainActor.run {
                        self.currentDriverLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    }
                    
                    await MainActor.run {
                        self.addAnnotationAtLocation(location: self.currentDriverLocation!)
                        self.updateMapRegionToShowAllAnnotations()
                        calculateDrivingDistance(from: self.currentUserLocation!, to: self.currentDriverLocation!) { distance, time in
                                if let distance = distance, let time = time {
                                    let distanceInMiles = (Measurement(value: distance, unit: UnitLength.meters))
                                        .converted(to: UnitLength.miles) // Convert meters to miles
                                    let timeInMinutes = time / 60 // Convert seconds to minutes
                                    
                                    print("Driving distance: \(String(format: "%.2f", distanceInMiles.value)) miles")
                                    print("Estimated travel time: \(String(format: "%.0f", timeInMinutes)) minutes")
                                } else {
                                    print("Unable to calculate distance or time")
                                }
                            }
                    }
                    
                    if let currentLocation = await MainActor.run(body: { self.currentUserLocation }) {
                        let distance = await MainActor.run { self.distanceBetween(coord1: currentLocation, coord2: self.currentDriverLocation!) }
                        if distance < 0.05 {
                            await MainActor.run {
                                self.isOperationActive = false
                            }
                            print("Locations are within 0.05 miles. Stopping database operations.")
                        }
                    }
                }
            } catch {
                print("Error getting document: \(error)")
            }
        }
    func distanceBetween(coord1: CLLocationCoordinate2D, coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        let distanceInMeters = location1.distance(from: location2)
        return distanceInMeters / 1609.344
    }

    func addAnnotationAtLocation(location: CLLocationCoordinate2D) {
        if let existingAnnotation = map.annotations.first(where: { $0.title == "Second Location" }) {
            map.removeAnnotation(existingAnnotation)
        }

        let annotation = CustomAnnotation(coordinate: location, title: "Second Location", useUserLocationStyle: true)
        self.map.addAnnotation(annotation)
    }
    
    func updateMapRegionToShowAllAnnotations() {
        var annotations = map.annotations
        if map.userLocation.location != nil {
            annotations.append(map.userLocation)
        }
        
        guard !annotations.isEmpty else { return }
        
        var zoomRect = MKMapRect.null
        for annotation in annotations {
            let annotationPoint = MKMapPoint(annotation.coordinate)
            let pointRect = MKMapRect(x: annotationPoint.x, y: annotationPoint.y, width: 0.1, height: 0.1)
            zoomRect = zoomRect.union(pointRect)
        }
        
        // Padding around the edges (30% on each side)
        let paddedRect = zoomRect.insetBy(dx: -zoomRect.size.width * 0.35,
                                          dy: -zoomRect.size.height * 0.35)
        
        map.setVisibleMapRect(paddedRect, animated: true)
    }
    
    
    func calculateDrivingDistance(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, completion: @escaping (CLLocationDistance?, TimeInterval?) -> Void) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            guard let route = response?.routes.first else {
                print("Error calculating route: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil, nil)
                return
            }
            
            let distanceInMeters = route.distance
            let travelTimeInSeconds = route.expectedTravelTime
            completion(distanceInMeters, travelTimeInSeconds)
        }
    }
        
    @IBOutlet weak var Time: UIImageView!
}

