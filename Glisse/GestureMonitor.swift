//
//  GestureMonitor.swift
//  Glisse
//
//  Écoute les mouvements à deux doigts sur le trackpad (macOS les envoie
//  sous forme d'événements de « défilement »).
//
//  Si le geste COMMENCE sur une barre de titre :
//    - on « avale » tous ses événements, pour que l'app en dessous ne défile pas,
//      y compris l'inertie après le lâcher ;
//    - pendant le geste, on montre ce qui va se passer (fenêtre en direct,
//      rectangle, vignette, ou bouton jaune / vert) ;
//    - au lâcher, on agit.
//  Partout ailleurs, on laisse passer : le défilement marche normalement.
//

import AppKit
import CoreGraphics

/// Ce que fera le swipe au lâcher.
enum SwipeAction: Equatable {
    case zone(Zone)          // ranger dans une zone (moitié, quart, maximiser)
    case minimize            // réduire dans le Dock
    case toggleFullScreen    // entrer en plein écran macOS, ou en sortir
}

final class GestureMonitor {

    /// Sensibilité : distance (en points) que les doigts doivent parcourir
    /// avant qu'un swipe compte. Plus petit = plus sensible.
    /// Réglable dans les Réglages (curseur « Sensibilité »).
    static let thresholdKey = "threshold"
    static let defaultThreshold: Double = 80
    static let thresholdRange: ClosedRange<Double> = 40...160

    /// La sensibilité choisie dans les Réglages.
    static var currentThreshold: CGFloat {
        let saved = UserDefaults.standard.object(forKey: thresholdKey) as? Double ?? defaultThreshold
        return CGFloat(min(max(saved, thresholdRange.lowerBound), thresholdRange.upperBound))
    }

    /// Mode direct : temps d'attente avant de déplacer la vraie fenêtre.
    /// Si la direction change encore pendant ce temps (doigts qui tournent),
    /// on attend : la fenêtre ne court pas après chaque direction.
    static let liveDelay: TimeInterval = 0.05

    /// Appui prolongé : temps (en secondes) pendant lequel les deux doigts
    /// doivent rester posés sans bouger avant le swipe. Ensuite, ↑ = plein écran.
    static let holdDuration: TimeInterval = 0.15

    /// Enchaînement : si un nouveau geste commence moins de 1,5 s après le
    /// précédent, sans que le curseur ait bougé, on continue avec la même
    /// fenêtre. Sinon, comme elle a glissé sous le curseur, celui-ci peut se
    /// retrouver au-dessus d'une autre fenêtre, qu'on ne veut pas toucher.
    static let followUpDelay: TimeInterval = 1.5
    static let followUpCursorTolerance: CGFloat = 3

    /// Fermer : pincer avec deux doigts sur la barre de titre, comme pour
    /// dézoomer. macOS mesure le pincement en « zoom » : 0 au début, négatif
    /// quand les doigts se rapprochent. Au-delà de −0,25, la fenêtre sera
    /// fermée au lâcher.
    static let pinchCloseThreshold: CGFloat = 0.25

    /// Types d'événements « geste » du trackpad (pincement, rotation…).
    private static let gestureEventTypes: Set<UInt32> = [
        UInt32(NSEvent.EventType.gesture.rawValue),
        UInt32(NSEvent.EventType.magnify.rawValue),
    ]

    private var tap: CFMachPort?

    /// Le dernier geste capté : sa fenêtre, la position du curseur et l'heure.
    private var lastCapture: (window: AXUIElement, cursor: CGPoint, time: TimeInterval)?
    private var retryTimer: Timer?

    // Moment où deux doigts se sont posés (avant de bouger), pour l'appui prolongé
    private var fingersDownTime: TimeInterval?

