//
//  VideoUploadViewController.swift
//  api.video iOS demo
//
//  Created by Alexandros on 18/01/2019.
//  Copyright © 2019 Alexandros Baramilis. All rights reserved.
//

import UIKit
import Alamofire
import Photos
import MobileCoreServices

class VideoUploadViewController: UIViewController {
    
    // MARK: - Dependencies
    
    var accessToken: String?
    
    // MARK: - Private API
    
    private var selectedVideoUrl: URL?
    private var uploadedVideoHLSUrl: URL?
    
    // MARK: - Outlets
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var videoQualitySegmentedControl: UISegmentedControl!
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var chooseVideoButton: UIButton!
    @IBOutlet weak var titleTextField: UITextField!
    @IBOutlet weak var descriptionTextField: UITextField!
    @IBOutlet weak var uploadButton: UIButton!
    @IBOutlet weak var progressLabel: UILabel!
    @IBOutlet weak var progressBar: UIProgressView!
    
    // MARK: - Actions
    
    @IBAction func chooseVideoButtonTapped(_ sender: UIButton) {
        presentChooseFileActionSheet()
    }
    
    private func presentChooseFileActionSheet() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Photo Library", style: .default, handler: { [unowned self] action in self.checkPhotoLibraryIsAuthorized() }))
        actionSheet.addAction(UIAlertAction(title: "Files", style: .default, handler: { [unowned self] action in self.openDocumentPicker() }))
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(actionSheet, animated: true, completion: nil)
    }
    
    @IBAction func uploadButtonTapped(_ sender: UIButton) {
        if selectedVideoUrl != nil {
            createVideoResource(title: titleTextField.text, description: descriptionTextField.text)
        } else {
            showAlert(title: "Missing data", message: "Select a video!")
        }
    }
    
    @IBAction func videoQualityChanged(_ sender: UISegmentedControl) {
        selectedVideoUrl = nil
        thumbnailImageView.image = nil
    }
    
    @IBAction func didTapBackground(_ sender: UITapGestureRecognizer) {
        view.endEditing(true)
    }
    
    @IBAction func cleanupButtonTapped(_ sender: UIButton) {
        showCleanupAlert()
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - Photo Library methods
    
    private func checkPhotoLibraryIsAuthorized() {
        switch PHPhotoLibrary.authorizationStatus() {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [unowned self] newStatus in
                if newStatus == .authorized {
                    DispatchQueue.main.async {
                        self.openPhotoLibrary()
                    }
                }
            }
        case .restricted, .denied: showSettingsAlert(title: "Allow Access", message: "This app needs access to your Photo Library. Please go to Settings to allow this.")
        case .authorized: openPhotoLibrary()
        }
    }
    
    private func openPhotoLibrary() {
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            let imagePickerController = UIImagePickerController()
            imagePickerController.delegate = self
            imagePickerController.sourceType = .photoLibrary
            imagePickerController.mediaTypes = Media.AllowedMediaTypes
            imagePickerController.videoExportPreset = Media.VideoQualityPreset[videoQualitySegmentedControl.selectedSegmentIndex]!
            present(imagePickerController, animated: true, completion: nil)
        } else {
            showAlert(title: "Error", message: "Photo Library is not available.")
        }
    }
    
    // MARK: - Document Picker methods
    
    private func openDocumentPicker() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: Media.AllowedMediaTypes, in: .import)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true, completion: nil)
    }
}

// MARK: - UIImagePickerControllerDelegate

extension VideoUploadViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let videoUrl = info[UIImagePickerController.InfoKey.mediaURL] as? URL {
            selectedVideoUrl = videoUrl
            thumbnailImageView.image = getThumbnailFrom(videoUrl: videoUrl)
        } else {
            showAlert(title: "File Error", message: "Video URL is corrupt.")
        }
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - UIDocumentPickerDelegate

