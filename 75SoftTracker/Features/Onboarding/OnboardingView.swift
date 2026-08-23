import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedMode: ChallengeMode = .soft

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text("Choose Your Challenge")
                    .font(.title2.bold())
            }

            VStack(spacing: 14) {
                ForEach(ChallengeMode.allCases) { mode in
                    modeCard(mode)
                }
            }
            .padding(.horizontal)

            Spacer()

            Button {
                let challenge = Challenge(mode: selectedMode)
                modelContext.insert(challenge)
                try? modelContext.save()
            } label: {
                Text("Start \(selectedMode.rawValue)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    private func modeCard(_ mode: ChallengeMode) -> some View {
        Button {
            selectedMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(mode.rawValue).font(.headline)
                    Spacer()
                    if selectedMode == mode {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
                Text(mode.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedMode == mode ? Color.accentColor.opacity(0.12) : .secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectedMode == mode ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
