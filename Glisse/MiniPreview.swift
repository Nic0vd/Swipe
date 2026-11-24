//
//  MiniPreview.swift
//  Glisse
//
//  Le MINI aperçu : une petite vignette à côté du curseur, qui représente
//  l'écran en miniature avec la zone cible allumée.
//  Le dessin est fait en SwiftUI (MiniPreviewView) et posé dans un
//  OverlayPanel, comme le grand aperçu.
//

import AppKit
import SwiftUI

final class MiniPreview {

    static let shared = MiniPreview()

    /// Largeur de la vignette, en points. La hauteur suit la forme de l'écran.
    private static let width: CGFloat = 132
    /// Écart entre le curseur et la vignette.
    private static let cursorGap: CGFloat = 18

    private let model = MiniPreviewModel()
    private let overlay: OverlayPanel

    private init() {
        let host = NSHostingView(rootView: MiniPreviewView(model: model))
        host.sizingOptions = []   // c'est nous qui fixons la taille, pas SwiftUI
        overlay = OverlayPanel(content: host)
    }

    /// Affiche la vignette près du curseur.
    /// - `zone` : la zone cible, `area` : la zone utile de l'écran, `cursor` :
    ///   la position du curseur. Tout est en coordonnées NSScreen.
    func show(zone: CGRect, in area: CGRect, near cursor: CGPoint) {
        // Une fenêtre peut dépasser de l'écran : on ne garde que la partie visible.
        let zone = zone.intersection(area)
        guard area.width > 0, area.height > 0, !zone.isNull else { return }

        // Zone cible en fractions de l'écran (0 à 1), origine en HAUT à gauche
        // comme en SwiftUI.
        model.zone = CGRect(x: (zone.minX - area.minX) / area.width,
                            y: (area.maxY - zone.maxY) / area.height,
                            width: zone.width / area.width,
                            height: zone.height / area.height)

        // La vignette ne bouge pas pendant le geste : on ne la place qu'à l'apparition.
        guard !overlay.isShown else { return }
        let height = ((Self.width - 2 * MiniPreviewView.padding) * area.height / area.width
                      + 2 * MiniPreviewView.padding).rounded()
        overlay.show(at: placement(size: CGSize(width: Self.width, height: height),
                                   cursor: cursor, area: area),
                     animated: false)
    }

    func hide() {
        overlay.hide()
    }

    /// En bas à droite du curseur, ou de l'autre côté s'il n'y a pas la place.
    private func placement(size: CGSize, cursor: CGPoint, area: CGRect) -> CGRect {
        // Avec plusieurs écrans, on reste sur l'écran où se trouve le curseur.
        let area = NSScreen.screens.first { $0.frame.contains(cursor) }?.visibleFrame ?? area
        var x = cursor.x + Self.cursorGap
        var y = cursor.y - Self.cursorGap - size.height
        if x + size.width > area.maxX { x = cursor.x - Self.cursorGap - size.width }
        if y < area.minY { y = cursor.y + Self.cursorGap }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// Ce que la vignette doit afficher.
@Observable
final class MiniPreviewModel {
    /// Zone cible en fractions de l'écran (0 à 1), origine en haut à gauche.
    var zone: CGRect = .zero
}

/// Le dessin de la vignette.
struct MiniPreviewView: View {

    static let padding: CGFloat = 6

    let model: MiniPreviewModel

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                // L'écran en miniature
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.25))
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                // La zone cible, allumée
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .controlAccentColor))
                    .frame(width: max(0, model.zone.width * size.width - 4),
                           height: max(0, model.zone.height * size.height - 4))
                    .offset(x: model.zone.minX * size.width + 2,
                            y: model.zone.minY * size.height + 2)
            }
        }
        .padding(Self.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.12), value: model.zone)
    }
}
