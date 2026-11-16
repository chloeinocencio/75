import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var social: SocialService
    @EnvironmentObject private var appLock: AppLock

    @AppStorage(PrefKey.waterUnit) private var waterUnitRaw = WaterUnit.localeDefault.rawValue
    @AppStorage(PrefKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(PrefKey.reminderMinutes) private var reminderMinutes = 20 * 60
    @AppStorage(PrefKey.appLockEnabled) private var appLockEnabled = false

    let challenge: Challenge

    @State private var notificationsDenied = false
    @State private var confirm: Confirmation?
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                challengeSection
                remindersSection
                displaySection
                privacySection
                friendsSection
                aboutSection
                dataSection
            }
            .scrollContentBackground(.hidden)
            .themedBackground(glow: 0.1)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                confirm?.title ?? "",
                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                titleVisibility: .visible,
                presenting: confirm
            ) { item in
                Button(item.actionLabel, role: .destructive) { run(item) }
            } message: { item in
                Text(item.message)
            }
            .alert("Change your name", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Save") { Task { _ = await social.saveProfile(displayName: newName) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is what friends see.")
            }
        }
    }

    // MARK: - Sections

    private var challengeSection: some View {
        Section("Challenge") {
            LabeledContent("Tier", value: challenge.mode.rawValue)
            LabeledContent("Started", value: challenge.startDate.formatted(date: .abbreviated, time: .omitted))
            if challenge.attemptNumber > 1 {
                LabeledContent("Attempt", value: "\(challenge.attemptNumber)")
            }
            if let pounds = challenge.bodyWeightPounds {
                LabeledContent("Water goal", value: unit.format(liters: challenge.waterGoalLiters))
                    .accessibilityHint("Based on \(Int(pounds)) pounds")
            }
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Daily check-in", isOn: Binding(
                get: { remindersEnabled },
                set: { on in Task { await setReminders(on) } }
            ))
            .tint(Theme.lime)

            if remindersEnabled {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Reminders")
        } footer: {
            if notificationsDenied {
                Text("Notifications are off for 75. Turn them on in iOS Settings → Notifications → 75.")
            } else {
                Text("Skipped automatically on days you've already finished.")
            }
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Water units", selection: $waterUnitRaw) {
                ForEach(WaterUnit.allCases) { Text($0.label).tag($0.rawValue) }
            }
        }
    }

    private var privacySection: some View {
        Section {
            if AppLock.isAvailable {
                Toggle("Lock with \(AppLock.biometryName)", isOn: Binding(
                    get: { appLockEnabled },
                    set: { on in Task { _ = await appLock.setEnabled(on) } }
                ))
                .tint(Theme.lime)
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Photos are stored only on this iPhone, encrypted while it's locked, and hidden from the app switcher. They're included in your own iPhone backup so they move with you to a new phone.")
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        if let profile = social.profile {
            Section {
                Toggle("Share my progress", isOn: Binding(
                    get: { social.isSharing },
                    set: { on in Task { await social.setSharing(on) } }
                ))
                .tint(Theme.lime)
                Button {
                    newName = profile.displayName
                    renaming = true
                } label: {
                    LabeledContent("Name", value: profile.displayName)
                }
                .foregroundStyle(Theme.ink)
                LabeledContent("Invite code", value: Sanitize.formatted(code: profile.inviteCode))
                Button("Delete my Friends profile", role: .destructive) { confirm = .deleteProfile }
            } header: {
                Text("Friends")
            } footer: {
                Text("Deleting removes your name, code, progress and connections from iCloud. Your challenge on this iPhone isn't affected.")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            DisclosureGroup("Health note") {
                Text(HealthNote.short)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .padding(.vertical, 4)
            }
            DisclosureGroup("Where the rules come from") {
                Text("75 Hard follows the published program at andyfrisella.com. 75 Soft and 75 Medium are community variants with no single owner; 75 uses the most widely published versions.")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .padding(.vertical, 4)
            }
            Button("Privacy policy") { openURL(SupportInfo.privacyPolicyURL) }
            Button("Contact support") {
                if let url = URL(string: "mailto:\(SupportInfo.email)?subject=75%20support") { openURL(url) }
            }
            LabeledContent("Version", value: Bundle.main.appVersion)
        } header: {
            Text("About")
        }
        .foregroundStyle(Theme.ink)
    }

    private var dataSection: some View {
        Section {
            Button("Start a new challenge") { confirm = .newChallenge }
            Button("Erase all data", role: .destructive) { confirm = .eraseAll }
        } header: {
            Text("Data")
        } footer: {
            Text("A new challenge keeps this one's history and photos. Erasing removes every challenge, photo and setting from this iPhone.")
        }
    }

    // MARK: - Helpers

    private var unit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .liters }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderMinutes = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
                rescheduleReminders()
            }
        )
    }

    private func setReminders(_ on: Bool) async {
        if on {
            let granted = await ReminderService.requestPermission()
            notificationsDenied = !granted
            remindersEnabled = granted
            if granted { rescheduleReminders() }
        } else {
            remindersEnabled = false
            ReminderService.cancelAll()
        }
    }

    private func rescheduleReminders() {
        guard remindersEnabled else { return }
        ReminderService.reschedule(
            minutesAfterMidnight: reminderMinutes,
            todayComplete: challenge.entry(forDay: challenge.currentDayNumber)?.isFullyComplete ?? false,
            mode: challenge.mode,
            currentDay: challenge.currentDayNumber,
            totalDays: challenge.totalDays
        )
    }

    private func run(_ item: Confirmation) {
        switch item {
        case .newChallenge:
            challenge.isArchived = true
            try? modelContext.save()
            ReminderService.cancelAll()
            dismiss()
        case .eraseAll:
            // Hide the challenge first so no visible view still holds the model, then
            // delete once the screen has moved to onboarding. Deleting a SwiftData object
            // that a live view is reading can crash.
            challenge.isArchived = true
            try? modelContext.save()
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { eraseEverything() }
        case .deleteProfile:
            Task { _ = await social.deleteProfile() }
        }
    }

    private func eraseEverything() {
        ReminderService.cancelAll()
        try? modelContext.delete(model: ProgressPhoto.self)
        try? modelContext.delete(model: DailyEntry.self)
        try? modelContext.delete(model: Challenge.self)
        try? modelContext.save()
        PhotoStorageService.deleteAll()
        for key in [PrefKey.remindersEnabled, PrefKey.reminderMinutes, PrefKey.waterUnit, PrefKey.acceptedHealthNote] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        Task { _ = await appLock.setEnabled(false) }
    }
}

private enum Confirmation: Identifiable {
    case newChallenge, eraseAll, deleteProfile

    var id: Self { self }

    var title: String {
        switch self {
        case .newChallenge: return "Start a new challenge?"
        case .eraseAll: return "Erase everything?"
        case .deleteProfile: return "Delete your Friends profile?"
        }
    }

    var actionLabel: String {
        switch self {
        case .newChallenge: return "Start new challenge"
        case .eraseAll: return "Erase all data"
        case .deleteProfile: return "Delete profile"
        }
    }

    var message: String {
        switch self {
        case .newChallenge: return "Your current challenge and photos stay saved on this iPhone."
        case .eraseAll: return "Every challenge, photo and setting on this iPhone is deleted. This can't be undone. Your Friends profile is separate — delete it above."
        case .deleteProfile: return "Friends will no longer see you, and your invite code stops working."
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
