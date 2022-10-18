//
//  HikeMapViewController.swift
//  TrailTutor
//
//  Created by Pasha Pashchenko on 12.04.2022.
//

import UIKit
import MapboxMaps

class HikeMapViewController: UIViewController {
    
    struct Place: Codable {
        let name: String
        let photo: String
        let video: String
    }
    
    struct HikeAnnotation {
        let view: UIView
        let options: ViewAnnotationOptions
        let order: Int
        let places: [Place]
    }

    @IBOutlet weak var photoLabel: UILabel!
    @IBOutlet weak var videoLabel: UILabel!
    @IBOutlet weak var loadingView: UIView!
    @IBOutlet weak var progressBar: UIProgressView!
    @IBOutlet weak var loadingLabel: UILabel!
    
    @IBOutlet weak var currentCoordinateLabel: UILabel!
    
    internal var mapView: MapView!
    var lineCoordinates:[CLLocationCoordinate2D] = []
    var hikeAnnotations:[HikeAnnotation] = []
    
    var hikeIndex = 0
    
    var attendedLocations: [CLLocationCoordinate2D] = []
    
    let userNotificationCenter = UNUserNotificationCenter.current()
   
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        updateMediaCounter()
        requestNotificationAuthorization()
        NotificationCenter.default.addObserver(self, selector: #selector(pointAchived), name: Notification.Name.pointAchived, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateMediaCounter()
    }
    
    @IBAction func didTapLocationButton(_ sender: Any) {
        let edgeInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let camera = self.mapView.mapboxMap.camera(for: self.lineCoordinates, padding: edgeInsets, bearing: 0, pitch: 0)
        self.mapView.camera.ease(to: camera, duration: 0.15)
    }
    
