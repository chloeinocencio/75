import Foundation
import SwiftData

enum FriendStatus: String, Codable {
    case pending
    case accepted
}

@Model
final class Friend {
    var id: UUID
    var phoneNumberE164: String
    var displayName: String
    var status: String
    var addedDate: Date

    /// Progress sharing is opt-in per app-wide toggle (Challenge.shareProgressWithFriends) and covers
    /// completion %, streak, and rest-day status only. Progress PHOTOS are never shared automatically —
    /// a user must explicitly send an individual photo from the timeline or compare view.
    init(phoneNumberE164: String, displayName: String, status: FriendStatus = .pending) {
        self.id = UUID()
        self.phoneNumberE164 = phoneNumberE164
        self.displayName = displayName
        self.status = status.rawValue
        self.addedDate = .now
    }
}
