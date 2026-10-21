import SwiftUI

/// Collects what the plan needs, then reveals the generated week.
///
/// - `.onboarding`: four input steps (strokes → goal → time → days), shown with a
///   segmented progress bar and a sideways push between steps, then a result page
///   that builds the week in front of the user.
/// - `.edit`: strokes and goal only, from Settings (the schedule is edited inline there).
struct SetupView: View {
    enum Mode { case onboarding, edit }

    private enum Step: Int, CaseIterable {
        case strokes, goal, time, days, result

        static let inputCount = 4

        var title: String {
            switch self {
            case .strokes: "Your strokes"
            case .goal: "Your goals"
            case .time: "Time per swim"
            case .days: "Swim days"
            case .result: "Your week"
            }
        }
    }

    let mode: Mode
    let onFinish: (SwimPreferences) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SwimPreferences
    @State private var step: Step = .strokes
    @State private var isMovingForward = true

    init(mode: Mode, initial: SwimPreferences, onFinish: @escaping (SwimPreferences) -> Void) {
        self.mode = mode
        self.onFinish = onFinish
        _draft = State(initialValue: initial.normalized())
    }

    var body: some View {
        NavigationStack {
            switch mode {
            case .onboarding: onboarding
            case .edit: editor
            }
        }
        .tint(Color.swimDeep)
        .fontDesign(.rounded)
        .onChange(of: draft.knownStrokes) { draft = draft.normalized() }
    }

    // MARK: Onboarding

    /// Calm step change: the incoming page drifts in a short way from the side
    /// you're heading to while fading in; the outgoing page only fades.
    private var contentTransition: AnyTransition {
        if step == .result { return .opacity }
        return .asymmetric(
            insertion: .offset(x: isMovingForward ? 24 : -24).combined(with: .opacity),
            removal: .opacity
        )
    }

    private static let stepAnimation: Animation = .easeInOut(duration: 0.3)

    private var onboarding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                // Old and new overlap in place (ZStack), so the layout never stacks or jumps.
                ZStack(alignment: .leading) {
                    Text(step.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                        .id(step)
                        .transition(.opacity)
                }
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 36) {
                        stepContent
                    }
                    .id(step)
                    .transition(contentTransition)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Fixed-height top row on every page, so the title never moves.
            HStack {
                if step != .strokes {
                    Button("Back", systemImage: "chevron.left") { move(by: -1) }
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .transition(.opacity)
                }
                Spacer()
            }
            .frame(height: 52)
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          VStack(spacing: 20) {
            if step != .result {
                StepProgress(current: step.rawValue, count: Step.inputCount)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }
            Button {
                if step == .result {
                    onFinish(draft.normalized())
                } else {
                    move(by: 1)
                }
            } label: {
                Text(step == .result ? "Start Swimming" : "Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
          }
          .padding(.top, 12)
          .padding(.bottom, 8)
          .animation(Self.stepAnimation, value: step == .result)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .strokes:
            pageIllustration("PageStrokes")
            strokeList
        case .goal:
            pageIllustration("PageGoal")
            goalList
        case .time:
            ClockDial(minutes: $draft.availableMinutes,
                      range: SwimPreferences.minuteRange,
                      step: SwimPreferences.minuteStep)
                .padding(.top, 12)
        case .days:
            pageIllustration("PageDays")
            VStack(alignment: .leading, spacing: 16) {
                PoolLanePicker(selection: $draft.swimWeekdays)
                restTip
            }
        case .result:
            WeekResult(week: PlanGenerator.weeklyPlan(for: draft), distance: DistanceStyle(draft))
        }
    }

    private func move(by delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        isMovingForward = delta > 0
        withAnimation(Self.stepAnimation) { step = next }
    }

