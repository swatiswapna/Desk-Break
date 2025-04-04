//
//  communityViewController.swift
//  DeskBreak_Test
//
//  Created by admin33 on 03/10/24.
//

import UIKit
import FirebaseFirestore
import CoreLocation
import Foundation
import MapKit

class communityViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, CLLocationManagerDelegate, MKMapViewDelegate, MapViewControllerDelegate, JoinCommunityDelegate{
    
    func joinCommunityAlert(community: Community) {
        let alertController = UIAlertController(title: "Join Community", message: "Do you want to join the community \(community.communityName)?", preferredStyle: .alert)
        
        let joinAction = UIAlertAction(title: "Join", style: .default) { [weak self] _ in
            self?.joinCommunity(code: community.communityCode) // Assume `communityCode` is available in the `Community` model
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        alertController.addAction(joinAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    @IBOutlet weak var communityCollectionView: UICollectionView!
    @IBOutlet weak var communitySearchBar: UISearchBar!
    
    let activityIndicator = UIActivityIndicatorView(style: .large)
    var userCommunities: [Community] = []
    var filteredCommunities: [Community] = []
    var isSearching = false
    
    let locationManager = CLLocationManager()
    var userLocation: CLLocation?
    let refreshControl = UIRefreshControl()
    
    @IBAction func unwindToCommunity(Segue : UIStoryboardSegue){
        fetchUserCommunities()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        communityCollectionView.delegate = self
        communityCollectionView.dataSource = self
        communityCollectionView.register(CommunityCollectionViewCell.self, forCellWithReuseIdentifier: "CommunityCell")
        
        // Configure layout
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.itemSize = CGSize(width: view.frame.width - 32, height: 120) // Adjust size as needed
        layout.minimumLineSpacing = 8 // Reduced space between cells
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8) // Reduced padding
        communityCollectionView.collectionViewLayout = layout
        
        // Configure activity indicator
        activityIndicator.center = view.center
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        fetchUserCommunities()
        
        refreshControl.addTarget(self, action: #selector(refreshData(_:)), for: .valueChanged)
        communityCollectionView.refreshControl = refreshControl
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false // Allows table view selection while the keyboard is dismissed
        view.addGestureRecognizer(tapGesture)
        tapGesture.isEnabled = false // Disabled initially

        // Observe keyboard events
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        reorderTabs()
    }
    
    @objc func refreshData(_ sender: UIRefreshControl) {
        fetchUserCommunities() // Refresh the data
    }
    
    func reorderTabs() {
        // Access the UITabBarController
        guard let tabBarController = self.tabBarController else {
            print("Tab bar controller is nil")
            return
        }

        // Get the current view controllers
        guard var viewControllers = tabBarController.viewControllers else {
            print("View controllers array is nil")
            return
        }

        // Ensure there are at least 3 tabs
        if viewControllers.count < 3 {
            print("Not enough tabs to reorder")
            return
        }

        // Print original order for debugging
        print("Original order: \(viewControllers.map { $0.tabBarItem.title ?? "Untitled" })")

        // Reorder the tabs
        let firstTab = viewControllers[0]
        let middleTab = viewControllers[1]
        let lastTab = viewControllers[2]

        viewControllers[0] = middleTab
        viewControllers[1] = lastTab
        viewControllers[2] = firstTab

        // Assign the reordered view controllers back to the tab bar controller
        tabBarController.viewControllers = viewControllers

        // Set the selected index to the new first tab
        tabBarController.selectedIndex = 0

        // Print reordered order for debugging
        print("Reordered order: \(viewControllers.map { $0.tabBarItem.title ?? "Untitled" })")
    }
    
    @objc func keyboardWillShow() {
        view.gestureRecognizers?.first(where: { $0 is UITapGestureRecognizer })?.isEnabled = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchUserCommunities() // Refresh the data when the view appears
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showCommunityDetails",
           let destinationVC = segue.destination as? CommunityDetailsViewController,
           let selectedCommunity = sender as? Community {
            destinationVC.community = selectedCommunity
        }
        if segue.identifier == "showJoinCommunity",
           let destinationVC = segue.destination as? joinCommunityViewController {
            destinationVC.delegate = self // Set the delegate
        }
    }
    
    func startLoading() {
        DispatchQueue.main.async {
            self.activityIndicator.startAnimating()
            self.refreshControl.isEnabled = false // Disable refresh control while loading
        }
    }

    func stopLoading() {
        DispatchQueue.main.async {
            self.activityIndicator.stopAnimating()
            self.refreshControl.isEnabled = true // Re-enable refresh control after loading
        }
    }

    // Disable tap gesture when the keyboard disappears
    @objc func keyboardWillHide() {
        view.gestureRecognizers?.first(where: { $0 is UITapGestureRecognizer })?.isEnabled = false
    }

    @objc func dismissKeyboard() {
        view.endEditing(true) // Hide keyboard
    }
    
    func fetchUserCommunities() {
        startLoading() // Start activity indicator animation

        let db = Firestore.firestore()
        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""

        db.collection("communities").getDocuments { querySnapshot, error in
            if let error = error {
                print("Error fetching communities: \(error.localizedDescription)")
                self.stopLoading() // Stop activity indicator
                self.refreshControl.endRefreshing() // Stop refresh control animation
                return
            }

            guard let querySnapshot = querySnapshot else {
                print("No communities found.")
                self.stopLoading() // Stop activity indicator
                self.refreshControl.endRefreshing() // Stop refresh control animation
                return
            }

            var communityIds: [String] = []
            let group = DispatchGroup()

            for document in querySnapshot.documents {
                let communityId = document.documentID
                group.enter()
                
                db.collection("communities").document(communityId)
                    .collection("members")
                    .document(userId)
                    .getDocument { memberSnapshot, error in
                        if let error = error {
                            print("Error checking member in community \(communityId): \(error.localizedDescription)")
                        } else if let memberSnapshot = memberSnapshot, memberSnapshot.exists {
                            communityIds.append(communityId)
                        }
                        group.leave()
                    }
            }

            group.notify(queue: .main) {
                self.fetchCommunityDetails(communityIds: communityIds) { communities in
                    self.userCommunities = communities
                    self.communityCollectionView.reloadData()
                    self.stopLoading() // Stop activity indicator
                    self.refreshControl.endRefreshing() // Stop refresh control animation
                }
            }
        }
    }

    func fetchCommunityDetails(communityIds: [String], completion: @escaping ([Community]) -> Void) {
        let db = Firestore.firestore()
        var communities: [Community] = []

        let group = DispatchGroup()

        for communityId in communityIds {
            group.enter()
            
            db.collection("communities").document(communityId).getDocument { documentSnapshot, error in
                if let error = error {
                    print("Error fetching community details: \(error.localizedDescription)")
                } else if let document = documentSnapshot, document.exists {
                    if let community = Community(document: document) {
                        communities.append(community)
                    } else {
                        print("Failed to parse community data for \(communityId)")
                    }
                }

                group.leave()
            }
        }

        // Once all community details are fetched, pass them to the completion handler
        group.notify(queue: .main) {
            completion(communities)
        }
    }
    
    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return isSearching ? filteredCommunities.count : userCommunities.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CommunityCell", for: indexPath) as? CommunityCollectionViewCell else {
            fatalError("Unable to dequeue CommunityCollectionViewCell")
        }
        
        // Configure the cell
        let community = isSearching ? filteredCommunities[indexPath.row] : userCommunities[indexPath.row]
        cell.configure(with: community)
        
        return cell
    }
    
    // MARK: - UICollectionViewDelegate
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // Get the selected community
        let community = isSearching ? filteredCommunities[indexPath.row] : userCommunities[indexPath.row]
        
        // Navigate to CommunityDetailsViewController
        performSegue(withIdentifier: "showCommunityDetails", sender: community)
    }
    
