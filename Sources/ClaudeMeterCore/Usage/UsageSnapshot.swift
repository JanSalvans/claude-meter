import Foundation

/// D'on surten les xifres que ensenyem.
public enum UsageSource: String, Sendable {
    /// Llegides de l'endpoint OAuth d'Anthropic. Coincideixen amb `/usage`.
    case official
    /// Calculades a partir dels transcripts locals. Aproximades.
    case estimated
    /// No hi ha cap dada fiable ara mateix.
    case unavailable
}

/// Una finestra de límit concreta: quant se n'ha gastat i quan es reinicia.
public struct UsageMetric: Equatable, Sendable {
    /// Fracció consumida, de 0 a 1. Pot passar d'1 si el servidor ho reporta així.
    public let utilization: Double
    /// Quan torna a zero aquesta finestra, si el servidor ens ho diu.
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    /// Percentatge arrodonit per ensenyar a la barra i al menú.
    public var percent: Int {
        Int((utilization * 100).rounded())
    }
}

/// Estat complet de l'ús en un instant donat.
public struct UsageSnapshot: Equatable, Sendable {
    /// Finestra curta (5 h). És la que ensenyem a la barra de menú.
    public let session: UsageMetric?
    /// Finestra setmanal de tots els models.
    public let week: UsageMetric?
    /// Finestra setmanal específica d'Opus, si el pla en té.
    public let weekOpus: UsageMetric?
    public let source: UsageSource
    public let fetchedAt: Date
    /// Motiu llegible quan alguna cosa ha anat malament, per ensenyar al menú.
    public let message: String?

    public init(
        session: UsageMetric?,
        week: UsageMetric?,
        weekOpus: UsageMetric? = nil,
        source: UsageSource,
        fetchedAt: Date = Date(),
        message: String? = nil
    ) {
        self.session = session
        self.week = week
        self.weekOpus = weekOpus
        self.source = source
        self.fetchedAt = fetchedAt
        self.message = message
    }

    public static func unavailable(message: String, at date: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(session: nil, week: nil, source: .unavailable, fetchedAt: date, message: message)
    }

    /// Cert si no hi ha cap mètrica utilitzable.
    public var isEmpty: Bool {
        session == nil && week == nil && weekOpus == nil
    }
}

/// Qualsevol cosa capaç de donar-nos un snapshot: endpoint oficial o estimador local.
public protocol UsageProviding: AnyObject {
    func fetch() async -> UsageSnapshot
}

/// Qui vol assabentar-se dels snapshots nous (barra de menú, avisos).
/// El poller sempre notifica al fil principal, per això el protocol hi va lligat.
@MainActor
public protocol UsageObserver: AnyObject {
    func usageDidUpdate(_ snapshot: UsageSnapshot)
}
