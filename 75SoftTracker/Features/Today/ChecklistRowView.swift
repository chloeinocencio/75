import SwiftUI

struct ChecklistRowView: View {
    let task: TaskKind
    let isComplete: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: task.systemImage)
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundStyle(isComplete ? .white : .primary)
                    .padding(8)
                    .background(isComplete ? Color.accentColor : Color.secondary.opacity(0.12), in: Circle())

                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(isComplete)
                    .foregroundStyle(isComplete ? .secondary : .primary)

                Spacer()

                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isComplete ? Color.accentColor : .secondary.opacity(0.4))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
