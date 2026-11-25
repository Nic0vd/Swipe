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
import Foundation

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

/// Les marges autour des fenêtres rangées, réglables dans les Réglages.
enum WindowGap {
    static let key = "windowGap"
    static let range: ClosedRange<Double> = 0...24

    /// En points ; 0 par défaut (les fenêtres touchent les bords).
    static var current: CGFloat {
        let saved = UserDefaults.standard.object(forKey: key) as? Double ?? 0
        return CGFloat(min(max(saved, range.lowerBound), range.upperBound))
    }
}

enum ZoneCalculator {

    /// Rectangle cible d'une zone, en coordonnées « écran » de macOS
    /// (origine en bas à gauche, comme `NSScreen.visibleFrame`).
    ///
    /// `gap` : marge en points. Elle s'applique tout autour de l'écran, et
    /// entre deux fenêtres voisines (la moitié de chaque côté, pour que
    /// l'espace entre deux moitiés soit aussi égal à `gap`).
    static func frame(for zone: Zone, in visible: CGRect, gap: CGFloat = 0) -> CGRect {
        guard gap > 0 else { return rawFrame(for: zone, in: visible) }
        let area = visible.insetBy(dx: gap, dy: gap)
        var f = rawFrame(for: zone, in: area)
        let half = gap / 2
        // Bords intérieurs (qui ne touchent pas le bord de l'écran) : demi-marge.
        if f.minX > area.minX + 0.5 { f.origin.x += half; f.size.width -= half }
        if f.maxX < area.maxX - 0.5 { f.size.width -= half }
        if f.minY > area.minY + 0.5 { f.origin.y += half; f.size.height -= half }
        if f.maxY < area.maxY - 0.5 { f.size.height -= half }
        return f
    }

    /// Le rectangle sans aucune marge.
    private static func rawFrame(for zone: Zone, in visible: CGRect) -> CGRect {
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
