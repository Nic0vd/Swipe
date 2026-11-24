//
//  TitleBarDetector.swift
//  Glisse
//
//  Trouve la fenêtre qui se trouve sous le curseur et dit si le curseur
//  est sur sa barre de titre (la bande du haut, avec les 3 boutons ronds).
//
//  Version simple pour commencer (piège n°4 du cahier des charges) :
//  - barre de titre standard : 28 points de haut ;
//  - si la fenêtre a une barre d'outils (Finder, Safari, Mail…), la barre
//    de titre va jusqu'en bas de cette barre d'outils.
//

import AppKit
import ApplicationServices

/// Ce qu'on a trouvé sous le curseur.
struct WindowHit {
    let window: AXUIElement
    let appName: String
    let elementRole: String     // type d'élément sous le curseur (pour comprendre les cas tordus)
    let cursorFromTop: CGFloat  // distance entre le haut de la fenêtre et le curseur
    let titleBarHeight: CGFloat // hauteur de barre de titre retenue pour cette fenêtre
    let isOnTitleBar: Bool
}

enum TitleBarDetector {

    /// Hauteur d'une barre de titre standard de macOS, en points.
    static let standardTitleBarHeight: CGFloat = 28

    /// Point d'entrée de l'API d'accessibilité pour « tout l'écran ».
    /// Si une app met plus de 0,25 s à répondre, on abandonne : la détection
    /// a lieu pendant le geste et doit rester rapide.
    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }()

    /// Analyse ce qui se trouve au point donné (coordonnées AX : origine en haut à gauche).
    static func hit(at point: CGPoint) -> WindowHit? {
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &found) == .success,
              let element = found,
              let window = window(containing: element),
              let frame = WindowManager.frame(of: window) else {
            return nil
        }

        let height = titleBarHeight(of: window, windowTop: frame.minY)
        let fromTop = point.y - frame.minY
        let onTitleBar = fromTop >= 0 && fromTop <= height

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"

        return WindowHit(window: window,
                         appName: appName,
                         elementRole: role(of: element) ?? "?",
                         cursorFromTop: fromTop,
                         titleBarHeight: height,
                         isOnTitleBar: onTitleBar)
    }

    // MARK: - Trouver la fenêtre

    /// Remonte de l'élément sous le curseur (un bouton, un texte…) jusqu'à sa fenêtre.
    private static func window(containing element: AXUIElement) -> AXUIElement? {
        if role(of: element) == kAXWindowRole {
            return element
        }
        if let window = WindowManager.element(kAXWindowAttribute, of: element) {
            return window
        }
        // Certaines apps ne donnent pas directement la fenêtre : on remonte
        // de parent en parent (20 niveaux maximum, par prudence).
        var current = element
        for _ in 0..<20 {
            guard let parent = WindowManager.element(kAXParentAttribute, of: current) else {
                return nil
            }
            if role(of: parent) == kAXWindowRole {
                return parent
            }
            current = parent
        }
        return nil
    }

    // MARK: - Hauteur de la barre de titre

    /// 28 points, ou plus si la fenêtre a une barre d'outils unifiée.
    private static func titleBarHeight(of window: AXUIElement, windowTop: CGFloat) -> CGFloat {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return standardTitleBarHeight
        }
        for child in children where role(of: child) == kAXToolbarRole {
            if let toolbar = WindowManager.frame(of: child) {
                return max(standardTitleBarHeight, toolbar.maxY - windowTop)
            }
        }
        return standardTitleBarHeight
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
