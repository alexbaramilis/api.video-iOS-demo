//
//  Constants.swift
//  api.video iOS demo
//
//  Created by Alexandros on 18/01/2019.
//  Copyright © 2019 Alexandros Baramilis. All rights reserved.
//

import Foundation
import MobileCoreServices
import Photos

enum APIVideo {
    static let Key = ""
    static let BaseURL = "https://ws.api.video"
    static let Auth = "/auth/api-key"
    static let Videos = "/videos"
}

enum SegueId {
    static let AuthSuccess = "AuthSuccess"
    static let PlayVideo = "PlayVideo"
}

enum Media {
    static let AllowedMediaTypes = [kUTTypeMovie as String]
    static let VideoQualityPreset = [
        0: AVAssetExportPreset640x480,
        1: AVAssetExportPreset1280x720,
        2: AVAssetExportPreset1920x1080
    ]
    static let ChunkSize = 10000000 // 10MB in Bytes
}

enum AttachmentType {
    case video
}
