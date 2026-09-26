import AppKit

// El codi de nivell superior ja corre al fil principal, però el compilador no ho
// dedueix: assumeIsolated li ho confirma perquè pugui tocar tipus @MainActor.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    // Accessori: viu a la barra de menú, no al Dock ni al Cmd+Tab.
    application.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    application.delegate = delegate
    // Retenim el delegat: NSApplication no ho fa.
    objc_setAssociatedObject(application, "ClaudeMeterDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    application.run()
}
