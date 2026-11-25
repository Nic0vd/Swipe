//
//  Haptics.swift
//  Glisse
//
//  Le retour haptique : un petit « tic » dans le trackpad quand la zone
//  visée change pendant un swipe (ou quand le pincement est assez marqué).
//  Ne marche qu'avec un trackpad Force Touch.
//
//  macOS ne permet pas de régler une intensité précise : il propose trois
//  sortes de « tic ». « Fort » en joue deux, très rapprochés.
//

import AppKit

/// La force du « tic », réglable dans les Réglages.
enum HapticStrength: String, CaseIterable, Identifiable {
    case light, medium, strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light:  return String(localized: "Léger")
        case .medium: return String(localized: "Moyen")
        case .strong: return String(localized: "Fort")
        }
    }
}

enum Haptics {

    /// Noms des préférences enregistrées.
    static let enabledKey = "hapticsEnabled"
    static let strengthKey = "hapticsStrength"

    /// Activé par défaut.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// « Moyen » par défaut.
    static var strength: HapticStrength {
        HapticStrength(rawValue: UserDefaults.standard.string(forKey: strengthKey) ?? "") ?? .medium
    }

    /// Joue un « tic », si le retour haptique est activé.
    static func tick() {
        guard isEnabled else { return }
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch strength {
        case .light:
            performer.perform(.alignment, performanceTime: .now)
        case .medium:
            performer.perform(.levelChange, performanceTime: .now)
        case .strong:
            performer.perform(.generic, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
                performer.perform(.generic, performanceTime: .now)
            }
        }
    }
}
