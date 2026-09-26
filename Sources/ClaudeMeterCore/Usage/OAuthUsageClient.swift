import Foundation

/// Errors del client oficial. El poller els mira per decidir si espaia o si cau a l'estimador.
public enum UsageClientError: Error, Equatable, LocalizedError {
    /// 401 o 403: el token no serveix i cal tornar a iniciar sessió a Claude Code.
    case invalidToken
    /// 429: massa peticions. `retryAfter` són segons, si el servidor ens els diu.
    case rateLimited(retryAfter: TimeInterval?)
    /// Codi HTTP inesperat.
    case httpError(status: Int)
    /// Fallada de xarxa o de sessió.
    case network(String)
    /// La resposta no és JSON o no hi hem sabut trobar cap mètrica.
    case unreadablePayload
    /// No hem pogut llegir la credencial del clauer.
    case credentials(CredentialsError)

    public var errorDescription: String? { userMessage }

    /// Text curt en català, pensat per ensenyar-lo al menú.
    public var userMessage: String {
        switch self {
        case .invalidToken:
            return "Sessió de Claude Code caducada. Torna a iniciar sessió."
        case .rateLimited:
            return "Massa peticions. Ho tornem a provar d'aquí a una estona."
        case .httpError(let status):
            return "El servidor ha respost amb l'error \(status)."
        case .network:
            return "Sense connexió amb l'API d'Anthropic."
        case .unreadablePayload:
            return "La resposta del servidor no s'ha pogut interpretar."
        case .credentials(let error):
            return error.errorDescription ?? "No s'ha pogut llegir la credencial."
        }
    }
}

/// Proveïdor que sap llançar errors tipats, a més de complir `UsageProviding`.
/// Existeix perquè `UsageProviding.fetch()` no llança i el poller necessita saber què ha fallat.
public protocol ThrowingUsageProviding: UsageProviding {
    func fetchThrowing() async throws -> UsageSnapshot
}

// MARK: - Parser

/// Heurística pura per llegir la resposta de `/api/oauth/usage`.
/// El format real encara no el sabem, per això va a part i es pot provar sense xarxa.
public enum UsagePayloadParser {
    /// Rols que pot tenir una fulla del JSON.
    private enum Role { case utilization, reset }

    /// Famílies de finestra que ens interessen.
    private enum Bucket { case session, week, weekOpus }

    private struct Candidate {
        var value: Any
        var score: Int
    }

    /// Normalitza per poder comparar `five_hour`, `fiveHour` i `FIVE-HOUR`.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Passa un percentatge a fracció 0..1.
    /// Qualsevol valor per damunt d'1 l'entenem com a percentatge (42 -> 0,42; 105 -> 1,05).
    public static func normalizeUtilization(_ raw: Double) -> Double? {
        guard raw.isFinite, raw >= 0 else { return nil }
        return raw > 1 ? raw / 100 : raw
    }

    /// Accepta ISO 8601 i epoch en segons o mil·lisegons.
    public static func normalizeDate(_ value: Any) -> Date? {
        CredentialDate.parse(value)
    }

    /// Recorre el JSON i munta un snapshot amb el que hagi trobat. `nil` si no hi ha res d'aprofitable.
    public static func parse(_ json: Any, fetchedAt: Date) -> UsageSnapshot? {
        var best: [Bucket: [Role: Candidate]] = [:]

        func consider(bucket: Bucket, role: Role, value: Any, score: Int) {
            var roles = best[bucket] ?? [:]
            if let existing = roles[role], existing.score >= score { return }
            roles[role] = Candidate(value: value, score: score)
            best[bucket] = roles
        }

        walk(json, path: []) { path, value in
            guard let last = path.last else { return }
            let components = path.map(normalize)
            let leaf = normalize(last)

            // La família surt de tot el camí: qualsevol tros pot portar-la.
            let hasOpus = components.contains { $0.contains("opus") }
            var bucket: Bucket?
            if components.contains(where: { $0.contains("fivehour") || $0.contains("session") }) {
                bucket = hasOpus ? nil : .session
            }
            if bucket == nil,
               components.contains(where: { $0.contains("sevenday") || $0.contains("week") }) {
                bucket = hasOpus ? .weekOpus : .week
            }
            guard var family = bucket else { return }

            // La profunditat penalitza: les claus de dalt són més fiables que les niades.
            let depthPenalty = path.count

            if let score = resetScore(leaf) {
                consider(bucket: family, role: .reset, value: value, score: score * 10 - depthPenalty)
                return
            }
            if let score = utilizationScore(leaf) {
                consider(bucket: family, role: .utilization, value: value, score: score * 10 - depthPenalty)
                return
            }
            // Cas pla: `{"five_hour": 0.42}`, on la clau de la família ja duu el número.
            if CredentialDate.number(from: value) != nil, isFamilyKey(leaf) {
                if leaf.contains("opus") { family = .weekOpus }
                consider(bucket: family, role: .utilization, value: value, score: 10 - depthPenalty)
            }
        }

        func metric(_ bucket: Bucket) -> UsageMetric? {
            guard let roles = best[bucket],
                  let rawUtilization = roles[.utilization]?.value,
                  let number = CredentialDate.number(from: rawUtilization),
                  let utilization = normalizeUtilization(number) else { return nil }
            let resets = roles[.reset].flatMap { normalizeDate($0.value) }
            return UsageMetric(utilization: utilization, resetsAt: resets)
        }

        let session = metric(.session)
        let week = metric(.week)
        let weekOpus = metric(.weekOpus)
        guard session != nil || week != nil || weekOpus != nil else { return nil }

        return UsageSnapshot(
            session: session,
            week: week,
            weekOpus: weekOpus,
            source: .official,
            fetchedAt: fetchedAt,
            message: nil
        )
    }

