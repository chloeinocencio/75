import SwiftUI
import SwiftData
import PhotosUI

struct ProgressPhotoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var camera = CameraController()

    let challenge: Challenge
    let dailyEntry: DailyEntry

    @State private var pose: PhotoPose = .front
    @State private var showGhostOverlay = true
    @State private var ghostOpacity: Double = 0.35
    @State private var alignMode = false
    /// Held as an Identifiable wrapper in state — not derived through a computed Binding —
    /// so the review screen keeps one identity. Re-wrapping on every render gave it a new id
    /// each time, which made SwiftUI dismiss and re-present it (the flicker).
    @State private var review: CapturedImage?
    @State private var ghostImage: UIImage?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showLibraryPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var shutterFlash = false

    private var showsCamera: Bool { camera.isAuthorized && camera.hasCamera }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showsCamera {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()

                if showGhostOverlay, let ghostImage {
                    Image(uiImage: ghostImage)
                        .resizable()
                        .scaledToFill()
                        .opacity(alignMode ? 1.0 : ghostOpacity)
                        .blendMode(alignMode ? .difference : .normal)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                Color.white
                    .opacity(shutterFlash ? 0.7 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else {
                cameraUnavailablePrompt
            }

            VStack {
                topBar
                Spacer()
                if showsCamera {
                    if ghostImage != nil {
                        alignmentControls
                    }
                    poseSelector
                    bottomBar
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .statusBarHidden()
        .onAppear { camera.requestAccessAndConfigure() }
        .onDisappear { camera.stop() }
        // Decoded once per pose at overlay size, not from disk on every slider movement.
        .task(id: pose) {
            if let photo = challenge.lastPhoto(before: dailyEntry.dayNumber, pose: pose) {
                ghostImage = await ImageCache.shared.load(fileName: photo.fileName, maxPixelSize: PhotoSize.overlay.pixels)
            } else {
                ghostImage = nil
            }
        }
        .fullScreenCover(item: $review) { captured in
            PhotoReviewView(
                image: captured.image,
                pose: pose,
                isSaving: isSaving,
                onRetake: { review = nil },
                onUse: { saveCapturedPhoto(captured.image) }
            )
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data, let image = UIImage(data: data) {
                        review = CapturedImage(image: image)
                    } else {
                        saveError = "That image couldn't be read."
                    }
                    pickedItem = nil
                }
            }
        }
        .alert("Couldn't save photo", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("Close camera")

            Spacer()

            Text("Day \(dailyEntry.dayNumber) of \(challenge.totalDays)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.4), in: Capsule())

            Spacer()

            Button {
                camera.flipCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("Switch camera")
            .opacity(showsCamera ? 1 : 0)
            .disabled(!showsCamera)
        }
    }

    private var alignmentControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Toggle(isOn: $showGhostOverlay.animation()) {
                    Label("Guide", systemImage: "person.crop.rectangle.stack")
                        .font(.footnote.weight(.medium))
                }
                .toggleStyle(.button)
                .tint(.white.opacity(0.25))

                if showGhostOverlay {
                    Toggle(isOn: $alignMode.animation()) {
                        Label("Align", systemImage: "wand.and.rays")
                            .font(.footnote.weight(.medium))
                    }
                    .toggleStyle(.button)
                    .tint(.white.opacity(0.25))
                }
            }
            .foregroundStyle(.white)

            if showGhostOverlay && !alignMode {
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                    Slider(value: $ghostOpacity, in: 0.1...0.7)
                        .tint(Theme.lime)
                        .accessibilityLabel("Guide opacity")
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8)
            } else if alignMode {
                Text("Match your pose until the outline disappears")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(10)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var poseSelector: some View {
        HStack(spacing: 6) {
            ForEach(PhotoPose.allCases) { option in
                Button {
                    withAnimation(.snappy) { pose = option }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(pose == option ? Theme.limeInk : .white)
                        .background(pose == option ? Theme.lime : .black.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(pose == option ? .isSelected : [])
            }
        }
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                showLibraryPicker = true
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("Choose a photo")

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
                withAnimation(.easeIn(duration: 0.25).delay(0.08)) { shutterFlash = false }
                camera.capturePhoto { image in
                    if let image {
                        review = CapturedImage(image: image)
                    } else {
                        saveError = "The camera wasn't ready. Try again."
                    }
                }
            } label: {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                    .overlay(Circle().fill(Theme.lime).frame(width: 64, height: 64))
            }
            .accessibilityLabel("Take photo")
            .sensoryFeedback(.impact(weight: .medium), trigger: shutterFlash) { _, new in new }

            Spacer()

            // Balances the library button so the shutter stays centred.
            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var cameraUnavailablePrompt: some View {
        switch camera.permission {
        case .undetermined:
            // iOS is presenting its own alert over this view. Anything written here would
            // read as if the request had already been refused, so stay quiet.
            Color.clear

        case .denied:
            permissionMessage(
                icon: "camera.fill",
                text: "75 needs camera access to take your progress photo.",
                action: ("Open Settings", {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })
            )

        case .restricted:
            // Screen Time or an MDM profile blocks the camera; Settings won't help the user.
            permissionMessage(
                icon: "lock.fill",
                text: "Camera access is restricted on this device, so a photo can't be taken here.",
                action: nil
            )

        case .authorized:
            // Authorised but no camera hardware — the Simulator, for one.
            permissionMessage(
                icon: "camera.badge.ellipsis",
                text: "No camera is available here. You can add a photo from your library.",
                action: nil
            )
        }
    }

    private func permissionMessage(icon: String, text: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text(text)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(LimeButtonStyle(compact: true))
            }
            Button("Choose a photo instead") { showLibraryPicker = true }
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }

    /// Saving is synchronous (a resize, a JPEG encode and a SwiftData insert), and SwiftData
    /// models must only be touched on the main actor — so this deliberately does NOT wrap
    /// the work in a Task.
    @MainActor
    private func saveCapturedPhoto(_ image: UIImage) {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let fileName = try PhotoStorageService.save(image, dayNumber: dailyEntry.dayNumber, pose: pose)
            let photo = ProgressPhoto(dayNumber: dailyEntry.dayNumber, date: .now, pose: pose, fileName: fileName)
            modelContext.insert(photo)
            // Setting the inverse is enough; SwiftData maintains dailyEntry.photos.
            photo.dailyEntry = dailyEntry
            // Only 75 Hard carries a daily photo task to check off; under Soft and
            // Medium the photo is a milestone, not a checklist item.
            if challenge.mode.photoCadence == .daily {
                dailyEntry.markComplete(.progressPhoto)
            }
            try modelContext.save()
            review = nil
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct CapturedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct PhotoReviewView: View {
    let image: UIImage
    let pose: PhotoPose
    let isSaving: Bool
    let onRetake: () -> Void
    let onUse: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()
                .accessibilityLabel("\(pose.rawValue) progress photo preview")

            VStack {
                Spacer()
                HStack(spacing: 14) {
                    Button("Retake", action: onRetake)
                        .buttonStyle(QuietButtonStyle(compact: false))

                    Button {
                        onUse()
                    } label: {
                        if isSaving {
                            ProgressView().tint(Theme.limeInk)
                        } else {
                            Text("Use \(pose.rawValue) Photo")
                        }
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(isSaving)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}
