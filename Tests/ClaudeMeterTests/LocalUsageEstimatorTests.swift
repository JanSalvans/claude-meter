import Foundation
import Testing
@testable import ClaudeMeterCore

/// Entorn aïllat per a cada prova: directori temporal propi i UserDefaults propi.
/// Les proves de swift-testing corren en paral·lel, per això res no pot ser compartit.
final class EstimatorFixture {
    let root: URL
    let projectsDirectory: URL
    let project: URL
    let cacheURL: URL
    let defaults: UserDefaults
    let suiteName: String

    init() throws {
        let id = UUID().uuidString
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudeMeterTests-\(id)", isDirectory: true)
        projectsDirectory = root.appendingPathComponent("projects", isDirectory: true)
        project = projectsDirectory.appendingPathComponent("proj", isDirectory: true)
        cacheURL = root.appendingPathComponent("estimator-cache.json")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        suiteName = "ClaudeMeterTests.estimator.\(id)"
        defaults = UserDefaults(suiteName: suiteName)!
        // Sostres rodons perquè els càlculs de les proves siguin llegibles.
        defaults.set(1000.0, forKey: LocalUsageEstimator.sessionBudgetKey)
        defaults.set(2000.0, forKey: LocalUsageEstimator.weeklyBudgetKey)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    /// Pesos d'1 i 0 per poder comptar els tokens a mà.
    func makeEstimator(weights: LocalUsageEstimator.Weights = .init(input: 1, output: 1, cacheCreation: 1, cacheRead: 0)) -> LocalUsageEstimator {
        LocalUsageEstimator(
            projectsDirectory: projectsDirectory,
            cacheURL: cacheURL,
            weights: weights,
            defaults: defaults
        )
    }

    func line(at date: Date, input: Int, output: Int, cacheRead: Int = 0) throws -> String {
        let payload: [String: Any] = [
            "type": "assistant",
            "timestamp": ISO8601DateFormatter().string(from: date),
            "message": [
                "model": "claude-opus-5",
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": cacheRead
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    var transcript: URL { project.appendingPathComponent("a.jsonl") }

    func write(_ lines: [String], append: Bool = false) throws {
        try appendRaw(lines.joined(separator: "\n") + "\n", append: append)
    }

    func appendRaw(_ text: String, append: Bool = true) throws {
        if append, let handle = try? FileHandle(forWritingTo: transcript) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: transcript)
        }
    }
}

@Suite("Estimador local")
struct LocalUsageEstimatorTests {

    @Test("suma bàsica dins de la finestra")
    func sumaBasica() throws {
        let fixture = try EstimatorFixture()
        let now = Date()
        try fixture.write([
            fixture.line(at: now.addingTimeInterval(-600), input: 100, output: 50),
            fixture.line(at: now.addingTimeInterval(-300), input: 200, output: 150)
        ])

        let snapshot = fixture.makeEstimator().snapshot(now: now)
        #expect(snapshot.source == .estimated)
        #expect(snapshot.message != nil)
        // 500 tokens ponderats sobre un sostre de 1000.
        #expect(approx(snapshot.session?.utilization, 0.5, 0.001))
        #expect(approx(snapshot.week?.utilization, 0.25, 0.001))
    }

    @Test("la lectura de cache compta molt poc")
    func pesDeCacheRead() throws {
        let fixture = try EstimatorFixture()
        let now = Date()
        try fixture.write([fixture.line(at: now.addingTimeInterval(-60), input: 0, output: 0, cacheRead: 1_000_000)])
        // Amb pes 0,1 el milió de tokens de lectura passa a comptar com 100.000.
        let snapshot = fixture.makeEstimator(weights: .init()).snapshot(now: now)
        #expect(approx(snapshot.week?.utilization, 100_000.0 / 2000, 0.01))
    }

    @Test("retall per les finestres de set dies i de cinc hores")
    func retallPerFinestra() throws {
        let fixture = try EstimatorFixture()
        let now = Date()
        try fixture.write([
            fixture.line(at: now.addingTimeInterval(-10 * 24 * 3600), input: 5000, output: 0), // fora de tot
            fixture.line(at: now.addingTimeInterval(-3 * 24 * 3600), input: 400, output: 0),   // només a la setmana
            fixture.line(at: now.addingTimeInterval(-1800), input: 100, output: 0)             // a totes dues
        ])

        let snapshot = fixture.makeEstimator().snapshot(now: now)
        #expect(approx(snapshot.week?.utilization, 500.0 / 2000, 0.001))
        #expect(approx(snapshot.session?.utilization, 100.0 / 1000, 0.001))
    }

    @Test("la finestra de cinc hores porta data de reinici")
    func dataDeReinici() throws {
        let fixture = try EstimatorFixture()
        let now = Date()
        try fixture.write([fixture.line(at: now.addingTimeInterval(-900), input: 100, output: 0)])
        let resets = try #require(fixture.makeEstimator().snapshot(now: now).session?.resetsAt)
        #expect(resets > now)
        #expect(resets.timeIntervalSince(now) <= LocalUsageEstimator.sessionWindow)
    }

    @Test("la memòria cau no compta dos cops")
    func cauSenseDuplicats() throws {
        let fixture = try EstimatorFixture()
        let now = Date()
        try fixture.write([fixture.line(at: now.addingTimeInterval(-600), input: 300, output: 0)])

        let estimator = fixture.makeEstimator()
        let first = estimator.snapshot(now: now)
        let second = estimator.snapshot(now: now)
        #expect(first.week?.utilization == second.week?.utilization)

        // Instància nova amb la mateixa memòria cau desada: tampoc no ha de duplicar.
        let third = fixture.makeEstimator().snapshot(now: now)
        #expect(approx(third.week?.utilization, 300.0 / 2000, 0.001))
    }

    @Test("només es llegeix la cua nova")
    func nomesLaCuaNova() throws {
        let fixture = try EstimatorFixture()
        let now = Date()
        try fixture.write([fixture.line(at: now.addingTimeInterval(-600), input: 300, output: 0)])

        let estimator = fixture.makeEstimator()
        _ = estimator.snapshot(now: now)

        try fixture.write([fixture.line(at: now.addingTimeInterval(-60), input: 200, output: 0)], append: true)
        #expect(approx(estimator.snapshot(now: now).week?.utilization, 500.0 / 2000, 0.001))
    }

    @Test("una línia incompleta no es consumeix fins que té salt de línia")
    func liniaIncompleta() throws {
        let fixture = try EstimatorFixture()
        let now = Date()
        let complete = try fixture.line(at: now.addingTimeInterval(-600), input: 300, output: 0)
        let partial = try fixture.line(at: now.addingTimeInterval(-60), input: 200, output: 0)
        let half = String(partial.prefix(partial.count / 2))
        try fixture.appendRaw(complete + "\n" + half, append: false)

        let estimator = fixture.makeEstimator()
        #expect(approx(estimator.snapshot(now: now).week?.utilization, 300.0 / 2000, 0.001))

        // Ara completem la línia: s'ha de comptar sencera i una sola vegada.
        try fixture.appendRaw(String(partial.dropFirst(half.count)) + "\n")
        #expect(approx(estimator.snapshot(now: now).week?.utilization, 500.0 / 2000, 0.001))
    }

    @Test("directori sense transcripts")
    func directoriBuit() throws {
        let fixture = try EstimatorFixture()
        let snapshot = fixture.makeEstimator().snapshot(now: Date())
        #expect(snapshot.source == .estimated)
        #expect(snapshot.isEmpty)
        #expect(snapshot.message != nil)
    }

    @Test("sostres per defecte quan no hi ha preferència")
    func sostresPerDefecte() throws {
        let fixture = try EstimatorFixture()
        fixture.defaults.removeObject(forKey: LocalUsageEstimator.sessionBudgetKey)
        fixture.defaults.removeObject(forKey: LocalUsageEstimator.weeklyBudgetKey)
        let budgets = fixture.makeEstimator().budgets
        #expect(budgets.session == LocalUsageEstimator.defaultSessionBudget)
        #expect(budgets.week == LocalUsageEstimator.defaultWeeklyBudget)
    }

    @Test("el bloc de cinc hores arrenca amb el primer missatge del bloc vigent")
    func blocDeCincHores() {
        let hour = 3600.0
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func index(_ offset: Double) -> Int { LocalUsageEstimator.hourIndex(base.addingTimeInterval(offset)) }

        // Activitat fa 9 h i fa 1 h: el bloc vigent és el segon, no el primer.
        let buckets: [Int: Double] = [index(-9 * hour): 10, index(-1 * hour): 20]
        let window = LocalUsageEstimator.currentSessionWindow(buckets: buckets, now: base)
        #expect(approx(window.end.timeIntervalSince(window.start), LocalUsageEstimator.sessionWindow, 1))
        #expect(LocalUsageEstimator.sum(buckets, from: window.start, to: window.end) == 20)
    }
}