extension VideoUploadViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let videoUrl = urls.first {
            compressVideo(videoUrl: videoUrl) { [unowned self] compressedVideoUrl in
                if let compressedVideoUrl = compressedVideoUrl {
                    self.selectedVideoUrl = compressedVideoUrl
                    self.thumbnailImageView.image = self.getThumbnailFrom(videoUrl: compressedVideoUrl)
                }
            }
        } else {
            showAlert(title: "File Error", message: "Video URL is corrupt.")
        }
    }
}

// MARK: - api.video Requests

extension VideoUploadViewController {
    private func createVideoResource(title: String?, description: String?) {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken!)"
        ]
        let parameters: Parameters = [
            "title": title ?? "",
            "description": description ?? ""
        ]
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        uploadButton.isEnabled = false
        Alamofire.request(APIVideo.BaseURL + APIVideo.Videos, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers).responseJSON { [unowned self] response in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            self.uploadButton.isEnabled = true
            print("REQUEST:", response.request ?? "nil")
            print("RESPONSE:", response)
            if let error = response.error {
                self.showAlert(title: "Upload failed", message: error.localizedDescription)
            } else if let statusCode = response.response?.statusCode, let json = response.result.value as? [String: Any] {
                switch statusCode {
                case 200...299:
                    if let source = json["source"] as? [String: Any], let uri = source["uri"] as? String {
                        self.uploadVideo(videoUrl: self.selectedVideoUrl!, uploadUri: uri)
                    } else {
                        self.showAlert(title: "Upload failed", message: "Corrupt JSON response data.")
                    }
                default: self.showAlert(title: "Upload failed", message: json["title"] as? String ?? "Please try again.")
                }
            } else {
                self.showAlert(title: "Upload failed", message: "Please try again.")
            }
        }
    }
    
    private func uploadInOneRequest(data: Data, uploadUri: String) {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken!)"
        ]
        let parameters: Parameters = [
            "Content-Disposition": "form-data; name=\"file\"; filename=\"source.mp4\"",
            "Content-Type": "video/mp4"
        ]
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        showProgressUI(force: true)
        updateProgress(progress: Float(0), label: "Uploading: ", animated: false)
        Alamofire.upload(multipartFormData: { multipartFormData in
            for (key, value) in parameters {
                multipartFormData.append("\(value)".data(using: String.Encoding.utf8)!, withName: key as String)
            }
            multipartFormData.append(data, withName: "file", fileName: "source.mp4", mimeType: "video/mp4")
        }, usingThreshold: UInt64(Media.ChunkSize), to: APIVideo.BaseURL + uploadUri, method: .post, headers: headers) { [unowned self] result in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            switch result {
            case .success(let uploadRequest, _, _):
                print("UPLOAD REQUEST:", uploadRequest.request ?? "nil")
                uploadRequest.responseJSON { [unowned self] response in
                    print("UPLOAD RESPONSE:", response)
                    if let error = response.error {
                        self.showAlert(title: "Upload Failed", message: error.localizedDescription)
                        self.showProgressUI(force: false)
                    } else if let statusCode = response.response?.statusCode, let json = response.result.value as? [String: Any] {
                        switch statusCode {
                        case 200...299:
                            if let assets = json["assets"] as? [String: Any], let hls = assets["hls"] as? String {
                                self.uploadedVideoHLSUrl = URL(string: hls)
                                self.updateProgress(progress: Float(1), label: "Uploading: ", animated: false)
                                self.showUploadCompletionAlert()
                            } else {
                                self.showAlert(title: "Upload Complete", message: "But failed to parse JSON response.")
                                self.showProgressUI(force: false)
                            }
                        default:
                            self.showAlert(title: "Upload Failed", message: "Please try again.")
                            self.showProgressUI(force: false)
                        }
                    } else {
                        self.showAlert(title: "Upload Failed", message: "Please try again.")
                        self.showProgressUI(force: false)
                    }
                }
            case .failure(let error):
                self.showAlert(title: "Upload Failed", message: error.localizedDescription)
                self.showProgressUI(force: false)
            }
        }
    }
    
    private func uploadInChunks(chunks: [Data], ranges: [Range<Int>], chunkIndex: Int, totalDataLength: Int, uploadUri: String) {
        var headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken!)",
            "Content-Range": "bytes \(ranges[chunkIndex].lowerBound)-\(ranges[chunkIndex].upperBound - 1)/\(totalDataLength)"
        ]
        if chunkIndex < chunks.count - 1 {
            headers["Expect"] = "100-Continue"
        }
        let parameters: Parameters = [
            "Content-Disposition": "form-data; name=\"file\"; filename=\"sourceChunked\(chunkIndex + 1)\"",
            "Content-Type": ""
        ]
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        showProgressUI(force: true)
        Alamofire.upload(multipartFormData: { multipartFormData in
            for (key, value) in parameters {
                multipartFormData.append("\(value)".data(using: String.Encoding.utf8)!, withName: key as String)
            }
            multipartFormData.append(chunks[chunkIndex], withName: "file", fileName: "sourceChunked\(chunkIndex + 1)", mimeType: "")
        }, usingThreshold: UInt64(Media.ChunkSize), to: APIVideo.BaseURL + uploadUri, method: .post, headers: headers) { [unowned self] result in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            switch result {
            case .success(let uploadRequest, _, _):
                print("UPLOAD REQUEST (Chunk \(chunkIndex + 1)/\(chunks.count):", uploadRequest.request ?? "nil")
                uploadRequest.responseJSON { [unowned self] response in
                    if let error = response.error {
                        self.showAlert(title: "Upload Failed", message: error.localizedDescription)
                        self.showProgressUI(force: false)
                    } else if let statusCode = response.response?.statusCode, let json = response.result.value as? [String: Any] {
                        switch statusCode {
                        case 200...299:
                            self.updateProgress(progress: Float(chunkIndex + 1) / Float(chunks.count), label: "Uploading: ")
                            if chunkIndex < chunks.count - 1 {
                                self.uploadInChunks(chunks: chunks, ranges: ranges, chunkIndex: chunkIndex + 1, totalDataLength: totalDataLength, uploadUri: uploadUri)
                            } else if let assets = json["assets"] as? [String: Any], let hls = assets["hls"] as? String {
                                self.uploadedVideoHLSUrl = URL(string: hls)
                                self.showUploadCompletionAlert()
                                print("UPLOAD RESPONSE:", response)
                            } else {
                                self.showAlert(title: "Upload Complete", message: "But failed to parse JSON response.")
                                self.showProgressUI(force: false)
                            }
                        default:
                            self.showAlert(title: "Upload Failed", message: "Please try again.")
                            self.showProgressUI(force: false)
                        }
                    } else {
                        self.showAlert(title: "Upload Failed", message: "Please try again.")
                        self.showProgressUI(force: false)
                    }
                }
            case .failure(let error):
                self.showAlert(title: "Upload Failed", message: error.localizedDescription)
                self.showProgressUI(force: false)
            }
        }
    }
}