    /// Scene illustration for a whole page: what the question is about.
    /// Always the same slot — under the title, fixed size — on every page that has one.
    private func pageIllustration(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 300, height: 140)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }

    /// One quiet line under the days; turns accent when two swim days touch.
    private var restTip: some View {
        Text(hasBackToBackDays
             ? "Two days in a row — a rest day between helps technique stick."
             : "Rest days between swims help technique stick.")
            .font(.subheadline)
            .foregroundStyle(hasBackToBackDays ? Color.swimDeep : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: hasBackToBackDays)
    }

    private var hasBackToBackDays: Bool {
        draft.swimWeekdays.contains { draft.swimWeekdays.contains($0 % 7 + 1) }
    }

    // MARK: Edit sheet

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Strokes you can swim")
                    strokeList
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Goals")
                    goalList
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("Strokes & Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onFinish(draft.normalized())
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: Strokes

    private func toggleStroke(_ stroke: StrokeStyle) {
        withAnimation(.snappy) {
            if draft.knownStrokes.contains(stroke) {
                if draft.knownStrokes.count > 1 { draft.knownStrokes.remove(stroke) }
            } else {
                draft.knownStrokes.insert(stroke)
            }
        }
    }

    /// The four strokes as a 2×2 grid of tiles — they're a set, so a grid reads
    /// faster than a list. Selected tiles fill with pool blue.
    private var strokeList: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(StrokeStyle.swimmable) { stroke in
                let isOn = draft.knownStrokes.contains(stroke)
                Button {
                    toggleStroke(stroke)
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            StrokeIcon(stroke: stroke, size: 44)
                                .foregroundStyle(isOn ? Color.swimDeep : Color.secondary)
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isOn ? Color.swimDeep : Color(.systemGray3))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Text(stroke.rawValue)
                            .foregroundStyle(Color.primary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isOn ? Color.swimDeep.opacity(0.10) : Color.swimMist,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(isOn ? Color.swimDeep : Color.clear, lineWidth: 1.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: draft.knownStrokes)
    }

    // MARK: Goals

    /// Concrete goals built from the strokes answered on the previous page,
    /// as two-column tiles. Pick one or more — the week rotates through them.
    private var goalList: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(draft.allFocusOptions) { option in
                let isOn = draft.focuses.contains(option)
                Button {
                    toggleFocus(option)
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            Image(option.goal.iconName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(isOn ? Color.swimDeep : Color.secondary)
                                .accessibilityHidden(true)
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isOn ? Color.swimDeep : Color(.systemGray3))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Text(option.title)
                            .foregroundStyle(Color.primary)
                            .lineLimit(2, reservesSpace: true)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isOn ? Color.swimDeep.opacity(0.10) : Color.swimMist,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(isOn ? Color.swimDeep : Color.clear, lineWidth: 1.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: draft.focuses)
    }

    private func toggleFocus(_ focus: SwimFocus) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let index = draft.focuses.firstIndex(of: focus) {
                if draft.focuses.count > 1 { draft.focuses.remove(at: index) }
            } else {
                draft.focuses.append(focus)
            }
        }
    }
}

// MARK: - Progress

/// One segment per input step; filled up to the current one.
private struct StepProgress: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.swimDeep : Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

// MARK: - Result

/// The generated week, in the same visual language as the Swim days page:
/// seven pool lanes where water rises in each swim day (deeper blue = goal
/// stroke), then each session as a roomy tile. The total counts up while the
/// water rises — one calm motion.
private struct WeekResult: View {
    let week: WeeklyPlan
    let distance: DistanceStyle

    @State private var hasAppeared = false
    @State private var total = 0
    private let calendar = Calendar.current
    private let laneHeight: CGFloat = 150

