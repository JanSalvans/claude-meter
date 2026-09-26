import Foundation
import UserNotifications

/// Dispara avisos locals quan l'ús de la finestra de sessió (5 h) creua el 25, 50 i 75 %.
/// Només mira la sessió: és una decisió explícita de l'usuari, la setmana no avisa mai.
@MainActor
public final class ThresholdNotifier: UsageObserver {

    /// Els tres llindars que vigilem, en ordre ascendent.
    public static let thresholds: [Int] = [25, 50, 75]

    private let center: UNUserNotificationCenterProtocol
    private let store: UserDefaults
    private let defaults: Defaults
    private let calendar: Calendar

    /// Clau de UserDefaults on es desen els llindars ja avisats per finestra.
    private static let firedKeyPrefix = "thresholdNotifier.fired."
    /// Clau de la finestra (resetsAt o bloc alternatiu) per detectar-ne el canvi.
    private static let windowKeyKey = "thresholdNotifier.windowKey"
    /// Si ja hem demanat permís alguna vegada, per no tornar-ho a demanar.
    private static let authorizationRequestedKey = "thresholdNotifier.authorizationRequested"

    public init(
        defaults: Defaults,
        store: UserDefaults = .standard,
        center: UNUserNotificationCenterProtocol = UNUserNotificationCenter.current(),
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.store = store
        self.center = center
        self.calendar = calendar
    }

    // MARK: - UsageObserver

    public func usageDidUpdate(_ snapshot: UsageSnapshot) {
        guard defaults.notificationsEnabled else { return }
        guard snapshot.source != .unavailable else { return }
        guard let session = snapshot.session else { return }

        requestAuthorizationIfNeeded()

        let windowKey = Self.windowKey(for: session, at: snapshot.fetchedAt, calendar: calendar)
        rearmIfWindowChanged(windowKey: windowKey, percent: session.percent)

        process(percent: session.percent, windowKey: windowKey, resetsAt: session.resetsAt)
    }

    // MARK: - Depuració

    /// Injecta percentatges falsos pel mateix camí que un snapshot real, per provar els avisos
    /// sense esperar que l'ús real creui cap llindar.
    public func simulate(percents: [Int]) {
        requestAuthorizationIfNeeded()
        let windowKey = "simulate.\(Int(Date().timeIntervalSince1970))"
        for percent in percents {
            process(percent: percent, windowKey: windowKey, resetsAt: nil)
        }
    }

    // MARK: - Nucli comú

    private func process(percent: Int, windowKey: String, resetsAt: Date?) {
        for threshold in Self.thresholds {
            guard percent >= threshold else { continue }
            guard !hasFired(threshold, windowKey: windowKey) else { continue }
            markFired(threshold, windowKey: windowKey)
            send(threshold: threshold, resetsAt: resetsAt)
        }
    }

    /// Quan la finestra canvia (o és la primera vegada que la veiem), reinicialitza l'estat:
    /// els llindars ja per sota de l'ús actual es marquen com a consumits sense notificar,
    /// perquè en arrencar l'app no s'engeguin tots els avisos endarrerits de cop.
    private func rearmIfWindowChanged(windowKey: String, percent: Int) {
        let previousKey = store.string(forKey: Self.windowKeyKey)
        guard previousKey != windowKey else { return }

        store.set(windowKey, forKey: Self.windowKeyKey)
        clearFired(windowKey: previousKey)
        clearFired(windowKey: windowKey)

        for threshold in Self.thresholds where percent >= threshold {
            markFired(threshold, windowKey: windowKey)
        }
    }

    private func hasFired(_ threshold: Int, windowKey: String) -> Bool {
        store.bool(forKey: firedKey(threshold, windowKey: windowKey))
    }

    private func markFired(_ threshold: Int, windowKey: String) {
        store.set(true, forKey: firedKey(threshold, windowKey: windowKey))
    }

    private func clearFired(windowKey: String?) {
        guard let windowKey else { return }
        for threshold in Self.thresholds {
            store.removeObject(forKey: firedKey(threshold, windowKey: windowKey))
        }
    }

    private func firedKey(_ threshold: Int, windowKey: String) -> String {
        "\(Self.firedKeyPrefix)\(windowKey).\(threshold)"
    }

    /// Clau que identifica la finestra vigent. Si el servidor ens dona `resetsAt` la fem
    /// servir directament; si no, la derivem del bloc de 5 h en curs (des de mitjanit local)
    /// perquè encara puguem rearmar els llindars quan canviï de bloc.
    private static func windowKey(for metric: UsageMetric, at date: Date, calendar: Calendar) -> String {
        if let resetsAt = metric.resetsAt {
            return "resetsAt.\(resetsAt.timeIntervalSince1970)"
        }
        let startOfDay = calendar.startOfDay(for: date)
        let secondsSinceMidnight = date.timeIntervalSince(startOfDay)
        let blockIndex = Int(secondsSinceMidnight / (5 * 3600))
        let dayIndex = Int(startOfDay.timeIntervalSince1970 / 86400)
        return "block.\(dayIndex).\(blockIndex)"
    }

    // MARK: - Enviament

    private func send(threshold: Int, resetsAt: Date?) {
        let content = UNMutableNotificationContent()
        content.title = "Claude: \(threshold) % de la sessió"
        content.body = body(for: threshold, resetsAt: resetsAt)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "claudemeter.threshold.\(threshold).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }

    private func body(for threshold: Int, resetsAt: Date?) -> String {
        let remaining: String
        switch threshold {
        case 25:
            remaining = "et queden tres quartes parts de la finestra."
        case 50:
            remaining = "et queda mitja finestra."
        case 75:
            remaining = "et queda un quart de la finestra."
        default:
            remaining = "revisa l'ús de la finestra."
        }
        guard let resetsAt else { return remaining }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(remaining) Es reinicia a les \(formatter.string(from: resetsAt))."
    }

    // MARK: - Permís

    private func requestAuthorizationIfNeeded() {
        guard !store.bool(forKey: Self.authorizationRequestedKey) else { return }
        store.set(true, forKey: Self.authorizationRequestedKey)
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

/// Protocol mínim sobre `UNUserNotificationCenter` perquè les proves puguin injectar un doble
/// sense disparar notificacions de debò ni demanar permisos reals.
public protocol UNUserNotificationCenterProtocol {
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    )
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    )
}

extension UNUserNotificationCenter: UNUserNotificationCenterProtocol {}
