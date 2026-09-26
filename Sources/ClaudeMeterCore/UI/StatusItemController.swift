import AppKit

/// Gestiona l'NSStatusItem de la barra de menú: barra d'ús + percentatge de sessió.
@MainActor
public final class StatusItemController: NSObject, UsageObserver, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let renderer: UsageBarRenderer
    private var latestSnapshot: UsageSnapshot?
    private var appearanceObservation: NSKeyValueObservation?

    /// Es crida quan l'usuari obre el desplegable, perquè qui ho cablegi
    /// pugui demanar una actualització immediata abans de mostrar-lo.
    public var onMenuWillOpen: (() -> Void)?

    public var button: NSStatusBarButton? { statusItem.button }

    public init(renderer: UsageBarRenderer) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.renderer = renderer
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
        }
        statusItem.menu?.delegate = self

        render(snapshot: nil)
        observeAppearanceChanges()
    }

    deinit {
        appearanceObservation?.invalidate()
    }

    /// Assigna el menú desplegable que s'obrirà en clicar la icona.
    public func setMenu(_ menu: NSMenu) {
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - UsageObserver

    public func usageDidUpdate(_ snapshot: UsageSnapshot) {
        latestSnapshot = snapshot
        render(snapshot: snapshot)
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
    }

    // MARK: - Dibuix

    private func render(snapshot: UsageSnapshot?) {
        guard let button = statusItem.button else { return }
        let appearance = button.effectiveAppearance
        let percent = snapshot?.session?.percent

        button.image = renderer.image(forPercent: percent, appearance: appearance)

        if let percent {
            let prefix = snapshot?.source == .estimated ? "~" : ""
            button.title = " \(prefix)\(percent)%"
        } else {
            button.title = ""
        }
    }

    private func observeAppearanceChanges() {
        guard let button = statusItem.button else { return }
        appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] button, _ in
            guard let self else { return }
            Task { @MainActor in
                self.render(snapshot: self.latestSnapshot)
            }
        }
    }
}
