import Foundation

/// Embolcall tipat de UserDefaults per a les preferències de l'app.
/// L'altre agent fa servir els valors de l'estimador; aquí només es declaren.
@MainActor
public final class Defaults {

    public static let shared = Defaults()

    private let store: UserDefaults

    /// Claus de UserDefaults, exposades per si cal fer servir KVO o testing extern.
    public enum Keys {
        public static let launchAtLogin = "launchAtLogin"
        public static let notificationsEnabled = "notificationsEnabled"
        public static let estimatorSessionTokenBudget = "estimatorSessionTokenBudget"
        public static let estimatorWeeklyTokenBudget = "estimatorWeeklyTokenBudget"
    }

    /// Es crida quan canvia `launchAtLogin` des de la interfície. Qui la cablegi
    /// hi registra (o desregistra) l'app amb SMAppService; aquí no es fa res més.
    public var onLaunchAtLoginChanged: ((Bool) -> Void)?

    public init(store: UserDefaults = .standard) {
        self.store = store
    }

    /// Registra els valors per defecte. Cridar-ho un cop a l'arrencada de l'app.
    public func registerDefaults() {
        store.register(defaults: [
            Keys.launchAtLogin: false,
            Keys.notificationsEnabled: true,
            // Han de coincidir amb LocalUsageEstimator.defaultSessionBudget i
            // defaultWeeklyBudget: són les mateixes claus i l'estimador les llegeix.
            Keys.estimatorSessionTokenBudget: Int(LocalUsageEstimator.defaultSessionBudget),
            Keys.estimatorWeeklyTokenBudget: Int(LocalUsageEstimator.defaultWeeklyBudget)
        ])
    }

    /// Obre l'app en iniciar sessió. En escriure-hi, avisa `onLaunchAtLoginChanged`.
    public var launchAtLogin: Bool {
        get { store.bool(forKey: Keys.launchAtLogin) }
        set {
            store.set(newValue, forKey: Keys.launchAtLogin)
            onLaunchAtLoginChanged?(newValue)
        }
    }

    /// Avisos al 25, 50 i 75 % de la sessió.
    public var notificationsEnabled: Bool {
        get { store.bool(forKey: Keys.notificationsEnabled) }
        set { store.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    /// Pressupost de tokens per finestra de sessió, per a l'estimador local.
    public var estimatorSessionTokenBudget: Int {
        get { store.integer(forKey: Keys.estimatorSessionTokenBudget) }
        set { store.set(newValue, forKey: Keys.estimatorSessionTokenBudget) }
    }

    /// Pressupost de tokens per finestra setmanal, per a l'estimador local.
    public var estimatorWeeklyTokenBudget: Int {
        get { store.integer(forKey: Keys.estimatorWeeklyTokenBudget) }
        set { store.set(newValue, forKey: Keys.estimatorWeeklyTokenBudget) }
    }
}
