import SwiftUI

struct BeforeAfterCompareView: View {
    let challenge: Challenge

    @State private var pose: PhotoPose = .front
    /// Selections are photo IDs, not day numbers: after a 75 Hard restart "Day 5" exists in
    /// more than one attempt, and a day number alone picked whichever came first.
    @State private var beforeID: UUID?
    @State private var afterID: UUID?
    @State private var dividerFraction: CGFloat = 0.5
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var shareImage: ShareableImage?
    @State private var isRendering = false

    var body: some View {
        let photos = challenge.photos(pose: pose)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Pose", selection: $pose) {
                        ForEach(PhotoPose.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if photos.count < 2 {
                        ContentUnavailableView(
                            "Need two \(pose.rawValue.lowercased()) photos",
                            systemImage: "square.split.2x1",
                            description: Text("Take a \(pose.rawValue.lowercased()) photo now and another later to see your progress side by side.")
                        )
                        .padding(.top, 40)
                    } else {
                        HStack(spacing: 10) {
                            picker("Before", photos: photos, selection: $beforeID)
                            Image(systemName: "arrow.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.dim)
                            picker("After", photos: photos, selection: $afterID)
                        }

                        if let beforeImage, let afterImage {
                            compareSlider(before: beforeImage, after: afterImage, photos: photos)

                            Button {
                                renderShare(photos: photos)
                            } label: {
                                if isRendering {
                                    ProgressView().tint(Theme.limeInk)
                                } else {
                                    Label("Share this comparison", systemImage: "square.and.arrow.up")
                                }
                            }
                            .buttonStyle(LimeButtonStyle())
                            .disabled(isRendering)

                            Text("Shared images include only these two photos. Nothing is uploaded unless you choose where to send it.")
                                .font(.caption)
                                .foregroundStyle(Theme.dim)
                                .multilineTextAlignment(.center)
                        } else {
                            ProgressView().padding(.top, 60)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .themedBackground(glow: 0.15)
            .navigationTitle("Before & After")
            .onAppear { resetSelection(photos) }
            .onChange(of: pose) { _, _ in
                beforeID = nil
                afterID = nil
                resetSelection(challenge.photos(pose: pose))
            }
            .onChange(of: photos.map(\.id)) { _, _ in resetSelection(photos) }
            // Images are decoded once per selection change — never during a divider drag.
            .task(id: beforeID) { beforeImage = await load(beforeID, in: challenge.photos(pose: pose)) }
            .task(id: afterID) { afterImage = await load(afterID, in: challenge.photos(pose: pose)) }
            .sheet(item: $shareImage) { wrapped in
                ActivityShareSheet(items: [wrapped.image])
            }
        }
    }

    /// Defaults to first vs latest, and repairs a selection whose photo was deleted.
    private func resetSelection(_ photos: [ProgressPhoto]) {
        let ids = Set(photos.map(\.id))
        if beforeID == nil || !ids.contains(beforeID!) { beforeID = photos.first?.id }
        if afterID == nil || !ids.contains(afterID!) { afterID = photos.last?.id }
    }

    private func load(_ id: UUID?, in photos: [ProgressPhoto]) async -> UIImage? {
        guard let id, let photo = photos.first(where: { $0.id == id }) else { return nil }
        return await ImageCache.shared.load(fileName: photo.fileName, maxPixelSize: PhotoSize.full.pixels)
    }

    private func label(for id: UUID?, in photos: [ProgressPhoto]) -> String {
        photos.first { $0.id == id }?.label(currentAttempt: challenge.attemptNumber) ?? "Select"
    }

    private func picker(_ title: String, photos: [ProgressPhoto], selection: Binding<UUID?>) -> some View {
        Menu {
            ForEach(photos) { photo in
                Button {
                    selection.wrappedValue = photo.id
                } label: {
                    if selection.wrappedValue == photo.id {
                        Label(photo.label(currentAttempt: challenge.attemptNumber), systemImage: "checkmark")
                    } else {
                        Text(photo.label(currentAttempt: challenge.attemptNumber))
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                Text(label(for: selection.wrappedValue, in: photos))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .accessibilityLabel("\(title) photo: \(label(for: selection.wrappedValue, in: photos))")
    }

    private func compareSlider(before: UIImage, after: UIImage, photos: [ProgressPhoto]) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Image(uiImage: after)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: geo.size.height)
                    .clipped()

                Image(uiImage: before)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: geo.size.height)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * dividerFraction)
                    }

                Rectangle()
                    .fill(.white)
                    .frame(width: 3)
                    .shadow(radius: 2)
                    .overlay(
                        Circle()
                            .fill(Theme.lime)
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "arrow.left.and.right").font(.caption.weight(.bold)).foregroundStyle(Theme.limeInk))
                            .shadow(radius: 3)
                    )
                    .offset(x: width * dividerFraction - 1.5)

                VStack {
                    HStack {
                        tag(label(for: beforeID, in: photos))
                        Spacer()
                        tag(label(for: afterID, in: photos))
                    }
                    Spacer()
                }
                .padding(10)
            }
            // The whole image is the drag target, not just the 3-pt divider line.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    dividerFraction = min(max(value.location.x / width, 0), 1)
                }
            )
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Before and after comparison")
        .accessibilityValue("Showing \(Int(dividerFraction * 100)) percent before")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: dividerFraction = min(dividerFraction + 0.1, 1)
            case .decrement: dividerFraction = max(dividerFraction - 0.1, 0)
            @unknown default: break
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.black.opacity(0.5), in: Capsule())
            .foregroundStyle(.white)
    }

    /// Renders a labelled side-by-side image at a sensible size, off the main thread.
    private func renderShare(photos: [ProgressPhoto]) {
        guard let before = photos.first(where: { $0.id == beforeID }),
              let after = photos.first(where: { $0.id == afterID }) else { return }
        let beforeName = before.fileName, afterName = after.fileName
        let beforeLabel = before.label(currentAttempt: challenge.attemptNumber)
        let afterLabel = after.label(currentAttempt: challenge.attemptNumber)
        isRendering = true
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                Self.composite(beforeName: beforeName, afterName: afterName, beforeLabel: beforeLabel, afterLabel: afterLabel)
            }.value
            isRendering = false
            if let image { shareImage = ShareableImage(image: image) }
        }
    }

    private static func composite(beforeName: String, afterName: String, beforeLabel: String, afterLabel: String) -> UIImage? {
        guard let before = ImageCache.shared.image(fileName: beforeName, maxPixelSize: 1600),
              let after = ImageCache.shared.image(fileName: afterName, maxPixelSize: 1600) else { return nil }
        let panel = CGSize(width: 900, height: 1200)
        let gap: CGFloat = 12
        let size = CGSize(width: panel.width * 2 + gap, height: panel.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(hex: 0xF5F0EA).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for (index, (image, text)) in [(before, beforeLabel), (after, afterLabel)].enumerated() {
                let rect = CGRect(x: CGFloat(index) * (panel.width + gap), y: 0, width: panel.width, height: panel.height)
                ctx.cgContext.saveGState()
                UIBezierPath(rect: rect).addClip()
                image.draw(in: aspectFill(image.size, in: rect))
                ctx.cgContext.restoreGState()

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .heavy),
                    .foregroundColor: UIColor(hex: 0x0A0A0C),
                ]
                let label = NSAttributedString(string: text, attributes: attrs)
                let labelSize = label.size()
                let pill = CGRect(x: rect.minX + 28, y: rect.maxY - labelSize.height - 56, width: labelSize.width + 36, height: labelSize.height + 20)
                UIColor(hex: 0xDAE644).setFill()
                UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
                label.draw(at: CGPoint(x: pill.minX + 18, y: pill.minY + 10))
            }
        }
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

private struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