// MARK: - Video Helpers

extension VideoUploadViewController {
    private func getThumbnailFrom(videoUrl: URL) -> UIImage? {
        do {
            let imageGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: videoUrl, options: nil))
            imageGenerator.appliesPreferredTrackTransform = true
            let cgImage = try imageGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch let error {
            print("Error generating thumbnail: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func uploadVideo(videoUrl: URL, uploadUri: String) {
        do {
            let data = try Data(contentsOf: videoUrl)
            let (chunks, ranges) = splitDataInChunks(data)
            if chunks.count == 1 {
                uploadInOneRequest(data: chunks.first!, uploadUri: uploadUri)
            } else if chunks.count > 1 {
                updateProgress(progress: Float(0), label: "Uploading: ", animated: false)
                uploadInChunks(chunks: chunks, ranges: ranges, chunkIndex: 0, totalDataLength: data.count, uploadUri: uploadUri)
            }
        } catch {
            showAlert(title: "File Error", message: error.localizedDescription)
        }
    }
    
    private func splitDataInChunks(_ data: Data) -> ([Data], [Range<Int>]) {
        let dataLength = data.count
        print("Data length:", dataLength)
        let fullChunks = dataLength / Media.ChunkSize
        let leftoverChunk = dataLength % Media.ChunkSize != 0 ? 1 : 0
        let totalChunks = fullChunks + leftoverChunk
        print("Number of chunks:", totalChunks)
        var chunks = [Data]()
        var ranges = [Range<Int>]()
        for i in 0..<totalChunks {
            let lowerBound = i * Media.ChunkSize
            let upperBound = i < totalChunks - 1 ? (i + 1) * Media.ChunkSize : dataLength
            let range = Range(uncheckedBounds: (lower: lowerBound, upper: upperBound))
            print("chunk \(i + 1) -> range: \(range)")
            ranges.append(range)
            chunks.append(data.subdata(in: range))
        }
        return (chunks, ranges)
    }
    
    private func compressVideo(videoUrl: URL, completion: @escaping (URL?) -> Void) {
        printFileSize(from: videoUrl, message: "File size before compression:")
        if let exportSession = AVAssetExportSession(asset:  AVAsset(url: videoUrl), presetName: Media.VideoQualityPreset[videoQualitySegmentedControl.selectedSegmentIndex]!) {
            exportSession.outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".MP4")
            exportSession.outputFileType = AVFileType.mp4
            exportSession.shouldOptimizeForNetworkUse = true
            showProgressUI(force: true)
            startCompressionProgressTimer(for: exportSession)
            exportSession.exportAsynchronously { [unowned self] in
                self.printFileSize(from: exportSession.outputURL!, message: "File size after compression:")
                DispatchQueue.main.async {
                    self.showProgressUI(force: false)
                    completion(exportSession.outputURL!)
                }
            }
        } else {
            showAlert(title: "Compression Failed", message: "Failed to initialize AVAssetExportSession.")
            completion(nil)
        }
    }
    