    private var maxMeters: Int { max(week.sessions.map(\.plan.totalDistanceMeters).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(distance.value(total))
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(total)))
                    Text("\(distance.unitLabel(week.totalDistanceMeters)) a week")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text("\(week.sessions.count) \(week.sessions.count == 1 ? "swim" : "swims") · \(week.preferences.availableMinutes) min each")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 6) {
                ForEach(calendar.orderedWeekdays, id: \.self) { weekday in
                    lane(weekday)
                }
            }

            VStack(spacing: 10) {
                ForEach(week.sessions) { session in
                    HStack(spacing: 14) {
                        Text(calendar.shortWeekdayName(session.weekday))
                            .font(.headline)
                            .frame(width: 44, alignment: .leading)
                        Text(session.plan.title)
                        Spacer(minLength: 8)
                        Text(distance.format(session.plan.totalDistanceMeters))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(Color.swimMist, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
            .opacity(hasAppeared ? 1 : 0)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.8)) {
                hasAppeared = true
                total = week.totalDistanceMeters
            }
        }
    }

    /// A pool lane; on a swim day, water rises to that day's distance.
    private func lane(_ weekday: Int) -> some View {
        let session = week.sessions.first { $0.weekday == weekday }
        let totalMeters = session?.plan.totalDistanceMeters ?? 0
        let focusMeters = session.map { $0.plan.meters(of: $0.focusStroke) } ?? 0
        let water = (laneHeight - 40) * CGFloat(totalMeters) / CGFloat(maxMeters)
        let focusWater = water * CGFloat(focusMeters) / CGFloat(max(totalMeters, 1))

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.swimMist)
            if session != nil {
                VStack(spacing: 0) {
                    Image(systemName: "water.waves")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.swimDeep.opacity(0.6))
                        .padding(.bottom, 4)
                    Rectangle().fill(Color.swimDeep.opacity(0.3))
                        .frame(height: max(water - focusWater, 0))
                    Rectangle().fill(Color.swimDeep)
                        .frame(height: focusWater)
                }
                .frame(height: hasAppeared ? water + 20 : 0, alignment: .bottom)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous))
                .padding(.bottom, 32)
            }
            Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                .font(.headline)
                .foregroundStyle(session == nil ? Color.secondary : Color.primary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: laneHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calendar.weekdayName(weekday))
        .accessibilityValue(session.map { "\($0.plan.title), \(distance.format($0.plan.totalDistanceMeters))" } ?? "Rest day")
    }
}

/// Swim days as seven pool lanes. Tap a lane to fill it with water; at least one stays chosen.
/// Seven pool lanes, one per weekday; a swim day fills with water.
struct PoolLanePicker: View {
    @Binding var selection: Set<Int>
    var height: CGFloat = 120
    /// Fill of a lane with no swim — lighter when the picker sits on a mist card.
    var idleFill: Color = .swimMist
    /// Read-only lanes show the week without reacting to taps.
    var isEditable = true

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 6) {
            ForEach(calendar.orderedWeekdays, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if isOn {
                            if selection.count > 1 { selection.remove(weekday) }
                        } else {
                            selection.insert(weekday)
                        }
                    }
                } label: {
                    VStack {
                        Image(systemName: "water.waves")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .opacity(isOn ? 1 : 0)
                            .padding(.top, height > 90 ? 14 : 10)
                        Spacer()
                        Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                            .font(.headline)
                            .foregroundStyle(isOn ? .white : Color.secondary)
                            .padding(.bottom, height > 90 ? 12 : 9)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(isOn ? Color.swimDeep : idleFill,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isEditable)
                .accessibilityLabel(calendar.weekdayName(weekday))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Chips

/// Capsule choices that wrap onto new lines.
private struct FlowChips<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    var icon: ((Item) -> Image)? = nil
    var isEnabled: (Item) -> Bool = { _ in true }
    let isOn: (Item) -> Bool
    let toggle: (Item) -> Void

    init(items: [Item], title: @escaping (Item) -> String, icon: ((Item) -> Image)? = nil,
         isEnabled: @escaping (Item) -> Bool = { _ in true },
         isOn: @escaping (Item) -> Bool, toggle: @escaping (Item) -> Void) {
        self.items = items
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.isOn = isOn
        self.toggle = toggle
    }

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let selected = isOn(item)
                Button {
                    toggle(item)
                } label: {
                    HStack(spacing: 6) {
                        if let icon {
                            icon(item)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                        Text(title(item))
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(selected ? Color.swimDeep : Color.secondary)
                .fontWeight(selected ? .semibold : .regular)
                .disabled(!isEnabled(item))
                .opacity(isEnabled(item) ? 1 : 0.4)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Minimal wrapping layout for chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let last = rows[rows.count - 1]
            let needed = last.indices.isEmpty ? size.width : last.width + spacing + size.width
            if needed > width, !last.indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

#Preview("Onboarding") {
    SetupView(mode: .onboarding, initial: SwimPreferences()) { _ in }
}

#Preview("Edit") {
    SetupView(mode: .edit, initial: SwimPreferences()) { _ in }
}
