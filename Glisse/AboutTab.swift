//
//  AboutTab.swift
//  Glisse
//
//  L'onglet « À propos » des Réglages : l'icône, le nom, la version
//  actuelle, les mises à jour et le lien vers le projet sur GitHub.
//

import SwiftUI

struct AboutTab: View {

    @State private var autoUpdate = true

    var body: some View {
        VStack(spacing: 0) {
            // En-tête : icône, nom, version
            VStack(spacing: 6) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("Swipe")
                    .font(.system(size: 24, weight: .bold))
                Text("Version \(Self.version)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Range tes fenêtres avec un swipe à deux doigts sur la barre de titre.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 32)

            Form {
                Section("Mises à jour") {
                    Toggle("Rechercher les mises à jour automatiquement", isOn: $autoUpdate)
                        .onChange(of: autoUpdate) { _, newValue in
                            UpdateManager.shared.automaticallyChecks = newValue
                        }
                    HStack {
                        Text("Swipe vérifie une fois par jour s'il existe une nouvelle version.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Rechercher maintenant…") {
                            UpdateManager.shared.checkForUpdates()
                        }
                    }
                }

                Section("Projet") {
                    Link(destination: URL(string: "https://github.com/Nic0vd/Swipe")!) {
                        Label("Le projet sur GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://github.com/Nic0vd/Swipe/releases")!) {
                        Label("Notes de version et téléchargements", systemImage: "list.bullet.rectangle")
                    }
                    Text("Mises à jour automatiques grâce à Sparkle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
        .frame(width: SettingsView.windowSize.width, height: SettingsView.windowSize.height)
        .onAppear { autoUpdate = UpdateManager.shared.automaticallyChecks }
    }

    /// Version affichée, par exemple « 1.3 (4) ».
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
