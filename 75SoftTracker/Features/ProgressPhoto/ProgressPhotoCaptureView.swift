import SwiftUI
import SwiftData

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
                    if let ghostImage {
                        alignmentControls(hasGhost: ghostImage != nil)
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

    private func alignmentControls(hasGhost: Bool) -> some View {
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
            Spacer()
        }
        .padding(.top, 16)
    }

    private var cameraPermissionPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text("Camera access is needed to take your progress photo.")
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func saveCapturedPhoto(_ image: UIImage) {
        isSaving = true
        Task {
            do {
                let fileName = try PhotoStorageService.save(image, dayNumber: dailyEntry.dayNumber, pose: pose)
                let photo = ProgressPhoto(dayNumber: dailyEntry.dayNumber, date: .now, pose: pose, fileName: fileName)
                photo.dailyEntry = dailyEntry
                dailyEntry.photos.append(photo)
                modelContext.insert(photo)
                dailyEntry.markComplete(.progressPhoto)
                try modelContext.save()
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run { isSaving = false }
            }
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
