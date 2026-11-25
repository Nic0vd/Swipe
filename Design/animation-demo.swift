//
//  animation-demo.swift
//  Dessine, image par image, l'animation de démonstration du README :
//  un écran avec une fenêtre, un trackpad avec deux doigts, et les 7 gestes.
//
//  Utilisation :
//    swiftc animation-demo.swift -o animation-demo && ./animation-demo <dossier-des-images>
//    puis assembler les images en GIF avec ffmpeg (voir Design/fabriquer-demo.sh).
//

import AppKit

// MARK: - Réglages de la scène

let W: CGFloat = 800, H: CGFloat = 600
let fps: Double = 15
let gestureDuration: Double = 2.7

let display = CGRect(x: 110, y: 36, width: 580, height: 348)       // l'écran (origine en haut à gauche)
let menuBarHeight: CGFloat = 12
let dock = CGRect(x: display.midX - 110, y: display.maxY - 25, width: 220, height: 19)
let usable = CGRect(x: display.minX + 6, y: display.minY + menuBarHeight + 6,
                    width: display.width - 12, height: display.height - menuBarHeight - 6 - 33)
let home = CGRect(x: display.midX - 150, y: display.minY + 70, width: 300, height: 182)
let cursorPoint = CGPoint(x: home.midX + 46, y: home.minY + 11)

let trackpad = CGRect(x: 300, y: 412, width: 200, height: 128)
let padCenter = CGPoint(x: trackpad.midX, y: trackpad.midY)

let accent = NSColor(srgbRed: 0.33, green: 0.45, blue: 1.0, alpha: 1)

enum Kind { case zone(CGRect), minimize, fullscreen, pinch }

struct Gesture {
    let caption: String
    let kind: Kind
    let move: CGVector        // déplacement des doigts sur le trackpad
}

func half(_ left: Bool) -> CGRect {
    let w = (usable.width / 2).rounded(.down)
    return CGRect(x: left ? usable.minX : usable.minX + w, y: usable.minY, width: w, height: usable.height)
}
let quarterTopRight = CGRect(x: usable.minX + (usable.width / 2).rounded(.down), y: usable.minY,
                             width: (usable.width / 2).rounded(.up), height: (usable.height / 2).rounded(.down))

let gestures: [Gesture] = [
    Gesture(caption: "←  Moitié gauche", kind: .zone(half(true)), move: CGVector(dx: -62, dy: 0)),
    Gesture(caption: "→  Moitié droite", kind: .zone(half(false)), move: CGVector(dx: 62, dy: 0)),
    Gesture(caption: "↑  Remplir l'écran", kind: .zone(usable), move: CGVector(dx: 0, dy: -42)),
    Gesture(caption: "↗  Quart d'écran (dans les 4 coins)", kind: .zone(quarterTopRight), move: CGVector(dx: 48, dy: -36)),
    Gesture(caption: "↓  Réduire dans le Dock", kind: .minimize, move: CGVector(dx: 0, dy: 42)),
    Gesture(caption: "Appui puis ↑  ·  Plein écran", kind: .fullscreen, move: CGVector(dx: 0, dy: -42)),
    Gesture(caption: "Pincer  ·  Fermer la fenêtre", kind: .pinch, move: .zero),
]

// MARK: - Petits outils

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
func easeInOut(_ x: Double) -> Double { let t = clamp(x); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
func mix(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
    CGRect(x: mix(a.minX, b.minX, t), y: mix(a.minY, b.minY, t),
           width: mix(a.width, b.width, t), height: mix(a.height, b.height, t))
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
}
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
}

// MARK: - Dessin des éléments

func drawBackground(_ c: CGContext) {
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [rgb(0.96, 0.97, 0.99), rgb(0.90, 0.92, 0.96)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: H), options: [])
}

