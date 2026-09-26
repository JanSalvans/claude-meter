import Foundation
import Testing
@testable import ClaudeMeterCore

// MARK: - Dobles de prova

/// Proveïdor oficial fals: pot respondre bé, llançar o entretenir-se.
final class FakeOfficialProvider: ThrowingUsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<UsageSnapshot, UsageClientError>
    private var storedDelay: TimeInterval = 0
    private var callCount = 0

    init(result: Result<UsageSnapshot, UsageClientError>, delay: TimeInterval = 0) {
        self.storedResult = result
        self.storedDelay = delay
    }

    var result: Result<UsageSnapshot, UsageClientError> {
        get { lock.lock(); defer { lock.unlock() }; return storedResult }
        set { lock.lock(); storedResult = newValue; lock.unlock() }
    }

    var calls: Int {
        lock.lock(); defer { lock.unlock() }
        return callCount
    }

    func fetchThrowing() async throws -> UsageSnapshot {
        lock.lock()
        callCount += 1
        let delay = storedDelay
        let outcome = storedResult
        lock.unlock()
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return try outcome.get()
    }

    func fetch() async -> UsageSnapshot {
        (try? await fetchThrowing()) ?? .unavailable(message: "proveïdor fals")
    }
}

final class FakeFallbackProvider: UsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: UsageSnapshot
    private var callCount = 0

    init(snapshot: UsageSnapshot) { self.snapshot = snapshot }

    var calls: Int {
        lock.lock(); defer { lock.unlock() }
        return callCount
    }

    func fetch() async -> UsageSnapshot {
        lock.lock(); callCount += 1; lock.unlock()
        return snapshot
    }
}

final class SpyObserver: UsageObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var received: [UsageSnapshot] = []
    private var offMainThread = false

    func usageDidUpdate(_ snapshot: UsageSnapshot) {
        let isMain = Thread.isMainThread
        lock.lock()
        received.append(snapshot)
        if !isMain { offMainThread = true }
        lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return received.count
    }

    var sawNonMainThread: Bool {
        lock.lock(); defer { lock.unlock() }
        return offMainThread
    }
}

// MARK: - Proves

@Suite("Poller")
struct UsagePollerTests {
    private let good = UsageSnapshot(
        session: UsageMetric(utilization: 0.4, resetsAt: nil),
        week: UsageMetric(utilization: 0.2, resetsAt: nil),
        source: .official
    )
    private let estimate = UsageSnapshot(
        session: UsageMetric(utilization: 0.7, resetsAt: nil),
        week: UsageMetric(utilization: 0.3, resetsAt: nil),
        source: .estimated,
        message: "Estimació local."
    )
    private let config = UsagePoller.Configuration(
        baseInterval: 0.05,
        maxInterval: 0.4,
        invalidTokenInterval: 0.2
    )

    private func poller(_ official: UsageProviding, _ fallback: UsageProviding) -> UsagePoller {
        UsagePoller(official: official, fallback: fallback, configuration: config)
    }

