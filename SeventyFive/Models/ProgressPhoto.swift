import Foundation
import SwiftData

enum PhotoPose: String, Codable, CaseIterable, Identifiable {
    case front = "Front"
    case side = "Side"
    case back = "Back"

    var id: String { rawValue }
}

@Model
final class ProgressPhoto {
    var id: UUID
    var dayNumber: Int
    var date: Date
    var poseRaw: String
    /// Filename inside the app's PhotoStorage documents subdirectory. Never store the raw image in SwiftData.
    var fileName: String

    var dailyEntry: DailyEntry?

    init(dayNumber: Int, date: Date, pose: PhotoPose, fileName: String) {
        self.id = UUID()
        self.dayNumber = dayNumber
        self.date = date
        self.poseRaw = pose.rawValue
        self.fileName = fileName
    }

    var pose: PhotoPose {
        get { PhotoPose(rawValue: poseRaw) ?? .front }
        set { poseRaw = newValue.rawValue }
    }
}
