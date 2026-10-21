import SwiftUI

extension Color {
    /// Deep sea blue accent: deep ink in light mode, luminous aqua in dark mode.
    /// Used sparingly for the focus stroke (freestyle by default); everything
    /// else stays neutral so the glass navigation and the primary action stand out.
    static var swimDeep: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.45, green: 0.84, blue: 0.95, alpha: 1.0)
                : UIColor(red: 0.05, green: 0.36, blue: 0.51, alpha: 1.0)
        })
    }
}

extension Color {
    /// Very light pool blue used for cards and list rows.
    static var swimMist: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.14, blue: 0.16, alpha: 1)
                : UIColor(red: 0.93, green: 0.96, blue: 0.97, alpha: 1)
        })
    }
}

private struct PoolHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("HeaderPool")
            .resizable()
            .scaledToFill()
            .frame(height: 260)
            .frame(maxWidth: .infinity)
            .clipped()
            .opacity(colorScheme == .dark ? 0.28 : 0.5)
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0),
                            .init(color: .black, location: 0.2),
                            .init(color: .clear, location: 0.7)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension StrokeStyle {
    /// Fill used wherever strokes are compared visually. The focus stroke gets
    /// the accent; other strokes get quiet grays.
    func allocationColor(focus: StrokeStyle) -> Color {
        if self == focus { return Color.swimDeep }
        switch self {
        case .breaststroke: return Color(uiColor: .systemGray3)
        case .freestyle: return Color(uiColor: .systemGray2)
        case .backstroke: return Color(uiColor: .systemGray4)
        case .butterfly: return Color(uiColor: .systemGray)
        case .mixed: return Color(uiColor: .systemGray5)
        }
    }
}

extension StrokeStyle {
    /// Pictogram from the asset catalog (template image, tint with foregroundStyle).
    var icon: Image {
        self == .mixed ? Image(systemName: "figure.pool.swim") : Image("Stroke-\(rawValue.lowercased())")
    }
}

extension View {
    /// Flat grouped section: a very light pool-blue rounded container, no shadow.
    func sectionCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.swimMist, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Soft colored-pencil pool scene behind the top of a page, fading out
    /// before the content. Atmosphere only — never carries information.
    func poolHeader() -> some View {
        background(alignment: .top) {
            PoolHeader()
        }
    }
}

extension Calendar {
    func weekdayName(_ weekday: Int) -> String { weekdaySymbols[(weekday - 1) % 7] }
    func shortWeekdayName(_ weekday: Int) -> String { shortWeekdaySymbols[(weekday - 1) % 7] }

    /// Calendar weekdays (1 = Sunday) in this calendar's display order.
    var orderedWeekdays: [Int] { (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 } }

    /// The days of the month containing `date`, padded with leading nils so the
    /// first day lands under its weekday column.
    func monthGrid(containing date: Date) -> [Date?] {
        guard let start = dateInterval(of: .month, for: date)?.start,
              let count = range(of: .day, in: .month, for: date)?.count else { return [] }
        let leading = (component(.weekday, from: start) - firstWeekday + 7) % 7
        let days: [Date?] = (0..<count).map { self.date(byAdding: .day, value: $0, to: start) }
        return Array(repeating: nil, count: leading) + days
    }

    /// The seven days of the week containing `date`, in display order.
    func week(containing date: Date) -> [Date] {
        guard let start = dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { self.date(byAdding: .day, value: $0, to: start) }
    }
}

extension Int {
    /// "1,250 m"
    var meters: String { "\(formatted()) m" }
}

/// Formats distances in meters or pool lengths, following the user's setting.
struct DistanceStyle {
    var unit: DistanceUnit = .meters
    var poolLength: Int = 25

    init(unit: DistanceUnit = .meters, poolLength: Int = 25) {
        self.unit = unit
        self.poolLength = max(poolLength, 1)
    }

    init(_ preferences: SwimPreferences) {
        self.init(unit: preferences.distanceUnit, poolLength: preferences.poolLengthMeters)
    }

    private func lengths(_ meters: Int) -> Int {
        Int((Double(meters) / Double(poolLength)).rounded())
    }

    /// Number only: "1,250" or "50".
    func value(_ meters: Int) -> String {
        unit == .meters ? meters.formatted() : lengths(meters).formatted()
    }

    /// Unit label matching `value`: "m" or "lengths".
    func unitLabel(_ meters: Int) -> String {
        unit == .meters ? "m" : (lengths(meters) == 1 ? "length" : "lengths")
    }

    /// "1,250 m" or "50 lengths".
    func format(_ meters: Int) -> String { "\(value(meters)) \(unitLabel(meters))" }

    /// A set's repeats: "12 × 25 m" or "12 × 1 length".
    func repeats(_ count: Int, of meters: Int) -> String { "\(count) × \(format(meters))" }
}

/// Reflections plus a way to save one — handed down through the environment.
struct ReflectionBook {
    var byDay: [String: SwimReflection] = [:]
    var save: (SwimReflection, Date) -> Void = { _, _ in }

    func reflection(on date: Date) -> SwimReflection {
        byDay[PlanGenerator.dayKey(date)] ?? SwimReflection()
    }
}

extension EnvironmentValues {
    @Entry var distanceStyle = DistanceStyle()
    @Entry var reflections = ReflectionBook()
}


// MARK: - Phase colours

extension SetPhase {
    /// Each part of a swim has its own colour, shared by the stage bar and the
    /// set list so one reads as the key to the other. Practice (the focus work)
    /// keeps the app's deep blue; the rest stay soft.
    var color: Color {
        switch self {
        case .warmUp: Color(red: 0.89, green: 0.66, blue: 0.45)      // warm sand
        case .practice: .swimDeep                                    // focus
        case .main: Color(red: 0.36, green: 0.66, blue: 0.68)        // pool teal
        case .intervals: Color(red: 0.47, green: 0.55, blue: 0.80)   // dusk blue
        case .longSwim: Color(red: 0.36, green: 0.66, blue: 0.68)    // pool teal
        case .coolDown: Color(red: 0.62, green: 0.74, blue: 0.88)    // sky
        }
    }
}
