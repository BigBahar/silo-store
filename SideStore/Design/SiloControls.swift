//
//  SiloControls.swift
//  Silo Store
//
//  Silo's own switch, list picker, menu and segmented control. They replace the
//  system look but keep system behaviour: 44 pt targets, press feedback on touch
//  down, VoiceOver values, hardware-keyboard arrows and Escape, Reduce Motion.
//

@preconcurrency import SwiftUI
@preconcurrency import UIKit

// MARK: - Shared

/// Press feedback that starts on touch down, not on release.
struct SiloPressStyle: ButtonStyle
{
    func makeBody(configuration: Configuration) -> some View
    {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct SiloOption<Value: Hashable>: Identifiable
{
    var value: Value
    var label: String
    var detail: String? = nil

    var id: Value { return value }
}

extension UIViewController
{
    /// The view controller currently on top, for presenting Silo panels from SwiftUI.
    static func siloTopMost() -> UIViewController?
    {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first

        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController
        {
            top = presented
        }
        return top
    }
}

// MARK: - Switch (SwiftUI)

struct SiloSwitchGraphic: View
{
    let isOn: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View
    {
        let look = SiloTheme.look(for: colorScheme)
        let rounded = look.radiusControl > 0
        let trackWidth: CGFloat = 52
        let trackHeight: CGFloat = 32
        let inset: CGFloat = 4
        let knob = trackHeight - inset * 2
        let trackShape = RoundedRectangle(cornerRadius: rounded ? trackHeight / 2 : 0, style: .continuous)
        let knobShape = RoundedRectangle(cornerRadius: rounded ? knob / 2 : 0, style: .continuous)

        return ZStack(alignment: .leading) {
            trackShape.fill(Color(uiColor: isOn ? look.accent : look.raised))
            trackShape.strokeBorder(Color(uiColor: isOn ? look.accent : look.borderStrong), lineWidth: 1.5)
            knobShape
                .fill(Color(uiColor: isOn ? look.accentInk : look.textMuted))
                .frame(width: knob, height: knob)
                .offset(x: isOn ? trackWidth - knob - inset : inset)
        }
        .frame(width: trackWidth, height: trackHeight)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 1), value: isOn)
    }
}

/// Use as `.toggleStyle(SiloToggleStyle())`; the row stays a Toggle for VoiceOver.
struct SiloToggleStyle: ToggleStyle
{
    func makeBody(configuration: Configuration) -> some View
    {
        Button {
            configuration.isOn.toggle()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: SiloSpace.s3) {
                configuration.label
                Spacer(minLength: SiloSpace.s2)
                SiloSwitchGraphic(isOn: configuration.isOn)
            }
            .frame(minHeight: SiloSpace.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(SiloPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: ""))
    }
}

// MARK: - Switch (UIKit)

/// Drop-in for UISwitch: `isOn`, `setOn(_:animated:)`, `.valueChanged`.
final class SiloSwitch: UIControl
{
    private let knob = UIView()

    private static let trackSize = CGSize(width: 52, height: 32)
    private static let inset: CGFloat = 4

    private(set) var isOnValue = false

    var isOn: Bool {
        get { return self.isOnValue }
        set { self.setOn(newValue, animated: false) }
    }

