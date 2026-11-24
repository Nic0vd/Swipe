//
//  ZoneCalculator.swift
//  Glisse
//
//  Calcule le rectangle où ranger une fenêtre (moitié gauche,
//  moitié droite, plein écran utile…) à partir de la zone utile
//  d'un écran, c'est-à-dire l'écran sans la barre des menus ni le Dock.
//
//  Ce fichier contient aussi LA fonction de conversion entre les deux
//  systèmes de coordonnées de macOS (piège n°1 du cahier des charges).
//

import CoreGraphics

/// Les zones où l'on peut ranger une fenêtre.
enum Zone: CaseIterable {
    case leftHalf     // moitié gauche
    case rightHalf    // moitié droite
    case maximize     // tout l'écran utile (sans plein écran natif)
    case topLeft      // quart en haut à gauche
    case topRight     // quart en haut à droite
    case bottomLeft   // quart en bas à gauche
    case bottomRight  // quart en bas à droite
}

enum ZoneCalculator {

    /// Rectangle cible d'une zone, en coordonnées « écran » de macOS
    /// (origine en bas à gauche, comme `NSScreen.visibleFrame`).
    static func frame(for zone: Zone, in visible: CGRect) -> CGRect {
        let halfWidth = (visible.width / 2).rounded(.down)
        // Attention : en coordonnées NSScreen, le « haut » a les y les plus grands.
        let bottomHeight = (visible.height / 2).rounded(.down)
        let topHeight = visible.height - bottomHeight
        let leftX = visible.minX
        let rightX = visible.minX + halfWidth
        let rightWidth = visible.width - halfWidth
        let bottomY = visible.minY
        let topY = visible.minY + bottomHeight

        switch zone {
        case .topLeft:
            return CGRect(x: leftX, y: topY, width: halfWidth, height: topHeight)
        case .topRight:
            return CGRect(x: rightX, y: topY, width: rightWidth, height: topHeight)
        case .bottomLeft:
            return CGRect(x: leftX, y: bottomY, width: halfWidth, height: bottomHeight)
        case .bottomRight:
            return CGRect(x: rightX, y: bottomY, width: rightWidth, height: bottomHeight)
        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY,
                          width: halfWidth, height: visible.height)
        case .rightHalf:
            return CGRect(x: visible.minX + halfWidth, y: visible.minY,
                          width: visible.width - halfWidth, height: visible.height)
        case .maximize:
            return visible
        }
    }

    /// Convertit un rectangle d'un système de coordonnées à l'autre.
    ///
    /// - `NSScreen` (AppKit) : origine en **bas** à gauche de l'écran principal, y vers le haut.
    /// - Accessibilité (AX) : origine en **haut** à gauche de l'écran principal, y vers le bas.
    ///
    /// La formule est la même dans les deux sens, d'où une seule fonction.
    /// `primaryHeight` = hauteur de l'écran principal (celui qui a la barre des menus).
    static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.minY - rect.height,
               width: rect.width,
               height: rect.height)
    }
}
