//
//  animation-demo.swift
//  Fabrique, image par image, l'animation du README (les 7 gestes à la suite,
//  avec une légende sous chacun).
//
//  Le dessin lui-même est dans l'app : Glisse/GestureDemo.swift (le même que
//  dans l'onglet « Gestes » des Réglages). Ce fichier ajoute seulement la
//  légende et enregistre les images.
//
//  Utilisation : Design/fabriquer-demo.sh
//

import AppKit

let W: CGFloat = 800, H: CGFloat = 600
let fps: Double = 15

func drawCaption(_ text: String, alpha: CGFloat) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.18, alpha: alpha),
        .paragraphStyle: style,
    ]
    NSAttributedString(string: text, attributes: attrs).draw(in: CGRect(x: 0, y: 552, width: W, height: 34))
}

/// Traduit une légende avec le catalogue de l'app (Glisse/Localizable.xcstrings).
/// Sans langue demandée, ou sans traduction, on garde le français.
func translator(catalog path: String?, language: String?) -> (String) -> String {
    guard let path, let language,
          let data = FileManager.default.contents(atPath: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = json["strings"] as? [String: Any] else { return { $0 } }
    return { key in
        let entry = strings[key] as? [String: Any]
        let loc = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        let unit = loc?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String ?? key
    }
}

@main
struct FabriqueDemo {
    static func main() {
        // Arguments : <dossier des images> [langue] [catalogue de traductions]
        let args = CommandLine.arguments
        let out = args.count > 1 ? args[1] : "."
        let tr = translator(catalog: args.count > 3 ? args[3] : nil, language: args.count > 2 ? args[2] : nil)
        var index = 0
        let perGesture = Int(GestureDemo.duration * fps)
        for g in GestureDemo.all {
            for i in 0..<perGesture {
                let t = Double(i) / fps
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
                cg.translateBy(x: 0, y: H); cg.scaleBy(x: 1, y: -1)       // origine en haut à gauche
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
                // fond sur toute la hauteur, puis la scène, puis la légende
                let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [GestureDemo.rgb(0.96, 0.97, 0.99), GestureDemo.rgb(0.90, 0.92, 0.96)] as CFArray,
                                      locations: [0, 1])!
                cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: H), options: [])
                cg.saveGState()
                cg.clip(to: CGRect(origin: .zero, size: GestureDemo.size))
                GestureDemo.draw(g, at: t, in: cg)
                cg.restoreGState()
                let fade = min(GestureDemo.clamp(t / 0.25), 1 - GestureDemo.clamp((t - (GestureDemo.duration - 0.35)) / 0.35))
                drawCaption("\(tr(g.symbol))  ·  \(tr(g.title))", alpha: CGFloat(0.6 + 0.4 * fade))
                NSGraphicsContext.restoreGraphicsState()
                try! rep.representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: String(format: "%@/f%04d.png", out, index)))
                index += 1
            }
        }
        print("\(index) images")
    }
}
