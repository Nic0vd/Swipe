//
//  SettingsView.swift
//  Glisse
//
//  La fenêtre de Réglages (menu Swipe → Réglages…).
//  Les choix sont enregistrés automatiquement et retenus après avoir quitté.
//

import SwiftUI

/// Comment montrer où la fenêtre va aller pendant un swipe.
enum PreviewMode: String, CaseIterable, Identifiable {
    case live       // la fenêtre bouge en direct
    case liveMini   // la fenêtre bouge en direct + vignette près du curseur
    case large      // grand rectangle, la fenêtre bouge au lâcher
    case mini       // vignette près du curseur, la fenêtre bouge au lâcher
    case both       // grand rectangle + vignette, la fenêtre bouge au lâcher

    /// Nom de la préférence enregistrée.
    static let storageKey = "previewMode"

    /// Le choix par défaut : en direct + vignette (choix de Nicolas).
    static let defaultMode: PreviewMode = .liveMini

    /// Le choix actuel.
    static var current: PreviewMode {
        PreviewMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? defaultMode
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live:     return "La fenêtre se déplace en direct"
        case .liveMini: return "En direct + vignette à côté du curseur"
        case .large:    return "Grand rectangle sur l'écran (déplacement au lâcher)"
        case .mini:     return "Vignette à côté du curseur (déplacement au lâcher)"
        case .both:     return "Grand rectangle + vignette (déplacement au lâcher)"
        }
    }

    var movesWindowLive: Bool { self == .live || self == .liveMini }
    var showsLarge: Bool { self == .large || self == .both }
    var showsMini: Bool { self == .mini || self == .both || self == .liveMini }
}

struct SettingsView: View {

    @AppStorage("enabled") private var isEnabled = true
    @AppStorage(PreviewMode.storageKey) private var previewMode: PreviewMode = PreviewMode.defaultMode
    @AppStorage(GestureMonitor.thresholdKey) private var threshold: Double = GestureMonitor.defaultThreshold

    private let launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        Form {
            Section("Général") {
                Toggle("Activer Swipe", isOn: $isEnabled)

                Toggle("Lancer Swipe au démarrage du Mac", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if launchAtLogin.needsApproval {
                    Text("À autoriser dans Réglages Système → Général → Ouverture.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !launchAtLogin.isInstalled {
                    Text("Conseil : place Swipe dans le dossier Applications avant de cocher cette case.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sensibilité") {
                Slider(value: $threshold, in: GestureMonitor.thresholdRange, step: 10) {
                    Text("Sensibilité")
                } minimumValueLabel: {
                    Text("Très sensible")
                } maximumValueLabel: {
                    Text("Peu sensible")
                }
                .labelsHidden()
                Text("Distance à parcourir avec les doigts : \(Int(threshold)) points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Aperçu pendant le swipe") {
                Picker("Aperçu", selection: $previewMode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Section("Mises à jour") {
                Toggle("Rechercher les mises à jour automatiquement", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, newValue in
                        UpdateManager.shared.automaticallyChecks = newValue
                    }
                HStack {
                    Text("Version \(Self.version)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Rechercher maintenant…") {
                        UpdateManager.shared.checkForUpdates()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
        .onAppear {
            launchAtLogin.refresh()
            autoUpdate = UpdateManager.shared.automaticallyChecks
        }
    }

    @State private var autoUpdate = true

    /// Version affichée, par exemple « 1.0 (1) ».
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
