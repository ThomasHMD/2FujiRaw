# Licences des dépendances tierces

2FujiRaw embarque deux composants externes dans son `.dmg` (macOS) et dans le
module Lightroom Windows (`2FujiRaw-Lightroom-Windows.zip`). Cette page liste
leurs licences et renvoie vers les sources. La section « Distribution Windows »
en fin de page détaille ce qui est propre au module Windows.

---

## dnglab (version 0.7.2, patchée)

- **Rôle** : conversion RAW → DNG
- **Source originale** : https://github.com/dnglab/dnglab (tag `v0.7.2`)
- **Licence** : **LGPL-2.1-or-later** — https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
- **Modifications apportées** : ajout de deux alias dans
  `rawler/data/cameras/hasselblad/x2d_100c.toml` pour router les `.3FR` Hasselblad
  X2D II 100C vers le décodeur existant du X2D 100C original (même capteur
  Sony IMX461). Script reproductible : [`scripts/build-dnglab.sh`](scripts/build-dnglab.sh).

### Obligations LGPL respectées

- Les modifications sont **publiées en clair** dans ce repo (via le script qui
  applique le patch). N'importe qui peut reconstruire le binaire dnglab utilisé.
- La licence LGPL d'origine est conservée pour la partie dnglab. Seul le code
  Swift de 2FujiRaw est couvert par la GPL-3.0.
- L'utilisateur final peut remplacer le binaire `dnglab` à l'intérieur du
  `.app` (`Contents/Resources/bin/dnglab`) par sa propre compilation sans
  recompiler 2FujiRaw.

---

## ExifTool

- **Rôle** : lecture / écriture des métadonnées TIFF et DNG
- **Source** : https://exiftool.org/
- **Licence** : **« same terms as Perl itself »**, c'est-à-dire au choix :
  - **Artistic License 1.0** — https://dev.perl.org/licenses/artistic.html
  - **GPL-1.0-or-later** — https://www.gnu.org/licenses/old-licenses/gpl-1.0.txt
- **Modifications apportées** : aucune. L'archive portable est téléchargée
  telle quelle depuis exiftool.org par `scripts/fetch-deps.sh`.

Le bundle 2FujiRaw inclut le répertoire `exiftool/` complet, qui contient
lui-même sa propre notice de licence (`exiftool/README`, `exiftool/LICENSE`).

---

## Résumé de compatibilité

| Composant | Licence | Compat GPL-3 | Statut |
|---|---|---|---|
| 2FujiRaw (code Swift) | GPL-3.0-or-later | — | propre projet |
| dnglab (bundlé) | LGPL-2.1-or-later | ✅ upgradable vers GPL-3 | modifié localement, patch publié |
| ExifTool (bundlé) | Artistic / GPL-1+ | ✅ upgradable vers GPL-3 | non modifié |

Le choix de **GPL-3.0-or-later** pour 2FujiRaw garantit :
- La conformité avec la distribution combinée dnglab + exiftool
- Le droit pour tout utilisateur de recompiler, modifier et redistribuer
  l'ensemble sous les mêmes conditions

---

## Distribution Windows (`2FujiRaw-Lightroom-Windows.zip`)

Le module Windows contient, sous `2FujiRaw.lrplugin/bin/windows/` :
`dnglab.exe`, `exiftool.exe` et le dossier `exiftool_files/`. Aucun de ces
trois éléments n'est écrit par 2FujiRaw ; les `.lua` du module sont couverts par
la GPL-3.0-or-later du projet (fichier `LICENSE`).

### dnglab.exe (version 0.7.2 par défaut, patchée)

- **Source originale** : https://github.com/dnglab/dnglab, tag `v0.7.2`
  (la version est une variable `DNGLAB_VERSION` en tête de
  [`.github/workflows/windows.yml`](.github/workflows/windows.yml) ; la 0.8.0
  est utilisable avec le même patch).
