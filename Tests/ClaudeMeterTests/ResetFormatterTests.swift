import Foundation
import Testing
@testable import ClaudeMeterCore

@Suite("Textos del restabliment")
struct ResetFormatterTests {
    private let formatter: ResetFormatter = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return ResetFormatter(calendar: calendar)
    }()

    private func date(_ iso: String) -> Date {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)!
    }

    // Dissabte 26 de setembre de 2026, 22.47 h a Barcelona.
    private var now: Date { date("2026-09-26T20:47:00Z") }

    @Test("avui, amb l'hora arrodonida al minut")
    func today() {
        #expect(formatter.whenLine(resetsAt: date("2026-09-26T20:59:59.842Z"), now: now)
                == "es restableix avui a les 23.00 h")
    }

    @Test("demà, amb article a la 1")
    func tomorrowAtOne() {
        #expect(formatter.whenLine(resetsAt: date("2026-09-26T23:00:00Z"), now: now)
                == "es restableix demà a la 1.00 h")
    }

    @Test("més enllà de demà, amb dia de la setmana")
    func laterDay() {
        #expect(formatter.whenLine(resetsAt: date("2026-09-28T17:00:00Z"), now: now)
                == "es restableix dilluns 28 a les 19.00 h")
    }

    @Test("compte enrere en hores, minuts i dies")
    func remaining() {
        #expect(formatter.remainingLine(resetsAt: date("2026-09-27T00:59:59.842Z"), now: now) == "falten 4 h 13 min")
        #expect(formatter.remainingLine(resetsAt: date("2026-09-26T21:47:00Z"), now: now) == "falten 1 h")
        #expect(formatter.remainingLine(resetsAt: date("2026-09-26T20:48:00Z"), now: now) == "falta 1 min")
        #expect(formatter.remainingLine(resetsAt: date("2026-09-28T23:47:00Z"), now: now) == "falten 2 dies i 3 h")
        #expect(formatter.remainingLine(resetsAt: date("2026-09-26T20:40:00Z"), now: now) == "es restableix ara")
    }
}
