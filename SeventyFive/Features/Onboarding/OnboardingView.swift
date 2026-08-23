import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedMode: ChallengeMode = .soft
    @State private var bodyWeightText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("75")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    Text("Pick your tier")
                        .font(.title3.weight(.semibold))
                    Text("You can't switch tiers mid-challenge, so start where you'll actually finish.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 32)

                VStack(spacing: 12) {
                    ForEach(ChallengeMode.allCases) { mode in
                        modeCard(mode)
                    }
                }
                .padding(.horizontal)

                if selectedMode.requiresBodyWeight {
                    bodyWeightField
                }

                Button {
                    startChallenge()
                } label: {
                    Text("Start \(selectedMode.rawValue)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    private var canStart: Bool {
        guard selectedMode.requiresBodyWeight else { return true }
        return (Double(bodyWeightText) ?? 0) > 0
    }

    private func modeCard(_ mode: ChallengeMode) -> some View {
        Button {
            withAnimation(.snappy) { selectedMode = mode }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(mode.rawValue).font(.headline)
                    Spacer()
                    Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedMode == mode ? Color.accentColor : .secondary.opacity(0.4))
                }

                Text(mode.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                if selectedMode == mode {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(mode.tasks) { task in
                            Label(task.title, systemImage: task.systemImage)
                                .font(.caption)
                        }
                        ForEach(mode.guidelines, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if mode.photoCadence == .milestone {
                            Label("Progress photo on Day 1 and Day 75 (optional in between)", systemImage: "camera")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectedMode == mode ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectedMode == mode ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var bodyWeightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your body weight")
                .font(.subheadline.weight(.medium))
            HStack {
                TextField("160", text: $bodyWeightText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Text("lbs").foregroundStyle(.secondary)
            }
            Text("75 Medium scales your water goal to half your body weight in ounces.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func startChallenge() {
        let challenge = Challenge(
            mode: selectedMode,
            bodyWeightPounds: selectedMode.requiresBodyWeight ? Double(bodyWeightText) : nil
        )
        modelContext.insert(challenge)
        try? modelContext.save()
    }
}