    override init(frame: CGRect)
    {
        super.init(frame: CGRect(origin: frame.origin, size: Self.trackSize))
        self.commonInit()
    }

    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        self.commonInit()
    }

    private func commonInit()
    {
        self.layer.borderWidth = 1.5
        self.addSubview(self.knob)
        self.addTarget(self, action: #selector(SiloSwitch.toggle), for: .touchUpInside)

        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
        self.updateAccessibilityValue()
        self.applyLook(animated: false)
    }

    override var intrinsicContentSize: CGSize {
        return Self.trackSize
    }

    /// The tappable area is larger than the drawn track.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool
    {
        return self.bounds.insetBy(dx: -4, dy: -6).contains(point)
    }

    override var isHighlighted: Bool {
        didSet { self.alpha = self.isHighlighted ? 0.6 : 1 }
    }

    override func layoutSubviews()
    {
        super.layoutSubviews()
        self.applyLook(animated: false)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
    {
        super.traitCollectionDidChange(previousTraitCollection)
        self.applyLook(animated: false)
    }

    func setOn(_ on: Bool, animated: Bool)
    {
        guard on != self.isOnValue else { return }
        self.isOnValue = on
        self.updateAccessibilityValue()
        self.applyLook(animated: animated)
    }

    @objc private func toggle()
    {
        self.setOn(!self.isOnValue, animated: true)
        UISelectionFeedbackGenerator().selectionChanged()
        self.sendActions(for: .valueChanged)
    }

    private func updateAccessibilityValue()
    {
        self.accessibilityValue = self.isOnValue ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: "")
    }

    private func applyLook(animated: Bool)
    {
        let look = SiloTheme.look(for: self.traitCollection.userInterfaceStyle)
        let rounded = look.radiusControl > 0
        let size = Self.trackSize
        let knobSide = size.height - Self.inset * 2
        let knobX = self.isOnValue ? size.width - knobSide - Self.inset : Self.inset

        let changes = {
            self.backgroundColor = self.isOnValue ? look.accent : look.raised
            self.layer.borderColor = (self.isOnValue ? look.accent : look.borderStrong).cgColor
            self.layer.cornerRadius = rounded ? size.height / 2 : 0
            self.knob.backgroundColor = self.isOnValue ? look.accentInk : look.textMuted
            self.knob.layer.cornerRadius = rounded ? knobSide / 2 : 0
            self.knob.frame = CGRect(x: knobX, y: Self.inset, width: knobSide, height: knobSide)
        }

        if animated, !UIAccessibility.isReduceMotionEnabled
        {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: changes)
        }
        else
        {
            changes()
        }
    }
}

// MARK: - List panel (picker and menu)

struct SiloListItem
{
    var title: String
    var detail: String? = nil
    var systemImage: String? = nil
    var isSelected = false
    var isDestructive = false
    var action: () -> Void
}

private final class SiloListRow: UIControl
{
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let checkView = UIImageView()
    private let iconView = UIImageView()
    private let item: SiloListItem

    var isKeyboardFocused = false {
        didSet { self.updateAppearance() }
    }

    init(item: SiloListItem)
    {
        self.item = item
        super.init(frame: .zero)

        self.titleLabel.text = item.title
        self.titleLabel.font = SiloFont.uiFont(.body)
        self.titleLabel.adjustsFontForContentSizeCategory = true
        self.titleLabel.numberOfLines = 0

        self.detailLabel.text = item.detail
        self.detailLabel.font = SiloFont.uiFont(.caption)
        self.detailLabel.adjustsFontForContentSizeCategory = true
        self.detailLabel.numberOfLines = 0
        self.detailLabel.isHidden = item.detail == nil

        let weight = UIImage.SymbolConfiguration(weight: .semibold)
        self.checkView.image = UIImage(systemName: "checkmark", withConfiguration: weight)
        self.checkView.isHidden = !item.isSelected
        self.checkView.setContentHuggingPriority(.required, for: .horizontal)

        self.iconView.image = item.systemImage.flatMap { UIImage(systemName: $0, withConfiguration: weight) }
        self.iconView.isHidden = item.systemImage == nil
        self.iconView.setContentHuggingPriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [self.titleLabel, self.detailLabel])
        text.axis = .vertical
        text.spacing = 2

