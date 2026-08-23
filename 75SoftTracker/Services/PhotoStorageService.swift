import Foundation
import UIKit

/// Persists progress photos as JPEG files under Application Support, outside iCloud/Photos
/// so they stay private to the app unless the user explicitly shares one.
enum PhotoStorageService {
    private static var directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ProgressPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func save(_ image: UIImage, dayNumber: Int, pose: PhotoPose) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw PhotoStorageError.encodingFailed
        }
        let fileName = "day\(dayNumber)-\(pose.rawValue.lowercased())-\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    static func loadImage(fileName: String) -> UIImage? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func delete(fileName: String) {
        let url = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}

enum PhotoStorageError: Error {
    case encodingFailed
}
