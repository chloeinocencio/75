import Foundation
import LocalAuthentication

/// Optional Face ID / Touch ID / passcode lock for the whole app.
///
/// Uses `.deviceOwnerAuthentication`, which falls back to the device passcode, so a failed
/// Face ID can never lock someone out of their own data.
@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var isLocked: Bool
    private var isAuthenticating = false

    init() {
        isLocked = UserDefaults.standard.bool(forKey: PrefKey.appLockEnabled)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: PrefKey.appLockEnabled) }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Called when the app goes to the background.
    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your progress")) ?? false
        if ok { isLocked = false }
    }

    /// Turning the lock on requires proving you can unlock, so nobody enables a lock they
    /// can't open.
    func setEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            let context = LAContext()
            let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on app lock")) ?? false
            guard ok else { return false }
        }
        UserDefaults.standard.set(enabled, forKey: PrefKey.appLockEnabled)
        if !enabled { isLocked = false }
        return true
    }
}
