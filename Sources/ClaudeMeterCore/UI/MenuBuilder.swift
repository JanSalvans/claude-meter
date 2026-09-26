import AppKit

/// Construeix el desplegable de la barra de menú a partir d'un UsageSnapshot.
@MainActor
public enum MenuBuilder {

    /// Construeix el menú complet. `target` rep els selectors `refresh`, `preferences` i `quit`.
    public static func buildMenu(
        from snapshot: UsageSnapshot?,
        target: AnyObject,
        refresh: Selector,
        preferences: Selector,
        quit: Selector
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let session = snapshot?.session {
            menu.addItem(progressItem(title: "sessió", metric: session))
        } else {
            menu.addItem(emptyMetricItem(title: "sessió"))
        }

        menu.addItem(.separator())

        if let week = snapshot?.week {
            menu.addItem(progressItem(title: "setmana", metric: week))
        } else {
            menu.addItem(emptyMetricItem(title: "setmana"))
        }

        if let weekOpus = snapshot?.weekOpus {
            menu.addItem(.separator())
            menu.addItem(progressItem(title: "setmana, opus", metric: weekOpus))
        }

        menu.addItem(.separator())
        menu.addItem(statusItem(for: snapshot))

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "actualitza ara", action: refresh, keyEquivalent: "r")
        refreshItem.target = target
        menu.addItem(refreshItem)

        let preferencesItem = NSMenuItem(title: "preferències...", action: preferences, keyEquivalent: ",")
        preferencesItem.target = target
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "surt", action: quit, keyEquivalent: "q")
        quitItem.target = target
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Ítems

    private static func progressItem(title: String, metric: UsageMetric) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = MetricRowView(title: title, percent: metric.percent, resetsAt: metric.resetsAt)
        return item
    }

    private static func emptyMetricItem(title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = MetricRowView(title: title, percent: nil, resetsAt: nil, emptyText: "sense dades")
        return item
    }

    private static func statusItem(for snapshot: UsageSnapshot?) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false

        let sourceText: String
        switch snapshot?.source {
        case .official:
            sourceText = "dades oficials"
        case .estimated:
            sourceText = "estimació local"
        case .unavailable, .none:
            sourceText = "sense dades"
        }

        var lines = [sourceText]
        if let fetchedAt = snapshot?.fetchedAt {
            lines.append("actualitzat fa \(minutesAgo(since: fetchedAt))")
        }
        if let message = snapshot?.message, !message.isEmpty {
            lines.append(message)
        }

        item.title = lines.joined(separator: ", ")
        item.attributedTitle = NSAttributedString(
            string: lines.joined(separator: ", "),
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
        )
        return item
    }

    // MARK: - Formatació

    private static func minutesAgo(since date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 {
            return "un moment"
        }
        return "\(minutes) min"
    }
}

/// Vista d'una fila de mètrica dins el menú: títol, percentatge, barra arrodonida
/// i, a sota, quan es restableix i quant falta.
///
/// Es col·loca a mà, sense Auto Layout: dins d'un NSMenu les restriccions no
/// fixen bé la mida i les línies de sota quedaven aixafades i tallades.
@MainActor
private final class MetricRowView: NSView {

    private static let minWidth: CGFloat = 240
    private static let inset: CGFloat = 14
    private static let barHeight: CGFloat = 6

    private let resetsAt: Date?
    private let emptyText: String
    private let titleLabel: NSTextField
    private let percentLabel: NSTextField
    private let resetLabel = NSTextField(labelWithString: "")
    private let remainingLabel = NSTextField(labelWithString: "")
    private let barBackground = NSView()
    private let barFill = NSView()
    private let fraction: CGFloat

    override var isFlipped: Bool { true }

