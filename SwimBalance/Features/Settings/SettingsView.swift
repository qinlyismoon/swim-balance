import SwiftUI

/// Settings in the same language as Swim and History. Each card shows the
/// current choice; changes happen in a sheet behind its Edit button and only
/// apply on Done. Apple Health is status only — it never triggers authorization.
struct SettingsView: View {
    let preferences: SwimPreferences
    let onUpdatePreferences: (SwimPreferences) -> Void
    let onReset: () -> Void

    private enum Editor: String, Identifiable {
        case profile, week, pool
        var id: String { rawValue }
    }

    @State private var editor: Editor?
    @State private var isConfirmingReset = false

    private var knownStrokes: [StrokeStyle] {
        StrokeStyle.swimmable.filter(preferences.knownStrokes.contains)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("You", editor: .profile) { swimmer }
                section("Your week", editor: .week) { week }
                section("Pool", editor: .pool) { pool }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .poolHeader()
        .navigationTitle("Settings")
        .sheet(item: $editor) { editor in
            switch editor {
            case .profile:
                SetupView(mode: .edit, initial: preferences, onFinish: onUpdatePreferences)
            case .week:
                WeekEditor(initial: preferences, onSave: onUpdatePreferences)
            case .pool:
                PoolEditor(initial: preferences, onSave: onUpdatePreferences)
            }
        }
        .confirmationDialog("Reset the demo?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Reset Demo", role: .destructive, action: onReset)
        } message: {
            Text("Clears all settings and restarts setup.")
        }
    }

    /// Title row with its Edit capsule, then a read-only card.
    private func section<Content: View>(_ title: String, editor: Editor,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: title)
                Button { self.editor = editor } label: {
                    MetaChip(systemImage: "pencil", text: "Edit")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(title)")
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .sectionCard()
        }
    }

    /// A small grey label above its values — the same pattern in every card.
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: Cards

    private var swimmer: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("You swim") {
                WrapLayout(spacing: 8) {
                    ForEach(knownStrokes) { stroke in
                        IconChip(image: stroke.icon, text: stroke.rawValue, style: .neutral)
                    }
                }
            }
            Divider()
            field("Working on") {
                WrapLayout(spacing: 8) {
                    ForEach(preferences.focuses, id: \.self) { focus in
                        IconChip(image: Image(focus.goal.iconName), text: focus.title, style: .accent)
                    }
                }
            }
        }
    }

    private var week: some View {
        VStack(alignment: .leading, spacing: 16) {
            PoolLanePicker(selection: .constant(preferences.swimWeekdays), height: 64,
                           idleFill: Color(.systemBackground).opacity(0.7), isEditable: false)
            Divider()
            HStack {
                Text("Each swim")
                    .foregroundStyle(.secondary)
                Spacer()
                MetaChip(systemImage: "clock", text: "\(preferences.availableMinutes) min")
            }
            .font(.subheadline)
        }
    }

    private var pool: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Length")
                    .foregroundStyle(.secondary)
                Spacer()
                MetaChip(systemImage: "arrow.left.and.right", text: "\(preferences.poolLengthMeters) m")
            }
            HStack {
                Text("Count in")
                    .foregroundStyle(.secondary)
                Spacer()
                MetaChip(systemImage: preferences.distanceUnit == .meters ? "ruler" : "arrow.triangle.2.circlepath",
                         text: preferences.distanceUnit.title)
            }
        }
        .font(.subheadline)
    }

    // MARK: Footer — quiet, no card

    private var footer: some View {
        VStack(spacing: 14) {
            MetaChip(systemImage: "heart", text: "Apple Health · coming later")
            Button("Reset demo", role: .destructive) { isConfirmingReset = true }
                .font(.subheadline)
                .foregroundStyle(.red)
            Text("Version 0.1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Chips

/// A capsule with a hand-drawn icon — strokes (neutral) and goals (accent).
private struct IconChip: View {
    let image: Image
    let text: String
    let style: MetaChip.Style

    var body: some View {
        HStack(spacing: 6) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
            Text(text)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.subheadline)
        .foregroundStyle(style == .accent ? Color.swimDeep : Color.primary.opacity(0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(style == .accent ? Color.swimDeep.opacity(0.12)
                                                    : Color(.systemBackground).opacity(0.75)))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// One choice in an editor: a filled capsule when chosen.
private struct OptionTile: View {
    let text: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.body.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(isOn ? Color.swimDeep : Color.swimMist))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Editors

/// Swim days and the usual length together — the two things that shape the week.
private struct WeekEditor: View {
    let initial: SwimPreferences
    let onSave: (SwimPreferences) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weekdays: Set<Int>
    @State private var contentHeight: CGFloat = 420
    @State private var minutes: Int

    init(initial: SwimPreferences, onSave: @escaping (SwimPreferences) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _weekdays = State(initialValue: initial.swimWeekdays)
        _minutes = State(initialValue: initial.availableMinutes)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Swim days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PoolLanePicker(selection: $weekdays, height: 88)
                }
                VStack(spacing: 10) {
                    Text("Each swim")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ClockDial(minutes: $minutes, range: SwimPreferences.minuteRange,
                              step: SwimPreferences.minuteStep, size: 220)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var updated = initial
                        updated.swimWeekdays = weekdays
                        updated.availableMinutes = minutes
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(weekdays == initial.swimWeekdays && minutes == initial.availableMinutes)
                }
            }
        }
        // The sheet is exactly as tall as what's in it — no empty bottom.
        .presentationDetents([.height(contentHeight + 64)])
        .fontDesign(.rounded)
        .tint(Color.swimDeep)
    }
}

/// Pool length and how distance is counted.
private struct PoolEditor: View {
    let initial: SwimPreferences
    let onSave: (SwimPreferences) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var length: Int
    @State private var contentHeight: CGFloat = 300
    @State private var unit: DistanceUnit

    init(initial: SwimPreferences, onSave: @escaping (SwimPreferences) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _length = State(initialValue: initial.poolLengthMeters)
        _unit = State(initialValue: initial.distanceUnit)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 6) {
                    Text("Pool length")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PoolLengthRuler(length: $length)
                }
                // Each choice shows today's 1,200 m swim the way it would read,
                // so the difference explains itself.
                VStack(alignment: .leading, spacing: 10) {
                    Text("Show distances as")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(DistanceUnit.allCases) { option in
                            UnitTile(unit: option, poolLength: length, isOn: option == unit) {
                                withAnimation(.easeInOut(duration: 0.2)) { unit = option }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .sensoryFeedback(.selection, trigger: length)
            .sensoryFeedback(.selection, trigger: unit)
            .navigationTitle("Pool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var updated = initial
                        updated.poolLengthMeters = length
                        updated.distanceUnit = unit
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(length == initial.poolLengthMeters && unit == initial.distanceUnit)
                }
            }
        }
        .presentationDetents([.height(contentHeight + 64)])
        .fontDesign(.rounded)
        .tint(Color.swimDeep)
    }
}


/// Pool length on a swipeable ruler: one tick per meter, labels on the
/// common lengths, the value under the centre line is the choice.
private struct PoolLengthRuler: View {
    @Binding var length: Int

    private let range = Array(10...60)
    private let common: Set<Int> = [15, 20, 25, 33, 50]
    private let spacing: CGFloat = 12

    @State private var position: Int?

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(length)")
                    .font(.system(size: 52, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(length)))
                Text("m")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.swimDeep)
            .animation(.snappy(duration: 0.2), value: length)

            GeometryReader { proxy in
            ZStack {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 0) {
                        ForEach(range, id: \.self) { meters in
                            tick(meters)
                                .frame(width: spacing)
                                .id(meters)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $position, anchor: .center)
                .safeAreaPadding(.horizontal, max((proxy.size.width - spacing) / 2, 0))
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                     startPoint: .leading, endPoint: .trailing))

                // Centre line
                Capsule()
                    .fill(Color.swimDeep)
                    .frame(width: 3, height: 44)
                    .offset(y: -8)
                    .allowsHitTesting(false)
            }
            }
            .frame(height: 70)
        }
        .onAppear { position = length }
        .onChange(of: position) { _, new in
            if let new, new != length { length = new }
        }
        .sensoryFeedback(.selection, trigger: length)
        .accessibilityElement()
        .accessibilityLabel("Pool length")
        .accessibilityValue("\(length) meters")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: length = min(length + 1, range.last!)
            case .decrement: length = max(length - 1, range.first!)
            @unknown default: break
            }
            position = length
        }
    }

    private func tick(_ meters: Int) -> some View {
        let isCommon = common.contains(meters)
        let isMajor = meters % 5 == 0 || isCommon
        return VStack(spacing: 6) {
            Capsule()
                .fill(isCommon ? Color.swimDeep.opacity(0.6) : Color.secondary.opacity(isMajor ? 0.5 : 0.25))
                .frame(width: isCommon ? 2 : 1.5, height: isMajor ? 28 : 16)
            Text(isCommon ? "\(meters)" : " ")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.swimDeep.opacity(0.7))
                .fixedSize()
                .frame(height: 14)
        }
        .frame(height: 64, alignment: .bottom)
    }
}


/// A distance-unit choice that shows a 1,200 m swim in that unit,
/// e.g. "1,200 m" vs "48 lengths" of a 25 m pool.
private struct UnitTile: View {
    let unit: DistanceUnit
    let poolLength: Int
    let isOn: Bool
    let action: () -> Void

    private var example: String { DistanceStyle(unit: unit, poolLength: poolLength).format(1200) }
    private var caption: String { unit == .meters ? "Meters" : "Lengths of a \(poolLength) m pool" }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(example)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.caption)
                    .opacity(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isOn ? Color.swimDeep : Color.swimMist))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: poolLength)
        .accessibilityLabel("\(caption), \(example)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
