import CloudKit
import Foundation

/// Friends, backed by the app's CloudKit public database. No server of our own.
///
/// ## Identity
/// The user's iCloud account *is* the account. CloudKit hands each app an app-scoped,
/// anonymous user record ID; the profile is keyed off it. There are no passwords, no phone
/// numbers and no emails stored anywhere.
///
/// ## Records (public database)
/// - `Profile` — one per person, record name `p_<user record name>`.
///   `displayName`, `inviteCode` (queryable), `isSharing`, `tier`, `day`, `totalDays`,
///   `streak`, `todayFraction`, `updatedAt`.
/// - `Connection` — "I added you", record name `c_<me>_<them>`, fields `from`, `to`
///   (both queryable). Two people are friends when *both* directions exist, so nobody can
///   be added to someone's list without their consent.
///
/// CloudKit's default public-database security means anyone can read, only the creator can
/// write — so nobody can edit someone else's profile or forge a connection in their name.
/// When sharing is off, the progress fields are zeroed rather than left stale.
///
/// ## Schema setup (once, in CloudKit Console)
/// See README → "CloudKit setup": the indexes on `inviteCode`, `from`, `to` and
/// `recordName` must be marked Queryable, and the schema deployed to Production before
/// release.
@MainActor
final class SocialService: ObservableObject {
    static let containerID = "iCloud.com.chloeinocencio.seventyfive"

