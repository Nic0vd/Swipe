//
//  ActionBadge.swift
//  Glisse
//
//  Le gros bouton rond affiché au centre de la fenêtre pendant un swipe
//  qui ne la range pas dans une zone :
//    - jaune avec « − » : la fenêtre va être réduite dans le Dock ;
//    - vert avec les flèches : elle va entrer en plein écran macOS (ou en sortir).
//  Mêmes couleurs que les boutons ronds en haut à gauche des fenêtres.
//

import AppKit
import SwiftUI

/// Quel bouton afficher.
enum BadgeKind: Equatable {
    case minimize
    case enterFullScreen
    case exitFullScreen
}

final class ActionBadge {

    static let shared = ActionBadge()

    /// Taille du panneau (le rond + la place pour son ombre), en points.
    private static let size: CGFloat = 96

    private let model = ActionBadgeModel()
    private let overlay: OverlayPanel

    private init() {
        let host = NSHostingView(rootView: ActionBadgeView(model: model))
        host.sizingOptions = []   // c'est nous qui fixons la taille, pas SwiftUI
        overlay = OverlayPanel(content: host)
    }

    /// Affiche le bouton au centre de `rect` (coordonnées NSScreen).
    func show(_ kind: BadgeKind, centeredOn rect: CGRect) {
        model.kind = kind
        let size = Self.size
        overlay.show(at: CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2,
                                width: size, height: size),
                     animated: false)
    }

    func hide() {
        overlay.hide()
    }
}

@Observable
final class ActionBadgeModel {
    var kind: BadgeKind = .minimize
}

struct ActionBadgeView: View {

    let model: ActionBadgeModel

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        .padding(10)   // de la place pour l'ombre
        .animation(.easeOut(duration: 0.12), value: model.kind)
    }

    private var color: Color {
        switch model.kind {
        case .minimize:
            return Color(red: 0.996, green: 0.737, blue: 0.180)   // jaune macOS
        case .enterFullScreen, .exitFullScreen:
            return Color(red: 0.157, green: 0.784, blue: 0.251)   // vert macOS
        }
    }

    private var symbol: String {
        switch model.kind {
        case .minimize:        return "minus"
        case .enterFullScreen: return "arrow.up.left.and.arrow.down.right"
        case .exitFullScreen:  return "arrow.down.right.and.arrow.up.left"
        }
    }
}
