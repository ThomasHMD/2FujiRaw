# 2FujiRaw

> **Nouveau, v0.2.0 (14/11/2026) : le module Lightroom Classic.** La conversion
> se lance depuis Lightroom, sur les photos sélectionnées, et le DNG Fuji revient
> empilé sur l'original avec ses mots-clés, sa note et ses retouches. La
> conversion des DNG Leica est maintenant dans l'app.
> ➜ [Télécharger la v0.2.0](https://github.com/ThomasHMD/2FujiRaw/releases/tag/v0.2.0) ·
> [Ce que fait le module](#module-lightroom-classic)

App macOS qui convertit des RAW qui ne viennent pas d'un boîtier Fuji en DNG
"maquillés" en **Fuji GFX 100S II**, pour débloquer les **Film Simulations Fuji
natives** (Provia, Velvia, Astia, Classic Chrome, Classic Neg, Eterna, Acros,
Pro Neg Hi/Std, Nostalgic Neg, Reala Ace…) dans Lightroom Classic.

Conversions disponibles :
- `Hasselblad X2D II 100C → Fuji GFX 100S II`
- `Leica DNG → Fuji GFX 100S II`
- `Leica DNG → Hasselblad X2D`

La conversion Leica est une contribution de [smartfuse](https://github.com/smartfuse)
([demande n° 1](https://github.com/ThomasHMD/2FujiRaw/pull/1)).

---

## Télécharger

### ➜ [**2FujiRaw.dmg** (dernière release)](https://github.com/ThomasHMD/2FujiRaw/releases/latest/download/2FujiRaw.dmg)

~20 Mo · macOS 13+ · Apple Silicon (arm64) · signé ad-hoc

### ➜ [**2FujiRaw-Lightroom.zip**, le module Lightroom Classic](https://github.com/ThomasHMD/2FujiRaw/releases/latest/download/2FujiRaw-Lightroom.zip)

~15 Mo · la même conversion depuis Lightroom, app comprise (cf [Module Lightroom Classic](#module-lightroom-classic))

Voir toutes les versions et leur changelog dans
[Releases](https://github.com/ThomasHMD/2FujiRaw/releases) ·
[Dernière release](https://github.com/ThomasHMD/2FujiRaw/releases/latest).

Le **code source** est ce repo même — licence GPL-3.0-or-later, cf
[`LICENSE`](./LICENSE).

---

## Pourquoi

Les Film Simulations Fuji ne sont pas des fichiers `.dcp` sur disque : elles sont
hardcodées dans le plugin Camera Raw d'Adobe et appliquées automatiquement quand
Lightroom détecte un fichier venant d'un boîtier Fuji. Le filtre se fait sur les
tags `Make` / `Model` / `UniqueCameraModel` du RAW.

En convertissant un `.3FR` Hasselblad en **DNG** (format TIFF standard), Lightroom
perd le lien avec le parseur propriétaire Hasselblad et se base uniquement sur les
tags TIFF. On peut donc les spoofer pour pointer vers un boîtier Fuji équivalent.

**Pourquoi le GFX 100S II et pas un X-T5 ?** Le Hasselblad X2D II 100C et le Fuji
GFX 100S II partagent physiquement le **même capteur Sony IMX461** (100 Mpx,
démosaïque Bayer). Le spoof est donc transparent pour le moteur de démosaïque de
Camera Raw. Spoofer vers un X-T5 imposerait une démosaïque **X-Trans** (différente)
sur des données **Bayer** → artefacts garantis.

## Comment ça marche

```
Hasselblad X2D / X2D II .3FR
      │
      ▼  [1] dnglab convert (patché pour X2D II 100C)
.dng Hasselblad
      │
      ▼  [2] exiftool : spoof Fuji
.dng Fuji GFX 100S II

Leica .DNG
      │
      ▼  [1] writer Swift natif : Leica → X2D .3FR
.3fr Hasselblad X2D
      │
      ├── sortie directe Hasselblad
      │
      ▼  [2] dnglab convert + spoof Fuji
.dng Fuji GFX 100S II
```

Les DNG Fuji s'importent ensuite dans Lightroom Classic : les profils Fuji
natifs apparaissent dans l'onglet "Camera Matching".

Les binaires `dnglab` et `exiftool` sont bundlés dans le `.app` et invoqués en
tant que sous-process. La chaîne Leica → X2D est native Swift.

### Template X2D bundlé

Les conversions Leica n'ont plus besoin d'un donor `.3FR` externe. L'app bundle
un template X2D tronqué à son en-tête utile
(`Contents/Resources/templates/hasselblad_x2d_header.3fr`, 16 Kio) et l'utilise
par défaut. L'option `--donor` côté CLI, et le sélecteur donor dans l'UI,
servent uniquement d'override.

### Pourquoi un dnglab patché

`dnglab 0.7.2` officiel ne reconnaît que le **X2D 100C** (2022), pas le
**X2D II 100C** (2024). Comme les deux boîtiers partagent le même capteur,
on ajoute simplement deux lignes d'alias dans
`rawler/data/cameras/hasselblad/x2d_100c.toml` et on recompile. Le script
`scripts/build-dnglab.sh` fait ça automatiquement (clone v0.7.2 → patch → cargo
build → copie dans `vendor/`).

## Installation (utilisateur final)

1. Télécharge le `.dmg` depuis la dernière [release GitHub](https://github.com/ThomasHMD/2FujiRaw/releases).
2. Double-clique dessus : macOS monte une fenêtre avec l'icône `2FujiRaw.app`
   et un raccourci `Applications`.
3. **Glisse `2FujiRaw.app` sur `Applications`**.
4. Éjecte le `.dmg` (clic-droit → « Éjecter »), tu peux le supprimer.

### Premier lancement

L'app est signée en **ad-hoc** (pas de compte Apple Developer). Au premier
lancement, macOS affiche :

> *« 2FujiRaw » ne peut pas être ouverte car l'identité du développeur ne peut
> pas être confirmée.*

Pour contourner, une seule fois :

1. Ouvre `/Applications` dans le Finder.
2. **Clic-droit** sur `2FujiRaw.app` → `Ouvrir`.
3. Re-clique `Ouvrir` dans la fenêtre de confirmation.

Les lancements suivants se font normalement (double-clic, Launchpad, Spotlight).

## Module Lightroom Classic

La même conversion, sans quitter Lightroom : **Bibliothèque ▸ Modules externes ▸
Convertir en Fuji GFX 100S II…** (aussi dans **Fichier ▸ Modules externes**),
sur les photos sélectionnées.

- Prend les Hasselblad `.3FR` / `.FFF` et les Leica `.DNG` ; le reste de la
  sélection est laissé de côté (le bilan dit pourquoi).
- Le DNG Fuji s'écrit à côté de l'original et entre au catalogue, **empilé
  au-dessus de lui** (Lightroom n'empile que dans un même dossier). Pile
  décochée : il va dans `DNG-Fuji-Converted/`, comme avec l'app.
- Reprend mots-clés, collections, note, drapeau, libellé, titre, légende, et
  les **réglages Développement** de l'original (décochable), **sauf le profil**.
- Applique en option un **paramètre prédéfini** de développement. Pour une
  simulation Fuji d'office : un paramètre prédéfini avec seulement le profil
  coché (Classic Chrome…), ou Préférences ▸ Paramètres prédéfinis ▸ Valeurs
  par défaut Raw ▸ GFX 100S II, que Lightroom applique seul à chaque import.

**Installation** : télécharger `2FujiRaw-Lightroom.zip` dans la
[dernière release](https://github.com/ThomasHMD/2FujiRaw/releases/latest),
le dézipper, puis Fichier ▸ Gestionnaire de modules externes ▸ Ajouter ▸
`2FujiRaw.lrplugin`. Le module embarque sa propre copie de l'app (inutile
d'installer le `.dmg`) et lève lui-même la quarantaine macOS au premier usage.
Mac Apple Silicon seulement, Lightroom Classic 10 ou plus récent.

Sans copie embarquée, le module cherche l'app dans `/Applications` puis
`~/Applications`, ou au chemin réglé dans le Gestionnaire de modules externes.

Les sources sont dans [`lightroom/`](./lightroom) : `Convertir.lua` (fenêtre et
boucle), `Conversion.lua` (une photo), `Outil.lua` (appel de la CLI),
`Regles.lua` (les décisions, sans SDK). Le SDK Lightroom n'a aucun point
d'entrée dans l'import : la conversion se lance après coup.

## Build depuis les sources (dev)

Prérequis :
- macOS 13+ sur Apple Silicon (arm64)
- Swift 5.9+ (livré avec les Command Line Tools Xcode)
- [Rust + cargo](https://rustup.rs) (pour compiler le dnglab patché)
- `unzip`, `curl`, `hdiutil` (déjà présents sur macOS — zéro dépendance tierce
  pour le `.dmg`)

```bash
# 1. Fetch les dépendances (compile dnglab patché + télécharge exiftool portable)
./scripts/fetch-deps.sh

# 2. Builder l'app (compile Swift release + assemble .app + codesign ad-hoc)
./scripts/build.sh

# 3. Tester depuis le CLI sans GUI
./src/.build/release/ToFujiRaw --cli --mapping hassy-x2d2-to-fuji-gfx100s2 /path/to/mon_fichier.3FR
./src/.build/release/ToFujiRaw --cli --mapping leica-dng-to-hasselblad-x2d2 /path/to/mon_fichier.DNG
./src/.build/release/ToFujiRaw --cli --mapping leica-dng-to-fuji-gfx100s2 /path/to/mon_fichier.DNG

# 4. Générer le .dmg final
./scripts/make-dmg.sh

# 5. Module Lightroom : dist/2FujiRaw.lrplugin + dist/2FujiRaw-Lightroom.zip
#    (--installer : le copie aussi dans les modules externes de Lightroom de ce Mac)
./scripts/make-lrplugin.sh

# Contrôles du module : règles seules, puis le module entier sur un SDK simulé
# avec la vraie app, sur la COPIE d'un .3FR
lua lightroom/tests/test_hors_lr.lua
lua lightroom/tests/test_avec_cli.lua /chemin/copie.3FR "$PWD/dist/2FujiRaw.app"
```

Essai dans le vrai Lightroom, sans interface : `lightroom/tests/essai_lightroom.py`
passe par un module d'essai qui exécute du Lua envoyé par fichier (celui de
SpektraLR chez l'auteur), importe la copie d'un `.3FR`, la convertit, relève
ce que voit Lightroom (Fujifilm GFX 100S II, profil par défaut PROVIA, pile,
note, mot-clé, collection, réglages) et exporte un JPEG par simulation. Passé
le 14/11/2026 sur Lightroom Classic 16.0.

Le flag `--donor` reste disponible si vous voulez override le template X2D bundlé :

```bash
./src/.build/release/ToFujiRaw --cli \
  --mapping leica-dng-to-hasselblad-x2d2 \
  --donor /path/to/custom_donor.3FR \
  /path/to/mon_fichier.DNG
```

## Licence

2FujiRaw est distribué sous **GPL-3.0-or-later** (cf [`LICENSE`](./LICENSE)).

Ce choix s'impose parce que le `.dmg` bundle **dnglab** (LGPL-2.1) et **exiftool**
(Artistic / GPL) : GPL-3 est la licence la plus simple qui reste compatible avec
les deux tout en garantissant que toute modification redistribuée reste libre.

Les licences complètes des dépendances tierces embarquées sont dans
[`THIRD_PARTY_LICENSES.md`](./THIRD_PARTY_LICENSES.md).

## Disclaimer

Projet indépendant, **non affilié** à Adobe, Fujifilm ou Hasselblad. Les marques
« Fujifilm », « GFX 100S II », « Hasselblad », « X2D II 100C », « Lightroom » et
les noms de Film Simulations (Provia, Velvia, Classic Chrome, etc.) appartiennent
à leurs propriétaires respectifs.

2FujiRaw ne redistribue **aucun code ni aucun profil** appartenant à Adobe,
Fujifilm ou Hasselblad. Il se contente de :
- convertir vos propres fichiers RAW en DNG (via dnglab, LGPL)
- réécrire les tags TIFF standards de ces DNG (via exiftool, Artistic/GPL)

Usage à vos propres risques, conformément aux conditions d'utilisation du logiciel
que vous utilisez pour ouvrir les DNG produits.

## Références

- Méthode originale (spoofing DNG pour débloquer les profils Fuji) :
  [rbrant.substack.com](https://rbrant.substack.com/p/how-to-use-fujifilm-profiles-with)
- [dnglab](https://github.com/dnglab/dnglab) — convertisseur RAW → DNG
- [ExifTool](https://exiftool.org/) — lecture / écriture de métadonnées
- [Spec DNG 1.4 Adobe](https://helpx.adobe.com/photoshop/digital-negative.html)
