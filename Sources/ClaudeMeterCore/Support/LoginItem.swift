import Foundation
import ServiceManagement
import os

/// Embolcall de SMAppService.mainApp per obrir l'app en iniciar sessió.
///
/// SMAppService només funciona quan l'app corre des d'un bundle .app instal·lat
/// (per exemple des de ~/Applications). Si s'executa des de la línia d'ordres,
/// amb `swift run` o com a binari solt, el registre falla: ho detectem i no petem,
/// només ho informem al log.
public enum LoginItem {

    private static let logger = Logger(subsystem: "com.jansalvans.claudemeter", category: "LoginItem")

    /// Cert si l'app té registrat l'inici automàtic amb l'usuari.
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registra o desregistra l'obertura automàtica en iniciar sessió.
    /// Llança si SMAppService no pot completar l'operació (per exemple perquè
    /// l'app no corre des d'un bundle instal·lat).
    public static func setEnabled(_ enabled: Bool) throws {
        guard isRunningFromAppBundle else {
            logger.notice("LoginItem: no es pot registrar perquè l'app no corre des d'un bundle .app instal·lat.")
            return
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Cablega el punt d'enganxada de `Defaults` amb el registre real de SMAppService.
    /// Cridar-ho un cop des de l'AppDelegate en arrencar.
    @MainActor
    public static func install(into defaults: Defaults) {
        defaults.onLaunchAtLoginChanged = { enabled in
            do {
                try setEnabled(enabled)
            } catch {
                logger.error("LoginItem: no s'ha pogut canviar l'inici automàtic: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Detecta si el binari en execució és dins d'un bundle .app (Contents/MacOS/...),
    /// que és el requisit de SMAppService per funcionar.
    private static var isRunningFromAppBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }
}
