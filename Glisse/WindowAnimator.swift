//
//  WindowAnimator.swift
//  Glisse
//
//  Fait glisser et redimensionner une fenêtre en douceur jusqu'à sa cible.
//
//  Principe : la fenêtre est tirée vers sa cible par un « ressort » amorti
//  (sans rebond). À chaque rafraîchissement de l'écran, on calcule la
//  nouvelle position et la nouvelle vitesse, et on place la fenêtre.
//  Avantages par rapport à une courbe à durée fixe :
//    - si la cible change en route (swipe en direct), la fenêtre garde son
//      élan et s'infléchit en douceur, sans cassure ;
//    - le mouvement est calé sur l'écran (display link), donc sans à-coups.
//

import AppKit
import ApplicationServices
import QuartzCore

final class WindowAnimator: NSObject {

    /// Raideur du ressort. Plus grand = plus rapide. Avec 32, la fenêtre fait
    /// 95 % du chemin en 0,15 s (comme l'ancienne animation validée par Nicolas),
    /// puis se pose en douceur.
    static let stiffness: CGFloat = 32

    /// Temps maximum accordé à une app pour répondre, en secondes.
    /// Au-delà, on n'attend pas : une app lente ne doit pas bloquer Swipe.
    private static let appTimeout: Float = 0.25

    /// Sécurité : une animation ne dure jamais plus d'une seconde.
    private static let maxDuration: CFTimeInterval = 1

    /// L'animation en cours, s'il y en a une (une seule à la fois).
    private static var current: WindowAnimator?

    private let window: AXUIElement
    private let app: AXUIElement
    private var target: CGRect
    private var spring: SpringRect
    private var lastApplied: CGRect          // dernière position donnée à la fenêtre
    private var lastTime: CFTimeInterval?
    private var startTime = CACurrentMediaTime()
    private var displayLink: CADisplayLink?
    private var restoreEnhancedUI = false

    // MARK: - Utilisation

    /// Amène `window` de `start` à `target` (coordonnées AX, origine en haut à gauche).
    /// Si la fenêtre est déjà en mouvement, elle garde son élan et change de cible.
    static func animate(_ window: AXUIElement, from start: CGRect, to target: CGRect) {
        if let running = current {
            if CFEqual(running.window, window) {
                running.retarget(to: target)
                return
            }
            running.finish()
        }
        guard start != target else {
            WindowManager.setFrame(target, of: window)
            return
        }
        let animator = WindowAnimator(window: window, start: start, target: target)
        current = animator
        animator.begin()
    }

    /// Termine tout de suite l'animation en cours (la fenêtre saute à sa place finale).
    static func stopCurrent() {
        current?.finish()
    }

    // MARK: - Fonctionnement interne

    private init(window: AXUIElement, start: CGRect, target: CGRect) {
        self.window = window
        self.target = target
        self.spring = SpringRect(start: start)
        self.lastApplied = start
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        self.app = AXUIElementCreateApplication(pid)
        super.init()
        AXUIElementSetMessagingTimeout(window, Self.appTimeout)
        AXUIElementSetMessagingTimeout(app, Self.appTimeout)
    }

    private func begin() {
        // Certaines apps (Chrome, Electron…) animent elles-mêmes chaque
        // changement quand « AXEnhancedUserInterface » est actif, ce qui rend
        // le mouvement saccadé. On le coupe pendant l'animation, puis on le remet.
        if boolAttribute("AXEnhancedUserInterface", of: app) {
            setEnhancedUI(false)
            restoreEnhancedUI = true
        }

        // Une image à chaque rafraîchissement de l'écran.
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let link = screen?.displayLink(target: self, selector: #selector(step(_:))) {
            link.add(to: .main, forMode: .common)   // continue même pendant qu'un menu est ouvert
            displayLink = link
        } else {
            finish()
        }
    }

    /// Nouvelle cible en route : on garde la position et la vitesse actuelles.
    private func retarget(to newTarget: CGRect) {
        target = newTarget
        startTime = CACurrentMediaTime()
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = min(max(now - (lastTime ?? now - 1.0 / 60.0), 0), 1.0 / 30.0)
        lastTime = now

        spring.advance(toward: target, stiffness: Self.stiffness, dt: CGFloat(dt))

        if spring.isSettled(on: target) || CACurrentMediaTime() - startTime > Self.maxDuration {
            finish()
            return
        }
        apply(spring.rounded)
    }

    /// Envoie à la fenêtre seulement ce qui a changé, dans le bon ordre :
    /// - fenêtre qui rétrécit : la taille d'abord (sinon le bord opposé tremble) ;
    /// - fenêtre qui grandit : la position d'abord (sinon elle déborde un instant).
    private func apply(_ frame: CGRect) {
        let moved = frame.origin != lastApplied.origin
        let resized = frame.size != lastApplied.size
        guard moved || resized else { return }

        let shrinking = frame.width < lastApplied.width || frame.height < lastApplied.height
        if shrinking {
            if resized { WindowManager.setSize(frame.size, of: window) }
            if moved { WindowManager.setPosition(frame.origin, of: window) }
        } else {
            if moved { WindowManager.setPosition(frame.origin, of: window) }
            if resized { WindowManager.setSize(frame.size, of: window) }
        }
        lastApplied = frame
    }

    /// Fin : la fenêtre est placée exactement sur sa cible.
    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        WindowManager.setFrame(target, of: window)
        lastApplied = target
        if restoreEnhancedUI {
            setEnhancedUI(true)
            restoreEnhancedUI = false
        }
        if Self.current === self {
            Self.current = nil
        }
    }

    // MARK: - Petits outils

    private func setEnhancedUI(_ on: Bool) {
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString,
                                     on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    private func boolAttribute(_ attribute: String, of element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }
}

// MARK: - Le ressort

/// Un rectangle tiré vers une cible par quatre ressorts amortis sans rebond
/// (« amortissement critique ») : un pour x, y, la largeur et la hauteur.
/// Calcul exact, donc stable même si une image arrive en retard.
struct SpringRect {
    private(set) var value: [CGFloat]          // x, y, largeur, hauteur
    private(set) var velocity: [CGFloat] = [0, 0, 0, 0]

    init(start: CGRect) {
        value = [start.minX, start.minY, start.width, start.height]
    }

    var rect: CGRect { CGRect(x: value[0], y: value[1], width: value[2], height: value[3]) }

    /// Position arrondie au point près, sans grossir la fenêtre.
    var rounded: CGRect {
        CGRect(x: value[0].rounded(), y: value[1].rounded(),
               width: value[2].rounded(), height: value[3].rounded())
    }

    mutating func advance(toward target: CGRect, stiffness omega: CGFloat, dt: CGFloat) {
        let goal = [target.minX, target.minY, target.width, target.height]
        let decay = exp(-omega * dt)
        for i in 0..<4 {
            let offset = value[i] - goal[i]
            let temp = (velocity[i] + omega * offset) * dt
            value[i] = goal[i] + (offset + temp) * decay
            velocity[i] = (velocity[i] - omega * temp) * decay
        }
    }

    /// Arrivé : à moins d'un point de la cible et presque immobile
    /// (le reste du mouvement serait invisible).
    func isSettled(on target: CGRect) -> Bool {
        let goal = [target.minX, target.minY, target.width, target.height]
        for i in 0..<4 where abs(value[i] - goal[i]) > 1 || abs(velocity[i]) > 30 {
            return false
        }
        return true
    }
}
