//
//  WindowManager.swift
//  Glisse
//
//  Déplace, redimensionne et réduit les fenêtres des autres apps,
//  grâce à l'API d'accessibilité de macOS (d'où la permission).
//

import AppKit
import ApplicationServices

enum WindowManager {

    // MARK: - Actions

    /// Range une fenêtre donnée dans une zone de l'écran où elle se trouve.
    static func move(_ window: AXUIElement, to zone: Zone) {
        // Si une animation tourne encore sur cette fenêtre, WindowAnimator
        // repartira de sa position réelle : pas besoin de l'arrêter ici.
        if isFullScreen(window) {
            log("fenêtre en plein écran natif : on ne touche à rien")
            return
        }
        guard isSettable(window, kAXPositionAttribute),
              isSettable(window, kAXSizeAttribute) else {
            log("fenêtre non déplaçable ou non redimensionnable : on ne touche à rien")
            return
        }
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let axFrame = frame(of: window) else { return }

        // 1. Sur quel écran est la fenêtre ? (en coordonnées NSScreen)
        let cocoaFrame = ZoneCalculator.flipped(axFrame, primaryHeight: primaryHeight)
        let screen = screenContaining(cocoaFrame)

        // 2. Où doit-elle aller ? (calcul en NSScreen, puis conversion en AX)
        let target = ZoneCalculator.frame(for: zone, in: screen.visibleFrame)
        let axTarget = ZoneCalculator.flipped(target, primaryHeight: primaryHeight)

        // 3. On y va, en douceur.
        WindowAnimator.animate(window, from: axFrame, to: axTarget)
        log("fenêtre rangée : \(zone)")
    }

    /// Ramène une fenêtre, en douceur, à un emplacement précis (coordonnées AX).
    /// Sert à la remettre à sa place d'origine quand on annule un swipe en direct.
    static func animate(_ window: AXUIElement, to target: CGRect) {
        guard let current = frame(of: window) else { return }
        WindowAnimator.animate(window, from: current, to: target)
    }

    /// Place une fenêtre d'un coup (coordonnées AX).
    /// Taille → position → taille : certaines apps refusent une taille
    /// qui dépasse de l'écran tant que la fenêtre n'a pas bougé.
    static func setFrame(_ frame: CGRect, of window: AXUIElement) {
        setSize(frame.size, of: window)
        setPosition(frame.origin, of: window)
        setSize(frame.size, of: window)
    }

    /// Réduit une fenêtre donnée dans le Dock.
    static func minimize(_ window: AXUIElement) {
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        log(result == .success ? "fenêtre réduite" : "impossible de réduire (\(result.rawValue))")
    }

    // MARK: - Écrans

    /// Zone utile (sans barre des menus ni Dock) de l'écran où se trouve
    /// la fenêtre, en coordonnées NSScreen. Sert à placer l'aperçu.
    static func visibleFrame(of window: AXUIElement) -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let axFrame = frame(of: window) else { return nil }
        let cocoaFrame = ZoneCalculator.flipped(axFrame, primaryHeight: primaryHeight)
        return screenContaining(cocoaFrame).visibleFrame
    }

    /// L'écran qui contient la plus grande partie de la fenêtre.
    private static func screenContaining(_ cocoaFrame: CGRect) -> NSScreen {
        let best = NSScreen.screens.max { a, b in
            area(a.frame.intersection(cocoaFrame)) < area(b.frame.intersection(cocoaFrame))
        }
        return best ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    // MARK: - Petites fonctions d'accès à l'API d'accessibilité

    static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axValue(_ attribute: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    /// Position et taille actuelles, en coordonnées AX (origine en haut à gauche).
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = axValue(kAXPositionAttribute, of: window),
              let sizeValue = axValue(kAXSizeAttribute, of: window) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    static func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }

    private static func isSettable(_ window: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(window, attribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    /// Fait entrer la fenêtre en plein écran macOS, ou l'en fait sortir.
    static func toggleFullScreen(_ window: AXUIElement) {
        let goingFull = !isFullScreen(window)
        if isSettable(window, "AXFullScreen") {
            let result = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString,
                                                      goingFull ? kCFBooleanTrue : kCFBooleanFalse)
            if result == .success {
                log(goingFull ? "plein écran : entrée" : "plein écran : sortie")
                return
            }
        }
        // Plan B : appuyer sur le bouton vert de la fenêtre.
        if let button = element(kAXFullScreenButtonAttribute, of: window) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            log("plein écran : bouton vert pressé")
        } else {
            log("cette fenêtre ne peut pas passer en plein écran")
        }
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }

    private static func log(_ message: String) {
        print("[Swipe] \(message)")
    }
}