    // État du geste capté en cours
    private var isCapturing = false          // un geste a commencé sur une barre de titre
    private var targetWindow: AXUIElement?   // la fenêtre concernée
    private var screenArea: CGRect?          // zone utile de son écran (pour l'aperçu)
    private var windowFrame: CGRect?         // place d'origine de la fenêtre (coordonnées NSScreen)
    private var originalAXFrame: CGRect?     // la même, en coordonnées AX (pour l'y ramener)
    private var windowIsFullScreen = false   // la fenêtre est en plein écran macOS
    private var heldBeforeSwipe = false      // appui prolongé avant de bouger
    private var previewActive = false       // l'aperçu est apparu pendant ce geste
    private var cursor: CGPoint = .zero      // position du curseur (pour le mini-aperçu)
    private var mode: PreviewMode = PreviewMode.defaultMode   // réglage choisi par l'utilisateur
    private var threshold: CGFloat = 80      // sensibilité, relue au début de chaque geste
    private var fingerX: CGFloat = 0         // + = les doigts vont vers la droite
    private var fingerY: CGFloat = 0         // + = les doigts vont vers le haut
    private var lastDirection: SwipeDirection?
    private var swallowingMomentum = false   // on avale l'inertie du geste capté
    private var pendingLiveMove: DispatchWorkItem?   // déplacement en direct en attente

    // État du pincement capté en cours
    private var pinchWindow: AXUIElement?    // la fenêtre à fermer
    private var pinchFrame: CGRect?          // sa place (coordonnées NSScreen), pour le bouton rouge
    private var pinchTotal: CGFloat = 0      // zoom cumulé (négatif = doigts qui se rapprochent)
    private var pinchArmed = false           // seuil dépassé : la fenêtre sera fermée au lâcher

    init() {
        start()
    }

    // MARK: - Mise en route

