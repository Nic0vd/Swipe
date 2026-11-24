//
//  PermissionManager.swift
//  Glisse
//
//  Vérifie si Swipe a la permission « Accessibilité » de macOS,
//  la demande si besoin, et ouvre les Réglages au bon endroit.
//  Sans cette permission, Swipe ne peut ni lire ni déplacer
//  les fenêtres des autres apps.
//

import AppKit
import ApplicationServices
import Observation

@Observable
final class PermissionManager {

    /// `true` quand macOS a autorisé Swipe dans
    /// Réglages Système → Confidentialité et sécurité → Accessibilité.
    private(set) var isTrusted: Bool = AXIsProcessTrusted()

    /// Vérifie l'état toutes les 1,5 s, car macOS ne prévient pas
    /// l'app quand on coche ou décoche la case dans les Réglages.
    private var timer: Timer?

    init() {
        if !isTrusted {
            requestPermission()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    /// Relit l'état de la permission.
    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    /// Affiche la fenêtre système « Swipe souhaite contrôler cet ordinateur… ».
    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// Ouvre une fenêtre du Finder avec Swipe.app sélectionnée,
    /// pour pouvoir la glisser dans la liste Accessibilité des Réglages.
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Ouvre directement la page Accessibilité des Réglages Système.
    func openSettings() {
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: address) {
            NSWorkspace.shared.open(url)
        }
    }
}
