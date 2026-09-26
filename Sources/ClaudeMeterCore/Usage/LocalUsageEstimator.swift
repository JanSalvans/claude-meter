import Foundation

/// Estimador local: llegeix els transcripts de `~/.claude/projects` quan l'endpoint oficial no va.
///
/// Suposicions (totes ajustables, cap ve documentada per Anthropic):
///   - Pesos per tipus de token, aproximant el cost relatiu de cada un.
///   - Sostres de tokens per finestra, llegits de UserDefaults.
/// Per això el snapshot sempre surt amb `source == .estimated` i amb un `message` que ho diu.
public final class LocalUsageEstimator: UsageProviding {

    /// Pes de cada mena de token dins la suma ponderada.
    public struct Weights: Sendable, Equatable {
        public var input: Double
        public var output: Double
        public var cacheCreation: Double
        /// La lectura de cache és molt més barata que la resta, per això compta poc.
        public var cacheRead: Double

        public init(input: Double = 1.0, output: Double = 1.0, cacheCreation: Double = 1.25, cacheRead: Double = 0.1) {
            self.input = input
            self.output = output
            self.cacheCreation = cacheCreation
            self.cacheRead = cacheRead
        }
    }

    public struct Budgets: Sendable, Equatable {
        public var session: Double
        public var week: Double
        public init(session: Double, week: Double) {
            self.session = session
            self.week = week
        }
    }

    /// Claus de UserDefaults per sobreescriure els sostres.
    public static let sessionBudgetKey = "estimatorSessionTokenBudget"
    public static let weeklyBudgetKey = "estimatorWeeklyTokenBudget"

    /// Sostres per defecte. Són conjectures: no sabem el límit real de cap pla.
    public static let defaultSessionBudget: Double = 25_000_000
    public static let defaultWeeklyBudget: Double = 250_000_000

    /// Durada del bloc curt de Claude Code.
    public static let sessionWindow: TimeInterval = 5 * 3600
    public static let weekWindow: TimeInterval = 7 * 24 * 3600

    private let projectsDirectory: URL
    private let cacheURL: URL
    private let weights: Weights
    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var cache: EstimatorCache

    public init(
        projectsDirectory: URL = LocalUsageEstimator.defaultProjectsDirectory,
        cacheURL: URL = LocalUsageEstimator.defaultCacheURL,
        weights: Weights = Weights(),
        defaults: UserDefaults = .standard
    ) {
        self.projectsDirectory = projectsDirectory
        self.cacheURL = cacheURL
        self.weights = weights
        self.defaults = defaults
        self.cache = EstimatorCache.load(from: cacheURL) ?? EstimatorCache()
    }

