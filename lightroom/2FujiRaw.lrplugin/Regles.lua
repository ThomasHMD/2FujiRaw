--[[ Regles.lua : les décisions du module, sans appel au SDK (testées hors de Lightroom par tests/test_hors_lr.lua).

  - quelle conversion de 2FujiRaw pour quel fichier ;
  - quels réglages Développement de l'original passent sur le DNG Fuji ;
  - où la CLI dit avoir écrit son fichier.
]]
local Regles = {}

Regles.MAPPING_HASSELBLAD = 'hassy-x2d2-to-fuji-gfx100s2'
Regles.MAPPING_LEICA = 'leica-dng-to-fuji-gfx100s2'

local function extension(chemin)
  return string.upper(tostring(chemin):match('%.([^./]+)$') or '')
end

-- Renvoie l'identifiant de conversion de la CLI, ou nil et la raison du refus.
-- marque : photo:getFormattedMetadata('cameraMake') (« Hasselblad », « Leica Camera AG », « FUJIFILM »…).
function Regles.mapping(chemin, marque)
  local ext = extension(chemin)
  local m = string.lower(marque or '')
  if ext == '3FR' or ext == 'FFF' then return Regles.MAPPING_HASSELBLAD end
  if ext == 'DNG' then
    if m:find('leica', 1, true) then return Regles.MAPPING_LEICA end
    if m:find('fujifilm', 1, true) then return nil, 'déjà un DNG Fuji' end
    return nil, 'DNG d\'un autre boîtier que Leica'
  end
  if ext == '' then return nil, 'fichier sans extension' end
  return nil, 'format non pris en charge (.' .. ext .. ')'
end

-- Le profil de l'original (Adobe Color, Hasselblad…) n'a pas de sens sur un DNG Fuji : il est laissé à
-- Lightroom (valeurs par défaut du GFX 100S II) ou au paramètre prédéfini choisi.
local NON_COPIES = { CameraProfile = true, CameraProfileDigest = true }

-- dev : photo:getDevelopSettings() de l'original. Renvoie la table à passer à applyDevelopSettings.
function Regles.reglagesACopier(dev)
  local r = {}
  for cle, valeur in pairs(dev or {}) do
    if not NON_COPIES[cle] then r[cle] = valeur end
  end
  -- « Telle quelle » : la température lue par Lightroom vaut pour l'original ; la recopier forcerait une
  -- balance personnalisée sur le DNG, qui doit relire celle du boîtier.
  if r.WhiteBalance == 'As Shot' then
    r.Temperature, r.Tint = nil, nil
  end
  return r
end

-- La CLI écrit « [1/1] ✓ /chemin/du/fichier.dng » par fichier converti. Renvoie le dernier chemin lu.
function Regles.fichierProduit(sortie)
  local dernier
  for chemin in tostring(sortie or ''):gmatch('✓ ([^\r\n]+)') do
    dernier = chemin:gsub('%s+$', '')
  end
  return dernier
end

-- Message d'erreur lisible depuis la sortie d'erreur de la CLI (« Erreur : … »).
function Regles.erreurLisible(erreurs, code)
  local texte = tostring(erreurs or ''):gsub('^%s+', ''):gsub('%s+$', '')
  texte = texte:gsub('^Erreur : ', '')
  if texte == '' then return '2FujiRaw a échoué (code ' .. tostring(code) .. ').' end
  return texte:sub(-600)
end

-- Guillemets simples pour /bin/sh.
function Regles.guillemets(s)
  return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

return Regles