    init(title: String, percent: Int?, resetsAt: Date?, emptyText: String = "sense hora de restabliment") {
        self.resetsAt = resetsAt
        self.emptyText = emptyText
        self.fraction = CGFloat(max(0, min(100, percent ?? 0))) / 100.0

        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.textColor = .labelColor

        percentLabel = NSTextField(labelWithString: percent.map { "\($0)%" } ?? "")
        percentLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right

        resetLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        resetLabel.textColor = .secondaryLabelColor

        remainingLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        remainingLabel.textColor = .labelColor

        barBackground.wantsLayer = true
        barBackground.layer?.cornerRadius = Self.barHeight / 2
        barBackground.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor

        barFill.wantsLayer = true
        barFill.layer?.cornerRadius = Self.barHeight / 2
        if let percent {
            barFill.layer?.backgroundColor = UsageBarRenderer.fillColor(forPercent: percent).cgColor
        } else {
            barFill.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        }

        super.init(frame: .zero)
        autoresizingMask = [.width]
        for view in [titleLabel, percentLabel, barBackground, barFill, resetLabel, remainingLabel] {
            addSubview(view)
        }
        for label in [titleLabel, percentLabel, resetLabel, remainingLabel] {
            label.lineBreakMode = .byClipping
            label.cell?.truncatesLastVisibleLine = false
        }
        updateResetText()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no implementat")
    }

    /// El menú afegeix la vista a la seva finestra cada cop que s'obre:
    /// així el compte enrere sempre surt calculat amb l'hora del moment.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateResetText()
        }
    }

    private func updateResetText() {
        if let resetsAt {
            let now = Date()
            let formatter = ResetFormatter()
            resetLabel.stringValue = formatter.whenLine(resetsAt: resetsAt, now: now)
            remainingLabel.stringValue = formatter.remainingLine(resetsAt: resetsAt, now: now)
        } else {
            resetLabel.stringValue = emptyText
            remainingLabel.stringValue = ""
        }
        let title = titleLabel.intrinsicContentSize
        let percent = percentLabel.intrinsicContentSize
        let contentWidth = max(
            title.width + percent.width + 20,
            resetLabel.intrinsicContentSize.width,
            remainingLabel.intrinsicContentSize.width
        )
        let naturalWidth = max(Self.minWidth, ceil(contentWidth) + Self.inset * 2)
        setFrameSize(NSSize(width: max(frame.width, naturalWidth), height: layoutRows(width: max(frame.width, naturalWidth))))
    }

    /// El menú estira la fila fins a la seva amplada: recol·loquem el que va a la dreta.
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        _ = layoutRows(width: bounds.width)
    }

    /// Posa cada element per a l'amplada donada i retorna l'alçada que ocupa.
    @discardableResult
    private func layoutRows(width: CGFloat) -> CGFloat {
        let inset = Self.inset
        let title = titleLabel.intrinsicContentSize
        let percent = percentLabel.intrinsicContentSize
        let reset = resetLabel.intrinsicContentSize
        let remaining = remainingLabel.intrinsicContentSize
        let innerWidth = width - inset * 2

        var y: CGFloat = 8
        // Amplades i alçades amb marge i arrodonides: amb la mida exacta del text,
        // a la pantalla real l'última lletra o els accents quedaven tallats.
        let rowHeight = ceil(max(title.height, percent.height)) + 2
        let percentWidth = ceil(percent.width) + 4
        percentLabel.frame = NSRect(x: width - inset - percentWidth, y: y, width: percentWidth, height: rowHeight)
        titleLabel.frame = NSRect(x: inset, y: y, width: max(ceil(title.width) + 4, innerWidth - percentWidth - 8), height: rowHeight)
        y += rowHeight + 6

        barBackground.frame = NSRect(x: inset, y: y, width: innerWidth, height: Self.barHeight)
        barFill.frame = NSRect(x: inset, y: y, width: max(Self.barHeight, innerWidth * fraction), height: Self.barHeight)
        y += Self.barHeight + 6

        let resetHeight = ceil(reset.height) + 2
        resetLabel.frame = NSRect(x: inset, y: y, width: innerWidth, height: resetHeight)
        y += resetHeight
        if !remainingLabel.stringValue.isEmpty {
            let remainingHeight = ceil(remaining.height) + 2
            remainingLabel.frame = NSRect(x: inset, y: y, width: innerWidth, height: remainingHeight)
            y += remainingHeight
        } else {
            remainingLabel.frame = .zero
        }
        return ceil(y + 8)
    }
}