    /// Espera fins que la condició es compleixi o se superi el límit, cedint el torn.
    private func wait(upTo seconds: Double = 2, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test("camí feliç: fa servir l'oficial i no toca l'estimador")
    func camiFeliç() async {
        let official = FakeOfficialProvider(result: .success(good))
        let fallback = FakeFallbackProvider(snapshot: estimate)
        let poller = poller(official, fallback)

        let snapshot = await poller.runCycle()
        #expect(snapshot?.source == .official)
        #expect(poller.latest?.session?.utilization == 0.4)
        #expect(fallback.calls == 0)
        #expect(poller.currentPollInterval == 0.05)
    }

    @Test("cau a l'estimador quan l'oficial peta")
    func fallback() async {
        let official = FakeOfficialProvider(result: .failure(.network("sense xarxa")))
        let fallback = FakeFallbackProvider(snapshot: estimate)
        let poller = poller(official, fallback)

        let snapshot = await poller.runCycle()
        #expect(snapshot?.source == .estimated)
        #expect(snapshot?.session?.utilization == 0.7)
        #expect(fallback.calls == 1)
        // El missatge ha de dir per què no hi ha xifres oficials.
        #expect(snapshot?.message?.contains("Sense connexió") == true)
    }

    @Test("estimador buit dona un snapshot no disponible")
    func estimadorBuit() async {
        let poller = poller(
            FakeOfficialProvider(result: .failure(.unreadablePayload)),
            FakeFallbackProvider(snapshot: .unavailable(message: "res"))
        )
        let snapshot = await poller.runCycle()
        #expect(snapshot?.source == .unavailable)
        #expect(snapshot?.message != nil)
    }

    @Test("backoff exponencial amb sostre i recuperació")
    func backoff() async {
        let official = FakeOfficialProvider(result: .failure(.network("caiguda")))
        let poller = poller(official, FakeFallbackProvider(snapshot: estimate))

        await poller.runCycle()
        #expect(approx(poller.currentPollInterval, 0.1))
        await poller.runCycle()
        #expect(approx(poller.currentPollInterval, 0.2))
        await poller.runCycle()
        #expect(approx(poller.currentPollInterval, 0.4))
        await poller.runCycle()
        // Sostre.
        #expect(approx(poller.currentPollInterval, 0.4))

        official.result = .success(good)
        await poller.runCycle()
        #expect(approx(poller.currentPollInterval, 0.05))
    }

    @Test("el rate limit respecta Retry-After")
    func retryAfter() async {
        let poller = poller(
            FakeOfficialProvider(result: .failure(.rateLimited(retryAfter: 0.3))),
            FakeFallbackProvider(snapshot: estimate)
        )
        await poller.runCycle()
        #expect(approx(poller.currentPollInterval, 0.3))
    }

    @Test("429 sense Retry-After fa backoff normal")
    func rateLimitSenseCapcalera() async {
        let poller = poller(
            FakeOfficialProvider(result: .failure(.rateLimited(retryAfter: nil))),
            FakeFallbackProvider(snapshot: estimate)
        )
        await poller.runCycle()
        #expect(approx(poller.currentPollInterval, 0.1))
    }

    @Test("token invàlid: espaia i explica el motiu")
    func tokenInvalid() async {
        let poller = poller(
            FakeOfficialProvider(result: .failure(.invalidToken)),
            FakeFallbackProvider(snapshot: estimate)
        )
        let snapshot = await poller.runCycle()
        #expect(approx(poller.currentPollInterval, 0.2))
        #expect(snapshot?.message?.contains("Sessió de Claude Code caducada") == true)
    }

    @Test("el client oficial llança errors tipats")
    func errorsTipats() async {
        let official = FakeOfficialProvider(result: .failure(.invalidToken))
        await #expect(throws: UsageClientError.invalidToken) {
            _ = try await official.fetchThrowing()
        }
        official.result = .failure(.rateLimited(retryAfter: 30))
        await #expect(throws: UsageClientError.self) {
            _ = try await official.fetchThrowing()
        }
    }

    @Test("no hi ha crides solapades")
    func senseSolapament() async {
        let official = FakeOfficialProvider(result: .success(good), delay: 0.3)
        let poller = poller(official, FakeFallbackProvider(snapshot: estimate))

        async let first = poller.runCycle()
        // Deixem que la primera passada entri abans de demanar-ne una altra.
        try? await Task.sleep(nanoseconds: 50_000_000)
        async let second = poller.runCycle()

        let results = await [first, second]
        #expect(results.compactMap { $0 }.count == 1)
        #expect(official.calls == 1)
        #expect(poller.cycleCount == 1)
    }

    @Test("els observadors reben al fil principal i es poden treure")
    @MainActor
    func observadors() async {
        let poller = poller(
            FakeOfficialProvider(result: .success(good)),
            FakeFallbackProvider(snapshot: estimate)
        )
        let spy = SpyObserver()
        poller.addObserver(spy)

        await poller.runCycle()
        await wait { spy.count == 1 }
        #expect(spy.count == 1)
        #expect(spy.sawNonMainThread == false)

        poller.removeObserver(spy)
        await poller.runCycle()
        await wait(upTo: 0.3) { spy.count > 1 }
        #expect(spy.count == 1)
    }

    @Test("un observador alliberat no reté res ni fa petar el poller")
    @MainActor
    func observadorFeble() async {
        let poller = poller(
            FakeOfficialProvider(result: .success(good)),
            FakeFallbackProvider(snapshot: estimate)
        )
        var observer: SpyObserver? = SpyObserver()
        poller.addObserver(observer!)
        observer = nil

        let snapshot = await poller.runCycle()
        #expect(snapshot?.source == .official)
    }

    @Test("start fa passades i stop les atura")
    func startIStop() async {
        let poller = poller(
            FakeOfficialProvider(result: .success(good)),
            FakeFallbackProvider(snapshot: estimate)
        )
        poller.start()
        await wait(upTo: 3) { poller.cycleCount >= 2 }
        poller.stop()
        let afterStop = poller.cycleCount
        #expect(afterStop >= 2)

        try? await Task.sleep(nanoseconds: 250_000_000)
        // Com a molt pot acabar la passada que ja estava en marxa.
        #expect(poller.cycleCount - afterStop <= 1)
    }

    @Test("refreshNow publica un snapshot nou")
    func refreshNow() async {
        let poller = poller(
            FakeOfficialProvider(result: .success(good)),
            FakeFallbackProvider(snapshot: estimate)
        )
        poller.refreshNow()
        await wait { poller.latest != nil }
        #expect(poller.latest?.source == .official)
    }
}
