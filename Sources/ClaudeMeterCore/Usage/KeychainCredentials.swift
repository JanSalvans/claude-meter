import Foundation
import Security

/// Credencial OAuth de Claude Code llegida del clauer.
/// El token no s'imprimeix mai: `description` només diu si n'hi ha i quan caduca.
public struct ClaudeCredentials: CustomStringConvertible, Sendable {
    public let accessToken: String
    /// Instant de caducitat, si la credencial el porta.
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    public var description: String {
        let caducitat = expiresAt.map { ISO8601DateFormatter().string(from: $0) } ?? "sense data"
        return "ClaudeCredentials(token: <ocult>, caduca: \(caducitat))"
    }
}

public enum CredentialsError: Error, Equatable, LocalizedError {
    /// No hi ha cap entrada al clauer per al servei de Claude Code.
    case notFound
    /// Hi ha entrada, però el JSON no té la forma esperada.
    case malformed(String)
    /// La credencial existeix però ja ha caducat.
    case expired(Date)
    /// El clauer ha tornat un error de sistema (per exemple, accés denegat).
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "No s'ha trobat la credencial de Claude Code al clauer."
        case .malformed:
            return "La credencial del clauer no té el format esperat."
        case .expired:
            return "La credencial de Claude Code ha caducat. Torna a iniciar sessió."
        case .keychain:
            return "El clauer no ha deixat llegir la credencial de Claude Code."
        }
    }
}

/// Lectura de la credencial OAuth que desa Claude Code al clauer del sistema.
public enum KeychainCredentials {
    public static let service = "Claude Code-credentials"

    /// Llegeix i interpreta la credencial. Llança `CredentialsError` en qualsevol cas de fallada.
    public static func load(service: String = KeychainCredentials.service) throws -> ClaudeCredentials {
        let data = try rawData(service: service)
        return try parse(data)
    }

    /// Dades crues del clauer, sense interpretar.
    public static func rawData(service: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, !data.isEmpty else {
                throw CredentialsError.malformed("entrada buida")
            }
            return data
        case errSecItemNotFound:
            throw CredentialsError.notFound
        default:
            throw CredentialsError.keychain(status)
        }
    }

    /// Interpreta el JSON de la credencial. Separat de la lectura perquè es pugui provar sense clauer.
    public static func parse(_ data: Data, now: Date = Date()) throws -> ClaudeCredentials {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw CredentialsError.malformed("no és JSON")
        }
        guard let token = findString(in: json, keys: ["accesstoken", "access_token"]), !token.isEmpty else {
            throw CredentialsError.malformed("no hi ha cap token d'accés")
        }

        var expiry: Date? = nil
        if let value = findValue(in: json, keys: ["expiresat", "expires_at"]) {
            expiry = CredentialDate.parse(value, now: now)
        }
        if expiry == nil, let value = findValue(in: json, keys: ["expiresin", "expires_in"]) {
            // `expiresIn` és una durada en segons comptada des d'ara, no un instant.
            // Si el número és prou gran per ser un epoch, l'interpretem com a instant.
            if let seconds = CredentialDate.number(from: value) {
                expiry = seconds > 1_000_000_000
                    ? CredentialDate.fromEpoch(seconds)
                    : now.addingTimeInterval(seconds)
            }
        }

        let credentials = ClaudeCredentials(accessToken: token, expiresAt: expiry)
        if let expiry, expiry <= now {
            throw CredentialsError.expired(expiry)
        }
        return credentials
    }

    // MARK: - Cerca tolerant

    /// Normalitza una clau perquè `access_token` i `accessToken` es comparin igual.
    static func normalize(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// Primer valor amb una de les claus donades, buscant en profunditat.
    static func findValue(in node: Any, keys: [String]) -> Any? {
        let wanted = Set(keys.map(normalize))
        var pending: [Any] = [node]
        // Recorregut per amplada: les claus de dalt guanyen les niades.
        while !pending.isEmpty {
            var next: [Any] = []
            for current in pending {
                if let dict = current as? [String: Any] {
                    for (key, value) in dict where wanted.contains(normalize(key)) {
                        if !(value is NSNull) { return value }
                    }
                    next.append(contentsOf: dict.values)
                } else if let array = current as? [Any] {
                    next.append(contentsOf: array)
                }
            }
            pending = next
        }
        return nil
    }

    static func findString(in node: Any, keys: [String]) -> String? {
        guard let value = findValue(in: node, keys: keys) else { return nil }
        if let string = value as? String { return string }
        return nil
    }
}

/// Conversions de data compartides entre el clauer i el client OAuth.
enum CredentialDate {
    static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func number(from value: Any) -> Double? {
        if let number = value as? NSNumber, !(value is Bool) { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// Accepta ISO 8601 (amb o sense fracció) i epoch en segons o mil·lisegons.
    static func parse(_ value: Any, now: Date = Date()) -> Date? {
        if let string = value as? String {
            if let date = isoWithFraction.date(from: string) { return date }
            if let date = isoPlain.date(from: string) { return date }
            if let numeric = Double(string.trimmingCharacters(in: .whitespaces)) {
                return fromEpoch(numeric)
            }
            return nil
        }
        if let numeric = number(from: value) { return fromEpoch(numeric) }
        return nil
    }

    /// Per damunt de 1e11 el valor només té sentit com a mil·lisegons.
    static func fromEpoch(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
    }
}
