import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var social: SocialService
    @Environment(\.openURL) private var openURL
    let challenge: Challenge

    @State private var showAddFriend = false
    @State private var pendingAction: PendingAction?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .themedBackground(glow: 0.2)
            .navigationTitle("Friends")
            .toolbar {
                if social.hasProfile {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showAddFriend = true } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        .accessibilityLabel("Add a friend")
                    }
                }
            }
            .refreshable { await social.refresh(force: true) }
            .task {
                await social.checkAccount()
                await social.refresh()
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendSheet()
            }
            .alert("Friends", isPresented: Binding(
                // The add-friend sheet shows its own errors inline.
                get: { social.errorMessage != nil && !showAddFriend },
                set: { if !$0 { social.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(social.errorMessage ?? "")
            }
            .confirmationDialog(
                pendingAction?.title ?? "",
                isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
                titleVisibility: .visible,
                presenting: pendingAction
            ) { action in
                Button(action.confirmLabel, role: .destructive) {
                    Task { await perform(action) }
                }
            } message: { action in
                Text(action.message)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch social.accountState {
        case .noAccount:
            notice(
                icon: "icloud.slash",
                title: "Sign in to iCloud",
                text: "Friends uses your iCloud account, so there's no new password to make. Sign in under Settings → your name, then come back."
            )
        case .restricted:
            notice(icon: "lock", title: "iCloud is restricted", text: "Screen Time or a device profile is blocking iCloud on this iPhone, so Friends can't connect.")
        case .temporarilyUnavailable:
            notice(icon: "icloud", title: "iCloud is unavailable", text: "iCloud isn't reachable right now. Your challenge works normally — try Friends again in a bit.")
        case .unknown, .available:
            if social.hasProfile {
                connectedContent
            } else if social.accountState == .available {
                ProfileSetupCard(challenge: challenge)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
    }

    @ViewBuilder
    private var connectedContent: some View {
        if let profile = social.profile {
            InviteCard(profile: profile)
        }

        if !social.incoming.isEmpty {
            VStack(spacing: 10) {
                SectionLabel(text: "Requests")
                ForEach(social.incoming) { person in
                    requestRow(person)
                }
            }
        }

        VStack(spacing: 10) {
            SectionLabel(text: social.friends.isEmpty ? "Your friends" : "Your friends · \(social.friends.count)")
            if social.friends.isEmpty {
                Text("Add someone with their invite code. You'll see each other's day, streak and today's progress once you've both added each other.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(social.friends.enumerated()), id: \.element.id) { index, friend in
                        friendRow(friend)
                        if index < social.friends.count - 1 {
                            Divider().overlay(Theme.line).padding(.leading, 66)
                        }
                    }
                }
                .card(padding: 6)
            }
        }

        if !social.outgoingPending.isEmpty {
            VStack(spacing: 10) {
                SectionLabel(text: "Waiting on them")
                VStack(spacing: 0) {
                    ForEach(social.outgoingPending) { person in
                        HStack {
                            Avatar(name: person.displayName, fraction: 0)
                            Text(person.displayName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button("Cancel") { Task { await social.remove(person) } }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.dim)
                        }
                        .padding(10)
                    }
                }
                .card(padding: 6)
            }
        }

        Text("Friends see your display name, tier, day, streak and today's completion — never your photos, notes or body weight. Turn sharing off in Settings anytime.")
            .font(.caption)
            .foregroundStyle(Theme.dim)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    private func friendRow(_ friend: FriendSnapshot) -> some View {
        HStack(spacing: 12) {
            Avatar(name: friend.displayName, fraction: friend.isSharing && friend.isFresh ? friend.todayFraction : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(summary(for: friend))
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            if friend.isSharing && friend.streak > 0 {
                Label("\(friend.streak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel("\(friend.streak) day streak")
            }
            Menu {
                Button("Remove friend", systemImage: "person.badge.minus") { pendingAction = .remove(friend) }
                Button("Block", systemImage: "hand.raised") { pendingAction = .block(friend) }
                Button("Report", systemImage: "exclamationmark.bubble") { report(friend) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options for \(friend.displayName)")
        }
        .padding(10)
        .accessibilityElement(children: .contain)
    }

    private func summary(for friend: FriendSnapshot) -> String {
        guard friend.isSharing else { return "Not sharing progress" }
        guard let tier = friend.tier, friend.day > 0 else { return "Hasn't started yet" }
        let today = friend.isFresh ? " · \(Int(friend.todayFraction * 100))% today" : ""
        return "\(tier) · Day \(friend.day) of \(friend.totalDays)\(today)"
    }

    private func requestRow(_ person: FriendSnapshot) -> some View {
        HStack(spacing: 12) {
            Avatar(name: person.displayName, fraction: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Wants to keep each other honest")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button("Accept") { Task { await social.accept(person) } }
                .buttonStyle(LimeButtonStyle(compact: true))
            Menu {
                Button("Decline", systemImage: "xmark") { Task { await social.remove(person) } }
                Button("Block", systemImage: "hand.raised") { pendingAction = .block(person) }
                Button("Report", systemImage: "exclamationmark.bubble") { report(person) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.dim)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("More options for \(person.displayName)")
        }
        .card(padding: 12)
    }

    private func notice(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
        }
        .card()
        .padding(.top, 8)
    }

    private func report(_ person: FriendSnapshot) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = SupportInfo.email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Report a 75 user"),
            URLQueryItem(name: "body", value: "Reported profile: \(person.id)\nName shown: \(person.displayName)\n\nWhat happened:\n"),
        ]
        if let url = components.url { openURL(url) }
    }

    private func perform(_ action: PendingAction) async {
        switch action {
        case .remove(let person): await social.remove(person)
        case .block(let person): await social.block(person)
        }
    }
}

private enum PendingAction: Identifiable {
    case remove(FriendSnapshot)
    case block(FriendSnapshot)

    var id: String {
        switch self {
        case .remove(let p): return "remove-\(p.id)"
        case .block(let p): return "block-\(p.id)"
        }
    }

    var title: String {
        switch self {
        case .remove(let p): return "Remove \(p.displayName)?"
        case .block(let p): return "Block \(p.displayName)?"
        }
    }

    var confirmLabel: String {
        switch self {
        case .remove: return "Remove"
        case .block: return "Block"
        }
    }

    var message: String {
        switch self {
        case .remove: return "You'll stop seeing each other's progress. You can add them again with their code."
        case .block: return "They're removed and their requests won't show up on this iPhone again."
        }
    }
}

// MARK: - Pieces

/// Initials inside a ring that fills with the friend's progress today.
struct Avatar: View {
    let name: String
    let fraction: Double

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.limeSoft)
            Text(initials)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.accentText, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(-3)
        }
        .frame(width: 42, height: 42)
        .padding(3)
        .accessibilityHidden(true)
    }
}

private struct InviteCard: View {
    let profile: MyProfile
    @State private var copied = false

    var body: some View {
        let code = Sanitize.formatted(code: profile.inviteCode)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your invite code")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.limeInk.opacity(0.7))
                    Text(code)
                        .font(.system(size: 32, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.limeInk)
                        .accessibilityLabel("Invite code \(profile.inviteCode.map(String.init).joined(separator: " "))")
                }
                Spacer()
            }
            HStack(spacing: 10) {
                ShareLink(item: "Keep me honest on 75 — add me with code \(code).") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(QuietButtonStyle())

                Button {
                    UIPasteboard.general.string = profile.inviteCode
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(QuietButtonStyle())
                .sensoryFeedback(.success, trigger: copied) { _, new in new }
            }
            Text("Signed in as \(profile.displayName) with iCloud")
                .font(.caption)
                .foregroundStyle(Theme.limeInk.opacity(0.7))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lime, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

private struct ProfileSetupCard: View {
    @EnvironmentObject private var social: SocialService
    let challenge: Challenge
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep each other honest")
                .font(.title2.weight(.heavy))
                .foregroundStyle(Theme.ink)
            Text("Connect with friends using a private invite code. No phone number, no password — it uses your iCloud account.")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Name friends will see")
                TextField("e.g. Chloe", text: $name)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .onChange(of: name) { _, new in
                        if new.count > Sanitize.maxNameLength { name = String(new.prefix(Sanitize.maxNameLength)) }
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                bullet("eye", "They see your tier, day, streak and today's %.")
                bullet("eye.slash", "Never your photos, notes or body weight.")
                bullet("hand.raised", "Only people you both add. Block or report anyone.")
                bullet("trash", "Delete your profile from Settings anytime.")
            }

            Button {
                focused = false
                Task {
                    if await social.saveProfile(displayName: name) {
                        await social.publish(ProgressSnapshot(
                            tier: challenge.mode.rawValue,
                            day: challenge.currentDayNumber,
                            totalDays: challenge.totalDays,
                            streak: challenge.currentStreak,
                            todayFraction: challenge.entry(forDay: challenge.currentDayNumber)?.completionFraction ?? 0
                        ))
                    }
                }
            } label: {
                if social.isBusy {
                    ProgressView().tint(Theme.limeInk)
                } else {
                    Text("Turn on Friends")
                }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(Sanitize.displayName(name).isEmpty || social.isBusy)
        }
        .card(padding: 18)
        .padding(.top, 8)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(Theme.ink)
    }
}

private struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialService
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ask your friend for their 8-character code from their Friends tab.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)

                TextField("ABCD-2345", text: $code)
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .onChange(of: code) { _, new in
                        if new.count > 12 { code = String(new.prefix(12)) }
                    }
                    .accessibilityLabel("Invite code")

                if let message = social.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.ink)
                }

                Button {
                    Task {
                        if await social.add(code: code) { dismiss() }
                    }
                } label: {
                    if social.isBusy {
                        ProgressView().tint(Theme.limeInk)
                    } else {
                        Text("Send request")
                    }
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(Sanitize.normalizedCode(code) == nil || social.isBusy)

                Text("They'll see your request and your display name. You'll see each other's progress once they accept.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                Spacer()
            }
            .padding(20)
            .themedBackground(glow: 0.2)
            .navigationTitle("Add a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
            .onDisappear { social.errorMessage = nil }
        }
        .presentationDetents([.medium, .large])
    }
}
