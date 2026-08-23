import SwiftUI
import SwiftData

struct FriendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Friend.addedDate) private var friends: [Friend]
    let challenge: Challenge

    @State private var showAddFriend = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { challenge.shareProgressWithFriends },
                        set: { newValue in
                            challenge.shareProgressWithFriends = newValue
                            try? modelContext.save()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share My Progress")
                            Text("Friends see your streak and completion %. Progress photos are never shared automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Friends") {
                    if friends.isEmpty {
                        Text("No friends added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(friends) { friend in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(friend.displayName)
                                    Text(friend.phoneNumberE164)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if friend.status == FriendStatus.pending.rawValue {
                                    Text("Pending").font(.caption).foregroundStyle(.orange)
                                } else {
                                    Text("Connected").font(.caption).foregroundStyle(.green)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet { modelContext.delete(friends[index]) }
                            try? modelContext.save()
                        }
                    }
                }
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
            }
        }
    }
}

private struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var phoneNumber = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Friend's Info") {
                    TextField("Name", text: $name)
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                }
                Text("An invite is sent by text. Once they accept on their end, their progress ring shows up here too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Add Friend")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") {
                        let friend = Friend(phoneNumberE164: phoneNumber, displayName: name.isEmpty ? phoneNumber : name)
                        modelContext.insert(friend)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
