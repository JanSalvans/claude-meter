import AppKit

/// Finestra de preferències, feta per codi, sense storyboard ni xib.
@MainActor
public final class PreferencesWindowController: NSWindowController {

    private let defaults: Defaults
    private var launchAtLoginSwitch: NSSwitch!
    private var notificationsSwitch: NSSwitch!

    public init(defaults: Defaults, projectPath: String, version: String) {
        self.defaults = defaults

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "preferències de claude meter"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        buildContent(projectPath: projectPath, version: version)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no implementat")
    }

    /// Mostra la finestra i porta l'app al davant.
    public func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    private func buildContent(projectPath: String, version: String) {
        guard let window else { return }

        let launchAtLoginLabel = NSTextField(labelWithString: "obre en iniciar sessió")
        let launchAtLoginSwitch = NSSwitch()
        launchAtLoginSwitch.state = defaults.launchAtLogin ? .on : .off
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginToggled(_:))
        self.launchAtLoginSwitch = launchAtLoginSwitch

        let notificationsLabel = NSTextField(labelWithString: "avisa'm al 25, 50 i 75 % de la sessió")
        let notificationsSwitch = NSSwitch()
        notificationsSwitch.state = defaults.notificationsEnabled ? .on : .off
        notificationsSwitch.target = self
        notificationsSwitch.action = #selector(notificationsToggled(_:))
        self.notificationsSwitch = notificationsSwitch

        let infoLabel = NSTextField(wrappingLabelWithString: "projecte: \(projectPath)\nversió: \(version)")
        infoLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        infoLabel.textColor = .secondaryLabelColor

        let launchRow = row(label: launchAtLoginLabel, control: launchAtLoginSwitch)
        let notificationsRow = row(label: notificationsLabel, control: notificationsSwitch)

        let stack = NSStackView(views: [launchRow, notificationsRow, infoLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        window.contentView = contentView
        window.setContentSize(NSSize(width: 360, height: 200))
        // No redimensionable: no s'afegeix .resizable a l'styleMask.
    }

    private func row(label: NSTextField, control: NSSwitch) -> NSView {
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.distribution = .fill
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    @objc private func launchAtLoginToggled(_ sender: NSSwitch) {
        defaults.launchAtLogin = sender.state == .on
    }

    @objc private func notificationsToggled(_ sender: NSSwitch) {
        defaults.notificationsEnabled = sender.state == .on
    }
}
