//
//  GestureDemo.swift
//  Glisse
//
//  Le dessin des petites animations qui expliquent les gestes : un écran
//  avec une fenêtre, un trackpad avec deux doigts, et ce qui se passe.
//
//  Ce fichier sert à DEUX endroits, pour que le dessin n'existe qu'une fois :
//    - dans l'app, onglet « Gestes » des Réglages (GesturesTab.swift) ;
//    - pour fabriquer le GIF du README (Design/fabriquer-demo.sh).
//  Il n'utilise donc que AppKit et CoreGraphics, pas SwiftUI.
//

import AppKit

nonisolated enum GestureDemo {

    // MARK: - Les gestes

    enum Kind { case zone(CGRect), minimize, fullscreen, pinch }

    struct Gesture: Identifiable {
        let id: Int
        let symbol: String       // ex. « ← »
        let title: String        // ex. « Moitié gauche »
        let detail: String       // l'explication, pour l'onglet Gestes
        let kind: Kind
        let move: CGVector       // déplacement des doigts sur le trackpad

        /// Légende du GIF, ex. « ←  Moitié gauche ».
        var caption: String { "\(symbol)  ·  \(title)" }
    }

    static let all: [Gesture] = [
        Gesture(id: 0, symbol: String(localized: "←"), title: String(localized: "Moitié gauche"),
                detail: String(localized: "Pose deux doigts, le curseur sur la barre de titre, et glisse vers la gauche : la fenêtre occupe la moitié gauche de l'écran."),
                kind: .zone(half(left: true)), move: CGVector(dx: -62, dy: 0)),
        Gesture(id: 1, symbol: String(localized: "→"), title: String(localized: "Moitié droite"),
                detail: String(localized: "Même geste vers la droite : la fenêtre occupe la moitié droite."),
                kind: .zone(half(left: false)), move: CGVector(dx: 62, dy: 0)),
        Gesture(id: 2, symbol: String(localized: "↑"), title: String(localized: "Remplir l'écran"),
                detail: String(localized: "Vers le haut : la fenêtre remplit tout l'écran, en laissant visibles la barre des menus et le Dock."),
                kind: .zone(usable), move: CGVector(dx: 0, dy: -42)),
        Gesture(id: 3, symbol: String(localized: "↖ ↗ ↙ ↘"), title: String(localized: "Quart d'écran"),
                detail: String(localized: "En diagonale : la fenêtre se range dans le coin correspondant. Le geste doit être un peu plus franc que pour les moitiés."),
                kind: .zone(quarterTopRight), move: CGVector(dx: 48, dy: -36)),
        Gesture(id: 4, symbol: String(localized: "↓"), title: String(localized: "Réduire dans le Dock"),
                detail: String(localized: "Vers le bas, franchement : un bouton jaune apparaît, et la fenêtre part dans le Dock quand tu lèves les doigts."),
                kind: .minimize, move: CGVector(dx: 0, dy: 42)),
        Gesture(id: 5, symbol: String(localized: "Appui puis ↑"), title: String(localized: "Plein écran"),
                detail: String(localized: "Garde les deux doigts posés un court instant sans bouger, puis glisse vers le haut : bouton vert, plein écran macOS. Le même geste en ressort."),
                kind: .fullscreen, move: CGVector(dx: 0, dy: -42)),
        Gesture(id: 6, symbol: String(localized: "Pincer"), title: String(localized: "Fermer la fenêtre"),
                detail: String(localized: "Rapproche deux doigts comme pour dézoomer : un bouton rouge apparaît, et la fenêtre se ferme quand tu lèves les doigts."),
                kind: .pinch, move: .zero),
    ]

    // MARK: - Les modes d'aperçu

    /// Comment l'aperçu s'affiche pendant un swipe (même choix que dans les Réglages).
    enum PreviewLook {
        case live, liveMini, large, mini, both

        var movesLive: Bool { self == .live || self == .liveMini }
        var showsLarge: Bool { self == .large || self == .both }
        var showsMini: Bool { self == .liveMini || self == .mini || self == .both }
    }

    /// Le geste utilisé pour montrer les modes d'aperçu : un swipe ←.
    static var previewGesture: Gesture { all[0] }

    // MARK: - La scène (origine en haut à gauche)

    /// Taille de la scène, sans la légende.
    static let size = CGSize(width: 800, height: 545)
    /// Durée d'un geste, en secondes (l'animation tourne en boucle).
    static let duration: Double = 2.7

    static let display = CGRect(x: 110, y: 36, width: 580, height: 348)
    static let menuBarHeight: CGFloat = 12
    static let dock = CGRect(x: display.midX - 110, y: display.maxY - 25, width: 220, height: 19)
    static let usable = CGRect(x: display.minX + 6, y: display.minY + menuBarHeight + 6,
                               width: display.width - 12, height: display.height - menuBarHeight - 6 - 33)
    static let home = CGRect(x: display.midX - 150, y: display.minY + 70, width: 300, height: 182)
    static let cursorPoint = CGPoint(x: home.midX + 46, y: home.minY + 11)
    static let trackpad = CGRect(x: 300, y: 412, width: 200, height: 128)
    static let padCenter = CGPoint(x: trackpad.midX, y: trackpad.midY)
    static let accent = rgb(0.33, 0.45, 1.0)

    static func half(left: Bool) -> CGRect {
        let w = (usable.width / 2).rounded(.down)
        return CGRect(x: left ? usable.minX : usable.minX + w, y: usable.minY, width: w, height: usable.height)
    }
    static let quarterTopRight = CGRect(x: usable.minX + (usable.width / 2).rounded(.down), y: usable.minY,
                                        width: (usable.width / 2).rounded(.up), height: (usable.height / 2).rounded(.down))

    // MARK: - Une image

    /// Dessine le geste `g` à l'instant `t` (secondes, 0 à `duration`) dans `c`,
    /// dont l'origine est en haut à gauche et qui mesure `size`.
    /// `look` : le mode d'aperçu montré pendant le geste.
    static func draw(_ g: Gesture, at t: Double, in c: CGContext, look: PreviewLook = .liveMini) {
        let fullscreen: Bool = { if case .fullscreen = g.kind { return true }; return false }()
        let moveStart = fullscreen ? 0.8 : 0.3
        let moveEnd = moveStart + 0.8
        let liftEnd = moveEnd + 0.2
        let p = easeInOut((t - moveStart) / (moveEnd - moveStart))      // progression des doigts
        let q = clamp((p - 0.3) / 0.7)                                   // la fenêtre réagit après le seuil
        let fingersAlpha = CGFloat(clamp(t / 0.25) * (1 - clamp((t - moveEnd) / 0.2)))
        let fadeOut = 1 - clamp((t - (duration - 0.35)) / 0.35)
        let fadeIn = clamp(t / 0.25)

        var win = home
        var winAlpha = CGFloat(fadeIn * fadeOut)
        var badge: (Badge, CGFloat)? = nil
        var miniZone: CGRect? = nil
        var largeZone: CGRect? = nil
        var dockBounce: CGFloat = 0
        var showCursor = true

        switch g.kind {
        case .zone(let target):
            if look.movesLive {
                win = mix(home, target, easeOut(q))                       // la fenêtre suit les doigts
            } else if t > moveEnd {
                win = mix(home, target, easeOut((t - moveEnd) / 0.35))    // elle ne bouge qu'au lâcher
            }
            if q > 0 {
                if look.showsMini { miniZone = target }
                if look.showsLarge { largeZone = target }
            }
        case .minimize:
            if q > 0 { badge = (.minimize, CGFloat(easeOut(q * 2))) }
            if t > liftEnd {
                let m = easeInOut((t - liftEnd) / 0.45)
                badge = (.minimize, CGFloat(1 - clamp((t - liftEnd) / 0.15)))
                let target = CGRect(x: dock.midX + 30, y: dock.minY, width: 16, height: 12)
                win = mix(home, target, m)
                winAlpha = m >= 1 ? 0 : CGFloat(fadeIn * (1 - m * 0.6))
                dockBounce = CGFloat(sin(Double.pi * clamp((t - liftEnd - 0.4) / 0.3))) * 4
            }
        case .fullscreen:
            if q > 0 { badge = (.fullscreen, CGFloat(easeOut(q * 2))) }
            if t > liftEnd {
                let m = easeInOut((t - liftEnd) / 0.4)
                badge = (.fullscreen, CGFloat(1 - clamp((t - liftEnd) / 0.15)))
                win = mix(home, display, m)
                showCursor = m < 0.5
            }
        case .pinch:
            let pinch = easeInOut((t - 0.3) / 0.8)
            if pinch > 0.4 { badge = (.close, CGFloat(easeOut((pinch - 0.4) * 3))) }
            if t > liftEnd {
                let m = easeInOut((t - liftEnd) / 0.3)
                badge = (.close, CGFloat(1 - clamp((t - liftEnd) / 0.15)))
                win = home.insetBy(dx: home.width * 0.06 * CGFloat(m), dy: home.height * 0.06 * CGFloat(m))
                winAlpha = CGFloat(fadeIn * (1 - m))
            }
        }

        // Doigts
        var fa = CGPoint(x: padCenter.x - 17, y: padCenter.y), fb = CGPoint(x: padCenter.x + 17, y: padCenter.y)
        if case .pinch = g.kind {
            let pinch = CGFloat(easeInOut((t - 0.3) / 0.8))
            let gap = 46 - 32 * pinch
            fa = CGPoint(x: padCenter.x - gap, y: padCenter.y + gap * 0.35)
            fb = CGPoint(x: padCenter.x + gap, y: padCenter.y - gap * 0.35)
        } else {
            let dx = -g.move.dx * 0.45 + g.move.dx * CGFloat(p)
            let dy = -g.move.dy * 0.45 + g.move.dy * CGFloat(p)
            fa = CGPoint(x: fa.x + dx, y: fa.y + dy)
            fb = CGPoint(x: fb.x + dx, y: fb.y + dy)
        }
        let ring: CGFloat = fullscreen && t > 0.2 && t < 0.8 ? CGFloat((t - 0.2) / 0.6) : 0

        drawBackground(c)
        drawDisplay(c, dockBounce: dockBounce)
        c.saveGState()
        c.addPath(rounded(display, 6)); c.clip()
        drawWindow(c, win, alpha: winAlpha, highlightTitle: fingersAlpha > 0.5)
        if let z = largeZone { drawLarge(c, zone: z, alpha: fingersAlpha * CGFloat(easeOut(q * 2))) }
        if let (kind, scale) = badge { drawBadge(c, kind, center: CGPoint(x: home.midX, y: home.midY + 8), scale: scale) }
        if let z = miniZone { drawMini(c, zone: z, alpha: fingersAlpha) }
        if showCursor { drawCursor(c, at: cursorPoint) }
        c.restoreGState()
        drawTrackpad(c)
        drawFingers(c, a: fa, b: fb, alpha: fingersAlpha, ring: ring)
    }

    // MARK: - Petits outils

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    static func easeInOut(_ x: Double) -> Double {
        let t = clamp(x); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    static func mix(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: mix(a.minX, b.minX, t), y: mix(a.minY, b.minY, t),
               width: mix(a.width, b.width, t), height: mix(a.height, b.height, t))
    }
    static func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
    }
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Les éléments de la scène

    static func drawBackground(_ c: CGContext) {
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [rgb(0.96, 0.97, 0.99), rgb(0.90, 0.92, 0.96)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    }

    static func drawDisplay(_ c: CGContext, dockBounce: CGFloat) {
        c.addPath(rounded(display.insetBy(dx: -9, dy: -9), 16)); c.setFillColor(rgb(0.11, 0.11, 0.12)); c.fillPath()
        c.saveGState()
        c.addPath(rounded(display, 6)); c.clip()
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [rgb(0.36, 0.55, 0.98), rgb(0.55, 0.36, 0.94)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(grad, start: CGPoint(x: display.minX, y: display.minY),
                             end: CGPoint(x: display.maxX, y: display.maxY), options: [])
        c.setFillColor(rgb(1, 1, 1, 0.55))
        c.fill(CGRect(x: display.minX, y: display.minY, width: display.width, height: menuBarHeight))
        c.setFillColor(rgb(0.1, 0.1, 0.1, 0.55))
        for i in 0..<4 { c.fill(CGRect(x: display.minX + 10 + CGFloat(i) * 26, y: display.minY + 4, width: 18, height: 4)) }
        let d = dock.offsetBy(dx: 0, dy: -dockBounce)
        c.addPath(rounded(d, 7)); c.setFillColor(rgb(1, 1, 1, 0.35)); c.fillPath()
        let colors = [rgb(0.2, 0.6, 1), rgb(0.3, 0.8, 0.4), rgb(1, 0.6, 0.2), rgb(0.9, 0.3, 0.4), rgb(0.6, 0.4, 0.9), rgb(0.95, 0.8, 0.2)]
        for (i, col) in colors.enumerated() {
            c.addPath(rounded(CGRect(x: d.minX + 12 + CGFloat(i) * 34, y: d.minY + 3, width: 13, height: 13), 3.5))
            c.setFillColor(col); c.fillPath()
        }
        c.restoreGState()
        c.setFillColor(rgb(0.75, 0.77, 0.80))
        c.addPath(rounded(CGRect(x: display.midX - 40, y: display.maxY + 9, width: 80, height: 10), 2)); c.fillPath()
    }

    static func drawWindow(_ c: CGContext, _ r: CGRect, alpha: CGFloat, highlightTitle: Bool) {
        guard alpha > 0.01, r.width > 4, r.height > 4 else { return }
        c.saveGState()
        c.setAlpha(alpha)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 5), blur: 14, color: rgb(0, 0, 0, 0.28))
        c.addPath(rounded(r, 8)); c.setFillColor(rgb(1, 1, 1)); c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(rounded(r, 8)); c.clip()
        let title = CGRect(x: r.minX, y: r.minY, width: r.width, height: min(22, r.height))
        c.setFillColor(highlightTitle ? rgb(0.86, 0.89, 1.0) : rgb(0.93, 0.94, 0.96)); c.fill(title)
        let dots = [rgb(1, 0.37, 0.34), rgb(1, 0.74, 0.18), rgb(0.16, 0.78, 0.25)]
        for (i, col) in dots.enumerated() where r.width > 60 {
            c.setFillColor(col); c.fillEllipse(in: CGRect(x: r.minX + 9 + CGFloat(i) * 15, y: r.minY + 6, width: 10, height: 10))
        }
        c.setFillColor(rgb(0.84, 0.86, 0.92))
        let lines: [CGFloat] = [0.72, 0.55, 0.64, 0.4]
        for (i, w) in lines.enumerated() {
            let y = r.minY + 36 + CGFloat(i) * 20
            if y + 9 < r.maxY - 6 { c.addPath(rounded(CGRect(x: r.minX + 14, y: y, width: (r.width - 28) * w, height: 9), 4.5)) }
        }
        c.fillPath()
        c.restoreGState()
        c.restoreGState()
    }

    static func drawCursor(_ c: CGContext, at p: CGPoint) {
        let path = CGMutablePath()
        path.move(to: p)
        path.addLine(to: CGPoint(x: p.x, y: p.y + 17))
        path.addLine(to: CGPoint(x: p.x + 4.5, y: p.y + 13))
        path.addLine(to: CGPoint(x: p.x + 7.5, y: p.y + 19.5))
        path.addLine(to: CGPoint(x: p.x + 10, y: p.y + 18.5))
        path.addLine(to: CGPoint(x: p.x + 7, y: p.y + 12))
        path.addLine(to: CGPoint(x: p.x + 12.5, y: p.y + 12))
        path.closeSubpath()
        c.addPath(path); c.setFillColor(rgb(0, 0, 0)); c.fillPath()
        c.addPath(path); c.setStrokeColor(rgb(1, 1, 1)); c.setLineWidth(1.3); c.strokePath()
    }

    static func drawMini(_ c: CGContext, zone: CGRect, alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        c.saveGState(); c.setAlpha(alpha)
        let box = CGRect(x: cursorPoint.x + 16, y: cursorPoint.y + 20, width: 86, height: 58)
        c.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: rgb(0, 0, 0, 0.25))
        c.addPath(rounded(box, 8)); c.setFillColor(rgb(0.97, 0.97, 0.98, 0.95)); c.fillPath()
        c.setShadow(offset: .zero, blur: 0, color: nil)
        let screen = box.insetBy(dx: 6, dy: 6)
        c.addPath(rounded(screen, 4)); c.setFillColor(rgb(0, 0, 0, 0.22)); c.fillPath()
        let fx = (zone.minX - usable.minX) / usable.width, fy = (zone.minY - usable.minY) / usable.height
        let z = CGRect(x: screen.minX + fx * screen.width, y: screen.minY + fy * screen.height,
                       width: zone.width / usable.width * screen.width, height: zone.height / usable.height * screen.height)
            .insetBy(dx: 1.5, dy: 1.5)
        c.addPath(rounded(z, 2.5)); c.setFillColor(accent); c.fillPath()
        c.restoreGState()
    }

    /// Le grand rectangle translucide posé sur la zone cible.
    static func drawLarge(_ c: CGContext, zone: CGRect, alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        let r = zone.insetBy(dx: 4, dy: 4)
        c.addPath(rounded(r, 8)); c.setFillColor(accent.copy(alpha: 0.32 * alpha)!); c.fillPath()
        c.addPath(rounded(r, 8)); c.setStrokeColor(accent.copy(alpha: 0.8 * alpha)!); c.setLineWidth(2.5); c.strokePath()
    }

    enum Badge { case close, minimize, fullscreen }

    static func drawBadge(_ c: CGContext, _ kind: Badge, center: CGPoint, scale: CGFloat) {
        guard scale > 0.01 else { return }
        let r: CGFloat = 26 * scale
        let color: CGColor
        switch kind {
        case .close: color = rgb(1, 0.37, 0.34)
        case .minimize: color = rgb(1, 0.74, 0.18)
        case .fullscreen: color = rgb(0.16, 0.78, 0.25)
        }
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: rgb(0, 0, 0, 0.3))
        c.setFillColor(color); c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        c.restoreGState()
        c.setStrokeColor(rgb(0, 0, 0, 0.55)); c.setLineWidth(4.5 * scale); c.setLineCap(.round)
        let k = 10 * scale
        switch kind {
        case .minimize:
            c.move(to: CGPoint(x: center.x - k, y: center.y)); c.addLine(to: CGPoint(x: center.x + k, y: center.y))
        case .close:
            c.move(to: CGPoint(x: center.x - k, y: center.y - k)); c.addLine(to: CGPoint(x: center.x + k, y: center.y + k))
            c.move(to: CGPoint(x: center.x + k, y: center.y - k)); c.addLine(to: CGPoint(x: center.x - k, y: center.y + k))
        case .fullscreen:
            c.setFillColor(rgb(0, 0, 0, 0.55))
            let a = CGMutablePath()   // deux triangles vers les coins
            a.move(to: CGPoint(x: center.x - k, y: center.y - k)); a.addLine(to: CGPoint(x: center.x + 2, y: center.y - k))
            a.addLine(to: CGPoint(x: center.x - k, y: center.y + 2)); a.closeSubpath()
            a.move(to: CGPoint(x: center.x + k, y: center.y + k)); a.addLine(to: CGPoint(x: center.x - 2, y: center.y + k))
            a.addLine(to: CGPoint(x: center.x + k, y: center.y - 2)); a.closeSubpath()
            c.addPath(a); c.fillPath()
        }
        c.strokePath()
    }

    static func drawTrackpad(_ c: CGContext) {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: rgb(0, 0, 0, 0.15))
        c.addPath(rounded(trackpad, 16)); c.setFillColor(rgb(0.98, 0.98, 0.99)); c.fillPath()
        c.restoreGState()
        c.addPath(rounded(trackpad, 16)); c.setStrokeColor(rgb(0.78, 0.79, 0.82)); c.setLineWidth(1.5); c.strokePath()
    }

    static func drawFingers(_ c: CGContext, a: CGPoint, b: CGPoint, alpha: CGFloat, ring: CGFloat) {
        guard alpha > 0.01 else { return }
        c.saveGState(); c.setAlpha(alpha)
        for p in [a, b] {
            if ring > 0 {   // onde de l'appui prolongé
                let rr = 14 + 16 * ring
                c.setStrokeColor(rgb(0.16, 0.78, 0.25, 0.8 * (1 - ring))); c.setLineWidth(3)
                c.strokeEllipse(in: CGRect(x: p.x - rr, y: p.y - rr, width: 2 * rr, height: 2 * rr))
            }
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: rgb(0, 0, 0, 0.3))
            c.setFillColor(rgb(0.30, 0.32, 0.38, 0.85))
            c.fillEllipse(in: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26))
            c.restoreGState()
        }
        c.restoreGState()
    }
}
