import AVFoundation
import UIKit

/// Camera authorisation, kept distinct from a simple yes/no.
///
/// `undetermined` matters: while the system alert is on screen the app is not authorised,
/// but it has not been refused either — telling the user to open Settings at that moment
/// would be wrong, and it would be sitting behind Apple's own alert.
enum CameraPermission {
    case undetermined
    case authorized
    case denied
    case restricted
}

final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private(set) var currentPosition: AVCaptureDevice.Position = .front
    @Published var permission: CameraPermission = .undetermined
    private var captureCompletion: ((UIImage?) -> Void)?

    var isAuthorized: Bool { permission == .authorized }

    /// Called when the capture screen appears, so the system alert arrives in context —
    /// right after the user asked to take a photo, which is what Apple's guidance wants.
    func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
            configure()
        case .notDetermined:
            permission = .undetermined
            // This is the standard iOS alert: "\"75\" Would Like to Access the Camera",
            // with NSCameraUsageDescription as its body. It is shown once per install —
            // after a refusal iOS answers immediately without presenting it again.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permission = granted ? .authorized : .denied
                    if granted { self?.configure() }
                }
            }
        case .restricted:
            permission = .restricted
        case .denied:
            permission = .denied
        @unknown default:
            permission = .denied
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
