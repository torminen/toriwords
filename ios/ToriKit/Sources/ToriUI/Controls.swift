#if canImport(SwiftUI)
import SwiftUI

// MARK: Buttons

/// Full-width filled button, radius 12, height ≥ 50. `tint` gives Forgot (danger) / Remembered (success).
public struct PrimaryButtonStyle: ButtonStyle {
    public var tint: Color
    @Environment(\.isEnabled) private var isEnabled

    public init(tint: Color = Palette.accent) { self.tint = tint }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.heading)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Spacing.l)
            .background(tint.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }
}

/// Full-width tinted-text button on a neutral fill ("Learn more new words").
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.heading)
            .foregroundStyle(isEnabled ? Palette.accent : Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Spacing.l)
            .background(Palette.neutralFill.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    public static var toriPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    public static func toriPrimary(tint: Color) -> PrimaryButtonStyle { PrimaryButtonStyle(tint: tint) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    public static var toriSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: Translation variants

/// One translation variant with a checkbox (Add preview, capture sheet; UQ-1: checkboxes as in the new frames).
/// Already-saved meanings are shown checked and disabled.
public struct VariantRow: View {
    public var text: String
    public var isMachine: Bool
    public var isChecked: Bool
    public var isDisabled: Bool
    public var toggle: () -> Void

    public init(_ text: String, isMachine: Bool = false, isChecked: Bool, isDisabled: Bool = false, toggle: @escaping () -> Void) {
        self.text = text
        self.isMachine = isMachine
        self.isChecked = isChecked
        self.isDisabled = isDisabled
        self.toggle = toggle
    }

    public var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? Palette.accent : Palette.border)
                    .imageScale(.large)
                Text(verbatim: text).font(Typography.body).foregroundStyle(Palette.text)
                Spacer(minLength: Spacing.s)
                if isMachine { Badge(Strings.machineTranslation, fill: Palette.infoFill, ink: Palette.accent) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }
}

// MARK: Chips

/// A rounded selectable chip (Words filters, capture word chips). Selected = accent fill.
public struct Chip: View {
    public var label: Text
    public var isSelected: Bool
    public var action: () -> Void

    public init(_ label: Text, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            label
                .font(Typography.secondary)
                .foregroundStyle(isSelected ? Palette.accent : Palette.text)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(isSelected ? Palette.infoFill : Palette.neutralFill,
                            in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// One horizontally scrolling row of chips.
public struct ChipsRow<ID: Hashable>: View {
    public struct Item {
        public var id: ID
        public var label: Text
        public init(id: ID, label: Text) {
            self.id = id
            self.label = label
        }
    }

    public var items: [Item]
    public var selected: Set<ID>
    public var onTap: (ID) -> Void

    public init(_ items: [Item], selected: Set<ID>, onTap: @escaping (ID) -> Void) {
        self.items = items
        self.selected = selected
        self.onTap = onTap
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(items, id: \.id) { item in
                    Chip(item.label, isSelected: selected.contains(item.id)) { onTap(item.id) }
                }
            }
            .padding(.horizontal, Spacing.l)
        }
    }
}

// MARK: Badges

/// Small filled label used by stage markers, "Machine translation" and the Wiktionary mark.
public struct Badge: View {
    public var text: LocalizedStringResource
    public var fill: Color
    public var ink: Color

    public init(_ text: LocalizedStringResource, fill: Color, ink: Color = Palette.text) {
        self.text = text
        self.fill = fill
        self.ink = ink
    }

    public var body: some View {
        Text(text)
            .font(Typography.groupLabel.weight(.medium))
            .foregroundStyle(ink)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 2)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Stage marker on Words rows and the entry. The app maps its stage model to `Kind`.
public struct StageMarker: View {
    public enum Kind: Sendable, CaseIterable {
        case new, learning, knownWell, known, paused, needsTranslation
    }

    public var kind: Kind

    public init(_ kind: Kind) { self.kind = kind }

    public var body: some View {
        switch kind {
        case .new: Badge(Strings.stageNew, fill: Palette.neutralFill)
        case .learning: Badge(Strings.stageLearning, fill: Palette.infoFill)
        case .knownWell: Badge(Strings.stageKnownWell, fill: Palette.successFill)
        case .known: Badge(Strings.stageKnown, fill: Palette.successFill)
        case .paused: Badge(Strings.stagePaused, fill: Palette.neutralFill)
        case .needsTranslation: Badge(Strings.stageNeedsTranslation, fill: Palette.warningFill)
        }
    }
}

/// "Wiktionary" mark next to Sense values with provenance `wiktionary`.
public struct WiktionaryMark: View {
    public init() {}
    public var body: some View { Badge(Strings.wiktionary, fill: Palette.neutralFill, ink: Palette.textSecondary) }
}

// MARK: Banners and empty states

/// Inline notice box: Check translation (warning), "Already in your vocabulary" (info), one-time tip (tip).
public struct Banner<Actions: View>: View {
    public enum Kind: Sendable { case info, warning, success, tip }

    public var kind: Kind
    public var title: Text
    public var message: Text?
    private let actions: Actions

    public init(_ kind: Kind, title: Text, message: Text? = nil, @ViewBuilder actions: () -> Actions) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            title.font(Typography.heading).foregroundStyle(Palette.text)
            if let message { message.font(Typography.secondary).foregroundStyle(Palette.textSecondary) }
            actions.font(Typography.secondary.weight(.semibold)).padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.cell, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var fill: Color {
        switch kind {
        case .info: Palette.infoFill
        case .warning: Palette.warningFill
        case .success: Palette.successFill
        case .tip: Palette.tip
        }
    }
}

extension Banner where Actions == EmptyView {
    public init(_ kind: Kind, title: Text, message: Text? = nil) {
        self.init(kind, title: title, message: message) { EmptyView() }
    }
}

extension Banner {
    /// Entry screen banner for automatically filled translations (proposal UQ-8).
    public static func checkTranslation(@ViewBuilder actions: () -> Actions) -> Banner {
        Banner(.warning, title: Text(Strings.checkTranslationTitle), message: Text(Strings.checkTranslationMessage),
               actions: actions)
    }
}

/// Centered empty state: title, message, optional primary action ("Add your first word", "Add '…'").
public struct EmptyStateView: View {
    public var title: Text
    public var message: Text?
    public var actionTitle: Text?
    public var action: (() -> Void)?

    public init(title: Text, message: Text? = nil, actionTitle: Text? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.m) {
            title.font(Typography.cardWord).multilineTextAlignment(.center)
            if let message {
                message.font(Typography.secondary).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) { actionTitle }.buttonStyle(.toriPrimary).padding(.top, Spacing.l)
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Strings

/// UI strings of shared components. Keys live in the String Catalog (EN defaults here; RU in step 9).
public enum Strings {
    public static let machineTranslation = LocalizedStringResource("ui.variant.machine", defaultValue: "Machine translation")
    public static let wiktionary = LocalizedStringResource("ui.mark.wiktionary", defaultValue: "Wiktionary")
    public static let stageNew = LocalizedStringResource("ui.stage.new", defaultValue: "New")
    public static let stageLearning = LocalizedStringResource("ui.stage.learning", defaultValue: "Learning")
    public static let stageKnownWell = LocalizedStringResource("ui.stage.knownWell", defaultValue: "Known well")
    public static let stageKnown = LocalizedStringResource("ui.stage.known", defaultValue: "Known")
    public static let stagePaused = LocalizedStringResource("ui.stage.paused", defaultValue: "Paused")
    public static let stageNeedsTranslation = LocalizedStringResource("ui.stage.needsTranslation", defaultValue: "Needs translation")
    public static let checkTranslationTitle = LocalizedStringResource("ui.banner.checkTranslation.title", defaultValue: "Check translation")
    public static let checkTranslationMessage = LocalizedStringResource(
        "ui.banner.checkTranslation.message", defaultValue: "Translation added automatically. Check it.")
    public static let forgot = LocalizedStringResource("ui.review.forgot", defaultValue: "Forgot")
    public static let remembered = LocalizedStringResource("ui.review.remembered", defaultValue: "Remembered")
}

// MARK: Previews

#Preview("Controls") {
    @Previewable @State var checked: Set<String> = ["тщательный"]
    @Previewable @State var filter = "all"
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ChipsRow([.init(id: "all", label: Text(verbatim: "All")), .init(id: "needs", label: Text(Strings.stageNeedsTranslation)),
                      .init(id: "check", label: Text(Strings.checkTranslationTitle))],
                     selected: [filter]) { filter = $0 }
                .padding(.horizontal, -Spacing.l)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(["тщательный", "основательный", "дотошный"], id: \.self) { v in
                    VariantRow(v, isMachine: v == "дотошный", isChecked: checked.contains(v)) {
                        if checked.contains(v) { checked.remove(v) } else { checked.insert(v) }
                    }
                }
            }
            .padding(.horizontal, Spacing.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.cell))
            HStack { ForEach(StageMarker.Kind.allCases, id: \.self) { StageMarker($0) } }
            WiktionaryMark()
            Banner.checkTranslation { Button("Edit") {} }
            Banner(.tip, title: Text(verbatim: "Tip: put ToriWords first"), message: Text(verbatim: "Shown once."))
            HStack(spacing: Spacing.m) {
                Button {} label: { Text(Strings.forgot) }.buttonStyle(.toriPrimary(tint: Palette.danger))
                Button {} label: { Text(Strings.remembered) }.buttonStyle(.toriPrimary(tint: Palette.success))
            }
            Button("Learn more new words") {}.buttonStyle(.toriSecondary)
        }
        .padding()
    }
    .background(Palette.background)
}

#Preview("Empty state") {
    EmptyStateView(title: Text(verbatim: "Nothing to review today"), message: Text(verbatim: "Next review: tomorrow"),
                   actionTitle: Text(verbatim: "Done")) {}
        .background(Palette.background)
}
#endif