    func setupMap() {
        let options = MapInitOptions(styleURI: .outdoors)
        var mapFrame = view.bounds
        mapFrame.size.height = mapFrame.height - (tabBarController?.tabBar.frame.height ?? 0)
        mapView = MapView(frame: mapFrame, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(mapView, at: 0)
      
        mapView.location.delegate = self
        mapView.location.options.activityType = .other
        mapView.location.options.puckType = .puck2D()
        mapView.location.locationProvider.startUpdatingLocation()
        
        mapView.mapboxMap.onNext(.mapLoaded) { [weak self] _ in
            self?.setupRoute()
            self?.updateMediaCounter()
            self?.showSpinner()
            self?.loadingView.isHidden = false
            self?.progressBar.isHidden = false
            self?.loadingLabel.isHidden = false
            
            
            DispatchQueue.global(qos: .userInitiated).async() {
                let loadGroup = DispatchGroup()
                loadGroup.enter()
                self?.downloadAllVideoIfNeccessary(annotationIndex: 0, placeIndex: 0, completion: {
                    loadGroup.leave()
                })
                loadGroup.enter()
                self?.downloadAllPhotosIfNeccessary(annotationIndex: 0, placeIndex: 0, completion: {
                    loadGroup.leave()
                })
                loadGroup.notify(queue: DispatchQueue.main) {
                    self?.hideSpinner()
                    self?.loadingView.isHidden = true
                    self?.progressBar.isHidden = true
                    self?.loadingLabel.isHidden = true
                }
            }
            
            

            let edgeInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
            let camera = self?.mapView.mapboxMap.camera(for: self?.lineCoordinates ?? [], padding: edgeInsets, bearing: 0, pitch: 0)
            self?.mapView.mapboxMap.setCamera(to: camera!)
            self?.hikeAnnotations.sort(by: {$0.order < $1.order})
            if let hikeAnnotations = self?.hikeAnnotations {
                for hikeAnnotation in hikeAnnotations {
                    try? self?.mapView.viewAnnotations.add(hikeAnnotation.view, options: hikeAnnotation.options)
                }
            }
            
            self?.drawLine()
            self?.setupLocationTracking()
            
        }
    }
    
    func requestNotificationAuthorization() {
        let authOptions = UNAuthorizationOptions.init(arrayLiteral: .alert, .badge, .sound)
        
        self.userNotificationCenter.requestAuthorization(options: authOptions) { (success, error) in
            if let error = error {
                print("Error: ", error)
            }
        }
    }
    
    func setupLocationTracking() {
        GPSManager.shared.startUpdatingLocation { [weak self] location in
            guard let lineCoordinates = self?.lineCoordinates,
            let attendedLocations = self?.attendedLocations else {
                return
                
            }
            var i = 0
            for lineCoordinate in lineCoordinates {
                let linePointLocation = CLLocation(latitude: lineCoordinate.latitude, longitude: lineCoordinate.longitude)
                print("location distance - \(location.distance(from: linePointLocation))")
                if location.distance(from: linePointLocation) < 10.0 && !attendedLocations.contains(lineCoordinate)  {
                    if let hikeAnnotations = self?.hikeAnnotations {
                        let annotation = hikeAnnotations[i]
                        let title = "Trail Tutor"
                        let body = "You have reached \(annotation.order) point of the hike - \(annotation.places[0].name)"
                        self?.sendNotification(title: title, body: body, pointNumber: annotation.order)
                        self?.attendedLocations.append(lineCoordinate)
                    }
                }
                i = i + 1
            }
        }
    }
    
    func sendNotification(title: String, body: String, pointNumber: Int) {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = title
        notificationContent.body = body
        notificationContent.badge = NSNumber(value: 1)
        notificationContent.sound = UNNotificationSound.default
        notificationContent.categoryIdentifier = "alarm"
        notificationContent.userInfo = ["pointNumber": pointNumber]
        let request = UNNotificationRequest(identifier: "testNotification",
                                            content: notificationContent,
                                            trigger: nil)
        
        userNotificationCenter.add(request) { (error) in
            if let error = error {
                print("Notification Error: ", error)
            } else {
                print("---- ok ----")
            }
        }
    }
    
    func updateMediaCounter() {
        let photoCounter = getPhotoCounter()
        photoLabel.text = "photo - \(photoCounter.0)/\(photoCounter.1)"
        let videoCounter = getVideoCounter()
        videoLabel.text = "video - \(videoCounter.0)/\(videoCounter.1)"
        
        
        let loadedMedia = photoCounter.0 + videoCounter.0
        let totalMedia = photoCounter.1 + videoCounter.1
        if totalMedia > 0 {
            progressBar.progress = Float(loadedMedia) / Float(totalMedia)
        } else {
            progressBar.progress = 0.0
        }
    }
    
    func downloadAllVideoIfNeccessary(annotationIndex: Int, placeIndex: Int, completion: @escaping (()->Void)) {

        if annotationIndex >= hikeAnnotations.count {
            completion()
            return
        }
        
        let hikeAnnotation = hikeAnnotations[annotationIndex]

        if placeIndex >= hikeAnnotation.places.count {
            downloadAllVideoIfNeccessary(annotationIndex: annotationIndex + 1, placeIndex: 0, completion: completion)
            return
        }
        
        let place = hikeAnnotation.places[placeIndex]
        
        
        let url = place.video.replacingOccurrences(of: "?dl=0", with: "")
        if let videoUrl = URL(string: url) {
            let documentsDirectoryURL =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationUrl = documentsDirectoryURL.appendingPathComponent(videoUrl.lastPathComponent)
            
            if FileManager.default.fileExists(atPath: destinationUrl.path) {
                downloadAllVideoIfNeccessary(annotationIndex: annotationIndex, placeIndex: placeIndex + 1, completion: completion)
            } else {
                let downloadLink = "\(url)?dl=1"
                if let downloadUrl = URL(string: downloadLink) {
                    URLSession.shared.downloadTask(with: downloadUrl) { [weak self] location, response, error in
                        if let location = location, error == nil {
                            do {
                                try FileManager.default.moveItem(at: location, to: destinationUrl)
                                print("File \(downloadLink) moved to documents folder")
                            } catch (let moveItemEror) {
                                print("File \(downloadLink) failed2 (moveItemEror) - \(moveItemEror)")
                                print(moveItemEror)
                            }
                        } else {
                            print("File filed, error - \(error)")
                        }
                        DispatchQueue.main.async {
                            self?.updateMediaCounter()
                        }
                        self?.downloadAllVideoIfNeccessary(annotationIndex: annotationIndex, placeIndex: placeIndex + 1, completion: completion)
                    }.resume()
                }
            }
        }
            
    }
    
    
    func downloadAllPhotosIfNeccessary(annotationIndex: Int, placeIndex: Int, completion: @escaping (()->Void)) {
        
        if annotationIndex >= hikeAnnotations.count {
            completion()
            return
        }

        let hikeAnnotation = hikeAnnotations[annotationIndex]

        if placeIndex >= hikeAnnotation.places.count {
            downloadAllPhotosIfNeccessary(annotationIndex: annotationIndex + 1, placeIndex: 0, completion: completion)
            return
        }
        
        let place = hikeAnnotation.places[placeIndex]
        
        let url = place.photo.replacingOccurrences(of: "?dl=0", with: "")
        if let photoUrl = URL(string: url) {
            let documentsDirectoryURL =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationUrl = documentsDirectoryURL.appendingPathComponent(photoUrl.lastPathComponent)
            
            if FileManager.default.fileExists(atPath: destinationUrl.path) {
                downloadAllPhotosIfNeccessary(annotationIndex: annotationIndex, placeIndex: placeIndex + 1, completion: completion)
            } else {
                let downloadLink = "\(url)?dl=1"
                if let downloadUrl = URL(string: downloadLink) {
                    //loadVideoGroup.enter()
                    URLSession.shared.downloadTask(with: downloadUrl) { [weak self] location, response, error in
                        if let location = location, error == nil {
                            do {
                                try FileManager.default.moveItem(at: location, to: destinationUrl)
                                print("File \(downloadLink) moved to documents folder")
                            } catch (let moveItemEror) {
                                print("File \(downloadLink) failed2 (moveItemEror) - \(moveItemEror)")
                                print(moveItemEror)
                            }
                        } else {
                            print("File filed, error - \(error)")
                        }
                        DispatchQueue.main.async {
                            self?.updateMediaCounter()
                        }
                        
                        self?.downloadAllPhotosIfNeccessary(annotationIndex: annotationIndex, placeIndex: placeIndex + 1, completion: completion)
                    }.resume()
                }
            }
        }
    }
    
    // Load GeoJSON file from local bundle and decode into a `FeatureCollection`.
    internal func decodeGeoJSON(from fileName: String) throws -> FeatureCollection? {
        guard let path = Bundle.main.path(forResource: fileName, ofType: "geojson") else {
            preconditionFailure("File '\(fileName)' not found.")
        }
        let filePath = URL(fileURLWithPath: path)
        var featureCollection: FeatureCollection?
        do {
            let data = try Data(contentsOf: filePath)
            featureCollection = try JSONDecoder().decode(FeatureCollection.self, from: data)
        } catch {
            print("Error parsing data: \(error)")
        }
        return featureCollection
    }
    
    func addLinePoint(coordinates: [Double]) {
        let locCoordinates = CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
        lineCoordinates.append(locCoordinates)
        
    }
    
    private func addAnnotation(coordinates: [Double], order: Int, places:[Place]) {
        let locCoordinates = CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
        let options = ViewAnnotationOptions(
            geometry: Point(locCoordinates),
            width: 32,
            height: 42,
            allowOverlap: true,
            anchor: .bottom
        )
        let sampleView = createSampleView(withText: "\(order)", light: order % 2 != 0)
        sampleView.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleAnnotationTap(_:)))
        sampleView.addGestureRecognizer(tap)
        tap.view?.tag = order
        
