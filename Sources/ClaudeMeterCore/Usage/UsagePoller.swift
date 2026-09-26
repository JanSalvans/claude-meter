import Foundation

/// Orquestra les consultes: primer l'endpoint oficial, i si falla, l'estimador local.
/// Manté l'últim snapshot bo i avisa els observadors sempre al fil principal.
public final class UsagePoller {

    /// Intervals i sostres, extrets perquè les proves puguin anar de pressa.
    public struct Configuration: Sendable {
        /// Interval normal entre consultes.
        public var baseInterval: TimeInterval
        /// Sostre del backoff exponencial.
        public var maxInterval: TimeInterval
        /// Interval quan el token no serveix: no val la pena insistir.
        public var invalidTokenInterval: TimeInterval

        public init(
            baseInterval: TimeInterval = 60,
            maxInterval: TimeInterval = 600,
            invalidTokenInterval: TimeInterval = 300
        ) {
            self.baseInterval = baseInterval
            self.maxInterval = maxInterval
            self.invalidTokenInterval = invalidTokenInterval
        }
    }

    private struct WeakObserver {
        weak var value: UsageObserver?
    }

    private let official: UsageProviding
    private let fallback: UsageProviding
    private let configuration: Configuration

    private let lock = NSRecursiveLock()
    private var observers: [WeakObserver] = []
    private var storedLatest: UsageSnapshot?
    private var currentInterval: TimeInterval
    private var isFetching = false
    private var loopTask: Task<Void, Never>?
    /// Comptador de passades acabades: les proves s'hi recolzen per saber quan hi ha hagut feina.
    private var completedCycles = 0

    public init(
        official: UsageProviding,
        fallback: UsageProviding,
        configuration: Configuration = Configuration()
    ) {
        self.official = official
        self.fallback = fallback
        self.configuration = configuration
        self.currentInterval = configuration.baseInterval
    }

    deinit {
        loopTask?.cancel()
    }

    // MARK: - Estat

    public var latest: UsageSnapshot? {
        withLock { storedLatest }
    }

    /// Interval que s'aplicarà a la pròxima espera. Útil per comprovar el backoff.
    public var currentPollInterval: TimeInterval {
        withLock { currentInterval }
    }

    public var cycleCount: Int {
        withLock { completedCycles }
    }

    // MARK: - Observadors

    public func addObserver(_ observer: UsageObserver) {
        let snapshot: UsageSnapshot? = withLock {
            observers.removeAll { $0.value == nil }
            if !observers.contains(where: { $0.value === observer }) {
                observers.append(WeakObserver(value: observer))
            }
            return storedLatest
        }
        if let snapshot {
            notify(snapshot)
        }
    }

    public func removeObserver(_ observer: UsageObserver) {
        withLock { observers.removeAll { $0.value == nil || $0.value === observer } }
    }

    private func notify(_ snapshot: UsageSnapshot) {
        let targets = withLock { observers.compactMap { $0.value } }
        guard !targets.isEmpty else { return }
        let deliver = {
            MainActor.assumeIsolated { targets.forEach { $0.usageDidUpdate(snapshot) } }
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }

    // MARK: - Cicle

    public func start() {
        let alreadyRunning = withLock { loopTask != nil }
        guard !alreadyRunning else { return }
        let task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runCycle()
                let wait = self.currentPollInterval
                try? await Task.sleep(nanoseconds: UInt64(max(0.01, wait) * 1_000_000_000))
            }
        }
        withLock { loopTask = task }
    }

    public func stop() {
        let task: Task<Void, Never>? = withLock {
            let current = loopTask
            loopTask = nil
            return current
        }
        task?.cancel()
    }

    /// Consulta immediata, per quan s'obre el menú. No fa res si ja n'hi ha una en marxa.
    public func refreshNow() {
        Task { [weak self] in
            await self?.runCycle()
        }
    }

    /// Una passada sencera. Retorna el snapshot publicat, o `nil` si s'ha saltat per solapament.
    @discardableResult
    public func runCycle() async -> UsageSnapshot? {
        guard beginCycle() else { return nil }
        let snapshot = await produceSnapshot()
        endCycle(with: snapshot)
        notify(snapshot)
        return snapshot
    }

    /// Marca l'inici d'una passada. Fals si ja n'hi havia una en marxa.
    private func beginCycle() -> Bool {
        withLock {
            if isFetching { return false }
            isFetching = true
            return true
        }
    }

    private func endCycle(with snapshot: UsageSnapshot) {
        withLock {
            storedLatest = snapshot
            isFetching = false
            completedCycles += 1
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func produceSnapshot() async -> UsageSnapshot {
        if let throwing = official as? ThrowingUsageProviding {
            do {
                let snapshot = try await throwing.fetchThrowing()
                setInterval(configuration.baseInterval)
                return snapshot
            } catch let error as UsageClientError {
                applyBackoff(for: error)
                return await fallbackSnapshot(reason: error.userMessage)
            } catch {
                applyBackoff(for: .network("desconegut"))
                return await fallbackSnapshot(reason: "No s'ha pogut consultar l'ús oficial.")
            }
        }

        // Proveïdor sense errors tipats: només podem mirar si el snapshot serveix.
        let snapshot = await official.fetch()
        if snapshot.source == .official && !snapshot.isEmpty {
            setInterval(configuration.baseInterval)
            return snapshot
        }
        bumpInterval()
        return await fallbackSnapshot(reason: snapshot.message ?? "Dades oficials no disponibles.")
    }

    private func fallbackSnapshot(reason: String) async -> UsageSnapshot {
        let snapshot = await fallback.fetch()
        let note = snapshot.message.map { "\(reason) \($0)" } ?? reason
        if snapshot.isEmpty {
            return .unavailable(message: note)
        }
        return UsageSnapshot(
            session: snapshot.session,
            week: snapshot.week,
            weekOpus: snapshot.weekOpus,
            source: snapshot.source,
            fetchedAt: snapshot.fetchedAt,
            message: note
        )
    }

    // MARK: - Backoff

    private func applyBackoff(for error: UsageClientError) {
        switch error {
        case .invalidToken, .credentials:
            // Token mort: no serveix de res martellejar.
            setInterval(configuration.invalidTokenInterval)
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                setInterval(min(max(retryAfter, configuration.baseInterval), configuration.maxInterval))
            } else {
                bumpInterval()
            }
        case .network, .httpError, .unreadablePayload:
            bumpInterval()
        }
    }

    private func bumpInterval() {
        withLock {
            let next = max(currentInterval, configuration.baseInterval) * 2
            currentInterval = min(next, configuration.maxInterval)
        }
    }

    private func setInterval(_ value: TimeInterval) {
        withLock { currentInterval = value }
    }
}
