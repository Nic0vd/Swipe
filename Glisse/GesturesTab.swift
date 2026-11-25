//
//  GesturesTab.swift
//  Glisse
//
//  L'onglet « Gestes » des Réglages : chaque geste, avec son animation
//  et une explication. Les animations sont dessinées en direct par
//  GestureDemo (le même dessin que le GIF du README).
//

import SwiftUI

struct GesturesTab: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Tous les gestes se font avec **deux doigts sur le trackpad**, le curseur posé sur la **barre de titre** d'une fenêtre. Partout ailleurs, le défilement marche normalement.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(GestureDemo.all) { gesture in
                    GestureRow(gesture: gesture)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Astuces").font(.headline)
                    Label("Tant que tes doigts sont posés, tu peux changer d'avis : la fenêtre suit.", systemImage: "arrow.triangle.swap")
                    Label("Pour annuler, ramène tes doigts près du point de départ avant de les lever.", systemImage: "arrow.uturn.backward")
                    Label("Enchaîne les gestes sans bouger la souris : Swipe garde la même fenêtre.", systemImage: "rectangle.on.rectangle")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(width: SettingsView.windowSize.width, height: SettingsView.windowSize.height)
    }
}

/// Une ligne : l'animation à gauche, le nom et l'explication à droite.
struct GestureRow: View {

    let gesture: GestureDemo.Gesture

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            GestureAnimation(gesture: gesture)
                .frame(width: 176, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(gesture.symbol)
                        .foregroundStyle(.tint)
                    Text(gesture.title)
                }
                .font(.headline)
                Text(gesture.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// L'animation d'un geste, rejouée en boucle (environ 30 images par seconde).
struct GestureAnimation: View {

    let gesture: GestureDemo.Gesture
    var look: GestureDemo.PreviewLook = .liveMini

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: GestureDemo.duration)
                // La scène fait 800 × 545 : on la réduit pour remplir la vignette.
                let scene = GestureDemo.size
                let scale = min(size.width / scene.width, size.height / scene.height)
                let x = (size.width - scene.width * scale) / 2
                let y = (size.height - scene.height * scale) / 2
                context.withCGContext { cg in
                    cg.translateBy(x: x, y: y)
                    cg.scaleBy(x: scale, y: scale)
                    GestureDemo.draw(gesture, at: t, in: cg, look: look)
                }
            }
        }
        .background(Color(red: 0.93, green: 0.94, blue: 0.97))
        .accessibilityLabel("Animation : \(gesture.symbol), \(gesture.title)")
    }
}
