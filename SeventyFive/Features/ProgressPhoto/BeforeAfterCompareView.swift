import SwiftUI

struct BeforeAfterCompareView: View {
    let challenge: Challenge

    @State private var pose: PhotoPose = .front
    @State private var beforeDay: Int?
    @State private var afterDay: Int?
    @State private var dividerFraction: CGFloat = 0.5
    @State private var shareImage: ShareableImage?

    /// Every day that has a photo of the selected pose, across all attempts, oldest first.
    /// Deduplicated by day number — after a 75 Hard restart the same day number can recur,
    /// and `ForEach(id: \.self)` requires unique ids.
    private var daysWithPhoto: [Int] {
        var seen = Set<Int>()
        return challenge.days
            .filter { day in day.photos.contains { $0.pose == pose } }
            .sorted { ($0.attemptNumber, $0.dayNumber) < ($1.attemptNumber, $1.dayNumber) }
            .map(\.dayNumber)
            .filter { seen.insert($0).inserted }
    }

    /// Resolved from `days` directly rather than `challenge.entry(forDay:)`, which is scoped
    /// to the current attempt and would miss photos from an earlier 75 Hard run.
    private func image(forDay day: Int?) -> UIImage? {
        guard let day,
              let photo = challenge.days
                  .filter({ $0.dayNumber == day })
                  .flatMap(\.photos)
                  .first(where: { $0.pose == pose })
        else { return nil }
        return PhotoStorageService.loadImage(fileName: photo.fileName)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Pose", selection: $pose) {
                    ForEach(PhotoPose.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    dayPicker("Before", selection: $beforeDay)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    dayPicker("After", selection: $afterDay)
                }

                if daysWithPhoto.count < 2 {
                    ContentUnavailableView(
                        "Need at least two \(pose.rawValue.lowercased()) photos",
                        systemImage: "square.split.2x1",
                        description: Text("Keep taking daily progress photos to unlock comparisons.")
                    )
                    .padding(.top, 40)
                } else if let before = image(forDay: beforeDay), let after = image(forDay: afterDay) {
                    compareSlider(before: before, after: after)
                    Button {
                        shareImage = ShareableImage(image: composite(before: before, after: after))
                    } label: {
                        Label("Share This Comparison", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ContentUnavailableView(
                        "Pick two days to compare",
                        systemImage: "photo.stack",
                        description: Text("Choose a before and after day above.")
                    )
                    .padding(.top, 40)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Before & After")
            .onAppear {
                if beforeDay == nil { beforeDay = daysWithPhoto.first }
                if afterDay == nil { afterDay = daysWithPhoto.last }
            }
            .sheet(item: $shareImage) { wrapped in
                ActivityShareSheet(items: [wrapped.image])
            }
        }
    }

    private func dayPicker(_ label: String, selection: Binding<Int?>) -> some View {
        Menu {
            ForEach(daysWithPhoto, id: \.self) { day in
                Button("Day \(day)") { selection.wrappedValue = day }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(selection.wrappedValue.map { "Day \($0)" } ?? "Select")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func compareSlider(before: UIImage, after: UIImage) -> some View {
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
                            .fill(.white)
                            .frame(width: 28, height: 28)
                            .overlay(Image(systemName: "arrow.left.and.right").font(.caption).foregroundStyle(.black))
                            .shadow(radius: 2)
                    )
                    .offset(x: width * dividerFraction - 1.5)
                    .gesture(
                        DragGesture().onChanged { value in
                            dividerFraction = min(max(value.location.x / width, 0), 1)
                        }
                    )

                VStack {
                    HStack {
                        dayLabel("Day \(beforeDay ?? 0)")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)

                VStack {
                    HStack {
                        Spacer()
                        dayLabel("Day \(afterDay ?? 0)")
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .aspectRatio(3/4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func dayLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.5))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    /// Renders a single flattened image (side-by-side) for sharing outside the divider UI.
    private func composite(before: UIImage, after: UIImage) -> UIImage {
        let size = CGSize(width: before.size.width + after.size.width, height: max(before.size.height, after.size.height))
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            before.draw(in: CGRect(x: 0, y: 0, width: before.size.width, height: before.size.height))
            after.draw(in: CGRect(x: before.size.width, y: 0, width: after.size.width, height: after.size.height))
        }
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
