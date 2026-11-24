//
//  LaunchAtLogin.swift
//  Glisse
//
//  Lance l'app automatiquement à l'ouverture de session sur le Mac,
//  grâce au service officiel de macOS (SMAppService). L'app apparaît
//  alors dans Réglages Système → Général → Ouverture.
//

import Foundation
import Observation
import ServiceManagement

@Observable
final class LaunchAtLogin {

    static let shared = LaunchAtLogin()

    /// L'app est inscrite au démarrage du Mac.
    private(set) var isEnabled = false
    /// macOS attend une validation dans Réglages Système → Général → Ouverture.
    private(set) var needsApproval = false

    /// Vrai si l'app tourne depuis le dossier Applications (version « installée »).
    /// Les versions lancées depuis Xcode sont ailleurs, dans un dossier temporaire.
    var isInstalled: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    private init() {
        refresh()
    }

    /// Relit l'état auprès de macOS.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    /// Inscrit l'app au démarrage du Mac, ou l'en retire.
    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Swipe] lancement au démarrage : échec (\(error.localizedDescription))")
        }
        refresh()
    }

    /// Case cochée par défaut : au tout premier lancement depuis le dossier
    /// Applications, on inscrit l'app au démarrage. On ne le fait qu'une fois,
    /// pour respecter le choix de l'utilisateur s'il décoche la case ensuite.
    static func applyDefaultOnFirstLaunch() {
        let key = "launchAtLoginInitialized"
        guard !UserDefaults.standard.bool(forKey: key), shared.isInstalled else { return }
        UserDefaults.standard.set(true, forKey: key)
        shared.set(true)
    }
}