        let hikeAnnotation = HikeAnnotation(view: sampleView, options: options, order: order, places: places)
        hikeAnnotations.append(hikeAnnotation)
    }
    
    private func createSampleView(withText text: String, light: Bool) -> UIView {
        let pinAnnotationView = UIImageView(frame: CGRect(x: 0, y: 0, width: 32, height: 42))
        let pinImage = UIImage(named: light ? "pinAnnotationLight" : "pinAnnotationDark")
        pinAnnotationView.image = pinImage
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        label.textColor = .white
        label.backgroundColor = .clear
        label.textAlignment = .center
        pinAnnotationView.addSubviewToCenter(subview: label, horOffset: 0.0, vertOffset: -4.0)
        return pinAnnotationView
    }
    
    internal func setupRoute() {
        
        guard let featureCollection = try? decodeGeoJSON(from: "terra_incognito") else { return }
    
        var geoJSONSource = GeoJSONSource()
        geoJSONSource.data = .featureCollection(featureCollection)
        do {
            let rootObject = try geoJSONSource.jsonObject()
            if let data = rootObject["data"] as? [String: Any] {
                if let features = data["features"] as? [[String:Any]] {
                    for feature in features {
                        if let geometry = feature["geometry"] as? [String: Any] {
                            print(geometry)
                            if let type = geometry["type"] as? String {
                                if type == "LineString" {
                                    if let coordinates = geometry["coordinates"] as? [[Double]] {
                                        for coordinate in coordinates {
                                            addLinePoint(coordinates: coordinate)
                                        }
                                    }
                                } else if type == "Point" {
                                    if let coordinates = geometry["coordinates"] as? [Double] {
                                        if let properties = feature["properties"] as? [String: Any], properties.count > 0 {
                                            var order = 0
                                            var places: [Place] = []
                                            for propertyKey in properties.keys {
                                                if propertyKey == "order" {
                                                    order = (properties["order"] as? Int) ?? 0
                                                }
                                                
                                                if propertyKey == "places" {
                                                    if let placesJSON = properties["places"] as? [[String: Any]] {
                                                        let jsonData = try JSONSerialization.data(withJSONObject: placesJSON, options: .prettyPrinted)
                                                        let readPlaces = try JSONDecoder().decode([Place].self, from: jsonData)
                                                    
                                                        places = readPlaces
                                                    }
                                                }
                                                
                                            }
                                            addAnnotation(coordinates:coordinates, order: order, places: places)
                                        }
                                    }
                                }
                                
                            }
                        }
                    }
                }
            }
        }
        catch (let error) {
            print(error)
        }
    }
    
    func drawLine() {
        // Attempt to decode GeoJSON from file bundled with application.
        guard let featureCollection = try? decodeGeoJSON(from: "Saddleback Butte") else { return }
        let geoJSONDataSourceIdentifier = "geoJSON-data-source"
         
        // Create a GeoJSON data source.
        var geoJSONSource = GeoJSONSource()
        geoJSONSource.data = .featureCollection(featureCollection)
        geoJSONSource.lineMetrics = true // MUST be `true` in order to use `lineGradient` expression
         
        // Create a line layer
        var lineLayer = LineLayer(id: "line-layer")
        lineLayer.filter = Exp(.eq) {
            "$type"
            "LineString"
        }
         
        // Setting the source
        lineLayer.source = geoJSONDataSourceIdentifier
         
        // Styling the line
        lineLayer.lineColor = .constant(StyleColor(.blue))
        if let dotImage = UIImage(named: "lineDot") {
            do {
                try mapView.mapboxMap.style.addImage(dotImage, id: "lineDot", sdf: true, stretchX: [], stretchY: [])
                lineLayer.linePattern = .constant(.name("lineDot"))
            }
            catch (let err) {
                print(err)
            }
        }
        
        lineLayer.lineWidth = .constant(10)
        lineLayer.lineCap = .constant(.round)
        lineLayer.lineJoin = .constant(.round)
         
        // Add the source and style layer to the map style.
        try! mapView.mapboxMap.style.addSource(geoJSONSource, id: geoJSONDataSourceIdentifier)
        try! mapView.mapboxMap.style.addLayer(lineLayer, layerPosition: nil)
    }
    
    @objc func handleAnnotationTap(_ sender: UITapGestureRecognizer) {
        guard let getTag = sender.view?.tag else { return }
        print("getTag == \(getTag)")
        let index = Int(getTag) - 1
        if index >= 0 && index < hikeAnnotations.count {
            annotationTapped(index: index, fromNotification: false)
        }
        
    }
    
    func annotationTapped(index: Int, fromNotification: Bool) {
        if let pointPreviewVC = AppNavigator.getViewControllerBy(storyboardName: STORYBOARD.MY_HIKE, vcName: CONTROLLER.POINT_PREVIEW) as? PointPreviewViewController {
            
            if hikeAnnotations[index].places.count > 0 {
                pointPreviewVC.videoLink = hikeAnnotations[index].places[0].video
                pointPreviewVC.photoLink = hikeAnnotations[index].places[0].photo
                pointPreviewVC.videoName = hikeAnnotations[index].places[0].name
                pointPreviewVC.pointNumber = index + 1
                pointPreviewVC.fromNotification = fromNotification
                pointPreviewVC.playVideo = {[weak self] videoName, videoURL in
                    pointPreviewVC.dismiss(animated: true) {
                        self?.showPlayer(videoName: videoName, videoURL: videoURL)
                    }
                }
                AppNavigator.presentViewControllerOn(vc: self, presentedVC: pointPreviewVC)
            }
            
        }
    }
    
    func showPlayer(videoName: String, videoURL: URL) {
        if let playerVC = AppNavigator.getViewControllerBy(storyboardName: STORYBOARD.MY_HIKE, vcName: CONTROLLER.PLAYER) as? PlayerViewController {
            playerVC.videoName = videoName
            playerVC.videoURL = videoURL
            playerVC.modalPresentationStyle = .fullScreen
            AppNavigator.presentViewControllerOn(vc: self, presentedVC: playerVC)
        }
    }
    
    func getPhotoCounter() -> (Int, Int) {
        var total = 0
        var loaded = 0
        for hikeAnnotation in hikeAnnotations {
            for place in hikeAnnotation.places {
                if place.photo.count > 0 {
                    total = total + 1
                    let url = place.photo.replacingOccurrences(of: "?dl=0", with: "")
                    if let photoUrl = URL(string: url) {
                        let documentsDirectoryURL =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let destinationUrl = documentsDirectoryURL.appendingPathComponent(photoUrl.lastPathComponent)
                        
                        if FileManager.default.fileExists(atPath: destinationUrl.path) {
                            loaded = loaded + 1
                        }
                    }
                }
            }
        }
        return (loaded, total)
    }
    
    func getVideoCounter() -> (Int, Int) {
        var total = 0
        var loaded = 0
        for hikeAnnotation in hikeAnnotations {
            for place in hikeAnnotation.places {
                if place.video.count > 0 {
                    total = total + 1
                    let url = place.video.replacingOccurrences(of: "?dl=0", with: "")
                    if let photoUrl = URL(string: url) {
                        let documentsDirectoryURL =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let destinationUrl = documentsDirectoryURL.appendingPathComponent(photoUrl.lastPathComponent)
                        
                        if FileManager.default.fileExists(atPath: destinationUrl.path) {
                            loaded = loaded + 1
                        }
                    }
                }
            }
        }
        return (loaded, total)
    }

}

extension HikeMapViewController: LocationPermissionsDelegate, LocationConsumer {
    func locationUpdate(newLocation: Location) {
        mapView.camera.fly(to: CameraOptions(center: newLocation.coordinate, zoom: 14.0), duration: 5.0)
    }
}


//MARK: - Notification Center
extension HikeMapViewController {
    @objc func pointAchived(notification: NSNotification) {
        guard let pointNumber = notification.object as? Int, pointNumber > 0 else { return }
        annotationTapped(index: pointNumber - 1, fromNotification: true)
    }
}