- **Licence** : **LGPL-2.1** (`license = "LGPL-2.1"` dans `rawler/Cargo.toml`,
  texte de la LGPL version 2.1 dans le `LICENSE` du dépôt amont) —
  https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt. Le binaire lie
  statiquement d'autres crates Rust, chacune sous sa propre licence, listées
  dans le `Cargo.lock` du dépôt amont.
- **Binaire modifié** : oui. Le seul changement est l'ajout, dans
  `rawler/data/cameras/hasselblad/x2d_100c.toml`, de deux alias après la ligne
  `["Hasselblad X2D 100C", "X2D 100C"],` :
  `["Hasselblad X2D II 100C", "X2D 100C"],` et `["X2D II 100C", "X2D 100C"],`
  (le X2D II 100C partage le capteur du X2D 100C).
- **Où est la source correspondante** : le code amont au tag indiqué, plus le
  patch publié dans ce dépôt, [`scripts/patch-dnglab-x2d2.py`](scripts/patch-dnglab-x2d2.py).
  Le binaire est compilé par GitHub Actions
  ([`.github/workflows/windows.yml`](.github/workflows/windows.yml)) avec
  `cargo build --release --locked --bin dnglab` ; le journal de chaque exécution
  donne la version de Rust utilisée, et l'empreinte SHA-256 du binaire figure
  dans le résumé de l'exécution.
- **Remplacer le binaire** : l'utilisateur peut remplacer
  `bin\windows\dnglab.exe` par sa propre compilation de dnglab (même ligne de
  commande), sans rien recompiler d'autre.

### exiftool.exe et exiftool_files/ (ExifTool 64 bits pour Windows)

- **Origine** : l'archive officielle `exiftool-<version>_64.zip` annoncée sur
  https://exiftool.org/ (téléchargement sur SourceForge), dont la somme SHA-256
  est contrôlée contre https://exiftool.org/checksums.txt avant l'assemblage.
  Le workflow prend la dernière version publiée.
- **Modifications** : aucune sur le contenu. Seul `exiftool(-k).exe` est
  renommé `exiftool.exe`, comme le demande le `README.txt` de l'archive.
- **ExifTool** (Phil Harvey) : « same terms as Perl itself », donc au choix
  **Artistic License 1.0** ou **GPL-1.0-or-later** (en-tête de
  `exiftool_files/lib/Image/ExifTool.pm`).
- **Perl embarqué** : ce paquet de Oliver Betz embarque Strawberry Perl
  (`perl.exe`, `perl532.dll`, version 5.32.1 dans l'archive 13.64), sous les
  mêmes termes que Perl (Artistic License 1.0 ou GPL-1.0-or-later ;
  textes `perl/Artistic` et `perl/Copying`). Les DLL voisines
  (`libgcc_s_seh-1.dll`, `libstdc++-6.dll`, `libwinpthread-1.dll`,
  `liblzma-5__.dll`) viennent de la chaîne MinGW de Strawberry Perl. Leurs
  licences sont dans `exiftool_files/Licenses_Strawberry_Perl.zip`, livré tel
  quel dans le module ; `exiftool_files/readme_windows.txt` décrit la
  composition du paquet. Le fichier `exiftool_files/LICENSE` de l'archive
  contient le texte de la GPL version 3.
- **Lanceur** `exiftool.exe` : minuscule lanceur de Oliver Betz, placé sous
  licence **CC0** (d'après `exiftool_files/readme_windows.txt`).

| Composant Windows | Licence | Statut |
|---|---|---|
| dnglab.exe | LGPL-2.1 | modifié (2 alias), patch et script de compilation publiés |
| ExifTool (Perl) | Artistic 1.0 ou GPL-1.0-or-later | non modifié |
| Strawberry Perl et DLL MinGW | Perl (Artistic / GPL) ; licences des DLL dans `Licenses_Strawberry_Perl.zip` | non modifiés |