    private func printFileSize(from url: URL, message: String = "") {
        do {
            let data = try Data(contentsOf: url)
            print(message, data.count)
        } catch {
            print("Error reading data from url:", error.localizedDescription)
        }
    }
}

// MARK: - UI helpers

extension VideoUploadViewController {
    private func setupUI() {
        titleTextField.delegate = self
        descriptionTextField.delegate = self
    }
    
    private func showSettingsAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Settings", style: .default, handler: { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    return
                }
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    private func showUploadCompletionAlert() {
        let alert = UIAlertController(title: "Success!", message: "Successfully uploaded video.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss", style: .default) { [unowned self] action in
            self.resetUI()
        })
        alert.addAction(UIAlertAction(title: "Play", style: .default) { [unowned self] action in
            self.resetUI()
            if self.uploadedVideoHLSUrl != nil {
                self.performSegue(withIdentifier: SegueId.PlayVideo, sender: self)
            }
        })
        present(alert, animated: true, completion: nil)
    }
    
    private func showProgressUI(force: Bool) {
        uploadButton.isEnabled = !force
        uploadButton.isHidden = force
        progressLabel.isHidden = !force
        progressBar.isHidden = !force
        if !force {
            progressLabel.text = ""
            progressBar.setProgress(0, animated: false)
        }
    }
    
    private func resetUI() {
        videoQualitySegmentedControl.selectedSegmentIndex = 1
        thumbnailImageView.image = nil
        selectedVideoUrl = nil
        titleTextField.text = ""
        descriptionTextField.text = ""
        uploadButton.isEnabled = true
        uploadButton.isHidden = false
        progressLabel.text = ""
        progressLabel.isHidden = true
        progressBar.setProgress(0, animated: false)
        progressBar.isHidden = true
    }
    
    private func updateProgress(progress: Float, label: String, animated: Bool = true) {
        progressLabel.text = "\(label)\(Int(progress*100))%"
        progressBar.setProgress(progress, animated: animated)
    }
    
    private func startCompressionProgressTimer(for exportSession: AVAssetExportSession) {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [unowned self] timer in
            self.updateProgress(progress: exportSession.progress, label: "Compressing: ")
            if exportSession.progress == 1 {
                timer.invalidate()
            }
        }
    }
}

