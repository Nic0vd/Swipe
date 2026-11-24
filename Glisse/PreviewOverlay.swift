//
//  PreviewOverlay.swift
//  Glisse
//
//  Les aperçus qui montrent, pendant le swipe, où la fenêtre va se placer.
//
//  - `OverlayPanel` : le socle commun, une petite fenêtre sans bordure,
//    transparente, qui laisse passer les clics et flotte au-dessus
//    des fenêtres normales, avec apparition et disparition en fondu.
//  - `PreviewOverlay` : le GRAND aperçu, un rectangle sur la zone cible.
//  (Le mini-aperçu près du curseur est dans MiniPreview.swift.)
//

import AppKit
import QuartzCore

// MARK: - Socle commun

final class OverlayPanel {

    private let panel: NSPanel
    private(set) var isShown = false

    init(content: NSView) {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true           // les clics passent à travers
        panel.level = .floating                   // au-dessus des fenêtres normales
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = content
    }

    /// Affiche le panneau à `frame` (coordonnées NSScreen). S'il est déjà
    /// visible, il s'y déplace (en douceur si `animated`).
    func show(at frame: CGRect, animated: Bool) {
        if !isShown {
            isShown = true
            panel.setFrame(frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                panel.animator().alphaValue = 1
            }
        } else if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Fait disparaître le panneau en fondu.
    func hide() {
        guard isShown else { return }
        isShown = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Si le panneau a été réaffiché entre-temps, on ne le cache pas.
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}

// MARK: - Grand aperçu

final class PreviewOverlay {

    static let shared = PreviewOverlay()

    /// Marge entre le bord de la zone et le rectangle, pour l'esthétique.
    private static let inset: CGFloat = 6
    private static let cornerRadius: CGFloat = 12

    private let box = NSView()
    private let overlay: OverlayPanel

    private init() {
        box.wantsLayer = true
        box.layer?.cornerRadius = Self.cornerRadius
        box.layer?.borderWidth = 2
        overlay = OverlayPanel(content: box)
    }

    /// Affiche le rectangle sur `frame` (coordonnées NSScreen).
    func show(_ frame: CGRect) {
        let accent = NSColor.controlAccentColor
        box.layer?.backgroundColor = accent.withAlphaComponent(0.2).cgColor
        box.layer?.borderColor = accent.withAlphaComponent(0.7).cgColor
        overlay.show(at: frame.insetBy(dx: Self.inset, dy: Self.inset), animated: true)
    }

    func hide() {
        overlay.hide()
    }
}
