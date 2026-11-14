-- Contrôles hors de Lightroom : Regles (sans SDK). Lancer : lua lightroom/tests/test_hors_lr.lua
package.path = arg[0]:gsub('[^/]*$', '') .. '../2FujiRaw.lrplugin/?.lua;' .. package.path

local Regles = require 'Regles'

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
local f = io.popen('printf %s ' .. Regles.guillemets("a 'b' $HOME `x`"))
verifie(f:read('*a') == "a 'b' $HOME `x`", 'passage intact par /bin/sh')
f:close()

print(n .. ' contrôles OK')
