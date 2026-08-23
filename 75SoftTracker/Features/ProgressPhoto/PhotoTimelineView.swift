import SwiftUI

struct PhotoTimelineView: View {
    let challenge: Challenge

    @State private var selectedPose: PhotoPose = .front
    @State private var viewerStartIndex: Int?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    private var photosByDay: [(day: Int, photo: ProgressPhoto)] {
        challenge.days
            .sorted { $0.dayNumber < $1.dayNumber }
            .compactMap { day in
                day.photos.first { $0.pose == selectedPose }.map { (day.dayNumber, $0) }
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Pose", selection: $selectedPose) {
                    ForEach(PhotoPose.allCases) { pose in
                        Text(pose.rawValue).tag(pose)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if photosByDay.isEmpty {
                    ContentUnavailableView(
                        "No \(selectedPose.rawValue.lowercased()) photos yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Take your first progress photo from the Today tab.")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(photosByDay.enumerated()), id: \.element.photo.id) { index, entry in
                            thumbnail(for: entry, index: index)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .navigationTitle("Progress Photos")
            .fullScreenCover(item: $viewerStartIndex.asIdentifiableIndex) { wrapped in
                PhotoViewerView(entries: photosByDay, startIndex: wrapped.index)
            }
        }
    }

    private func thumbnail(for entry: (day: Int, photo: ProgressPhoto), index: Int) -> some View {
        Button {
            viewerStartIndex = index
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let image = PhotoStorageService.loadImage(fileName: entry.photo.fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.secondary.opacity(0.2))
                }
                Text("Day \(entry.day)")
                    .font(.caption2.weight(.semibold))
                    .padding(4)
                    .background(.black.opacity(0.5))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
            .aspectRatio(3/4, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct PhotoViewerView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [(day: Int, photo: ProgressPhoto)]
    @State var startIndex: Int

    init(entries: [(day: Int, photo: ProgressPhoto)], startIndex: Int) {
        self.entries = entries
        self._startIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $startIndex) {
                ForEach(Array(entries.enumerated()), id: \.element.photo.id) { index, entry in
                    VStack {
                        if let image = PhotoStorageService.loadImage(fileName: entry.photo.fileName) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        }
                        Text("Day \(entry.day) · \(entry.photo.date.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.white)
                            .font(.subheadline)
                            .padding(.bottom, 40)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

private struct IdentifiableIndex: Identifiable {
    let id: Int
    var index: Int { id }
}

private extension Binding where Value == Int? {
    var asIdentifiableIndex: Binding<IdentifiableIndex?> {
        Binding<IdentifiableIndex?>(
            get: { wrappedValue.map(IdentifiableIndex.init) },
            set: { wrappedValue = $0?.index }
        )
    }
}