        let row = UIStackView(arrangedSubviews: [self.iconView, text, self.checkView])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = SiloSpace.s3
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: SiloSpace.s4),
            row.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -SiloSpace.s4),
            row.topAnchor.constraint(equalTo: self.topAnchor, constant: SiloSpace.s2),
            row.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -SiloSpace.s2),
            self.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])

        self.isAccessibilityElement = true
        self.accessibilityLabel = item.title
        self.accessibilityValue = item.detail
        self.accessibilityTraits = item.isSelected ? [.button, .selected] : .button

        self.updateAppearance()
    }

    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { self.updateAppearance() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
    {
        super.traitCollectionDidChange(previousTraitCollection)
        self.updateAppearance()
    }

    private func updateAppearance()
    {
        let look = SiloTheme.look(for: self.traitCollection.userInterfaceStyle)
        let textColor = self.item.isDestructive ? look.danger : look.text

        self.backgroundColor = self.isHighlighted ? look.raised : .clear
        self.titleLabel.textColor = textColor
        self.detailLabel.textColor = look.textMuted
        self.checkView.tintColor = look.accent
        self.iconView.tintColor = self.item.isDestructive ? look.danger : look.textMuted

        self.layer.borderColor = look.accent.cgColor
        self.layer.borderWidth = self.isKeyboardFocused ? 2 : 0
    }
}

final class SiloListboxViewController: UIViewController
{
    private let panelTitle: String?
    private let items: [SiloListItem]

    private let scrim = UIView()
    private let card = UIView()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var rows: [SiloListRow] = []
    private var focusedIndex: Int?
    private var isClosing = false

    init(title: String?, items: [SiloListItem])
    {
        self.panelTitle = title
        self.items = items
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func viewDidLoad()
    {
        super.viewDidLoad()

        self.view.backgroundColor = .clear
        self.view.accessibilityViewIsModal = true

        self.scrim.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        self.scrim.alpha = 0
        self.scrim.translatesAutoresizingMaskIntoConstraints = false
        self.scrim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(SiloListboxViewController.scrimTapped)))
        self.scrim.isAccessibilityElement = true
        self.scrim.accessibilityLabel = NSLocalizedString("Close", comment: "")
        self.scrim.accessibilityTraits = .button
        self.view.addSubview(self.scrim)

        self.card.translatesAutoresizingMaskIntoConstraints = false
        self.card.layer.borderWidth = 1
        self.card.clipsToBounds = true
        self.card.alpha = 0
        if !UIAccessibility.isReduceMotionEnabled
        {
            self.card.transform = CGAffineTransform(translationX: 0, y: 24)
        }
        self.view.addSubview(self.card)

        self.scroll.translatesAutoresizingMaskIntoConstraints = false
        self.scroll.alwaysBounceVertical = false
        self.card.addSubview(self.scroll)

        self.stack.axis = .vertical
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        self.scroll.addSubview(self.stack)

