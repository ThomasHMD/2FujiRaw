-- Contrôles hors de Lightroom : Regles (sans SDK). Lancer : lua lightroom/tests/test_hors_lr.lua
package.path = arg[0]:gsub('[^/]*$', '') .. '../2FujiRaw.lrplugin/?.lua;' .. package.path

local Regles = require 'Regles'
local W = require 'ChaineWindows'
local Textes = require 'Textes'

local n = 0
local function verifie(condition, message)
  n = n + 1
  if not condition then error('ÉCHEC : ' .. message, 2) end
end

-- Choix de la conversion
verifie(Regles.mapping('/a/B0002380.3FR', 'Hasselblad') == Regles.MAPPING_HASSELBLAD, '3FR')
verifie(Regles.mapping('/a/b.fff', nil) == Regles.MAPPING_HASSELBLAD, 'FFF en minuscules, sans marque')
verifie(Regles.mapping('/Été 2026/L1000123.DNG', 'Leica Camera AG') == Regles.MAPPING_LEICA, 'DNG Leica')
verifie(Regles.mapping('/a/b.dng', 'LEICA') == Regles.MAPPING_LEICA, 'DNG Leica, marque en capitales')
local m, raison = Regles.mapping('/a/DNG-Fuji-Converted/b.dng', 'FUJIFILM')
verifie(m == nil and raison:find('Fuji'), 'DNG déjà converti refusé')
m, raison = Regles.mapping('/a/b.dng', 'Apple')
verifie(m == nil and raison:find('Leica'), 'DNG d\'un autre boîtier refusé')
m, raison = Regles.mapping('/a/b.jpg', 'Hasselblad')
verifie(m == nil and raison:find('JPG'), 'JPEG refusé : ' .. tostring(raison))
m, raison = Regles.mapping('/a.b/sansext', 'Hasselblad')
verifie(m == nil and raison:find('sans extension'), 'point dans le dossier, pas dans le nom')

-- Réglages recopiés
local r = Regles.reglagesACopier {
  CameraProfile = 'Adobe Color', CameraProfileDigest = 'ABC', Exposure2012 = 0.7, CropTop = 0.1,
  WhiteBalance = 'As Shot', Temperature = 5200, Tint = 3,
}
verifie(r.CameraProfile == nil and r.CameraProfileDigest == nil, 'profil laissé de côté')
verifie(r.Exposure2012 == 0.7 and r.CropTop == 0.1, 'retouches gardées')
verifie(r.WhiteBalance == 'As Shot' and r.Temperature == nil and r.Tint == nil, 'balance telle quelle relue sur le DNG')
r = Regles.reglagesACopier { WhiteBalance = 'Custom', Temperature = 4300, Tint = 12 }
verifie(r.Temperature == 4300 and r.Tint == 12, 'balance personnalisée recopiée')
verifie(next(Regles.reglagesACopier(nil)) == nil, 'aucun réglage')

-- Sortie de la CLI
local sortie = '2FujiRaw CLI — mapping: Hasselblad X2D II → Fuji GFX 100S II\n→ 1 fichier(s) à convertir\n'
  .. '[1/1] ✓ /Volumes/SSD Spare/Été/DNG-Fuji-Converted/B0002380.dng\nOK\n'
verifie(Regles.fichierProduit(sortie) == '/Volumes/SSD Spare/Été/DNG-Fuji-Converted/B0002380.dng', 'chemin lu')
verifie(Regles.fichierProduit('[1/1] ✓ /a/b.dng \r\n') == '/a/b.dng', 'fin de ligne nettoyée')
verifie(Regles.fichierProduit('2FujiRaw CLI\n') == nil, 'rien d\'écrit')
verifie(Regles.erreurLisible('Erreur : Échec conversion DNG\n', 1) == 'Échec conversion DNG', 'erreur lisible')
verifie(Regles.erreurLisible('', 1):find('code 1'), 'erreur vide')

