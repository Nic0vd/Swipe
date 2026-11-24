import AppKit

func png(_ size: Int, _ draw: (CGContext, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// ---------- Icône de la barre des menus : deux doigts + traits de mouvement (18 pt) ----------
func menuBar(_ c: CGContext, _ s: CGFloat) {
    let k = s / 18
    c.scaleBy(x: k, y: k)
    c.setFillColor(NSColor.black.cgColor)
    c.setStrokeColor(NSColor.black.cgColor)
    // Main légèrement penchée, deux doigts tendus (index + majeur)
    c.saveGState()
    c.translateBy(x: 11, y: 8)
    c.rotate(by: -0.26)
    func capsule(_ r: CGRect) { c.addPath(CGPath(roundedRect: r, cornerWidth: r.width / 2, cornerHeight: r.width / 2, transform: nil)) }
    capsule(CGRect(x: -4.4, y: -2.0, width: 3.1, height: 11.0))   // index
    capsule(CGRect(x: 0.1, y: -2.0, width: 3.1, height: 11.8))   // majeur
    capsule(CGRect(x: 3.3, y: -3.2, width: 2.6, height: 5.6))     // doigts repliés
    c.addPath(CGPath(roundedRect: CGRect(x: -4.2, y: -7.6, width: 10.0, height: 7.4), cornerWidth: 3, cornerHeight: 3, transform: nil)) // paume
    c.fillPath()
    // pouce replié
    c.setLineCap(.round); c.setLineWidth(2.4)
    c.move(to: CGPoint(x: -4.0, y: -4.8)); c.addLine(to: CGPoint(x: -6.0, y: -2.4))
    c.strokePath()
    c.restoreGState()
    // traits de mouvement à gauche
    c.setLineCap(.round)
    c.setLineWidth(1.5)
    c.move(to: CGPoint(x: 0.9, y: 12.5)); c.addLine(to: CGPoint(x: 3.6, y: 12.5))
    c.move(to: CGPoint(x: 0.9, y: 9.0)); c.addLine(to: CGPoint(x: 2.6, y: 9.0))
    c.strokePath()
}

// ---------- Icône de l'app : fenêtre qui glisse, dégradé bleu → violet (1024 px) ----------
func appIcon(_ c: CGContext, _ s: CGFloat) {
    let k = s / 1024
    c.scaleBy(x: k, y: k)
    let space = CGColorSpaceCreateDeviceRGB()

    // Fond arrondi (grille d'icône macOS : 824 px centré, ombre légère)
    let bg = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bgPath = CGPath(roundedRect: bg, cornerWidth: 185, cornerHeight: 185, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.30).cgColor)
    c.addPath(bgPath); c.setFillColor(NSColor.black.cgColor); c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(bgPath); c.clip()
    let grad = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.25, green: 0.56, blue: 1.00, alpha: 1).cgColor,
        NSColor(srgbRed: 0.55, green: 0.27, blue: 0.98, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(grad, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    // reflet doux en haut
    let shine = CGGradient(colorsSpace: space, colors: [
        NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    c.restoreGState()

    // Une fenêtre stylisée à la position x
    func window(x: CGFloat, alpha: CGFloat, details: Bool) {
        let r = CGRect(x: x, y: 330, width: 440, height: 360)
        let p = CGPath(roundedRect: r, cornerWidth: 44, cornerHeight: 44, transform: nil)
        c.saveGState()
        if details {
            c.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        }
        c.addPath(p); c.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor); c.fillPath()
        c.restoreGState()
        guard details else { return }
        // barre de titre
        c.saveGState()
        c.addPath(p); c.clip()
        c.setFillColor(NSColor(srgbRed: 0.92, green: 0.93, blue: 0.97, alpha: 1).cgColor)
        c.fill(CGRect(x: x, y: 690 - 78, width: 440, height: 78))
        c.restoreGState()
        // trois boutons ronds
        let colors = [NSColor(srgbRed: 1.00, green: 0.37, blue: 0.34, alpha: 1),
                      NSColor(srgbRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
                      NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)]
        for (i, col) in colors.enumerated() {
            c.setFillColor(col.cgColor)
            c.fillEllipse(in: CGRect(x: x + 34 + CGFloat(i) * 46, y: 690 - 39 - 15, width: 30, height: 30))
        }
        // lignes de contenu
        c.setFillColor(NSColor(srgbRed: 0.80, green: 0.83, blue: 0.92, alpha: 1).cgColor)
        for (i, w) in [300.0, 240.0, 270.0].enumerated() {
            c.addPath(CGPath(roundedRect: CGRect(x: x + 40, y: 540 - CGFloat(i) * 62, width: w, height: 26), cornerWidth: 13, cornerHeight: 13, transform: nil))
        }
        c.fillPath()
    }
    // traînée (fenêtres fantômes) puis la fenêtre principale, qui glisse vers la droite
    window(x: 190, alpha: 0.16, details: false)
    window(x: 260, alpha: 0.30, details: false)
    window(x: 330, alpha: 1.0, details: true)
}

let out = CommandLine.arguments[1]
try! png(18, menuBar).write(to: URL(fileURLWithPath: "\(out)/menubar.png"))
try! png(36, menuBar).write(to: URL(fileURLWithPath: "\(out)/menubar@2x.png"))
try! png(160, menuBar).write(to: URL(fileURLWithPath: "\(out)/menubar-preview.png"))
try! png(1024, appIcon).write(to: URL(fileURLWithPath: "\(out)/icon_1024.png"))
print("ok")
