# Licences des dépendances tierces

2FujiRaw embarque deux composants externes dans son `.dmg`. Cette page liste
leurs licences et renvoie vers les sources.

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