-- Guillemets
verifie(Regles.guillemets("L'été") == "'L'\\''été'", 'apostrophe échappée')
if package.config:sub(1, 1) == '/' then -- /bin/sh n'existe que sur Mac (la CI Windows saute ce contrôle)
  local f = io.popen('printf %s ' .. Regles.guillemets("a 'b' $HOME `x`"))
  verifie(f:read('*a') == "a 'b' $HOME `x`", 'passage intact par /bin/sh')
  f:close()
end

-- Chaîne Windows : guillemets (dans un .cmd : % doublé, " retiré, le reste inerte entre guillemets)
verifie(W.guillemets([[C:\Users\Léa Müller\L'été & co (1)\a.3FR]]) == [["C:\Users\Léa Müller\L'été & co (1)\a.3FR"]],
  'guillemets : espaces, accents, apostrophe, &, parenthèses')
verifie(W.guillemets('100%.3fr') == '"100%%.3fr"', 'guillemets : % doublé')
verifie(W.guillemets('a"b') == '"ab"', 'guillemets : " retiré')
verifie(W.guillemets('') == '""', 'guillemets : vide')

-- Commandes (identiques à ConversionEngine.swift)
verifie(W.commandeDnglab([[C:\P l\dnglab.exe]], [[D:\é'ü & co\a.3FR]], [[D:\é'ü & co\DNG-Fuji-Converted\a.dng]])
  == [["C:\P l\dnglab.exe" convert --compression lossless "D:\é'ü & co\a.3FR" "D:\é'ü & co\DNG-Fuji-Converted\a.dng"]],
  'commande dnglab')
verifie(W.commandeExiftool([[C:\P l\exiftool.exe]], [[C:\Temp\2fujiraw-lr-1-1.args]])
  == [["C:\P l\exiftool.exe" -charset filename=UTF8 -@ "C:\Temp\2fujiraw-lr-1-1.args"]], 'commande exiftool')
verifie(W.argumentsExiftool([[D:\é'ü & co\a.dng]], '0.3.0')
  == '-Make=FUJIFILM\n-Model=GFX 100S II\n-UniqueCameraModel=Fujifilm GFX 100S II\n-PreviewApplicationName=2FujiRaw\n'
  .. '-PreviewApplicationVersion=0.3.0\n-PreviewDateTime=now\n-PreviewColorSpace=sRGB\n-overwrite_original\n'
  .. [[D:\é'ü & co\a.dng]] .. '\n', 'arguments exiftool (fichier -@, nom en UTF-8 intact)')
do
  local debut = '-tagsFromFile\n' .. [[D:\é\a.3FR]] .. '\n-BaselineExposure\n-Make=FUJIFILM\n'
  verifie(W.argumentsExiftool([[D:\x\a.dng]], '0.3.0', [[D:\é\a.3FR]]):sub(1, #debut) == debut,
    'BaselineExposure recopiée du .3FR')
end

-- Script .cmd
local ligne = W.ligneAvecRedirections('"C:\\x y\\t.exe" -ver', 'C:\\T\\a.out', 'C:\\T\\a.log')
verifie(ligne == [["C:\x y\t.exe" -ver > "C:\T\a.out" 2> "C:\T\a.log"]], 'redirections')
local cmd = W.scriptCmd { ligne }
verifie(cmd:find('@echo off\r\nchcp 65001 >nul\r\n', 1, true) == 1, 'script : @echo off puis chcp 65001')
verifie(cmd:find('\r\n' .. ligne:gsub('%p', '%%%0') .. '\r\nexit /b %%ERRORLEVEL%%\r\n$'), 'script : commande puis exit /b %ERRORLEVEL%')
verifie(not cmd:find('[^\r]\n'), 'script : fins de ligne CRLF seulement')
verifie(cmd:sub(1, 3) ~= '\239\187\191', 'script : pas de BOM')
verifie(W.lancerCmd([[C:\T x\a.cmd]]) == [[""C:\T x\a.cmd""]], 'lancement : paire de guillemets en plus (cmd /c)')

-- Nom de sortie
local function joindre(d, n) return d .. '\\' .. n end
local existants = {}
local function existe(p) return existants[p] == true end
verifie(W.choisirSortie([[C:\d]], 'B02', existe, joindre) == [[C:\d\B02.dng]], 'sortie : nom libre')
existants["C:\\d\\B02.dng"] = true
verifie(W.choisirSortie([[C:\d]], 'B02', existe, joindre) == [[C:\d\B02_converted.dng]], 'sortie : _converted')
existants["C:\\d\\B02_converted.dng"] = true
verifie(W.choisirSortie([[C:\d]], 'B02', existe, joindre) == [[C:\d\B02_converted-2.dng]], 'sortie : _converted-2')
existants["C:\\d\\B02_converted-2.dng"] = true
verifie(W.choisirSortie([[C:\d]], 'B02', existe, joindre) == [[C:\d\B02_converted-3.dng]], 'sortie : _converted-3')
local d, nom, base = W.decouper([[D:\Été 2026\essai é'ü\B0002380.3FR]])
verifie(d == [[D:\Été 2026\essai é'ü]] and nom == 'B0002380.3FR' and base == 'B0002380', 'découpage Windows')
d, nom, base = W.decouper('/Volumes/a b/c.d/photo.v2.fff')
verifie(d == '/Volumes/a b/c.d' and nom == 'photo.v2.fff' and base == 'photo.v2', 'découpage Mac, points dans le nom')
d, nom, base = W.decouper('sans-dossier.3FR')
verifie(d == '' and base == 'sans-dossier', 'découpage sans dossier')

-- Code de sortie : Mac = code × 256, Windows = code tel quel
verifie(W.statut(256, false) == 1 and W.statut(0, false) == 0 and W.statut(512, false) == 2, 'statut Mac')
verifie(W.statut(1, true) == 1 and W.statut(0, true) == 0, 'statut Windows : codes bas')
verifie(W.statut(259, true) == 259 and W.statut(3221225477, true) == 3221225477, 'statut Windows : pas de division')
verifie(W.statut(-1073741819, true) == -1073741819, 'statut Windows : code négatif')
verifie(W.statut(nil, true) == nil, 'statut nil')

-- Divers purs
verifie(W.estAscii('C:\\Users\\Public') and not W.estAscii('C:\\Users\\Léa'), 'estAscii')
verifie(W.versionTexte({ major = 0, minor = 3, revision = 0 }) == '0.3.0' and W.versionTexte(nil) == W.VERSION_DEFAUT,
  'version')
local entree = W.entreeJournal('2026-11-23 10:00:00', 'Windows', '0.3.0', {
  { nom = 'dnglab', commande = '"a.exe" convert', code = 1, sortie = '', erreurs = 'boum\n' } })
verifie(entree:find('=== 2026-11-23 10:00:00 | Windows | 2FujiRaw 0.3.0', 1, true) and entree:find('> "a.exe" convert', 1, true)
  and entree:find('exit code : 1', 1, true) and entree:find('boum', 1, true), 'entrée du journal')
verifie(W.borner('abc', 10) == 'abc', 'journal court gardé')
local long = ''
for i = 1, 100 do long = long .. 'ligne ' .. i .. '\n' end
local court = W.borner(long, 100)
verifie(#court <= 100 and court:sub(-10) == 'ligne 100\n' and court:sub(1, 5) == 'ligne', 'journal borné : fin gardée, ligne entière')
verifie(Textes.langue('fr') == 'fr' and Textes.langue('fr_FR') == 'fr' and Textes.langue('en') == 'en'
  and Textes.langue(nil) == 'en' and Textes.langue('de') == 'en', 'langue')
verifie(Textes.t('leica_win', 'fr'):find('Mac seulement') and Textes.t('leica_win', 'en'):find('only available on Mac'),
  'textes bilingues')
verifie(Textes.t('echec_dnglab', 'en', '1', 'boum') == 'dnglab failed (exit code 1): boum', 'texte mis en forme')

print(n .. ' contrôles OK')