    private static func isFamilyKey(_ leaf: String) -> Bool {
        ["fivehour", "session", "sevenday", "week"].contains { leaf.contains($0) }
    }

    /// Com de segurs estem que aquesta clau és la utilització. Més alt, més fiable.
    private static func utilizationScore(_ leaf: String) -> Int? {
        if leaf.contains("utilization") { return 5 }
        if leaf.contains("usedpct") || leaf.contains("usedpercent") { return 4 }
        if leaf.contains("percent") || leaf.contains("pct") { return 3 }
        if leaf == "usage" || leaf.contains("used") { return 2 }
        return nil
    }

    private static func resetScore(_ leaf: String) -> Int? {
        if leaf.contains("resetsat") { return 5 }
        if leaf.contains("resetat") || leaf.contains("resettime") { return 4 }
        if leaf.contains("expiresat") { return 3 }
        if leaf.contains("reset") { return 2 }
        return nil
    }

    /// Claus que solen donar nom a una finestra quan el format usa llistes en comptes d'objectes.
    private static let labelKeys = ["name", "type", "id", "key", "window", "limit", "limittype"]

    /// Visita cada fulla escalar del JSON amb el camí de claus que hi porta.
    /// Si un objecte s'identifica amb un camp de nom (`{"name": "session", ...}`),
    /// aquest nom s'afegeix al camí perquè compti com si fos una clau.
    private static func walk(_ node: Any, path: [String], visit: ([String], Any) -> Void) {
        if let dict = node as? [String: Any] {
            var base = path
            for (key, value) in dict {
                if labelKeys.contains(normalize(key)), let label = value as? String {
                    base = path + [label]
                    break
                }
            }
            for (key, value) in dict {
                walk(value, path: base + [key], visit: visit)
            }
        } else if let array = node as? [Any] {
            for element in array {
                walk(element, path: path, visit: visit)
            }
        } else if !(node is NSNull) {
            visit(path, node)
        }
    }
}

// MARK: - Client

/// Client de l'endpoint oficial `/api/oauth/usage`.
public final class OAuthUsageClient: ThrowingUsageProviding {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession
    private let tokenProvider: () throws -> ClaudeCredentials
    private let endpoint: URL

    public init(
        endpoint: URL = OAuthUsageClient.endpoint,
        session: URLSession? = nil,
        tokenProvider: @escaping () throws -> ClaudeCredentials = { try KeychainCredentials.load() }
    ) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetch() async -> UsageSnapshot {
        do {
            return try await fetchThrowing()
        } catch let error as UsageClientError {
            return .unavailable(message: error.userMessage)
        } catch {
            return .unavailable(message: "No s'ha pogut consultar l'ús.")
        }
    }

    public func fetchThrowing() async throws -> UsageSnapshot {
        let credentials: ClaudeCredentials
        do {
            credentials = try tokenProvider()
        } catch let error as CredentialsError {
            throw error == .notFound ? UsageClientError.credentials(error) : UsageClientError.invalidToken
        } catch {
            throw UsageClientError.credentials(.malformed("error desconegut"))
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Mai no incloem la petició sencera al missatge: hi aniria el token.
            throw UsageClientError.network((error as NSError).localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.network("resposta sense codi HTTP")
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw UsageClientError.invalidToken
        case 429:
            throw UsageClientError.rateLimited(retryAfter: Self.retryAfter(from: http))
        default:
            throw UsageClientError.httpError(status: http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data),
              let snapshot = UsagePayloadParser.parse(json, fetchedAt: Date()) else {
            throw UsageClientError.unreadablePayload
        }
        return snapshot
    }

    /// `Retry-After` pot venir en segons o com a data HTTP.
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }
}
