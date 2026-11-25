//
//  UpdateManager.swift
//  Glisse
//
//  Mises à jour automatiques avec Sparkle.
//  Une fois par jour, Swipe lit l'annonce de la dernière version publiée
//  sur GitHub (appcast.xml). S'il y a plus récent, il propose de la
//  télécharger, vérifie qu'elle est bien signée par Nicolas, l'installe
//  et se relance.
//

import AppKit
import Sparkle

final class UpdateManager: NSObject, SPUStandardUserDriverDelegate {

    static let shared = UpdateManager()

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: self)
    }

    /// Réglage « Rechercher les mises à jour automatiquement ».
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Menu « Rechercher des mises à jour… ».
    func checkForUpdates() {
        // Swipe n'a pas d'icône dans le Dock : on la passe au premier plan
        // pour que la fenêtre de Sparkle ne s'ouvre pas en dessous.
        NSApplication.shared.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: - Swipe vit dans la barre des menus

    // Sparkle recommande, pour les apps sans icône dans le Dock, d'accepter
    // les rappels « en douceur » et de passer l'app au premier plan quand
    // une mise à jour s'affiche.

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        NSApplication.shared.activate()
    }
}
