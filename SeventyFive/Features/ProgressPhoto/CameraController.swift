import AVFoundation
import UIKit

final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private(set) var currentPosition: AVCaptureDevice.Position = .front
    @Published var isAuthorized = false
    private var captureCompletion: ((UIImage?) -> Void)?

    func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.configure() }
                }
            }
        default:
            isAuthorized = false
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        addInput(for: currentPosition)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
        start()
    }

    private func addInput(for position: AVCaptureDevice.Position) {
        session.inputs.forEach { session.removeInput($0) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
    }

    func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    func flipCamera() {
        currentPosition = currentPosition == .front ? .back : .front
        session.beginConfiguration()
        addInput(for: currentPosition)
        session.commitConfiguration()
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        captureCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // AVFoundation calls this on its own queue; the completion feeds SwiftUI @State,
        // so it has to land on the main thread.
        let result: UIImage? = {
            guard error == nil,
                  let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else { return nil }
            return currentPosition == .front ? image.mirroredHorizontally() : image
        }()

        DispatchQueue.main.async { [weak self] in
            self?.captureCompletion?(result)
        }
    }
}

extension UIImage {
    /// Mirrors the image across its vertical axis. Front-camera captures come back
    /// un-mirrored relative to the live preview, so they'd otherwise look "flipped"
    /// compared to what the user framed.
    ///
    /// This has to map every orientation to its mirrored counterpart — capture output is
    /// usually `.right` or `.left` in portrait, not `.up`, so special-casing `.up` alone
    /// would silently do nothing in the common case.
    func mirroredHorizontally() -> UIImage {
        guard let cgImage else { return self }
        let mirrored: UIImage.Orientation
        switch imageOrientation {
        case .up: mirrored = .upMirrored
        case .upMirrored: mirrored = .up
        case .down: mirrored = .downMirrored
        case .downMirrored: mirrored = .down
        case .left: mirrored = .leftMirrored
        case .leftMirrored: mirrored = .left
        case .right: mirrored = .rightMirrored
        case .rightMirrored: mirrored = .right
        @unknown default: mirrored = imageOrientation
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: mirrored)
    }
}
