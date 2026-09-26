import AppKit
import ClaudeMeterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let defaults = Defaults.shared
    private let statusItem = StatusItemController(renderer: .shared)
    private let notifier = ThresholdNotifier(defaults: .shared)
    private var poller: UsagePoller!
    private var preferences: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.registerDefaults()
        LoginItem.install(into: defaults)

        poller = UsagePoller(
            official: OAuthUsageClient(),
            fallback: LocalUsageEstimator()
        )
        poller.addObserver(statusItem)
        poller.addObserver(notifier)
        poller.addObserver(self)

        statusItem.onMenuWillOpen = { [weak self] in
            self?.poller.refreshNow()
        }

        rebuildMenu(with: nil)
        poller.start()

        // Mode de depuració: ClaudeMeter --simulate 30,55,80 dispara els tres avisos.
        if let percents = Self.simulatedPercents() {
            notifier.simulate(percents: percents)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        poller?.stop()
    }

    // MARK: - Menú

    /// El menú es reconstrueix a cada snapshot perquè les files porten vistes pròpies.
    private func rebuildMenu(with snapshot: UsageSnapshot?) {
        let menu = MenuBuilder.buildMenu(
            from: snapshot,
            target: self,
            refresh: #selector(refreshNow),
            preferences: #selector(openPreferences),
            quit: #selector(quit)
        )
        statusItem.setMenu(menu)
    }

    @objc private func refreshNow() {
        poller.refreshNow()
    }

    @objc private func openPreferences() {
        if preferences == nil {
            preferences = PreferencesWindowController(
                defaults: defaults,
                projectPath: Bundle.main.bundlePath,
                version: Self.versionString()
            )
        }
        preferences?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Ajudes

    private static func versionString() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private static func simulatedPercents() -> [Int]? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--simulate"), index + 1 < arguments.count else {
            return nil
        }
        let values = arguments[index + 1]
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return values.isEmpty ? nil : values
    }
}

/// Observador pont: manté el menú al dia amb l'últim snapshot.
extension AppDelegate: UsageObserver {
    nonisolated func usageDidUpdate(_ snapshot: UsageSnapshot) {
        Task { @MainActor in
            self.rebuildMenu(with: snapshot)
        }
    }
}