    enum AccountState: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
    }

    @Published private(set) var accountState: AccountState = .unknown
    @Published private(set) var profile: MyProfile?
    @Published private(set) var isSharing: Bool
    @Published private(set) var friends: [FriendSnapshot] = []
    @Published private(set) var incoming: [FriendSnapshot] = []
    @Published private(set) var outgoingPending: [FriendSnapshot] = []
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private var lastPublished: ProgressSnapshot?
    private var lastRefresh: Date?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let profile = "social.profile"
        static let sharing = "social.isSharing"
        static let blocked = "social.blocked"
        static let friendsCache = "social.friendsCache"
    }

    /// Created lazily: touching CKContainer before the iCloud capability is configured
    /// would crash, and most people open the app without ever visiting Friends.
    private lazy var container = CKContainer(identifier: Self.containerID)
    private var db: CKDatabase { container.publicCloudDatabase }

    init() {
        isSharing = defaults.object(forKey: Key.sharing) as? Bool ?? true
        if let data = defaults.data(forKey: Key.profile) {
            profile = try? JSONDecoder().decode(MyProfile.self, from: data)
        }
        if let data = defaults.data(forKey: Key.friendsCache),
           let cached = try? JSONDecoder().decode([FriendSnapshot].self, from: data) {
            friends = cached
        }
    }

    var hasProfile: Bool { profile != nil }

    // MARK: - Blocking (local)

    private var blockedIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.blocked) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.blocked) }
    }

    // MARK: - Account

    func checkAccount() async {
        do {
            switch try await container.accountStatus() {
            case .available: accountState = .available
            case .noAccount: accountState = .noAccount
            case .restricted: accountState = .restricted
            case .temporarilyUnavailable: accountState = .temporarilyUnavailable
            case .couldNotDetermine: accountState = .unknown
            @unknown default: accountState = .unknown
            }
        } catch {
            accountState = .unknown
            report(error)
        }
    }

    private func myRecordName() async throws -> String {
        "p_" + (try await container.userRecordID().recordName)
    }

    // MARK: - Profile

    /// Creates the user's sharing profile, or renames it if it exists.
    func saveProfile(displayName raw: String) async -> Bool {
        let name = Sanitize.displayName(raw)
        guard !name.isEmpty else {
            errorMessage = "Add a name so friends know it's you."
            return false
        }
        guard Sanitize.isAllowedName(name) else {
            errorMessage = "Please choose a different name."
            return false
        }

        return await perform {
            let recordName = try await self.myRecordName()
            let code = self.profile?.inviteCode ?? Sanitize.newInviteCode()
            let record = CKRecord(recordType: "Profile", recordID: CKRecord.ID(recordName: recordName))
            record["displayName"] = name as CKRecordValue
            record["inviteCode"] = code as CKRecordValue
            record["isSharing"] = (self.isSharing ? 1 : 0) as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            try await self.upsert(record)

            let profile = MyProfile(recordName: recordName, displayName: name, inviteCode: code)
            self.profile = profile
            self.persistProfile()
            self.lastPublished = nil
        }
    }

    func setSharing(_ on: Bool) async {
        isSharing = on
        defaults.set(on, forKey: Key.sharing)
        lastPublished = nil
        guard let profile else { return }
        _ = await perform {
            let record = CKRecord(recordType: "Profile", recordID: CKRecord.ID(recordName: profile.recordName))
            record["isSharing"] = (on ? 1 : 0) as CKRecordValue
            if !on { self.zeroProgress(record) }
            record["updatedAt"] = Date() as CKRecordValue
            try await self.upsert(record)
        }
    }

    /// Publishes today's progress if it changed. Cheap to call often: it no-ops when there's
    /// no profile, sharing is off, or nothing moved since the last publish.
    func publish(_ snapshot: ProgressSnapshot) async {
        guard let profile, isSharing, snapshot != lastPublished else { return }
        lastPublished = snapshot
        let record = CKRecord(recordType: "Profile", recordID: CKRecord.ID(recordName: profile.recordName))
        record["tier"] = snapshot.tier as CKRecordValue
        record["day"] = snapshot.day as CKRecordValue
        record["totalDays"] = snapshot.totalDays as CKRecordValue
        record["streak"] = snapshot.streak as CKRecordValue
        record["todayFraction"] = snapshot.todayFraction as CKRecordValue
        record["isSharing"] = 1 as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        do {
            try await upsert(record)
        } catch {
            lastPublished = nil   // try again next time
        }
    }

    /// Deletes the profile and every connection this user created. Afterwards nothing about
    /// them remains in CloudKit. This is the "delete account" the App Store requires.
    func deleteProfile() async -> Bool {
        guard let profile else { return true }
        return await perform {
            let mine = try await self.connectionRecordNames(field: "from", equals: profile.recordName)
            let ids = [CKRecord.ID(recordName: profile.recordName)] + mine.map { CKRecord.ID(recordName: $0) }
            _ = try await self.db.modifyRecords(saving: [], deleting: ids)
            self.profile = nil
            self.friends = []
            self.incoming = []
            self.outgoingPending = []
            self.lastPublished = nil
            self.defaults.removeObject(forKey: Key.profile)
            self.defaults.removeObject(forKey: Key.friendsCache)
        }
    }

    // MARK: - Connections

    /// Sends a friend request to whoever owns `rawCode`.
    func add(code rawCode: String) async -> Bool {
        guard let profile else { return false }
        guard let code = Sanitize.normalizedCode(rawCode) else {
            errorMessage = "Invite codes are 8 letters and numbers, like ABCD-2345."
            return false
        }
        guard code != profile.inviteCode else {
            errorMessage = "That's your own code — share it with a friend instead."
            return false
        }

        return await perform {
            let query = CKQuery(recordType: "Profile", predicate: NSPredicate(format: "inviteCode == %@", code))
            let (results, _) = try await self.db.records(matching: query, desiredKeys: ["displayName"], resultsLimit: 1)
            guard let match = results.first, case .success(let record) = match.1 else {
                throw SocialError.codeNotFound
            }
            let theirID = record.recordID.recordName
            var blocked = self.blockedIDs
            blocked.remove(theirID)   // adding someone on purpose un-blocks them
            self.blockedIDs = blocked
            try await self.saveConnection(from: profile.recordName, to: theirID)
            try await self.reloadConnections()
        }
    }

    func accept(_ request: FriendSnapshot) async {
        guard let profile else { return }
        _ = await perform {
            try await self.saveConnection(from: profile.recordName, to: request.id)
            try await self.reloadConnections()
        }
    }

    /// Removes a friend, cancels a sent request, or declines an incoming one. Only deletes
    /// the record *we* created; their side is theirs.
    func remove(_ person: FriendSnapshot) async {
        guard let profile else { return }
        _ = await perform {
            let id = CKRecord.ID(recordName: Self.connectionName(from: profile.recordName, to: person.id))
            _ = try await self.db.modifyRecords(saving: [], deleting: [id])
            try await self.reloadConnections()
        }
    }

    /// Removes the person and hides any future requests from them on this device.
    func block(_ person: FriendSnapshot) async {
        var blocked = blockedIDs
        blocked.insert(person.id)
        blockedIDs = blocked
        await remove(person)
    }

    /// Pulls friends, requests and their progress. Throttled so tab switches don't hammer
    /// CloudKit; pass `force` for pull-to-refresh.
    func refresh(force: Bool = false) async {
        guard profile != nil else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 30 { return }
        _ = await perform { try await self.reloadConnections() }
    }

    // MARK: - Internals

    private static func connectionName(from: String, to: String) -> String {
        "c_\(from)_\(to)"
    }

    private func saveConnection(from: String, to: String) async throws {
        let record = CKRecord(recordType: "Connection", recordID: CKRecord.ID(recordName: Self.connectionName(from: from, to: to)))
        record["from"] = from as CKRecordValue
        record["to"] = to as CKRecordValue
        try await upsert(record)
    }

    private func connectionRecordNames(field: String, equals value: String) async throws -> [String] {
        let query = CKQuery(recordType: "Connection", predicate: NSPredicate(format: "%K == %@", field, value))
        var names: [String] = []
        var (results, cursor) = try await db.records(matching: query, desiredKeys: [], resultsLimit: CKQueryOperation.maximumResults)
        names += results.map(\.0.recordName)
        while let next = cursor {
            (results, cursor) = try await db.records(continuingMatchFrom: next, desiredKeys: [], resultsLimit: CKQueryOperation.maximumResults)
            names += results.map(\.0.recordName)
        }
        return names
    }

    private func reloadConnections() async throws {
        guard let me = profile?.recordName else { return }
        let prefixOut = "c_\(me)_"
        let suffixIn = "_\(me)"

        let outgoing = Set(try await connectionRecordNames(field: "from", equals: me)
            .compactMap { $0.hasPrefix(prefixOut) ? String($0.dropFirst(prefixOut.count)) : nil })
        let incomingIDs = Set(try await connectionRecordNames(field: "to", equals: me)
            .compactMap { name -> String? in
                guard name.hasPrefix("c_"), name.hasSuffix(suffixIn) else { return nil }
                return String(name.dropFirst(2).dropLast(suffixIn.count))
            })

        let blocked = blockedIDs
        let mutual = outgoing.intersection(incomingIDs).subtracting(blocked)
        let sent = outgoing.subtracting(incomingIDs)
        let requests = incomingIDs.subtracting(outgoing).subtracting(blocked)

        let all = mutual.union(sent).union(requests)
        let profiles = try await fetchProfiles(Array(all))

        friends = mutual.compactMap { profiles[$0] }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        outgoingPending = sent.compactMap { profiles[$0] }
        incoming = requests.compactMap { profiles[$0] }
        lastRefresh = Date()

        if let data = try? JSONEncoder().encode(friends) {
            defaults.set(data, forKey: Key.friendsCache)
        }
    }

    private func fetchProfiles(_ names: [String]) async throws -> [String: FriendSnapshot] {
        guard !names.isEmpty else { return [:] }
        var out: [String: FriendSnapshot] = [:]
        // CloudKit caps a single fetch at 400 records.
        for chunk in stride(from: 0, to: names.count, by: 200).map({ Array(names[$0..<min($0 + 200, names.count)]) }) {
            let results = try await db.records(for: chunk.map { CKRecord.ID(recordName: $0) })
            for (id, result) in results {
                guard case .success(let record) = result else { continue }
                out[id.recordName] = Self.snapshot(from: record)
            }
        }
        return out
    }

    /// Decodes a Profile written by someone else's device. Every field is clamped.
    private static func snapshot(from record: CKRecord) -> FriendSnapshot {
        let total = Sanitize.int(record["totalDays"], in: 1...365)
        let sharing = Sanitize.int(record["isSharing"], in: 0...1) == 1
        let rawName = Sanitize.displayName(record["displayName"] as? String ?? "")
        let name = rawName.isEmpty || !Sanitize.isAllowedName(rawName) ? "75 friend" : rawName
        let tierRaw = record["tier"] as? String
        return FriendSnapshot(
            id: record.recordID.recordName,
            displayName: name,
            isSharing: sharing,
            tier: ChallengeMode(rawValue: tierRaw ?? "")?.rawValue,
            day: sharing ? Sanitize.int(record["day"], in: 0...total) : 0,
            totalDays: total,
            streak: sharing ? Sanitize.int(record["streak"], in: 0...total) : 0,
            todayFraction: sharing ? Sanitize.fraction(record["todayFraction"]) : 0,
            updatedAt: record["updatedAt"] as? Date
        )
    }

    private func zeroProgress(_ record: CKRecord) {
        record["tier"] = "" as CKRecordValue
        record["day"] = 0 as CKRecordValue
        record["streak"] = 0 as CKRecordValue
        record["todayFraction"] = 0.0 as CKRecordValue
    }

    /// Saves only the fields set on `record`, creating it if needed. `.changedKeys` writes
    /// without fetching first, so a snapshot publish is a single round trip.
    private func upsert(_ record: CKRecord) async throws {
        let (saveResults, _) = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys, atomically: false)
        for (_, result) in saveResults {
            if case .failure(let error) = result { throw error }
        }
    }

    private func persistProfile() {
        if let profile, let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Key.profile)
        }
    }

    /// Runs a CloudKit operation with a busy flag and human-readable errors.
    private func perform(_ work: @escaping () async throws -> Void) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func report(_ error: Error) {
        if let social = error as? SocialError {
            errorMessage = social.message
            return
        }
        guard let ck = error as? CKError else {
            errorMessage = "Something went wrong. Try again in a moment."
            return
        }
        switch ck.code {
        case .notAuthenticated:
            accountState = .noAccount
            errorMessage = "Sign in to iCloud in Settings to use Friends."
        case .networkUnavailable, .networkFailure, .serviceUnavailable:
            errorMessage = "You're offline. Friends will update when you're back online."
        case .requestRateLimited, .zoneBusy:
            errorMessage = "iCloud is busy. Try again in a minute."
        case .quotaExceeded:
            errorMessage = "iCloud storage is full."
        case .permissionFailure:
            errorMessage = "iCloud didn't allow that change."
        case .unknownItem:
            errorMessage = "That person isn't on 75 anymore."
        default:
            errorMessage = "iCloud couldn't complete that. Try again in a moment."
        }
    }
}

enum SocialError: Error {
    case codeNotFound

    var message: String {
        switch self {
        case .codeNotFound: return "No one has that invite code. Check it with your friend."
        }
    }
}
