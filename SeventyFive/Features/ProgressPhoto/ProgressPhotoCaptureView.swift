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
    @State private var capturedImage: UIImage?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showLibraryPicker = false
    @State private var pickedItem: PhotosPickerItem?

    private var ghostImage: UIImage? {
        guard let photo = challenge.lastPhoto(before: dailyEntry.dayNumber, pose: pose) else { return nil }
        return PhotoStorageService.loadImage(fileName: photo.fileName)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isAuthorized {
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
                }
            } else {
                cameraPermissionPrompt
            }

            VStack {
                topBar
                Spacer()
                if camera.isAuthorized {
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
        .fullScreenCover(item: $capturedImage.asIdentifiableImage) { wrapped in
            PhotoReviewView(
                image: wrapped.image,
                isSaving: isSaving,
                onRetake: { capturedImage = nil },
                onUse: { saveCapturedPhoto(wrapped.image) }
            )
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data, let image = UIImage(data: data) {
                        capturedImage = image
                    } else {
                        saveError = "That image couldn't be read."
                    }
                    pickedItem = nil
                }
            }
        }
        .alert("Couldn't save photo", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
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
        Picker("Pose", selection: $pose) {
            ForEach(PhotoPose.allCases) { pose in
                Text(pose.rawValue).tag(pose)
            }
        }
        .pickerStyle(.segmented)
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
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("Choose a photo")

            Spacer()

            Button {
                camera.capturePhoto { image in
                    guard let image else { return }
                    capturedImage = image
                }
            } label: {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                    .overlay(Circle().fill(.white).frame(width: 64, height: 64).padding(6))
            }
            .accessibilityLabel("Take photo")

            Spacer()

            // Balances the library button so the shutter stays centred.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var cameraPermissionPrompt: some View {
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
            EmptyView()
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
                    .buttonStyle(.borderedProminent)
            }
            Button("Choose a photo instead") { showLibraryPicker = true }
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }

    /// Saving is fully synchronous (a JPEG encode plus a SwiftData insert), and SwiftData
    /// models must only be touched on the main actor — so this deliberately does NOT wrap
    /// the work in a Task.
    @MainActor
    private func saveCapturedPhoto(_ image: UIImage) {
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
            capturedImage = nil
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct PhotoReviewView: View {
    let image: UIImage
    let isSaving: Bool
    let onRetake: () -> Void
    let onUse: (UIImage) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()

            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Button("Retake", action: onRetake)
                        .buttonStyle(.bordered)
                        .tint(.white)

                    Button {
                        onUse(image)
                    } label: {
                        if isSaving {
                            ProgressView().tint(.black)
                        } else {
                            Text("Use Photo")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
                .padding(.bottom, 40)
            }
        }
    }
}

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private extension Binding where Value == UIImage? {
    var asIdentifiableImage: Binding<IdentifiableImage?> {
        Binding<IdentifiableImage?>(
            get: { wrappedValue.map(IdentifiableImage.init) },
            set: { wrappedValue = $0?.image }
        )
    }
}
