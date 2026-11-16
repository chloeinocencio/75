import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PrefKey.acceptedHealthNote) private var acceptedHealthNote = false

    @State private var selectedMode: ChallengeMode = .soft
    @State private var weightText = ""
    @State private var weightInKilograms = Locale.current.measurementSystem == .metric
    @FocusState private var weightFocused: Bool

    var body: some View {
        // The NavigationStack is only here so the keyboard's Done button can appear.
        NavigationStack {
        ScrollView {
            VStack(spacing: 22) {
                header

                VStack(spacing: 12) {
                    ForEach(ChallengeMode.allCases) { mode in
                        modeCard(mode)
                    }
                }

                if selectedMode.requiresBodyWeight {
                    bodyWeightField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                healthNote

                Button {
                    startChallenge()
                } label: {
                    Text("Start \(selectedMode.rawValue)")
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(!canStart)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedBackground(glow: 0.25)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("75")
                .font(.system(size: 72, weight: .heavy))
                .tracking(-3)
                .foregroundStyle(Theme.accentText)
            Text("Pick your challenge")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("You can't switch tiers partway through, so start where you'll actually finish.")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 36)
    }

    // MARK: - Weight

    /// Parsed with the user's locale, so "72,5" works in Europe and "160.5" in the US.
    private var parsedWeight: Double? {
        try? Double(weightText.trimmingCharacters(in: .whitespaces), format: .number)
    }

    private var weightPounds: Double? {
        guard let value = parsedWeight else { return nil }
        return weightInKilograms ? value * 2.20462 : value
    }

    /// Guards against typos ("1600") that would set an unsafe water goal.
    private var weightIsPlausible: Bool {
        guard let pounds = weightPounds else { return false }
        return (70...700).contains(pounds)
    }

    private var canStart: Bool {
        guard acceptedHealthNote else { return false }
        guard selectedMode.requiresBodyWeight else { return true }
        return weightIsPlausible
    }

    private var bodyWeightField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Your body weight")
            HStack(spacing: 10) {
                TextField(weightInKilograms ? "72" : "160", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($weightFocused)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .accessibilityLabel("Body weight")

                Picker("Unit", selection: $weightInKilograms) {
                    Text("lb").tag(false)
                    Text("kg").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }

            Group {
                if !weightText.isEmpty && !weightIsPlausible {
                    Text("Double-check that number — it looks off.")
                } else if let pounds = weightPounds, weightIsPlausible {
                    let liters = WaterGoal.halfBodyWeightInOunces.resolvedLiters(bodyWeightPounds: pounds)
                    Text("Your water goal: \(WaterUnit.localeDefault.format(liters: liters)) a day — half your body weight in ounces.")
                } else {
                    Text("75 Medium scales your water goal to half your body weight in ounces. It stays on this iPhone.")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.dim)
        }
    }

    // MARK: - Health

    private var healthNote: some View {
        Button {
            withAnimation(.snappy) { acceptedHealthNote.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: acceptedHealthNote ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(acceptedHealthNote ? Theme.accentText : Theme.dim)
                VStack(alignment: .leading, spacing: 4) {
                    Text("75 is a habit tracker, not medical advice.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(HealthNote.short)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.leading)
                }
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(acceptedHealthNote ? .isSelected : [])
        .accessibilityHint("Confirms you've read the health note")
    }

    // MARK: - Tier cards

    private func modeCard(_ mode: ChallengeMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.snappy) { selectedMode = mode }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(mode.rawValue)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.accentText : Theme.dim.opacity(0.5))
                }

                Text(mode.tagline)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.leading)

                if isSelected {
                    Divider().overlay(Theme.line)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(mode.tasks) { task in
                            Label(task.title, systemImage: task.systemImage)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.ink)
                        }
                        ForEach(mode.guidelines, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(Theme.dim)
                        }
                        if mode.photoCadence == .milestone {
                            Label("Progress photo on Day 1 and Day 75 (optional in between)", systemImage: "camera")
                                .font(.footnote)
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.limeSoft : Theme.surface,
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accentText.opacity(0.8) : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func startChallenge() {
        let challenge = Challenge(
            mode: selectedMode,
            bodyWeightPounds: selectedMode.requiresBodyWeight ? weightPounds : nil
        )
        modelContext.insert(challenge)
        try? modelContext.save()
    }
}

enum HealthNote {
    static let short = "Check with a doctor before starting a strict diet, twice-daily training or drinking a gallon of water a day — especially if you're pregnant, take medication, or have a heart, kidney or eating-related condition. Stop and get help if something feels wrong."
}
