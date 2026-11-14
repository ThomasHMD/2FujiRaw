--[[ Conversion.lua : une photo, sans fenêtre (Convertir.lua pour la fenêtre et la boucle).

Conversion par la CLI, import du DNG au catalogue (empilé au-dessus de l'original si demandé), puis reprise
des métadonnées, des collections, des réglages Développement (sauf le profil) et du paramètre prédéfini.

Lightroom n'empile que des photos d'un même dossier : pour une pile, le DNG s'écrit à côté de l'original ;
sinon dans DNG-Fuji-Converted/, comme l'app.
]]
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Outil = require 'Outil'
local Regles = require 'Regles'

local Conversion = { TITRE = '2FujiRaw' }

local CHAMPS_TEXTE = { 'title', 'caption', 'headline', 'copyright', 'creator' }

local function lireMetadonnees(photo)
  local m = {
    motsCles = photo:getRawMetadata('keywords') or {},
    collections = photo:getContainedCollections() or {},
    note = photo:getRawMetadata('rating'),
    drapeau = photo:getRawMetadata('pickStatus'),
    libelle = photo:getFormattedMetadata('label'),
    textes = {},
  }
  for _, champ in ipairs(CHAMPS_TEXTE) do
    local ok, v = pcall(photo.getFormattedMetadata, photo, champ)
    if ok and v and v ~= '' then m.textes[champ] = v end
  end
  return m
end

-- Chaque écriture séparément : un champ refusé (collection dynamique, champ verrouillé) n'arrête pas les autres.
-- LrTasks.pcall et pas pcall : addPhotos cède la main, ce que pcall interdit (« Yielding is not allowed within a
-- C or metamethod call », vu dans Lightroom 16.0 le 14/11/2026).
local function ecrireMetadonnees(photo, m, refus)
  local function essayer(quoi, f, ...)
    local ok, erreur = LrTasks.pcall(f, ...)
    if not ok then refus[#refus + 1] = quoi .. ' (' .. tostring(erreur) .. ')' end
  end
  for _, motCle in ipairs(m.motsCles) do essayer('mot-clé', photo.addKeyword, photo, motCle) end
  for _, collection in ipairs(m.collections) do
    essayer('collection', collection.addPhotos, collection, { photo })
  end
  if m.note and m.note > 0 then essayer('note', photo.setRawMetadata, photo, 'rating', m.note) end
  if m.drapeau and m.drapeau ~= 0 then essayer('drapeau', photo.setRawMetadata, photo, 'pickStatus', m.drapeau) end
  if m.libelle and m.libelle ~= '' then essayer('libellé', photo.setRawMetadata, photo, 'label', m.libelle) end
  for champ, v in pairs(m.textes) do essayer(champ, photo.setRawMetadata, photo, champ, v) end
end

--[[ choix : reprendreReglages (bool), empiler (bool), preset (LrDevelopPreset ou nil).
Renvoie le DNG écrit, ou nil et l'erreur ; en troisième valeur, la liste des reprises refusées. ]]
function Conversion.convertir(catalogue, photo, choix)
  local chemin = photo:getRawMetadata('path')
  local mapping, raison = Regles.mapping(chemin, photo:getFormattedMetadata('cameraMake'))
  if not mapping then return nil, raison end

  local dossier = choix.empiler and LrPathUtils.parent(chemin) or nil
  local fichier, erreur = Outil.convertir(chemin, mapping, dossier)
  if not fichier then return nil, erreur end
  if catalogue:findPhotoByPath(fichier) then return fichier, nil, {} end

  local metadonnees = lireMetadonnees(photo)
  local reglages = choix.reprendreReglages and Regles.reglagesACopier(photo:getDevelopSettings()) or nil

  local refus = {}
  local nouvelle
  local function importer(pile)
    return LrTasks.pcall(function()
      catalogue:withWriteAccessDo(Conversion.TITRE, function()
        if pile then
          nouvelle = catalogue:addPhoto(fichier, photo, 'above')
        else
          nouvelle = catalogue:addPhoto(fichier)
        end
      end)
    end)
  end
  local importe, erreurImport = importer(choix.empiler)
  if not importe and choix.empiler and not catalogue:findPhotoByPath(fichier) then
    -- Pile refusée : le DNG entre quand même, sans pile.
    refus[#refus + 1] = 'pile (' .. tostring(erreurImport) .. ')'
    importe, erreurImport = importer(false)
  end
  nouvelle = nouvelle or catalogue:findPhotoByPath(fichier)
  if not importe or not nouvelle then
    return nil, 'Écrit mais pas importé (' .. fichier .. ') : ' .. tostring(erreurImport)
  end

  local repris, erreurReprise = LrTasks.pcall(function()
    catalogue:withWriteAccessDo(Conversion.TITRE, function()
      ecrireMetadonnees(nouvelle, metadonnees, refus)
      if reglages then nouvelle:applyDevelopSettings(reglages, Conversion.TITRE .. ' : réglages de l\'original') end
      if choix.preset then nouvelle:applyDevelopPreset(choix.preset, _PLUGIN) end
    end)
  end)
  if not repris then refus[#refus + 1] = 'réglages (' .. tostring(erreurReprise) .. ')' end
  return fichier, nil, refus
end

return Conversion