    public static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    public static var defaultCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeMeter", isDirectory: true)
            .appendingPathComponent("estimator-cache.json")
    }

    public var budgets: Budgets {
        let session = defaults.double(forKey: Self.sessionBudgetKey)
        let week = defaults.double(forKey: Self.weeklyBudgetKey)
        return Budgets(
            session: session > 0 ? session : Self.defaultSessionBudget,
            week: week > 0 ? week : Self.defaultWeeklyBudget
        )
    }

    public func fetch() async -> UsageSnapshot {
        snapshot(now: Date())
    }

    /// Versió síncrona amb `now` injectable, per poder provar les finestres.
    public func snapshot(now: Date) -> UsageSnapshot {
        lock.lock()
        defer { lock.unlock() }

        scanIncrementally(now: now)
        cache.prune(before: now.addingTimeInterval(-Self.weekWindow - 3600))
        cache.save(to: cacheURL)

        let buckets = cache.mergedBuckets()
        guard !buckets.isEmpty else {
            return UsageSnapshot(
                session: nil,
                week: nil,
                source: .estimated,
                fetchedAt: now,
                message: "Estimació local: encara no hi ha activitat recent."
            )
        }

        let limits = budgets
        let window = Self.currentSessionWindow(buckets: buckets, now: now)
        let sessionTokens = Self.sum(buckets, from: window.start, to: window.end)
        let weekTokens = Self.sum(buckets, from: now.addingTimeInterval(-Self.weekWindow), to: now)

        let session = UsageMetric(utilization: sessionTokens / limits.session, resetsAt: window.end)
        let week = UsageMetric(utilization: weekTokens / limits.week, resetsAt: nil)

        return UsageSnapshot(
            session: session,
            week: week,
            source: .estimated,
            fetchedAt: now,
            message: "Estimació a partir dels transcripts locals. No és la xifra oficial."
        )
    }

    // MARK: - Escaneig

    /// Passa per tots els `.jsonl` i llegeix només la cua nova de cada un.
    private func scanIncrementally(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.weekWindow)
        guard let projects = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var seen = Set<String>()
        for project in projects {
            let files = (try? fileManager.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for file in files where file.pathExtension == "jsonl" {
                let key = file.path
                seen.insert(key)
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(values?.fileSize ?? 0)
                let modified = values?.contentModificationDate ?? .distantPast

                var entry = cache.files[key] ?? FileState()
                // Si el fitxer ha encongit, l'han rotat: tornem a començar.
                if size < entry.offset {
                    entry = FileState()
                }
                // Res de nou per llegir.
                if size == entry.offset { cache.files[key] = entry; continue }
                // Fitxer antic i mai llegit: no aporta res a cap finestra.
                if entry.offset == 0 && modified < cutoff {
                    entry.offset = size
                    cache.files[key] = entry
                    continue
                }

                readTail(of: file, state: &entry)
                cache.files[key] = entry
            }
        }

        // Fitxers desapareguts: fora de la memòria cau.
        for key in cache.files.keys where !seen.contains(key) {
            cache.files.removeValue(forKey: key)
        }
    }

    /// Llegeix per trossos des de l'offset desat i només avança fins a l'últim salt de línia complet.
    private func readTail(of url: URL, state: inout FileState) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(max(0, state.offset)))
        } catch {
            return
        }

        let chunkSize = 256 * 1024
        var pending = Data()
        var consumed = state.offset

        while true {
            let chunk = (try? handle.read(upToCount: chunkSize)) ?? Data()
            if chunk.isEmpty { break }
            pending.append(chunk)

            while let index = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<index]
                consumed += Int64(pending.distance(from: pending.startIndex, to: index)) + 1
                pending = pending[pending.index(after: index)...]
                ingest(line: line, into: &state)
            }
            // La cua sense salt de línia es queda per a la passada següent.
        }
        state.offset = consumed
    }

    /// Passa una línia a tokens ponderats i els suma al calaix de l'hora corresponent.
    private func ingest(line: Data, into state: inout FileState) {
        guard line.count > 2 else { return }
        // Filtre barat abans de parsejar JSON: només ens interessen les respostes amb ús.
        guard line.range(of: Data("\"usage\"".utf8)) != nil,
              line.range(of: Data("\"assistant\"".utf8)) != nil else { return }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              (object["type"] as? String) == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let timestampRaw = object["timestamp"],
              let timestamp = CredentialDate.parse(timestampRaw) else { return }

        func tokens(_ key: String) -> Double {
            CredentialDate.number(from: usage[key] ?? 0) ?? 0
        }

        let weighted = tokens("input_tokens") * weights.input
            + tokens("output_tokens") * weights.output
            + tokens("cache_creation_input_tokens") * weights.cacheCreation
            + tokens("cache_read_input_tokens") * weights.cacheRead

        guard weighted > 0 else { return }
        state.add(weighted, at: timestamp)
    }

    // MARK: - Finestres

    /// Suma els calaixos horaris que cauen dins l'interval.
    static func sum(_ buckets: [Int: Double], from: Date, to: Date) -> Double {
        let first = hourIndex(from)
        let last = hourIndex(to)
        var total: Double = 0
        for (hour, value) in buckets where hour >= first && hour <= last {
            total += value
        }
        return total
    }

    /// Blocs de 5 h a l'estil de Claude Code: el bloc arrenca a l'hora en punt
    /// del primer missatge posterior al final del bloc anterior.
    static func currentSessionWindow(buckets: [Int: Double], now: Date) -> (start: Date, end: Date) {
        let hours = buckets.filter { $0.value > 0 }.keys.sorted()
        let blockHours = Int(sessionWindow / 3600)
        var start = hourIndex(now)
        var found = false
        for hour in hours {
            if !found || hour >= start + blockHours {
                start = hour
                found = true
            }
        }
        if !found { start = hourIndex(now) }
        var blockStart = start
        // Si l'últim bloc ja ha caducat, la finestra vigent és la que conté ara mateix.
        if hourIndex(now) >= blockStart + blockHours {
            blockStart = hourIndex(now)
        }
        let startDate = Date(timeIntervalSince1970: TimeInterval(blockStart) * 3600)
        return (startDate, startDate.addingTimeInterval(sessionWindow))
    }

    /// Hora UTC des de l'epoch. Els calaixos horaris mantenen la memòria cau petita.
    static func hourIndex(_ date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / 3600))
    }
}

// MARK: - Memòria cau

/// Estat desat per fitxer: fins on l'hem llegit i què hi hem comptat.
struct FileState: Codable {
    var offset: Int64 = 0
    /// Tokens ponderats per hora epoch. Hi cap una setmana sencera en poques desenes d'entrades.
    var buckets: [Int: Double] = [:]

    mutating func add(_ value: Double, at date: Date) {
        let hour = LocalUsageEstimator.hourIndex(date)
        buckets[hour, default: 0] += value
    }
}

struct EstimatorCache: Codable {
    var version: Int = 1
    var files: [String: FileState] = [:]

    static func load(from url: URL) -> EstimatorCache? {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(EstimatorCache.self, from: data),
              cache.version == 1 else { return nil }
        return cache
    }

    func save(to url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Treu els calaixos que ja han sortit de la finestra de set dies.
    mutating func prune(before date: Date) {
        let limit = LocalUsageEstimator.hourIndex(date)
        for key in Array(files.keys) {
            guard var state = files[key] else { continue }
            let kept = state.buckets.filter { $0.key >= limit }
            state.buckets = kept
            files[key] = state
        }
    }

    func mergedBuckets() -> [Int: Double] {
        var merged: [Int: Double] = [:]
        for state in files.values {
            for (hour, value) in state.buckets {
                merged[hour, default: 0] += value
            }
        }
        return merged
    }
}
