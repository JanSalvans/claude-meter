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
            menu.addItem(progressItem(title: "sessió", metric: session, resetPrefix: "es reinicia a les"))
        } else {
            menu.addItem(emptyMetricItem(title: "sessió"))
        }

        menu.addItem(.separator())

        if let week = snapshot?.week {
            menu.addItem(progressItem(title: "setmana", metric: week, resetPrefix: "es reinicia"))
        } else {
            menu.addItem(emptyMetricItem(title: "setmana"))
        }

        if let weekOpus = snapshot?.weekOpus {
            menu.addItem(.separator())
            menu.addItem(progressItem(title: "setmana, opus", metric: weekOpus, resetPrefix: "es reinicia"))
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

    private static func progressItem(title: String, metric: UsageMetric, resetPrefix: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = MetricRowView(
            title: title,
            percent: metric.percent,
            resetLine: resetLine(prefix: resetPrefix, resetsAt: metric.resetsAt)
        )
        return item
    }

    private static func emptyMetricItem(title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = MetricRowView(title: title, percent: nil, resetLine: "sense dades")
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

    private static func resetLine(prefix: String, resetsAt: Date?) -> String {
        guard let resetsAt else { return "sense hora de reinici" }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ca_ES")
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: resetsAt)

        if Calendar.current.isDateInToday(resetsAt) {
            return "\(prefix) les \(time)"
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ca_ES")
        dayFormatter.dateFormat = "EEEE"
        let day = dayFormatter.string(from: resetsAt)
        return "\(prefix) \(day) a les \(time)"
    }

    private static func minutesAgo(since date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 {
            return "un moment"
        }
        return "\(minutes) min"
    }
}

/// Vista d'una fila de mètrica dins el menú: títol, percentatge i barra arrodonida.
@MainActor
private final class MetricRowView: NSView {

    private static let width: CGFloat = 240
    private static let height: CGFloat = 52

    init(title: String, percent: Int?, resetLine: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.textColor = .labelColor

        let percentLabel = NSTextField(labelWithString: percent.map { "\($0)%" } ?? "")
        percentLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right

        let resetLabel = NSTextField(labelWithString: resetLine)
        resetLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        resetLabel.textColor = .secondaryLabelColor

        let barBackground = NSView()
        barBackground.wantsLayer = true
        barBackground.layer?.cornerRadius = 3
        barBackground.layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.25).cgColor

        let barFill = NSView()
        barFill.wantsLayer = true
        barFill.layer?.cornerRadius = 3
        if let percent {
            barFill.layer?.backgroundColor = BatteryIconRenderer.fillColor(forPercent: percent).cgColor
        } else {
            barFill.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        }

        for view in [titleLabel, percentLabel, resetLabel, barBackground, barFill] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let horizontalInset: CGFloat = 14
        let barHeight: CGFloat = 6
        let fraction = CGFloat(max(0, min(100, percent ?? 0))) / 100.0

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),

            percentLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            percentLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            barBackground.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            barBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            barBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            barBackground.heightAnchor.constraint(equalToConstant: barHeight),

            barFill.leadingAnchor.constraint(equalTo: barBackground.leadingAnchor),
            barFill.centerYAnchor.constraint(equalTo: barBackground.centerYAnchor),
            barFill.heightAnchor.constraint(equalToConstant: barHeight),
            barFill.widthAnchor.constraint(equalTo: barBackground.widthAnchor, multiplier: max(fraction, 0.02)),

            resetLabel.topAnchor.constraint(equalTo: barBackground.bottomAnchor, constant: 6),
            resetLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            resetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            resetLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no implementat")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: Self.height)
    }
}
