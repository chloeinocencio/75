import SwiftUI

/// A yes/no task. The glyph fills chartreuse and the tick bounces in when it's done.
struct ChecklistRowView: View {
    let task: TaskKind
    let isComplete: Bool
    var subtitle: String? = nil
    var isExcused = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: task.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isComplete ? Theme.limeInk : Theme.ink)
                    .background(isComplete ? Theme.lime : Theme.surface2, in: Circle())
                    .symbolEffect(.bounce, value: isComplete)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isComplete ? Theme.dim : Theme.ink)
                        .strikethrough(isComplete && !isExcused, color: Theme.dim)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isComplete ? Theme.accentText : Theme.dim.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isComplete)
        .accessibilityLabel(task.title)
        .accessibilityValue(isExcused ? "Rest day" : (isComplete ? "Done" : "Not done"))
        .accessibilityAddTraits(isComplete ? .isSelected : [])
    }
}

/// A numeric task — water, pages, minutes — with steppers, a progress bar and quick actions.
struct CounterRowView: View {
    let task: TaskKind
    let label: String
    let current: Double
    let goal: Double
    let step: Double
    let format: (Double) -> String
    /// Extra one-tap amounts, e.g. "+500 ml". Empty for tasks where a single "Done" is better.
    var quickAdds: [(label: String, amount: Double)] = []
    let set: (Double) -> Void

    private var isComplete: Bool { current >= goal }
    private var fraction: Double { min(current / max(goal, 0.0001), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: task.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isComplete ? Theme.limeInk : Theme.ink)
                    .background(isComplete ? Theme.lime : Theme.surface2, in: Circle())
                    .symbolEffect(.bounce, value: isComplete)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text("\(format(current)) of \(format(goal))")
                        .font(.caption.weight(isComplete ? .bold : .regular))
                        .foregroundStyle(isComplete ? Theme.accentText : Theme.dim)
                        .contentTransition(.numericText(value: current))
                        .animation(.snappy, value: current)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                stepButton("minus", label: "Less \(label.lowercased())") { set(max(0, current - step)) }
                    .disabled(current <= 0)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        Capsule()
                            .fill(Theme.lime)
                            .frame(width: max(geo.size.width * fraction, fraction > 0 ? 8 : 0))
                            .animation(.snappy(duration: 0.3), value: fraction)
                    }
                }
                .frame(height: 8)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityValue("\(format(current)) of \(format(goal))")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: set(current + step)
                    case .decrement: set(max(0, current - step))
                    @unknown default: break
                    }
                }

                stepButton("plus", label: "More \(label.lowercased())") { set(current + step) }
            }

            HStack(spacing: 8) {
                ForEach(quickAdds, id: \.label) { quick in
                    chip(quick.label) { set(current + quick.amount) }
                }
                if !isComplete {
                    chip(quickAdds.isEmpty ? "Done" : "Fill to goal", filled: true) { set(goal) }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .sensoryFeedback(.success, trigger: isComplete) { old, new in !old && new }
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.ink)
                .background(Theme.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func chip(_ text: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .foregroundStyle(filled ? Theme.limeInk : Theme.ink)
                .background(filled ? Theme.limeSoft : Theme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
