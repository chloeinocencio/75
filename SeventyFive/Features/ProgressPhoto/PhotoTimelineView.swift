import SwiftUI
import SwiftData

struct PhotoTimelineView: View {
    let challenge: Challenge

    @State private var selectedPose: PhotoPose = .front
    @State private var viewer: ViewerStart?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        let photos = challenge.photos(pose: selectedPose)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Pose", selection: $selectedPose) {
                        ForEach(PhotoPose.allCases) { pose in
                            Text(pose.rawValue).tag(pose)
                        }
                    }
                    .pickerStyle(.segmented)

                    if photos.isEmpty {
                        ContentUnavailableView(
                            "No \(selectedPose.rawValue.lowercased()) photos yet",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("Take your first progress photo from the Today tab. Photos stay on this iPhone.")
                        )
                        .padding(.top, 50)
                    } else {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                                thumbnail(photo, index: index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .themedBackground(glow: 0.15)
            .navigationTitle("Progress Photos")
            .fullScreenCover(item: $viewer) { start in
                PhotoViewerView(challenge: challenge, pose: selectedPose, startID: start.id)
            }
        }
    }

    private func thumbnail(_ photo: ProgressPhoto, index: Int) -> some View {
        Button {
            viewer = ViewerStart(id: photo.id)
        } label: {
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { StoredPhotoView(fileName: photo.fileName, size: .thumbnail) }
                .overlay(alignment: .bottomLeading) {
                    Text(photo.label(currentAttempt: challenge.attemptNumber))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(selectedPose.rawValue) photo, \(photo.label(currentAttempt: challenge.attemptNumber))")
    }
}

private struct ViewerStart: Identifiable {
    let id: UUID
}

/// Full-screen pager with delete. Reads the photo list live, so deleting updates in place.
private struct PhotoViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let challenge: Challenge
    let pose: PhotoPose
    @State private var currentID: UUID?
    @State private var confirmDelete = false

    init(challenge: Challenge, pose: PhotoPose, startID: UUID) {
        self.challenge = challenge
        self.pose = pose
        self._currentID = State(initialValue: startID)
    }

    var body: some View {
        let photos = challenge.photos(pose: pose)
        let current = photos.first { $0.id == currentID }

        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(photos) { photo in
                    StoredPhotoView(fileName: photo.fileName, size: .full, contentMode: .fit)
                        .tag(Optional(photo.id))
                        .accessibilityLabel("\(pose.rawValue) photo, \(photo.label(currentAttempt: challenge.attemptNumber))")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    circleButton("trash", label: "Delete photo") { confirmDelete = true }
                        .disabled(current == nil)
                    Spacer()
                    circleButton("xmark", label: "Close") { dismiss() }
                }
                .padding()
                Spacer()
                if let current {
                    Text("\(current.label(currentAttempt: challenge.attemptNumber)) · \(current.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 30)
                }
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) {
                if let current { delete(current, from: photos) }
            }
        } message: {
            Text("It's removed from this iPhone. This can't be undone.")
        }
    }

    private func circleButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func delete(_ photo: ProgressPhoto, from photos: [ProgressPhoto]) {
        let index = photos.firstIndex { $0.id == photo.id } ?? 0
        let remaining = photos.filter { $0.id != photo.id }
        let entry = photo.dailyEntry
        // Checked before deleting: the relationship can still list the photo until save.
        let wasOnlyPhoto = entry?.photos.allSatisfy { $0.id == photo.id } ?? false

        PhotoStorageService.delete(fileName: photo.fileName)
        modelContext.delete(photo)

        // Under 75 Hard, removing the day's only photo un-ticks the photo task.
        if let entry, wasOnlyPhoto, challenge.mode.photoCadence == .daily {
            entry.markIncomplete(.progressPhoto)
        }
        try? modelContext.save()

        if remaining.isEmpty {
            dismiss()
        } else {
            currentID = remaining[min(index, remaining.count - 1)].id
        }
    }
}