        if let panelTitle = self.panelTitle, !panelTitle.isEmpty
        {
            let label = UILabel()
            label.text = panelTitle
            label.font = SiloFont.uiFont(.label)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
            label.accessibilityTraits = .header
            label.tag = 1

            let holder = UIView()
            label.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: SiloSpace.s4),
                label.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -SiloSpace.s4),
                label.topAnchor.constraint(equalTo: holder.topAnchor, constant: SiloSpace.s4),
                label.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -SiloSpace.s2)
            ])
            self.stack.addArrangedSubview(holder)
        }

        for (index, item) in self.items.enumerated()
        {
            let row = SiloListRow(item: item)
            row.tag = index
            row.addTarget(self, action: #selector(SiloListboxViewController.rowTapped(_:)), for: .touchUpInside)
            self.rows.append(row)
            self.stack.addArrangedSubview(row)
        }

        self.focusedIndex = self.items.firstIndex(where: { $0.isSelected })

        let maxWidth = self.card.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        let fullWidth = self.card.widthAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.widthAnchor, constant: -SiloSpace.s3 * 2)
        fullWidth.priority = .defaultHigh

        let fitContent = self.scroll.heightAnchor.constraint(equalTo: self.stack.heightAnchor)
        fitContent.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            self.scrim.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.scrim.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.scrim.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrim.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.card.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.card.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -SiloSpace.s3),
            self.card.topAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.topAnchor, constant: SiloSpace.s5),
            maxWidth,
            fullWidth,

            self.scroll.topAnchor.constraint(equalTo: self.card.topAnchor),
            self.scroll.bottomAnchor.constraint(equalTo: self.card.bottomAnchor),
            self.scroll.leadingAnchor.constraint(equalTo: self.card.leadingAnchor),
            self.scroll.trailingAnchor.constraint(equalTo: self.card.trailingAnchor),
            fitContent,

            self.stack.topAnchor.constraint(equalTo: self.scroll.contentLayoutGuide.topAnchor),
            self.stack.bottomAnchor.constraint(equalTo: self.scroll.contentLayoutGuide.bottomAnchor),
            self.stack.leadingAnchor.constraint(equalTo: self.scroll.contentLayoutGuide.leadingAnchor),
            self.stack.trailingAnchor.constraint(equalTo: self.scroll.contentLayoutGuide.trailingAnchor),
            self.stack.widthAnchor.constraint(equalTo: self.scroll.frameLayoutGuide.widthAnchor)
        ])

        self.applyLook()
    }

    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        self.applyLook()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
    {
        super.traitCollectionDidChange(previousTraitCollection)
        self.applyLook()
    }

    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        self.becomeFirstResponder()

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            self.scrim.alpha = 1
            self.card.alpha = 1
            self.card.transform = .identity
        }
    }

    private func applyLook()
    {
        let look = SiloTheme.look(for: self.traitCollection.userInterfaceStyle)
        self.card.backgroundColor = look.surface
        self.card.layer.borderColor = look.border.cgColor
        self.card.layer.cornerRadius = look.radiusPanel

        self.stack.arrangedSubviews.forEach { view in
            if let label = view.viewWithTag(1) as? UILabel
            {
                label.textColor = look.textFaint
            }
        }
    }

    // MARK: Actions

    @objc private func scrimTapped()
    {
        self.closeAnimated(completion: nil)
    }

    @objc private func rowTapped(_ row: UIControl)
    {
        self.select(index: row.tag)
    }

    private func select(index: Int)
    {
        guard self.items.indices.contains(index) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        let action = self.items[index].action
        self.closeAnimated(completion: action)
    }

    private func closeAnimated(completion: (() -> Void)?)
    {
        guard !self.isClosing else { return }
        self.isClosing = true

        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
            self.scrim.alpha = 0
            self.card.alpha = 0
            if !reduceMotion
            {
                self.card.transform = CGAffineTransform(translationX: 0, y: 24)
            }
        } completion: { _ in
            self.dismiss(animated: false) {
                completion?()
            }
        }
    }

    override func accessibilityPerformEscape() -> Bool
    {
        self.closeAnimated(completion: nil)
        return true
    }

    // MARK: Hardware keyboard

    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(SiloListboxViewController.moveFocusUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(SiloListboxViewController.moveFocusDown)),
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(SiloListboxViewController.activateFocused)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(SiloListboxViewController.escapePressed))
        ]
    }

    @objc private func moveFocusUp()
    {
        self.moveFocus(by: -1)
    }

    @objc private func moveFocusDown()
    {
        self.moveFocus(by: 1)
    }

    @objc private func activateFocused()
    {
        guard let index = self.focusedIndex else { return }
        self.select(index: index)
    }

    @objc private func escapePressed()
    {
        self.closeAnimated(completion: nil)
    }

    private func moveFocus(by offset: Int)
    {
        guard !self.rows.isEmpty else { return }

        let next: Int
        if let current = self.focusedIndex
        {
            next = min(max(current + offset, 0), self.rows.count - 1)
        }
        else
        {
            next = offset > 0 ? 0 : self.rows.count - 1
        }

        self.focusedIndex = next
        for (index, row) in self.rows.enumerated()
        {
            row.isKeyboardFocused = index == next
        }
        self.scroll.scrollRectToVisible(self.rows[next].frame, animated: true)
    }
}

