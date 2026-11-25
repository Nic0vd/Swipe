//
//  GlisseApp.swift
//  Swipe (projet Xcode « Glisse », son nom provisoire)
//
//  Point d'entrée de l'app : c'est ce qui se lance en premier.
//  Swipe vit dans la barre des menus (en haut à droite de l'écran),
//  avec un petit menu et une fenêtre de Réglages.
//

import SwiftUI

@main
struct GlisseApp: App {

    /// Surveille la permission Accessibilité.
    @State private var permissions = PermissionManager()

    /// Écoute les gestes à deux doigts sur le trackpad.
    @State private var gestures = GestureMonitor()

    init() {
        // « Lancer au démarrage » coché par défaut (une seule fois,
        // et seulement pour la version placée dans Applications).
        LaunchAtLogin.applyDefaultOnFirstLaunch()
        // Démarre Sparkle : vérification des mises à jour une fois par jour.
        _ = UpdateManager.shared
    }

    var body: some Scene {
        // Icône dessinée sur mesure : une main avec deux doigts (Assets → MenuBarIcon).
        MenuBarExtra("Swipe", image: "MenuBarIcon") {
            MenuContent(permissions: permissions)
        }

        // La fenêtre de Réglages : fermée au lancement, ouverte depuis le menu.
        Window("Réglages de Swipe", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// Le contenu du menu de l'icône Swipe.
struct MenuContent: View {

    let permissions: PermissionManager

    /// Interrupteur général. Il est retenu même après avoir quitté l'app.
    @AppStorage("enabled") private var isEnabled = true

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Activé", isOn: $isEnabled)

        Divider()

        if permissions.isTrusted {
            Text("Accessibilité : autorisée ✅")
        } else {
            Text("Accessibilité : non autorisée ⚠️")
            Button("Demander l'autorisation") {
                permissions.requestPermission()
            }
            Button("Ouvrir les Réglages…") {
                permissions.openSettings()
            }
            Button("Montrer Swipe dans le Finder") {
                permissions.revealAppInFinder()
            }
        }

        Divider()

        Button("Réglages…") {
            openWindow(id: "settings")
            // Swipe n'a pas d'icône dans le Dock : on la passe au premier
            // plan pour que la fenêtre de Réglages ne s'ouvre pas en dessous.
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",")

        Button("Rechercher des mises à jour…") {
            UpdateManager.shared.checkForUpdates()
        }

        Divider()

        Button("Quitter Swipe") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
