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
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            captureCompletion?(nil)
            return
        }
        let normalized = currentPosition == .front ? image.mirroredHorizontally() : image
        captureCompletion?(normalized)
    }
}

extension UIImage {
    func mirroredHorizontally() -> UIImage {
        UIImage(cgImage: cgImage!, scale: scale, orientation: imageOrientation == .up ? .upMirrored : imageOrientation)
    }
}
