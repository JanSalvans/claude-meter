import AppKit

/// Dibuixa la barra d'ús de la barra de menú per codi (sense fitxers d'imatge):
/// una càpsula horitzontal amb un fons tènue i el farciment de color a dins.
@MainActor
public final class UsageBarRenderer {

    public static let shared = UsageBarRenderer()

    /// Alçada de plantilla pensada per a la barra de menú.
    public static let templateHeight: CGFloat = 22
    /// Amplada de plantilla.
    public static let templateWidth: CGFloat = 34
    /// Gruix de la barra dins la plantilla.
    static let barHeight: CGFloat = 7

    private struct CacheKey: Hashable {
        let percent: Int?
        let isDark: Bool
    }

    private var cache: [CacheKey: NSImage] = [:]

    public init() {}

    /// Retorna el color del farciment segons el percentatge d'ús (0...100).
    public static func fillColor(forPercent percent: Int) -> NSColor {
        switch percent {
        case ..<50:
            return .systemGreen
        case 50..<75:
            return .systemYellow
        case 75..<90:
            return .systemOrange
        default:
            return .systemRed
        }
    }

    /// Imatge de la barra per a un percentatge donat. `percent` a `nil` vol dir
    /// "sense dades": només el fons, sense farciment.
    public func image(forPercent percent: Int?, appearance: NSAppearance) -> NSImage {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = CacheKey(percent: percent, isDark: isDark)
        if let cached = cache[key] {
            return cached
        }

        let size = NSSize(width: Self.templateWidth, height: Self.templateHeight)
        let image = NSImage(size: size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                Self.draw(percent: percent, in: rect)
            }
            return true
        }
        image.isTemplate = false
        cache[key] = image
        return image
    }

    /// Buida la memòria cau, per exemple en canviar l'aparença efectiva.
    public func clearCache() {
        cache.removeAll()
    }

    private static func draw(percent: Int?, in rect: NSRect) {
        let trackRect = NSRect(
            x: rect.minX + 1,
            y: rect.midY - barHeight / 2,
            width: rect.width - 2,
            height: barHeight
        )
        let radius = barHeight / 2

        // Dins de performAsCurrentDrawingAppearance, labelColor ja resol contra
        // l'aparença efectiva vigent (clara o fosca).
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius).fill()

        guard let percent else { return }

        let clampedPercent = max(0, min(100, percent))
        let fraction = CGFloat(clampedPercent) / 100.0
        // Amplada mínima d'un cercle perquè el 0-3 % encara es vegi.
        let fillWidth = max(barHeight, trackRect.width * fraction)
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: min(fillWidth, trackRect.width),
            height: barHeight
        )
        fillColor(forPercent: clampedPercent).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}
