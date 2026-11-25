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

    /// Nom court, sous chaque vignette des Réglages.
    var shortLabel: String {
        switch self {
        case .live:     return "En direct"
        case .liveMini: return "En direct + vignette"
        case .large:    return "Grand rectangle"
        case .mini:     return "Vignette"
        case .both:     return "Rectangle + vignette"
        }
    }

    /// Le même mode, pour le dessin des animations.
    var look: GestureDemo.PreviewLook {
        switch self {
        case .live:     return .live
        case .liveMini: return .liveMini
        case .large:    return .large
        case .mini:     return .mini
        case .both:     return .both
        }
    }

    var movesWindowLive: Bool { self == .live || self == .liveMini }
    var showsLarge: Bool { self == .large || self == .both }
    var showsMini: Bool { self == .mini || self == .both || self == .liveMini }
}

struct SettingsView: View {

    /// Taille fixe des onglets. En plus, `FixedSizeWindow` retire à la
    /// fenêtre le droit d'être redimensionnée (SwiftUI seul ne suffit pas).
    static let windowSize = CGSize(width: 500, height: 540)

    /// L'onglet affiché (sert aussi à re-bloquer la taille à chaque changement).
    @State private var tab = "settings"

    @AppStorage("enabled") private var isEnabled = true
    @AppStorage(PreviewMode.storageKey) private var previewMode: PreviewMode = PreviewMode.defaultMode
    @AppStorage(GestureMonitor.thresholdKey) private var threshold: Double = GestureMonitor.defaultThreshold

    private let launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        TabView(selection: $tab) {
            Tab("Réglages", systemImage: "gearshape", value: "settings") {
                settingsForm
            }
            Tab("Gestes", systemImage: "hand.draw", value: "gestures") {
                GesturesTab()
            }
            Tab("À propos", systemImage: "info.circle", value: "about") {
                AboutTab()
            }
        }
        // Tout le contenu (onglets + barre d'onglets) prend sa taille idéale et
        // n'en change pas : SwiftUI calcule alors taille mini = taille maxi.
        .fixedSize()
        .background(FixedSizeWindow(tab: tab))
    }

    /// L'onglet « Réglages ».
    private var settingsForm: some View {
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

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                    ForEach(PreviewMode.allCases) { mode in
                        PreviewModeCard(mode: mode, isSelected: mode == previewMode) {
                            previewMode = mode
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Aperçu pendant le swipe")
            } footer: {
                Text("« En direct » : la fenêtre suit tes doigts. Les autres modes la déplacent quand tu lèves les doigts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .onAppear { launchAtLogin.refresh() }
    }
}

/// Empêche la fenêtre de Réglages d'être redimensionnée ou agrandie,
/// directement au niveau de la fenêtre macOS (NSWindow).
struct FixedSizeWindow: NSViewRepresentable {

    /// L'onglet affiché : à chaque changement, on re-bloque la fenêtre,
    /// au cas où SwiftUI lui aurait rendu le droit d'être redimensionnée.
    let tab: String

    func makeNSView(context: Context) -> WindowLockView { WindowLockView() }

    func updateNSView(_ view: WindowLockView, context: Context) { view.lock() }

    final class WindowLockView: NSView {

        /// La taille retenue pour la fenêtre (calculée à la première ouverture).
        private var lockedSize: CGSize?
        private var observers: [NSObjectProtocol] = []
        private var isScheduled = false
        private var didSetInitialSize = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // SwiftUI peut rendre la fenêtre redimensionnable quand il refait sa
            // mise en page : si elle change de taille ou redevient active, on la
            // remet en place. (Surtout PAS à chaque mise à jour de la fenêtre :
            // re-bloquer provoque une mise à jour, d'où une boucle sans fin.)
            for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.lock() }
                })
            }
            lock()
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        /// On attend toujours la fin de la mise en page en cours, et on ne
        /// prévoit jamais deux blocages à la fois.
        func lock() {
            guard !isScheduled else { return }
            isScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.isScheduled = false
                self?.apply()
            }
        }

        private func apply() {
            guard let window else { return }

            // 1. La bonne taille : celle du contenu (onglets + barre d'onglets).
            //    Sans ça, la fenêtre garde la grande taille donnée à l'ouverture.
            if lockedSize == nil {
                let fitting = window.contentView?.fittingSize ?? .zero
                lockedSize = (200...1600).contains(fitting.width) && (200...1600).contains(fitting.height)
                    ? fitting
                    : CGSize(width: SettingsView.windowSize.width, height: SettingsView.windowSize.height + 40)
            }
            guard let size = lockedSize else { return }
            if window.contentMinSize != size { window.contentMinSize = size }
            if window.contentMaxSize != size { window.contentMaxSize = size }
            // La taille n'est imposée qu'UNE fois, à l'ouverture : la réimposer à
            // chaque fois risquerait un ping-pong sans fin avec SwiftUI.
            if !didSetInitialSize {
                didSetInitialSize = true
                let current = window.contentRect(forFrameRect: window.frame).size   // barre d'onglets comprise
                if abs(current.width - size.width) > 1 || abs(current.height - size.height) > 1 {
                    let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
                    window.setContentSize(size)
                    window.setFrameTopLeftPoint(topLeft)   // le haut de la fenêtre ne bouge pas
                }
            }

            // 2. Plus de redimensionnement, ni de bouton vert, ni de plein écran
            //    (seulement si besoin, pour ne rien redessiner pour rien).
            if window.styleMask.contains(.resizable) { window.styleMask.remove(.resizable) }
            if let zoom = window.standardWindowButton(.zoomButton), zoom.isEnabled { zoom.isEnabled = false }
            if !window.collectionBehavior.contains(.fullScreenNone) { window.collectionBehavior.insert(.fullScreenNone) }
        }
    }
}

/// Une vignette cliquable : l'animation d'un swipe ← avec ce mode d'aperçu.
struct PreviewModeCard: View {

    let mode: PreviewMode
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                GestureAnimation(gesture: GestureDemo.previewGesture, look: mode.look)
                    .aspectRatio(GestureDemo.size.width / GestureDemo.size.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                          lineWidth: isSelected ? 3 : 1)
                    )
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                    }
                    Text(mode.shortLabel)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
