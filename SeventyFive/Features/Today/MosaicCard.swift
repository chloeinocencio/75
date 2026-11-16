import SwiftUI

/// All 75 days at a glance — 15 across, 5 down — so the whole challenge is one picture.
///
/// Filled chartreuse is a finished day; today fills from the bottom as the checklist
/// does; yesterday (still loggable) is outlined; a missed day is a small dot; the future
/// is faint. Tapping yesterday opens it for logging.
struct MosaicCard: View {
    let challenge: Challenge
    var onSelectDay: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 15)

    var body: some View {
        let total = challenge.totalDays
        let completed = challenge.completedDayCount
        let missed = challenge.missedDayCount(through: challenge.calendarDayNumber - 1)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Your \(total)")
                Spacer()
                Text("\(completed) done\(missed > 0 ? " · \(missed) missed" : "")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dim)
            }

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(1...max(total, 1), id: \.self) { day in
                    cell(day: day, status: challenge.status(ofDay: day))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Challenge overview")
            .accessibilityValue("\(completed) of \(total) days complete, \(missed) missed, day \(challenge.currentDayNumber) today")
        }
        .card()
    }

    @ViewBuilder
    private func cell(day: Int, status: DayStatus) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            switch status {
            case .complete:
                shape.fill(Theme.lime)
            case .today(let fraction):
                shape.fill(Theme.surface2)
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Theme.lime
                                .frame(height: geo.size.height * fraction)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .clipShape(shape)
                    }
                    .overlay(shape.strokeBorder(Theme.ink, lineWidth: 1.5))
            case .open(let fraction):
                Button { onSelectDay(day) } label: {
                    shape.fill(fraction > 0 ? Theme.limeSoft : .clear)
                        .overlay(shape.strokeBorder(Theme.accentText.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                }
                .buttonStyle(.plain)
            case .missed:
                shape.fill(Theme.surface2.opacity(0.5))
                    .overlay(Circle().fill(Theme.dim.opacity(0.55)).frame(width: 4, height: 4))
            case .future:
                shape.fill(Theme.surface2.opacity(0.55))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
