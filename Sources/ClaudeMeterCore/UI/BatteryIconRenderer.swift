import AppKit

/// Dibuixa la icona de bateria de la barra de menú per codi (sense fitxers d'imatge).
@MainActor
public final class BatteryIconRenderer {

    public static let shared = BatteryIconRenderer()

    /// Alçada de plantilla pensada per a la barra de menú.
    public static let templateHeight: CGFloat = 22
    /// Amplada de plantilla.
    public static let templateWidth: CGFloat = 28

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

    /// Imatge de la bateria per a un percentatge donat. `percent` a `nil` vol dir
    /// "sense dades": bateria buida amb un guionet a dins.
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
        // Dins de performAsCurrentDrawingAppearance, labelColor ja resol contra
        // l'aparença efectiva vigent (clara o fosca).
        let outlineColor = NSColor.labelColor

        // Geometria: cos amb cantonades arrodonides + tapeta a la dreta.
        let capWidth: CGFloat = 2.0
        let capHeight: CGFloat = rect.height * 0.4
        let bodyInset: CGFloat = 1.0
        let strokeWidth: CGFloat = 1.4

        let bodyRect = NSRect(
            x: rect.minX + bodyInset,
            y: rect.minY + bodyInset,
            width: rect.width - capWidth - bodyInset * 2,
            height: rect.height - bodyInset * 2
        )
        let cornerRadius = min(4.0, bodyRect.height / 2.6)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius)
        bodyPath.lineWidth = strokeWidth

        let capRect = NSRect(
            x: bodyRect.maxX + 1.0,
            y: rect.midY - capHeight / 2,
            width: capWidth,
            height: capHeight
        )
        let capPath = NSBezierPath(roundedRect: capRect, xRadius: 1.0, yRadius: 1.0)

        outlineColor.setStroke()
        bodyPath.stroke()
        outlineColor.setFill()
        capPath.fill()

        guard let percent else {
            // Estat "sense dades": bateria buida amb un guionet gris a dins.
            let dashHeight: CGFloat = 1.6
            let dashInsetX: CGFloat = bodyRect.width * 0.28
            let dashRect = NSRect(
                x: bodyRect.minX + dashInsetX,
                y: bodyRect.midY - dashHeight / 2,
                width: bodyRect.width - dashInsetX * 2,
                height: dashHeight
            )
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(roundedRect: dashRect, xRadius: dashHeight / 2, yRadius: dashHeight / 2).fill()
            return
        }

        let clampedPercent = max(0, min(100, percent))
        let fillInset: CGFloat = strokeWidth + 1.0
        let fillableRect = bodyRect.insetBy(dx: fillInset, dy: fillInset)
        guard fillableRect.width > 0, fillableRect.height > 0 else { return }

        let fillFraction = CGFloat(clampedPercent) / 100.0
        let fillWidth = max(fillableRect.height * 0.5, fillableRect.width * fillFraction)
        let fillRect = NSRect(
            x: fillableRect.minX,
            y: fillableRect.minY,
            width: min(fillWidth, fillableRect.width),
            height: fillableRect.height
        )
        let fillRadius = min(cornerRadius * 0.7, fillRect.height / 2)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: fillRadius, yRadius: fillRadius)
        fillColor(forPercent: clampedPercent).setFill()
        fillPath.fill()
    }
}