    @IBAction func nearbyCommunitiesButtonPressed(_ sender: UIButton) {
    }
    
    @IBAction func joinCommunityButtonPressed(_ sender: UIBarButtonItem) {
        performSegue(withIdentifier: "showJoinCommunity", sender: self)
    }

    // MARK: - JoinCommunityDelegate
    func didJoinCommunity() {
        fetchUserCommunities() // Refresh the data
    }
    
    func showNearbyCommunitiesAlert(community: Community) {
        let alertController = UIAlertController(title: "Nearby Community", message: "Do you want to join this community?", preferredStyle: .alert)
        
        let joinAction = UIAlertAction(title: "Join", style: .default) { _ in
            self.joinCommunity(code: community.communityCode) // Adjust if communityCode isn't directly available
        }
        
        alertController.addAction(joinAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            userLocation = location
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get location: \(error.localizedDescription)")
    }

    func geohashEncode(latitude: Double, longitude: Double, precision: Int = 9) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var hash = ""
        var minLat = -90.0, maxLat = 90.0
        var minLon = -180.0, maxLon = 180.0
        var isEven = true
        var bit = 0
        var currentChar = 0

        while hash.count < precision {
            if isEven {
                let mid = (minLon + maxLon) / 2
                if longitude > mid {
                    currentChar |= (1 << (4 - bit))
                    minLon = mid
                } else {
                    maxLon = mid
                }
            } else {
                let mid = (minLat + maxLat) / 2
                if latitude > mid {
                    currentChar |= (1 << (4 - bit))
                    minLat = mid
                } else {
                    maxLat = mid
                }
            }

            isEven.toggle()
            if bit < 4 {
                bit += 1
            } else {
                hash.append(base32[currentChar])
                bit = 0
                currentChar = 0
            }
        }
        return hash
    }

