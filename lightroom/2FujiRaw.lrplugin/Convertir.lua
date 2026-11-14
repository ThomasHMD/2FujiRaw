--[[ Convertir.lua : Bibliothèque (ou Fichier) ▸ Modules externes ▸ Convertir en Fuji GFX 100S II…

Pour chaque photo choisie : Hasselblad (.3FR, .FFF) ou Leica (.DNG) → DNG Fuji GFX 100S II, importé au
catalogue (à côté de l'original et empilé avec lui, ou dans DNG-Fuji-Converted/). Les autres fichiers sont
laissés de côté.
]]
local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPrefs = import 'LrPrefs'
local LrProgressScope = import 'LrProgressScope'
local LrView = import 'LrView'

local Conversion = require 'Conversion'
local Outil = require 'Outil'
local Regles = require 'Regles'

local TITRE = Conversion.TITRE

local function listePresets()
  local items = { { title = 'Aucun', value = '' } }
  for _, dossier in ipairs(LrApplication.developPresetFolders() or {}) do
    for _, preset in ipairs(dossier:getDevelopPresets() or {}) do
      items[#items + 1] = { title = dossier:getName() .. ' ▸ ' .. preset:getName(), value = preset:getUuid() }
    end
  end
  return items
end

local function valeurDans(items, v)
  for _, item in ipairs(items) do
    if item.value == v then return v end
  end
end

-- Ouvre la fenêtre. Renvoie les choix, ou nil si annulé.
local function demanderChoix(context, nombre, ignores)
  local prefs = LrPrefs.prefsForPlugin()
  local presets = listePresets()
  local p = LrBinding.makePropertyTable(context)
  p.reprendreReglages = prefs.reprendreReglages ~= false
  p.empiler = prefs.empiler ~= false
  p.preset = valeurDans(presets, prefs.preset) or ''

  local f = LrView.osFactory()
  local resume = string.format('%d photo(s) à convertir en DNG Fuji GFX 100S II.', nombre)
  if ignores > 0 then resume = resume .. string.format(' %d autre(s) laissée(s) de côté.', ignores) end
  local contenu = f:column {
    bind_to_object = p,
    spacing = f:control_spacing(),
    f:static_text { title = resume },
    f:checkbox { value = LrView.bind 'reprendreReglages',
      title = 'Reprendre les réglages Développement de l\'original (sauf le profil)' },
    f:checkbox { value = LrView.bind 'empiler', title = 'Empiler le DNG au-dessus de l\'original' },
    f:row {
      f:static_text { title = 'Paramètre prédéfini :' },
      f:popup_menu { items = presets, value = LrView.bind 'preset', width_in_chars = 40 },
    },
    f:static_text {
      title = 'Pour une simulation Fuji d\'office (Classic Chrome…) : un paramètre prédéfini avec seulement le '
        .. 'profil coché, ou Préférences ▸ Paramètres prédéfinis ▸ Valeurs par défaut Raw ▸ GFX 100S II.',
      width_in_chars = 60, height_in_lines = 3,
    },
  }
  if LrDialogs.presentModalDialog { title = TITRE, contents = contenu, actionVerb = 'Convertir' } ~= 'ok' then
    return nil
  end
  prefs.reprendreReglages, prefs.empiler, prefs.preset = p.reprendreReglages, p.empiler, p.preset
  local preset = p.preset ~= '' and LrApplication.developPresetByUuid(p.preset) or nil
  return { reprendreReglages = p.reprendreReglages, empiler = p.empiler, preset = preset }
end

LrFunctionContext.postAsyncTaskWithContext(TITRE, function(context)
  LrDialogs.attachErrorDialogToFunctionContext(context)
  local catalogue = LrApplication.activeCatalog()
  local aConvertir, ignores = {}, {}
  for _, photo in ipairs(catalogue:getTargetPhotos()) do
    local mapping, raison = Regles.mapping(photo:getRawMetadata('path'), photo:getFormattedMetadata('cameraMake'))
    if mapping then
      aConvertir[#aConvertir + 1] = photo
    else
      ignores[#ignores + 1] = photo:getFormattedMetadata('fileName') .. ' : ' .. raison
    end
  end
  if not aConvertir[1] then
    LrDialogs.message('Rien à convertir dans la sélection.',
      'Formats pris en charge : Hasselblad .3FR et .FFF, Leica .DNG.\n\n' .. table.concat(ignores, '\n'), 'info')
    return
  end
  local exe, erreurOutil = Outil.trouver()
  if not exe then
    LrDialogs.message('2FujiRaw est introuvable.', erreurOutil, 'critical')
    return
  end

  local choix = demanderChoix(context, #aConvertir, #ignores)
  if not choix then return end

  local progression = LrProgressScope { title = TITRE, functionContext = context }
  local faits, echecs, avertissements = 0, {}, {}
  for i, photo in ipairs(aConvertir) do
    if progression:isCanceled() then break end
    local nom = photo:getFormattedMetadata('fileName')
    progression:setCaption(string.format('%s (%d sur %d)', nom, i, #aConvertir))
    local fichier, erreur, refus = Conversion.convertir(catalogue, photo, choix)
    if fichier then
      faits = faits + 1
      if refus and refus[1] then avertissements[#avertissements + 1] = nom .. ' : ' .. table.concat(refus, ', ') end
    else
      echecs[#echecs + 1] = nom .. ' : ' .. tostring(erreur)
    end
    progression:setPortionComplete(i, #aConvertir)
  end
  progression:done()

  local bilan = string.format('%d DNG Fuji sur %d photo(s).', faits, #aConvertir)
  if ignores[1] then bilan = bilan .. string.format(' %d laissée(s) de côté.', #ignores) end
  local details = {}
  if echecs[1] then details[#details + 1] = 'Échecs :\n' .. table.concat(echecs, '\n') end
  if avertissements[1] then details[#details + 1] = 'Repris en partie :\n' .. table.concat(avertissements, '\n') end
  if details[1] then
    LrDialogs.message(bilan, table.concat(details, '\n\n'), echecs[1] and 'warning' or 'info')
  else
    LrDialogs.showBezel(bilan)
  end
end)