enum SiloListbox
{
    static func present(title: String?, items: [SiloListItem])
    {
        guard !items.isEmpty, let top = UIViewController.siloTopMost() else { return }
        top.present(SiloListboxViewController(title: title, items: items), animated: false)
    }
}

// MARK: - Picker and menu (SwiftUI)

/// Replaces `Picker` in a row: shows the current choice and opens a Silo list.
struct SiloPicker<Value: Hashable>: View
{
    let title: String
    @Binding var selection: Value
    let options: [SiloOption<Value>]

    private var currentLabel: String {
        return self.options.first(where: { $0.value == self.selection })?.label ?? ""
    }

    var body: some View
    {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            self.present()
        } label: {
            HStack(spacing: SiloSpace.s3) {
                Text(self.title)
                    .siloFont(.body)
                    .foregroundColor(.siloText)
                Spacer(minLength: SiloSpace.s2)
                Text(self.currentLabel)
                    .siloFont(.body)
                    .foregroundColor(.siloTextMuted)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.siloTextFaint)
            }
            .frame(minHeight: SiloSpace.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(SiloPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func present()
    {
        let items = self.options.map { option in
            SiloListItem(title: option.label, detail: option.detail, isSelected: option.value == self.selection) {
                self.selection = option.value
            }
        }
        SiloListbox.present(title: self.title, items: items)
    }
}

struct SiloMenuAction
{
    var title: String
    var systemImage: String? = nil
    var isDestructive = false
    var action: () -> Void
}

/// Replaces `Menu`: any label view that opens a Silo list of actions.
struct SiloMenu<Content: View>: View
{
    var title: String? = nil
    let actions: [SiloMenuAction]
    let label: () -> Content

    var body: some View
    {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            let items = self.actions.map { action in
                SiloListItem(title: action.title, systemImage: action.systemImage, isDestructive: action.isDestructive, action: action.action)
            }
            SiloListbox.present(title: self.title, items: items)
        } label: {
            self.label()
        }
        .buttonStyle(SiloPressStyle())
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Segmented (SwiftUI)

/// Replaces `Picker(...).pickerStyle(.segmented)`.
struct SiloSegmented<Value: Hashable>: View
{
    @Binding var selection: Value
    let options: [SiloOption<Value>]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View
    {
        let look = SiloTheme.look(for: self.colorScheme)
        let rounded = look.radiusControl > 0
        let outer = RoundedRectangle(cornerRadius: rounded ? look.radiusControl : 0, style: .continuous)
        // Concentric: inner radius = outer radius - padding.
        let inner = RoundedRectangle(cornerRadius: rounded ? max(look.radiusControl - 4, 0) : 0, style: .continuous)

        let animation: Animation? = self.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)
        
        return HStack(spacing: 4) {
            ForEach(self.options) { option in
                let selected = option.value == self.selection
                let traits: AccessibilityTraits = selected ? [.isButton, .isSelected] : [.isButton]
                Button {
                    guard !selected else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    self.selection = option.value
                } label: {
                    Text(option.label)
                        .siloFont(.label)
                        .foregroundColor(selected ? .siloAccentInk : .siloTextMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(inner.fill(selected ? Color.siloAccent : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SiloPressStyle())
                .accessibilityAddTraits(traits)
            }
        }
        .padding(4)
        .background(outer.fill(Color.siloRaised))
        .overlay(outer.strokeBorder(Color.siloBorder, lineWidth: 1))
        .animation(animation, value: self.selection)
    }
}

// MARK: - Hosting

/// Hosts a SwiftUI screen with Silo's switch and, until the screen is moved to the
/// semantic colours, the dark look it was drawn for.
final class SiloHostingController<Content: View>: UIHostingController<AnyView>
{
    init(rootView: Content)
    {
        super.init(rootView: AnyView(rootView.toggleStyle(SiloToggleStyle())))
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = .dark
    }
}