func drawDisplay(_ c: CGContext, dockBounce: CGFloat) {
    // cadre noir
    c.addPath(rounded(display.insetBy(dx: -9, dy: -9), 16)); c.setFillColor(rgb(0.11, 0.11, 0.12)); c.fillPath()
    // fond d'écran
    c.saveGState()
    c.addPath(rounded(display, 6)); c.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [rgb(0.36, 0.55, 0.98), rgb(0.55, 0.36, 0.94)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(grad, start: CGPoint(x: display.minX, y: display.minY),
                         end: CGPoint(x: display.maxX, y: display.maxY), options: [])
    // barre des menus
    c.setFillColor(rgb(1, 1, 1, 0.55)); c.fill(CGRect(x: display.minX, y: display.minY, width: display.width, height: menuBarHeight))
    c.setFillColor(rgb(0.1, 0.1, 0.1, 0.55))
    for i in 0..<4 { c.fill(CGRect(x: display.minX + 10 + CGFloat(i) * 26, y: display.minY + 4, width: 18, height: 4)) }
    // Dock
    let d = dock.offsetBy(dx: 0, dy: -dockBounce)
    c.addPath(rounded(d, 7)); c.setFillColor(rgb(1, 1, 1, 0.35)); c.fillPath()
    let colors = [rgb(0.2, 0.6, 1), rgb(0.3, 0.8, 0.4), rgb(1, 0.6, 0.2), rgb(0.9, 0.3, 0.4), rgb(0.6, 0.4, 0.9), rgb(0.95, 0.8, 0.2)]
    for (i, col) in colors.enumerated() {
        c.addPath(rounded(CGRect(x: d.minX + 12 + CGFloat(i) * 34, y: d.minY + 3, width: 13, height: 13), 3.5))
        c.setFillColor(col); c.fillPath()
    }
    c.restoreGState()
    // pied de l'écran
    c.setFillColor(rgb(0.75, 0.77, 0.80))
    c.addPath(rounded(CGRect(x: display.midX - 40, y: display.maxY + 9, width: 80, height: 10), 2)); c.fillPath()
}

func drawWindow(_ c: CGContext, _ r: CGRect, alpha: CGFloat, highlightTitle: Bool) {
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
    // boutons ronds
    let dots = [rgb(1, 0.37, 0.34), rgb(1, 0.74, 0.18), rgb(0.16, 0.78, 0.25)]
    for (i, col) in dots.enumerated() where r.width > 60 {
        c.setFillColor(col); c.fillEllipse(in: CGRect(x: r.minX + 9 + CGFloat(i) * 15, y: r.minY + 6, width: 10, height: 10))
    }
    // lignes de contenu
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

func drawCursor(_ c: CGContext, at p: CGPoint) {
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

func drawMini(_ c: CGContext, zone: CGRect, alpha: CGFloat) {
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
    c.addPath(rounded(z, 2.5)); c.setFillColor(accent.cgColor); c.fillPath()
    c.restoreGState()
}

enum Badge { case close, minimize, fullscreen }

func drawBadge(_ c: CGContext, _ kind: Badge, center: CGPoint, scale: CGFloat) {
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

func drawTrackpad(_ c: CGContext) {
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: rgb(0, 0, 0, 0.15))
    c.addPath(rounded(trackpad, 16)); c.setFillColor(rgb(0.98, 0.98, 0.99)); c.fillPath()
    c.restoreGState()
    c.addPath(rounded(trackpad, 16)); c.setStrokeColor(rgb(0.78, 0.79, 0.82)); c.setLineWidth(1.5); c.strokePath()
}

func drawFingers(_ c: CGContext, a: CGPoint, b: CGPoint, alpha: CGFloat, ring: CGFloat) {
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

func drawCaption(_ text: String, alpha: CGFloat) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.18, alpha: alpha),
        .paragraphStyle: style,
    ]
    NSAttributedString(string: text, attributes: attrs).draw(in: CGRect(x: 0, y: 552, width: W, height: 34))
}

// MARK: - Une image

func frame(_ g: Gesture, _ t: Double, _ c: CGContext) {
    let fullscreen: Bool = { if case .fullscreen = g.kind { return true }; return false }()
    let moveStart = fullscreen ? 0.8 : 0.3
    let moveEnd = moveStart + 0.8
    let liftEnd = moveEnd + 0.2
    let p = easeInOut((t - moveStart) / (moveEnd - moveStart))      // progression des doigts
    let q = clamp((p - 0.3) / 0.7)                                   // la fenêtre réagit après le seuil
    let fingersAlpha = CGFloat(clamp(t / 0.25) * (1 - clamp((t - moveEnd) / 0.2)))
    let fadeOut = 1 - clamp((t - (gestureDuration - 0.35)) / 0.35)
    let fadeIn = clamp(t / 0.25)

    var win = home
    var winAlpha = CGFloat(fadeIn * fadeOut)
    var badge: (Badge, CGFloat)? = nil
    var miniZone: CGRect? = nil
    var dockBounce: CGFloat = 0
    var showCursor = true

    switch g.kind {
    case .zone(let target):
        win = mix(home, target, easeOut(q))
        if q > 0 { miniZone = target }
    case .minimize:
        if q > 0 { badge = (.minimize, CGFloat(easeOut(q * 2))) }
        let m = easeInOut((t - liftEnd) / 0.45)
        if t > liftEnd {
            badge = (.minimize, CGFloat(1 - clamp((t - liftEnd) / 0.15)))
            let target = CGRect(x: dock.midX + 30, y: dock.minY, width: 16, height: 12)
            win = mix(home, target, m)
            winAlpha = CGFloat(fadeIn * (1 - m * 0.6))
            dockBounce = CGFloat(sin(Double.pi * clamp((t - liftEnd - 0.4) / 0.3))) * 4
            if m >= 1 { winAlpha = 0 }
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
        let start = CGPoint(x: -g.move.dx * 0.45, y: -g.move.dy * 0.45)
        let dx = start.x + g.move.dx * CGFloat(p), dy = start.y + g.move.dy * CGFloat(p)
        fa = fa.applying(CGAffineTransform(translationX: dx, y: dy))
        fb = fb.applying(CGAffineTransform(translationX: dx, y: dy))
    }
    let ring: CGFloat = fullscreen && t > 0.2 && t < 0.8 ? CGFloat((t - 0.2) / 0.6) : 0

    drawBackground(c)
    drawDisplay(c, dockBounce: dockBounce)
    c.saveGState()
    c.addPath(rounded(display, 6)); c.clip()
    let fingersDown = fingersAlpha > 0.5
    drawWindow(c, win, alpha: winAlpha, highlightTitle: fingersDown)
    if let (kind, scale) = badge { drawBadge(c, kind, center: CGPoint(x: home.midX, y: home.midY + 8), scale: scale) }
    if let z = miniZone { drawMini(c, zone: z, alpha: fingersAlpha) }
    if showCursor { drawCursor(c, at: cursorPoint) }
    c.restoreGState()
    drawTrackpad(c)
    drawFingers(c, a: fa, b: fb, alpha: fingersAlpha, ring: ring)
    drawCaption(g.caption, alpha: CGFloat(fadeIn * fadeOut) * 0.4 + 0.6 * CGFloat(min(fadeIn, fadeOut)))
}

// MARK: - Toutes les images

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
var index = 0
let perGesture = Int(gestureDuration * fps)
for g in gestures {
    for i in 0..<perGesture {
        let t = Double(i) / fps
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let base = NSGraphicsContext(bitmapImageRep: rep)!
        let cg = base.cgContext
        cg.translateBy(x: 0, y: H); cg.scaleBy(x: 1, y: -1)       // origine en haut à gauche
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        frame(g, t, cg)
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: String(format: "%@/f%04d.png", out, index)))
        index += 1
    }
}
print("\(index) images")
