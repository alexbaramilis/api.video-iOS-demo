//
//  AuthViewController.swift
//  api.video iOS demo
//
//  Created by Alexandros on 18/01/2019.
//  Copyright © 2019 Alexandros Baramilis. All rights reserved.
//

import UIKit
import Alamofire

class AuthViewController: UIViewController {
    @IBOutlet weak var authStatusLabel: UILabel!
    
    private var accessToken: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        authenticate()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == SegueId.AuthSuccess, let videoUploadVC = segue.destination as? VideoUploadViewController {
            videoUploadVC.accessToken = accessToken
        }
    }
}

// MARK: - api.video Requests

extension AuthViewController {
    private func authenticate() {
        let parameters: Parameters = [
            "apiKey": APIVideo.Key
        ]
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        Alamofire.request(APIVideo.BaseURL + APIVideo.Auth, method: .post, parameters: parameters, encoding: JSONEncoding.default).responseJSON { [unowned self] response in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            print("REQUEST:", response.request ?? "nil")
            print("RESPONSE:", response)
            if let error = response.error {
                self.authenticationError(message: error.localizedDescription)
            } else if let statusCode = response.response?.statusCode, let json = response.result.value as? [String: Any] {
                switch statusCode {
                case 200...299:
                    if let accessToken = json["access_token"] as? String {
                        self.accessToken = accessToken
                        self.authStatusLabel.text = "Success!"
                        self.performSegue(withIdentifier: SegueId.AuthSuccess, sender: nil)
                    } else {
                        self.authenticationError(message: "Authentication failed.")
                    }
                default: self.authenticationError(message: json["title"] as? String ?? "Authentication failed.")
                }
            } else {
                self.authenticationError(message: "Authentication failed.")
            }
        }
    }
}

// MARK: - Helper methods

extension AuthViewController {
    private func authenticationError(message: String) {
        let alert = UIAlertController(title: "Authentication Error", message: "\(message)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Try again", style: .default) { [unowned self] action in
            self.authenticate()
        })
        present(alert, animated: true, completion: nil)
    }
}
