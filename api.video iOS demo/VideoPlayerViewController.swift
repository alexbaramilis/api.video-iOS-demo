//
//  VideoPlayerViewController.swift
//  api.video iOS demo
//
//  Created by Alexandros on 18/01/2019.
//  Copyright © 2019 Alexandros Baramilis. All rights reserved.
//

import UIKit
import AVKit

class VideoPlayerViewController: AVPlayerViewController, AVPlayerViewControllerDelegate {
    
    // MARK: - Dependencies
    
    var hlsUrl: URL?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        player = AVPlayer(url: hlsUrl!)
        player?.play()
        NotificationCenter.default.addObserver(self, selector: #selector(didReachEnd), name: Notification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    @objc func didReachEnd() {
        player?.seek(to: CMTime.zero)
    }
}
