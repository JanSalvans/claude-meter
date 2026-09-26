import Foundation
import Testing
@testable import ClaudeMeterCore

/// Comprova que `x` i `y` són iguals dins d'un marge, per no dependre de bits de coma flotant.
func approx(_ x: Double?, _ y: Double, _ epsilon: Double = 0.0001) -> Bool {
    guard let x else { return false }
    return abs(x - y) < epsilon
}

@Suite("Parser de la resposta oficial")
struct UsagePayloadParserTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func parse(_ raw: String) throws -> UsageSnapshot? {
        let json = try JSONSerialization.jsonObject(with: Data(raw.utf8))
        return UsagePayloadParser.parse(json, fetchedAt: now)
    }

    @Test("snake_case amb fracció i data ISO")
    func snakeCase() throws {
        let snapshot = try parse("""
        {
          "five_hour": { "utilization": 0.42, "resets_at": "2023-11-14T23:00:00Z" },
          "seven_day": { "utilization": 0.1, "resets_at": "2023-11-20T00:00:00Z" },
          "seven_day_opus": { "utilization": 0.05, "resets_at": "2023-11-20T00:00:00Z" }
        }
        """)
        #expect(approx(snapshot?.session?.utilization, 0.42))
        #expect(approx(snapshot?.week?.utilization, 0.1))
        #expect(approx(snapshot?.weekOpus?.utilization, 0.05))
        #expect(snapshot?.source == .official)
        #expect(snapshot?.session?.resetsAt == ISO8601DateFormatter().date(from: "2023-11-14T23:00:00Z"))
    }

    @Test("camelCase amb percentatge i epoch")
    func camelCase() throws {
        let snapshot = try parse("""
        {
          "usage": {
            "fiveHour": { "usedPct": 42, "resetsAt": 1700003600 },
            "sevenDay": { "usedPct": 100, "resetsAt": 1700003600000 }
          }
        }
        """)
        #expect(approx(snapshot?.session?.utilization, 0.42))
        #expect(approx(snapshot?.week?.utilization, 1.0))
        // Segons i mil·lisegons han de donar el mateix instant.
        #expect(snapshot?.session?.resetsAt == Date(timeIntervalSince1970: 1_700_003_600))
        #expect(snapshot?.week?.resetsAt == snapshot?.session?.resetsAt)
    }

    @Test("llista amb el nom de la finestra dins de l'element")
    func llistaAmbNom() throws {
        let snapshot = try parse("""
        {
          "limits": [
            { "name": "session", "percent": 73.5, "reset": "2023-11-14T23:30:00Z" },
            { "name": "week", "percent": 12 }
          ]
        }
        """)
        #expect(approx(snapshot?.session?.utilization, 0.735))
        #expect(approx(snapshot?.week?.utilization, 0.12))
        #expect(snapshot?.week?.resetsAt == nil)
    }

    @Test("clau plana amb el número directe")
    func clauPlana() throws {
        let snapshot = try parse(#"{ "five_hour": 0.6, "week": 0.2 }"#)
        #expect(approx(snapshot?.session?.utilization, 0.6))
        #expect(approx(snapshot?.week?.utilization, 0.2))
        #expect(snapshot?.weekOpus == nil)
    }

    @Test("Opus no contamina la setmana general")
    func opusSeparat() throws {
        let snapshot = try parse("""
        { "seven_day": { "utilization": 0.30 }, "seven_day_opus": { "utilization": 0.90 } }
        """)
        #expect(approx(snapshot?.week?.utilization, 0.30))
        #expect(approx(snapshot?.weekOpus?.utilization, 0.90))
    }

    @Test("camps que falten")
    func campsQueFalten() throws {
        let snapshot = try parse("""
        { "five_hour": { "resets_at": "2023-11-14T23:00:00Z" }, "seven_day": { "utilization": 0.5 } }
        """)
        #expect(snapshot?.session == nil)
        #expect(approx(snapshot?.week?.utilization, 0.5))
    }

    @Test("resposta buida o sense mètriques")
    func respostaBuida() throws {
        #expect(try parse("{}") == nil)
        #expect(try parse(#"{ "account": { "email_hash": "abc" }, "plan": "max" }"#) == nil)
    }

    @Test("normalització de percentatges")
    func normalitzacioPercentatges() {
        #expect(approx(UsagePayloadParser.normalizeUtilization(0.42), 0.42))
        #expect(approx(UsagePayloadParser.normalizeUtilization(42), 0.42))
        #expect(approx(UsagePayloadParser.normalizeUtilization(100), 1.0))
        #expect(approx(UsagePayloadParser.normalizeUtilization(0), 0))
        #expect(UsagePayloadParser.normalizeUtilization(-1) == nil)
        #expect(UsagePayloadParser.normalizeUtilization(.nan) == nil)
    }

    @Test("normalització de dates")
    func normalitzacioDates() {
        let reference = Date(timeIntervalSince1970: 1_700_003_600)
        #expect(UsagePayloadParser.normalizeDate("2023-11-14T23:13:20Z") == reference)
        #expect(UsagePayloadParser.normalizeDate("2023-11-14T23:13:20.000Z") == reference)
        #expect(UsagePayloadParser.normalizeDate(1_700_003_600) == reference)
        #expect(UsagePayloadParser.normalizeDate(1_700_003_600_000) == reference)
        #expect(UsagePayloadParser.normalizeDate("1700003600") == reference)
        #expect(UsagePayloadParser.normalizeDate("demà") == nil)
    }

    @Test("Retry-After en segons")
    func retryAfterSegons() throws {
        let response = try #require(HTTPURLResponse(
            url: OAuthUsageClient.endpoint,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "120"]
        ))
        #expect(OAuthUsageClient.retryAfter(from: response) == 120)
    }

    @Test("Retry-After absent")
    func retryAfterAbsent() throws {
        let response = try #require(HTTPURLResponse(
            url: OAuthUsageClient.endpoint,
            statusCode: 429,
            httpVersion: nil,
            headerFields: [:]
        ))
        #expect(OAuthUsageClient.retryAfter(from: response) == nil)
    }
}