    func addMemberToCommunity(communityId: String, userId: String, completion: @escaping (Error?) -> Void) {
        let db = Firestore.firestore()

        // Create the membership document in the community's "members" sub-collection
        let memberData: [String: Any] = [
            "userId": userId,
            "joinedAt": Date()
        ]

        db.collection("communities").document(communityId).collection("members").document(userId).setData(memberData) { error in
            completion(error) // Call the completion handler with the error (if any)
        }
    }

    func joinCommunity(code: String) {
        let db = Firestore.firestore()
        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""

        // Check if the user is already a member of any community with the provided code
        db.collection("communities")
            .whereField("communityCode", isEqualTo: code)
            .getDocuments { querySnapshot, error in
                if let error = error {
                    self.showAlert(title: "Error", message: "Failed to check community: \(error.localizedDescription)")
                    return
                }

                guard let communityDocument = querySnapshot?.documents.first else {
                    self.showAlert(title: "Error", message: "Community with the code \(code) not found.")
                    return
                }

                let communityId = communityDocument.documentID

                // Now check if the user is already a member of the community
                self.checkIfUserIsMember(communityId: communityId, userId: userId) { isMember in
                    if isMember {
                        self.showAlert(title: "Already a Member", message: "You are already a member of this community.")
                    } else {
                        // Add the user as a member if they're not already
                        self.addMemberToCommunity(communityId: communityId, userId: userId) { membershipError in
                            if let membershipError = membershipError {
                                self.showAlert(title: "Error", message: "Failed to join community: \(membershipError.localizedDescription)")
                            } else {
                                self.showAlert(title: "Success", message: "You have successfully joined the community!")
                                self.fetchUserCommunities() // Refresh the list of user communities
                            }
                        }
                    }
                }
            }
    }

    func checkIfUserIsMember(communityId: String, userId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()

        db.collection("communities").document(communityId).collection("members")
            .document(userId).getDocument { documentSnapshot, error in
                if let error = error {
                    print("Error checking membership: \(error.localizedDescription)")
                    completion(false)
                } else {
                    // If the document exists, the user is already a member
                    completion(documentSnapshot?.exists ?? false)
                }
            }
    }

    func addMembership(userId: String, communityId: String, completion: @escaping (Error?) -> Void) {
        let db = Firestore.firestore()
        let membershipId = UUID().uuidString

        let membershipData: [String: Any] = [
            "membershipId": membershipId,
            "userId": userId,
            "communityId": communityId,
            "joinedAt": Date()
        ]

        db.collection("communityMemberships").document(membershipId).setData(membershipData) { error in
            completion(error) // Call the completion handler with the error (if any)
        }
    }

    // MARK: - Alert Helper
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    }

extension communityViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            isSearching = false
            filteredCommunities = []
        } else {
            isSearching = true
            filteredCommunities = userCommunities.filter {
                $0.communityName.lowercased().contains(searchText.lowercased())
            }
        }
        communityCollectionView.reloadData()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        isSearching = false
        searchBar.text = ""
        communityCollectionView.reloadData()
        searchBar.resignFirstResponder()
    }
}