    /// Branche l'écoute du trackpad. Sans permission Accessibilité, macOS
    /// refuse : on réessaie alors toutes les 2 secondes.
    func start() {
        guard tap == nil else { return }

        // On écoute les défilements (swipes) et les gestes (pincements).
        var mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        for type in Self.gestureEventTypes {
            mask |= CGEventMask(1) << CGEventMask(type)
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: gestureTapCallback,
                                          userInfo: me) else {
            log("écoute du trackpad impossible pour l'instant (permission ?), nouvel essai dans 2 s")
            scheduleRetry()
            return
        }

        self.tap = tap
        retryTimer?.invalidate()
        retryTimer = nil
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("écoute du trackpad démarrée (sensibilité : \(Int(Self.currentThreshold)) points)")
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.start()
            }
        }
    }

    // MARK: - Traitement de chaque événement (doit rester très rapide)

    /// Renvoie l'événement pour le laisser passer, ou `nil` pour l'avaler.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        // Piège n°2 : macOS coupe l'écoute si on est trop lent, ou parfois
        // sans raison. On la rallume aussitôt.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("écoute coupée par macOS, rallumée")
            return passThrough
        }

        // Pincement (et autres gestes du trackpad) : traité à part.
        if Self.gestureEventTypes.contains(type.rawValue) {
            return handlePinch(event)
        }

        // On ne garde que les défilements « continus », c'est-à-dire ceux du
        // trackpad. Une molette de souris classique n'est jamais touchée.
        guard type == .scrollWheel,
              event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
              let ns = NSEvent(cgEvent: event) else {
            return passThrough
        }

        // Piège n°3 : l'inertie. Après le lâcher, macOS continue d'envoyer des
        // défilements pour que la page « glisse ». Pour un geste capté, on les avale.
        if ns.momentumPhase != [] {
            guard swallowingMomentum else { return passThrough }
            if ns.momentumPhase.contains(.ended) || ns.momentumPhase.contains(.cancelled) {
                swallowingMomentum = false
            }
            return nil
        }

        // Deux doigts viennent de se poser, sans bouger encore : on note l'heure.
        if ns.phase.contains(.mayBegin) {
            fingersDownTime = ns.timestamp
            return passThrough
        }

        // Un nouveau geste commence : est-ce sur une barre de titre ?
        if ns.phase.contains(.began) {
            swallowingMomentum = false
            let held = fingersDownTime.map { ns.timestamp - $0 } ?? 0
            fingersDownTime = nil
            // event.location : position du curseur, origine en haut à gauche (comme l'API AX).
            beginGesture(at: event.location, heldFor: held)
            return isCapturing ? nil : passThrough
        }

        // Doigts levés sans avoir bougé : plus d'appui en cours.
        if ns.phase.contains(.cancelled) && !isCapturing {
            fingersDownTime = nil
        }

        // Geste non capté : on ne s'en mêle pas.
        guard isCapturing else { return passThrough }

        if ns.phase.contains(.changed) {
            updateGesture(with: ns)
        } else if ns.phase.contains(.ended) {
            endGesture()
            swallowingMomentum = true
        } else if ns.phase.contains(.cancelled) {
            // En mode direct, la fenêtre a peut-être déjà bougé : on la remet en place.
            if mode.movesWindowLive, previewActive, !windowIsFullScreen { restoreWindow() }
            resetGesture()
            log("   geste interrompu par macOS : rien")
        }
        return nil
    }

    private func beginGesture(at location: CGPoint, heldFor held: TimeInterval) {
        resetGesture()

        guard let (window, origin) = chooseWindow(at: location) else { return }
        let mouse = NSEvent.mouseLocation   // coordonnées NSScreen

        isCapturing = true
        targetWindow = window
        screenArea = WindowManager.visibleFrame(of: window)
        if let axFrame = WindowManager.frame(of: window),
           let primaryHeight = NSScreen.screens.first?.frame.height {
            originalAXFrame = axFrame
            windowFrame = ZoneCalculator.flipped(axFrame, primaryHeight: primaryHeight)
        }
        windowIsFullScreen = WindowManager.isFullScreen(window)
        heldBeforeSwipe = held >= Self.holdDuration
        cursor = mouse
        mode = PreviewMode.current
        threshold = Self.currentThreshold

        var details = "doigts immobiles \(String(format: "%.2f", held)) s"
        if heldBeforeSwipe { details += " → appui prolongé (↑ = plein écran)" }
        if windowIsFullScreen { details += ", fenêtre en plein écran" }
        log("geste capté : \(origin)  (\(details))")
    }

    /// Quelle fenêtre vise ce geste ? La même que le geste précédent s'il
    /// enchaîne (curseur immobile, moins de 1,5 s), sinon celle dont la barre
    /// de titre est sous le curseur. `nil` : le geste ne concerne pas Swipe.
    private func chooseWindow(at location: CGPoint) -> (AXUIElement, String)? {
        let enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        guard enabled else { return nil }

        let now = ProcessInfo.processInfo.systemUptime
        let mouse = NSEvent.mouseLocation   // coordonnées NSScreen

        if let last = lastCapture,
           now - last.time < Self.followUpDelay,
           hypot(mouse.x - last.cursor.x, mouse.y - last.cursor.y) <= Self.followUpCursorTolerance,
           WindowManager.frame(of: last.window) != nil {
            return (last.window, "suite du geste précédent, même fenêtre")
        }
        if let hit = TitleBarDetector.hit(at: location), hit.isOnTitleBar {
            return (hit.window, "barre de titre de \(hit.appName)")
        }
        lastCapture = nil
        return nil
    }

    // MARK: - Pincement (fermer la fenêtre)

    /// Pincement sur une barre de titre : bouton rouge dès que le seuil est
    /// dépassé, fermeture au lâcher. Ailleurs, le pincement marche normalement
    /// (zoom dans Safari, Plans…).
    private func handlePinch(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        guard let ns = NSEvent(cgEvent: event), ns.type == .magnify else {
            // Autres gestes (rotation…) : avalés seulement pendant un pincement capté.
            return pinchWindow == nil ? passThrough : nil
        }

        if ns.phase.contains(.began) {
            beginPinch(at: event.location)
            return pinchWindow == nil ? passThrough : nil
        }
        guard let window = pinchWindow else { return passThrough }

        if ns.phase.contains(.changed) {
            pinchTotal += ns.magnification
            let armed = pinchTotal <= -Self.pinchCloseThreshold
            if armed != pinchArmed {
                pinchArmed = armed
                if armed, let frame = pinchFrame {
                    ActionBadge.shared.show(.close, centeredOn: frame)
                } else {
                    ActionBadge.shared.hide()
                }
                Haptics.tick()
                log("   pincement \(String(format: "%.2f", pinchTotal)) : \(armed ? "la fenêtre sera fermée" : "rien")")
            }
        } else if ns.phase.contains(.ended) {
            let close = pinchArmed
            log("   pincement relâché à \(String(format: "%.2f", pinchTotal)) : \(close ? "fermeture" : "rien")")
            resetPinch()
            if close {
                lastCapture = nil
                DispatchQueue.main.async {
                    WindowManager.close(window)
                }
            }
        } else if ns.phase.contains(.cancelled) {
            resetPinch()
        }
        return nil
    }

    private func beginPinch(at location: CGPoint) {
        resetPinch()
        guard let (window, origin) = chooseWindow(at: location) else { return }
        pinchWindow = window
        if let axFrame = WindowManager.frame(of: window),
           let primaryHeight = NSScreen.screens.first?.frame.height {
            pinchFrame = ZoneCalculator.flipped(axFrame, primaryHeight: primaryHeight)
        }
        log("pincement capté : \(origin)")
    }

    private func resetPinch() {
        if pinchArmed { ActionBadge.shared.hide() }
        pinchWindow = nil
        pinchFrame = nil
        pinchTotal = 0
        pinchArmed = false
    }

    private func updateGesture(with event: NSEvent) {
        // Avec le « défilement naturel » de macOS (réglage par défaut), les
        // valeurs sont inversées par rapport au mouvement des doigts.
        // On les remet dans le sens des doigts.
        let natural = event.isDirectionInvertedFromDevice
        fingerX += natural ? event.scrollingDeltaX : -event.scrollingDeltaX
        fingerY += natural ? -event.scrollingDeltaY : event.scrollingDeltaY

        let direction = SwipeDirection.from(dx: fingerX, dy: fingerY,
                                            threshold: threshold, current: lastDirection)
        if direction != lastDirection {
            lastDirection = direction
            log("   en cours : \(direction?.rawValue ?? "(pas assez loin)")")

            // L'aperçu apparaît quand on dépasse le seuil, puis reste actif
            // jusqu'au lâcher, même si les doigts repassent par le point de départ.
            if direction != nil { previewActive = true }
            if previewActive {
                showPreview(for: action(for: direction))
                Haptics.tick()      // un « tic » à chaque changement de zone
            }
        }
    }

    /// Direction → action, selon la fenêtre et l'appui prolongé.
    private func action(for direction: SwipeDirection?) -> SwipeAction? {
        guard let direction else { return nil }
        // Appui prolongé puis ↑ : plein écran (entrée ou sortie).
        if direction == .up && heldBeforeSwipe {
            return .toggleFullScreen
        }
        // Une fenêtre en plein écran ne se range pas dans une zone.
        if windowIsFullScreen {
            return nil
        }
        if let zone = direction.zone {
            return .zone(zone)
        }
        return .minimize
    }

    // MARK: - Aperçus

    /// Montre ce qui se passerait si l'on lâchait maintenant.
    private func showPreview(for action: SwipeAction?) {
        guard let area = screenArea, let window = targetWindow else { return }

        switch action {
        case .zone(let zone):
            // Ranger : la fenêtre en direct et/ou rectangle et/ou vignette.
            ActionBadge.shared.hide()
            let frame = ZoneCalculator.frame(for: zone, in: area, gap: WindowGap.current)
            if mode.movesWindowLive { scheduleLiveMove(to: zone, window: window) }
            showFramePreviews(frame, in: area)

        case .minimize, .toggleFullScreen:
            // Réduire ou plein écran : la fenêtre reste à sa place et un gros
            // bouton jaune ou vert remplace les autres aperçus.
            if mode.movesWindowLive { scheduleLiveMove(to: nil, window: window) }
            hideFramePreviews()
            let kind: BadgeKind = action == .minimize
                ? .minimize
                : (windowIsFullScreen ? .exitFullScreen : .enterFullScreen)
            ActionBadge.shared.show(kind, centeredOn: windowFrame ?? area)

        case nil:
            // Doigts revenus au départ : la fenêtre ne bougera pas.
            ActionBadge.shared.hide()
            if mode.movesWindowLive { scheduleLiveMove(to: nil, window: window) }
            if windowIsFullScreen {
                hideFramePreviews()
            } else if let original = windowFrame {
                showFramePreviews(original, in: area)
            }
        }
    }

    /// Le grand rectangle et/ou la vignette, selon le réglage.
    private func showFramePreviews(_ frame: CGRect, in area: CGRect) {
        if mode.showsLarge {
            PreviewOverlay.shared.show(frame)
        } else {
            PreviewOverlay.shared.hide()
        }
        if mode.showsMini {
            MiniPreview.shared.show(zone: frame, in: area, near: cursor)
        } else {
            MiniPreview.shared.hide()
        }
    }

    private func hideFramePreviews() {
        PreviewOverlay.shared.hide()
        MiniPreview.shared.hide()
    }

    private func hideAllPreviews() {
        hideFramePreviews()
        ActionBadge.shared.hide()
    }

    // MARK: - Déplacements en direct

    /// Déplace la vraie fenêtre après un court délai. Un nouvel appel
    /// pendant ce délai remplace le précédent. Le déplacement a lieu hors de
    /// l'écoute du trackpad, pour ne jamais la ralentir.
    /// `zone == nil` : la fenêtre revient à sa place d'origine.
    private func scheduleLiveMove(to zone: Zone?, window: AXUIElement) {
        pendingLiveMove?.cancel()
        guard !windowIsFullScreen else { return }   // on ne bouge pas une fenêtre plein écran
        let original = originalAXFrame
        let work = DispatchWorkItem {
            if let zone {
                WindowManager.move(window, to: zone)
            } else if let original {
                WindowManager.animate(window, to: original)
            }
        }
        pendingLiveMove = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.liveDelay, execute: work)
    }

    /// Ramène la fenêtre à sa place d'origine, en douceur.
    private func restoreWindow() {
        guard let window = targetWindow, let original = originalAXFrame else { return }
        DispatchQueue.main.async {
            WindowManager.animate(window, to: original)
        }
    }

    // MARK: - Lâcher

    private func endGesture() {
        // On agit selon ce qui est affiché à l'écran (accroche comprise).
        let action = action(for: lastDirection)
        let window = targetWindow
        let live = mode.movesWindowLive && !windowIsFullScreen
        let wasActive = previewActive
        let original = originalAXFrame
        resetGesture()   // annule aussi un déplacement en direct encore en attente

        guard let window else { return }
        log("   au lâcher : \(action.map { "\($0)" } ?? "rien (swipe trop court ou retour au départ)")")

        // On retient la fenêtre pour un éventuel geste qui enchaîne, sauf si
        // elle part dans le Dock ou change de plein écran.
        switch action {
        case .minimize, .toggleFullScreen:
            lastCapture = nil
        case .zone, nil:
            lastCapture = (window, NSEvent.mouseLocation, ProcessInfo.processInfo.systemUptime)
        }

        // On agit juste après, pour rendre la main à macOS au plus vite.
        DispatchQueue.main.async {
            Self.perform(action, on: window, original: original, movedLive: live, wasActive: wasActive)
        }
    }

    /// Au lâcher : on s'assure que la fenêtre finit au bon endroit, même si
    /// le dernier déplacement en direct n'a pas eu le temps de partir.
    private static func perform(_ action: SwipeAction?, on window: AXUIElement,
                                original: CGRect?, movedLive: Bool, wasActive: Bool) {
        switch action {
        case .zone(let zone):
            WindowManager.move(window, to: zone)

        case .minimize:
            // En mode direct, la fenêtre reprend d'abord sa place d'origine.
            if movedLive {
                WindowAnimator.stopCurrent()
                if let original { WindowManager.setFrame(original, of: window) }
            }
            WindowManager.minimize(window)

        case .toggleFullScreen:
            if movedLive {
                WindowAnimator.stopCurrent()
                if let original { WindowManager.setFrame(original, of: window) }
            }
            WindowManager.toggleFullScreen(window)

        case nil:
            // Annulé : en mode direct, retour à la place d'origine.
            if movedLive, wasActive, let original {
                WindowManager.animate(window, to: original)
            }
        }
    }

    private func resetGesture() {
        pendingLiveMove?.cancel()
        pendingLiveMove = nil
        hideAllPreviews()
        isCapturing = false
        targetWindow = nil
        screenArea = nil
        windowFrame = nil
        originalAXFrame = nil
        windowIsFullScreen = false
        heldBeforeSwipe = false
        previewActive = false
        fingerX = 0
        fingerY = 0
        lastDirection = nil
    }

    private func log(_ message: String) {
        print("[Swipe] \(message)")
    }
}

/// Fonction appelée par macOS pour chaque événement de défilement.
/// Elle doit être une fonction « C » simple : elle retrouve le
/// GestureMonitor grâce au pointeur `refcon` et lui passe la main.
private nonisolated func gestureTapCallback(proxy: CGEventTapProxy,
                                            type: CGEventType,
                                            event: CGEvent,
                                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<GestureMonitor>.fromOpaque(refcon).takeUnretainedValue()
    // L'écoute est branchée sur le fil principal : on y est déjà.
    return MainActor.assumeIsolated {
        monitor.handle(type: type, event: event)
    }
}
