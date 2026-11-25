#!/bin/bash
#
# publier.sh : publie une nouvelle version de Swipe sur GitHub.
#
# Ce que fait le script :
#   1. prend l'app exportée par Xcode dans build/export ;
#   2. fabrique le DMG (Swipe.app + raccourci vers Applications) ;
#   3. signe le DMG avec la clé Sparkle (rangée dans le trousseau) ;
#   4. écrit l'annonce de mise à jour (appcast.xml) ;
#   5. crée la « Release » sur GitHub avec le DMG et l'annonce.
#
# Avant de le lancer :
#   - augmenter la version dans Xcode (Version et Build) ;
#   - Product → Archive → Distribute App → Custom → Copy App,
#     enregistrer dans le dossier  build/export  du projet ;
#   - avoir tout enregistré dans Git et envoyé sur GitHub (git push).
#
# Utilisation :  Scripts/publier.sh "Ce qui change (français)" "What's new (English)"
# (sans texte anglais, le français est repris tel quel)
#
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="Nic0vd/Swipe"
TEAM="X3GBSP2626"
NOTES_FR="${1:-}"
NOTES_EN="${2:-}"

fail() { echo "❌ $1" >&2; exit 1; }

# --- 1. L'app exportée par Xcode -------------------------------------------
# (Xcode crée un sous-dossier daté à chaque export : on prend le plus récent.)
APP=$(ls -td build/export/*.app build/export/*/*.app 2>/dev/null | head -1 || true)
[ -n "$APP" ] || fail "Aucune app dans build/export. Dans Xcode : Product → Archive → Distribute App → Custom → Copy App, vers le dossier build/export du projet."

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
VERSION=$(plist CFBundleShortVersionString)
BUILD=$(plist CFBundleVersion)
MIN_OS=$(plist LSMinimumSystemVersion)
TAG="v$VERSION"
[ -n "$NOTES_FR" ] || NOTES_FR="Swipe $VERSION"
[ -n "$NOTES_EN" ] || NOTES_EN="$NOTES_FR"

echo "▶︎ Swipe $VERSION (build $BUILD), macOS $MIN_OS minimum"

# Copie de travail hors du dossier Documents : iCloud Drive y colle des
# attributs invisibles (FinderInfo, fileprovider) que la vérification stricte
# de la signature refuse. On les retire en copiant.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ditto --norsrc --noextattr --noqtn "$APP" "$WORK/Swipe.app"
APP="$WORK/Swipe.app"

codesign --verify --deep --strict "$APP" || fail "La signature de l'app est invalide."
SIGN_INFO=$(codesign -dv "$APP" 2>&1)   # lu d'abord en entier (grep -q + pipefail = faux échec)
[[ "$SIGN_INFO" == *"TeamIdentifier=$TEAM"* ]] \
  || fail "L'app n'est pas signée avec ta Personal Team ($TEAM). Les mises à jour seraient refusées."

gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
  && fail "La version $TAG existe déjà sur GitHub. Augmente la version dans Xcode et refais l'Archive."

if [ -n "$(git status --porcelain)" ]; then
  echo "⚠️  Des modifications ne sont pas enregistrées dans Git (la publication continue quand même)."
fi

SPARKLE_BIN=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Glisse-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)
[ -x "$SPARKLE_BIN/sign_update" ] || fail "Outils Sparkle introuvables : ouvre le projet dans Xcode et compile-le une fois."

# --- 2. Le DMG ----------------------------------------------------------------
STAGE="$WORK/dmg"
DMG="build/Swipe-$VERSION.dmg"
rm -f "$DMG"
mkdir -p "$STAGE"
ditto --norsrc --noextattr "$APP" "$STAGE/Swipe.app"   # nommée Swipe.app (la signature reste valide)
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Swipe $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "✓ DMG : $DMG"

# --- 3. Signature Sparkle -----------------------------------------------------
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG")   # sparkle:edSignature="…" sparkle:length="…"
echo "✓ DMG signé pour Sparkle"

# --- 4. L'annonce de mise à jour (appcast.xml) --------------------------------
URL="https://github.com/$REPO/releases/download/$TAG/Swipe-$VERSION.dmg"
DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
html() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
NOTES_HTML="<p>🇬🇧 $(html "$NOTES_EN")</p><p>🇫🇷 $(html "$NOTES_FR")</p>"
cat > build/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Swipe</title>
    <item>
      <title>Swipe $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES_HTML]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF
echo "✓ Annonce : build/appcast.xml"

# --- 5. Publication sur GitHub ------------------------------------------------
gh release create "$TAG" "$DMG" build/appcast.xml \
  --repo "$REPO" --title "Swipe $VERSION" --notes "$(printf '🇬🇧 %s\n\n🇫🇷 %s' "$NOTES_EN" "$NOTES_FR")"
echo "✓ Publié : https://github.com/$REPO/releases/tag/$TAG"
echo "  Les Swipe déjà installés verront la mise à jour à leur prochaine vérification."
