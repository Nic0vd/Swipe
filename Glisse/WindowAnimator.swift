//
//  WindowAnimator.swift
//  Glisse
//
//  Fait glisser et redimensionner une fenêtre en douceur, de sa place
//  actuelle jusqu'à sa zone cible, au lieu de la téléporter.
//
//  Principe : environ 120 fois par seconde, on calcule où la fenêtre
//  devrait être à cet instant et on la place là. Le mouvement ralentit
//  en fin de course (« ease-out »), ce qui paraît plus naturel.
//
//  Si la cible change en cours de route (swipe en direct), la nouvelle
//  animation repart de là où la fenêtre se trouve vraiment : pas de saut.
//

import ApplicationServices
import Foundation

final class WindowAnimator {

    /// Durée de l'animation, en secondes. 0 = placement instantané.
    static let duration: TimeInterval = 0.15

    /// Temps maximum accordé à une app pour répondre, en secondes.
    /// Au-delà, on n'attend pas : une app lente ne doit pas bloquer Swipe.
    private static let appTimeout: Float = 0.25

    /// L'animation en cours, s'il y en a une (une seule à la fois).
    private static var current: WindowAnimator?

    private let window: AXUIElement
    private let app: AXUIElement
    private let start: CGRect
    private let target: CGRect
    private let startTime = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    private var lastApplied: CGRect       // dernière position donnée à la fenêtre
    private var restoreEnhancedUI = false

    // MARK: - Utilisation

    /// Anime `window` de `start` à `target` (coordonnées AX, origine en haut à gauche).
    static func animate(_ window: AXUIElement, from start: CGRect, to target: CGRect) {
        var start = start
        var enhancedUIWasOn = false

        if let running = current {
            if CFEqual(running.window, window) {
                // Même fenêtre, nouvelle cible : on repart de là où elle est.
                start = running.lastApplied
                enhancedUIWasOn = running.restoreEnhancedUI
                running.cancel(keepEnhancedUIOff: true)
            } else {
                running.finish()
            }
        }

        guard duration > 0, start != target else {
            WindowManager.setFrame(target, of: window)
            if enhancedUIWasOn {
                setEnhancedUI(true, on: appElement(of: window))
            }
            return
        }

        let animator = WindowAnimator(window: window, start: start, target: target)
        current = animator
        animator.begin(enhancedUIWasOn: enhancedUIWasOn)
    }

    /// Termine tout de suite l'animation en cours (la fenêtre saute à sa place finale).
    static func stopCurrent() {
        current?.finish()
    }

    // MARK: - Fonctionnement interne

    private init(window: AXUIElement, start: CGRect, target: CGRect) {
        self.window = window
        self.start = start
        self.target = target
        self.lastApplied = start
        self.app = Self.appElement(of: window)
        AXUIElementSetMessagingTimeout(window, Self.appTimeout)
        AXUIElementSetMessagingTimeout(app, Self.appTimeout)
    }

    private func begin(enhancedUIWasOn: Bool) {
        // Certaines apps (Chrome, Electron…) animent elles-mêmes chaque
        // changement quand « AXEnhancedUserInterface » est actif, ce qui rend
        // le mouvement saccadé. On le coupe pendant l'animation, puis on le remet.
        if enhancedUIWasOn {
            restoreEnhancedUI = true      // déjà coupé par l'animation précédente
        } else if boolAttribute("AXEnhancedUserInterface", of: app) {
            Self.setEnhancedUI(false, on: app)
            restoreEnhancedUI = true
        }

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // Mode « common » : l'animation continue même pendant qu'un menu est ouvert.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func tick() {
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        let progress = min(1, elapsed / Self.duration)
        if progress >= 1 {
            finish()
            return
        }
        // Ease-out cubique : rapide au début, ralentit à l'arrivée.
        let eased = 1 - pow(1 - progress, 3)
        let frame = CGRect(
            x: start.minX + (target.minX - start.minX) * eased,
            y: start.minY + (target.minY - start.minY) * eased,
            width: start.width + (target.width - start.width) * eased,
            height: start.height + (target.height - start.height) * eased
        ).integral
        WindowManager.setPosition(frame.origin, of: window)
        WindowManager.setSize(frame.size, of: window)
        lastApplied = frame
    }

    /// Fin normale : la fenêtre est placée exactement sur sa cible.
    private func finish() {
        timer?.invalidate()
        timer = nil
        WindowManager.setFrame(target, of: window)
        lastApplied = target
        if restoreEnhancedUI {
            Self.setEnhancedUI(true, on: app)
            restoreEnhancedUI = false
        }
        if Self.current === self {
            Self.current = nil
        }
    }

    /// Arrêt en route, sans placer la fenêtre sur la cible.
    private func cancel(keepEnhancedUIOff: Bool) {
        timer?.invalidate()
        timer = nil
        if restoreEnhancedUI && !keepEnhancedUIOff {
            Self.setEnhancedUI(true, on: app)
        }
        restoreEnhancedUI = false
        if Self.current === self {
            Self.current = nil
        }
    }

    // MARK: - Petits outils

    private static func appElement(of window: AXUIElement) -> AXUIElement {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return AXUIElementCreateApplication(pid)
    }

    private static func setEnhancedUI(_ on: Bool, on app: AXUIElement) {
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