// MARK: - UITextFieldDelegate

extension VideoUploadViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        var contentOffset = scrollView.contentOffset
        contentOffset.y = textField.frame.origin.y - view.bounds.height/4
        scrollView.setContentOffset(contentOffset, animated: true)
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        scrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: true)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Navigation

extension VideoUploadViewController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == SegueId.PlayVideo, let videoPlayerVC = segue.destination as? VideoPlayerViewController {
            videoPlayerVC.hlsUrl = uploadedVideoHLSUrl
        }
    }
}

// MARK: - Cleanup

extension VideoUploadViewController {
    private func showCleanupAlert() {
        let alert = UIAlertController(title: "Cleanup", message: "This will delete all the videos associated with your API key.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Do it!", style: .default, handler: { [unowned self] _ in
            self.performCleanup()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    private func performCleanup() {
        getVideoIds { [unowned self] videoIds in
            if let videoIds = videoIds {
                print("Video Ids:", videoIds)
                if videoIds.isEmpty {
                    self.showAlert(title: "No videos", message: "There are no videos associated with your API key.")
                } else {
                    for videoId in videoIds {
                        self.deleteVideo(videoId: videoId, isLast: videoId == videoIds.last)
                    }
                }
            }
        }
    }
    
    private func getVideoIds(completion: @escaping ([String]?) -> Void) {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken!)"
        ]
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        Alamofire.request(APIVideo.BaseURL + APIVideo.Videos, method: .get, headers: headers).responseJSON { [unowned self] response in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            print("REQUEST:", response.request ?? "nil")
            print("RESPONSE:", response.result)
            if let error = response.error {
                self.showAlert(title: "Cleanup failed", message: error.localizedDescription)
            } else if let statusCode = response.response?.statusCode, let json = response.result.value as? [String: Any] {
                switch statusCode {
                case 200...299:
                    if let data = json["data"] as? [[String: Any]] {
                        var videoIds = [String]()
                        for videoData in data {
                            if let videoId = videoData["videoId"] as? String {
                                videoIds.append(videoId)
                            } else {
                                self.showAlert(title: "Cleanup failed", message: "Corrupt JSON response data.")
                                completion(nil)
                                return
                            }
                        }
                        completion(videoIds)
                        return
                    } else {
                        self.showAlert(title: "Cleanup failed", message: "Corrupt JSON response data.")
                    }
                default: self.showAlert(title: "Cleanup failed", message: json["title"] as? String ?? "Please try again.")
                }
            } else {
                self.showAlert(title: "Cleanup failed", message: "Please try again.")
            }
            completion(nil)
        }
    }
    
    private func deleteVideo(videoId: String, isLast: Bool) {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken!)"
        ]
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        Alamofire.request(APIVideo.BaseURL + APIVideo.Videos + "/" + videoId, method: .delete, headers: headers).responseJSON { [unowned self] response in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            print("REQUEST:", response.request ?? "nil")
            print("RESPONSE:", response.result)
            if let error = response.error {
                self.showAlert(title: "Delete failed", message: error.localizedDescription)
            } else if let statusCode = response.response?.statusCode {
                switch statusCode {
                case 204:
                    print("Deleting \(videoId) succeeded.")
                    if isLast {
                        self.showAlert(title: "Cleanup complete!", message: "")
                    }
                default: self.showAlert(title: "Delete failed", message: "Deleting \(videoId) failed.")
                }
            } else {
                self.showAlert(title: "Delete failed", message: "Deleting \(videoId) failed 2.")
            }
        }
    }
}
