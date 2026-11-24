//
//  SwipeDirection.swift
//  Glisse
//
//  Les directions d'un swipe (4 droites + 4 diagonales) et les règles
//  pour décider, au lâcher, ce qu'il faut faire. Ce fichier ne fait que
//  des calculs : il est facile à tester.
//

import CoreGraphics

/// Les directions possibles d'un swipe, du point de vue des doigts.
enum SwipeDirection: String, CaseIterable {
    case left      = "← gauche"
    case right     = "→ droite"
    case up        = "↑ haut"
    case down      = "↓ bas"
    case upLeft    = "↖ haut-gauche"
    case upRight   = "↗ haut-droite"
    case downLeft  = "↙ bas-gauche"
    case downRight = "↘ bas-droite"

    /// Tolérance d'angle (en degrés) de chaque côté d'un axe droit.
    /// 22,5° = le cercle coupé en 8 parts égales de 45°.
    /// Plus grand = les diagonales sont plus difficiles à déclencher.
    static let straightHalfAngle: CGFloat = 22.5

    // « Accroche » : une fois une direction choisie, on la garde tant qu'on
    // ne s'en écarte pas franchement. Sans ça, quand les doigts sont pile sur
    // une frontière, la direction (et donc la fenêtre) fait des allers-retours.

    /// Pour revenir à « rien », il faut revenir sous 60 % du seuil.
    static let releaseRatio: CGFloat = 0.6
    /// Pour changer de direction, il faut dépasser la frontière d'au moins 8°.
    static let stickyAngle: CGFloat = 8

    /// Angle de la direction, en degrés (0 = droite, 90 = haut).
    var angle: CGFloat {
        switch self {
        case .right:     return 0
        case .upRight:   return 45
        case .up:        return 90
        case .upLeft:    return 135
        case .left:      return 180
        case .downLeft:  return 225
        case .down:      return 270
        case .downRight: return 315
        }
    }

    var isDiagonal: Bool {
        switch self {
        case .upLeft, .upRight, .downLeft, .downRight: return true
        default: return false
        }
    }

    /// Zone où ranger la fenêtre, ou `nil` pour ↓ (réduire dans le Dock).
    var zone: Zone? {
        switch self {
        case .left:      return .leftHalf
        case .right:     return .rightHalf
        case .up:        return .maximize
        case .down:      return nil
        case .upLeft:    return .topLeft
        case .upRight:   return .topRight
        case .downLeft:  return .bottomLeft
        case .downRight: return .bottomRight
        }
    }

    /// Direction d'un déplacement des doigts (x vers la droite, y vers le haut),
    /// ou `nil` si le déplacement est plus court que `threshold`.
    /// `current` = la direction affichée jusqu'ici, pour l'« accroche ».
    static func from(dx: CGFloat, dy: CGFloat, threshold: CGFloat,
                     current: SwipeDirection? = nil) -> SwipeDirection? {
        let needed = current == nil ? threshold : threshold * releaseRatio
        guard hypot(dx, dy) >= needed else { return nil }

        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }

        // On garde la direction actuelle tant qu'on reste dans sa part du
        // cercle, élargie de `stickyAngle` de chaque côté.
        if let current {
            let halfWidth = (current.isDiagonal ? 45 - straightHalfAngle : straightHalfAngle) + stickyAngle
            let gap = abs(degrees - current.angle)
            if min(gap, 360 - gap) <= halfWidth {
                return current
            }
        }

        // Proche d'un axe droit ? Alors c'est une direction droite.
        let axes: [(CGFloat, SwipeDirection)] = [(0, .right), (90, .up), (180, .left), (270, .down), (360, .right)]
        for (axis, direction) in axes where abs(degrees - axis) <= straightHalfAngle {
            return direction
        }
        // Sinon, c'est la diagonale du quart de cercle.
        switch degrees {
        case ..<90:  return .upRight
        case ..<180: return .upLeft
        case ..<270: return .downLeft
        default:     return .downRight
        }
    }
}

// Règle au lâcher (choix de Nicolas) : c'est la direction au moment du lâcher
// qui compte, même si l'on a changé d'avis en route (← puis → = →).
// Pour annuler, on ramène les doigts près du point de départ : la distance
// repasse sous le seuil, `from` renvoie nil et rien ne se passe.
