# 2FujiRaw

App macOS qui convertit des RAW **Hasselblad X2D II 100C** en DNG "maquillés" en
**Fuji GFX 100S II**, pour débloquer les **Film Simulations Fuji natives**
(Provia, Velvia, Astia, Classic Chrome, Classic Neg, Eterna, Acros, Pro Neg Hi/Std,
Nostalgic Neg, Reala Ace…) dans Lightroom Classic sur des fichiers qui ne viennent
pas d'un boîtier Fuji.

---

## Télécharger

### ➜ [**2FujiRaw.dmg** (dernière release)](https://github.com/ThomasHMD/2FujiRaw/releases/latest/download/2FujiRaw.dmg)

~19 Mo · macOS 13+ · Apple Silicon (arm64) · signé ad-hoc

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
.3FR Hasselblad
      │
      ▼  [1] dnglab convert (patché pour X2D II 100C)
.dng (Make="Hasselblad", Model="X2D II 100C")
      │
      ▼  [2] exiftool : spoof des tags + marquage preview DNG 1.4
.dng (Make="FUJIFILM", Model="GFX 100S II", preview marqué valide)
      │
      ▼  [3] import dans Lightroom Classic
Profils Fuji natifs disponibles (onglet "Camera Matching")
```

Les binaires `dnglab` (patché) et `exiftool` sont bundlés dans le `.app` et
invoqués en tant que sous-process.

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
./src/.build/release/ToFujiRaw --cli /path/to/mon_fichier.3FR

# 4. Générer le .dmg final
./scripts/make-dmg.sh
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
