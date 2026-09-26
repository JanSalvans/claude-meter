import Foundation

/// Textos del restabliment d'una finestra: quin dia i a quina hora, i quant falta.
/// Hores en format català (`a les 3.00 h`, `a la 1.00 h`).
public struct ResetFormatter {

    private let calendar: Calendar
    private let locale = Locale(identifier: "ca_ES")

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// "es restableix avui a les 21.00 h", "demà a la 1.00 h" o "dilluns 28 a les 19.00 h".
    /// Arrodoneix al minut, perquè el servidor dona hores com 00:59:59.84.
    public func whenLine(resetsAt: Date, now: Date) -> String {
        let date = Self.roundedToMinute(resetsAt)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let time = String(format: "%d.%02d h", hour, minute)
        let article = hour == 1 ? "a la" : "a les"

        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "avui"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "demà"
        } else {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEEE d"
            day = formatter.string(from: date)
        }
        return "es restableix \(day) \(article) \(time)"
    }

    /// "falten 3 h 12 min", "falten 45 min", "falten 2 dies i 4 h" o "es restableix ara".
    public func remainingLine(resetsAt: Date, now: Date) -> String {
        let minutes = Int((Self.roundedToMinute(resetsAt).timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return "es restableix ara" }

        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let mins = minutes % 60

        if days > 0 {
            let dayText = days == 1 ? "1 dia" : "\(days) dies"
            return hours > 0 ? "falten \(dayText) i \(hours) h" : "falten \(dayText)"
        }
        if hours > 0 {
            return mins > 0 ? "falten \(hours) h \(mins) min" : "falten \(hours) h"
        }
        return "falta\(mins == 1 ? "" : "n") \(mins) min"
    }

    static func roundedToMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
    }
}
