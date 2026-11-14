--[[ Essai de bout en bout hors de Lightroom : Convertir.lua tourne sur un SDK simulé, avec la vraie app
2FujiRaw, sur la COPIE d'un .3FR (le DNG s'écrit à côté d'elle, pour la pile).

  lua lightroom/tests/test_avec_cli.lua <copie d'un .3FR> [chemin de 2FujiRaw.app]

La fenêtre est validée telle quelle ; un JPEG de la sélection doit être laissé de côté ; l'import, la pile,
les métadonnées et les réglages repris sont relevés.
]]
local dossierTests = arg[0]:gsub('[^/]*$', '')
-- MODULE_2FUJIRAW=dist/2FujiRaw.lrplugin : essaie le module empaqueté, et son app embarquée si aucune n'est donnée.
local dossierModule = os.getenv('MODULE_2FUJIRAW') or (dossierTests .. '../2FujiRaw.lrplugin')
package.path = dossierModule .. '/?.lua;' .. package.path

local brut, app = arg[1], arg[2]
assert(brut and io.open(brut), 'usage : lua lightroom/tests/test_avec_cli.lua <copie d\'un .3FR> [2FujiRaw.app]')

local function parent(p) return (p:gsub('/[^/]*$', '')) end
local releve = { ajouts = {}, messages = {}, ecrit = {}, motsCles = {}, collections = 0 }

_PLUGIN = { path = dossierModule }

local nouvelle = {
  addKeyword = function(_, k) releve.motsCles[#releve.motsCles + 1] = k end,
  setRawMetadata = function(_, cle, v) releve.ecrit[cle] = v end,
  applyDevelopSettings = function(_, reglages) releve.reglages = reglages end,
  applyDevelopPreset = function(_, preset) releve.preset = preset end,
}
local original = {
  getRawMetadata = function(_, cle)
    return ({ path = brut, fileFormat = 'RAW', rating = 4, pickStatus = 1, keywords = { 'Copenhague' } })[cle]
  end,
  getFormattedMetadata = function(_, cle)
    return ({ fileName = brut:match('[^/]*$'), cameraMake = 'Hasselblad', label = 'Rouge', title = 'Nyhavn' })[cle]
  end,
  getContainedCollections = function()
    return { { addPhotos = function(_, photos) releve.collections = releve.collections + #photos end } }
  end,
  getDevelopSettings = function()
    return { CameraProfile = 'Adobe Color', Exposure2012 = 0.3, WhiteBalance = 'As Shot', Temperature = 5100, Tint = 2 }
  end,
}
local jpeg = {
  getRawMetadata = function(_, cle) return ({ path = parent(brut) .. '/vue.jpg', fileFormat = 'JPG' })[cle] end,
  getFormattedMetadata = function(_, cle) return ({ fileName = 'vue.jpg', cameraMake = 'Hasselblad' })[cle] end,
}

local preset = { nom = 'Classic Chrome' }
local SDK = {
  LrTasks = {
    -- Comme Lightroom sur Mac : le statut de wait(), soit le code de sortie × 256.
    execute = function(cmd)
      local _, _, code = os.execute(cmd)
      return (code or 0) * 256
    end,
    pcall = pcall,
  },
  LrFileUtils = {
    exists = function(p) local f = io.open(p) if f then f:close() return true end return false end,
    readFile = function(p) local f = assert(io.open(p)) local t = f:read('*a') f:close() return t end,
    delete = function(p) os.remove(p) end,
  },
  LrPathUtils = {
    child = function(d, n) return d .. '/' .. n end,
    parent = parent,
    getStandardFilePath = function(quoi) return quoi == 'home' and os.getenv('HOME') or parent(brut) end,
  },
  LrPrefs = { prefsForPlugin = (function() local prefs = { app = app } return function() return prefs end end)() },
  LrBinding = { makePropertyTable = function() return {} end },
  LrView = {
    osFactory = function()
      return setmetatable({}, { __index = function() return function(_, args) return args or {} end end })
    end,
    bind = function(k) return { bind = k } end,
  },
  LrDialogs = {
    presentModalDialog = function(t)
      local p = t.contents.bind_to_object
      p.preset = 'uuid-cc'
      releve.fenetre = { reprendreReglages = p.reprendreReglages, empiler = p.empiler }
      return 'ok'
    end,
    message = function(m, info) releve.messages[#releve.messages + 1] = m .. ' / ' .. tostring(info) end,
    showBezel = function(m) releve.messages[#releve.messages + 1] = m end,
    attachErrorDialogToFunctionContext = function() end,
  },
  LrFunctionContext = { postAsyncTaskWithContext = function(_, f) f({}) end },
  LrProgressScope = function()
    return { isCanceled = function() return false end, setCaption = function() end,
      setPortionComplete = function() end, done = function() end }
  end,
  LrApplication = {
    developPresetFolders = function()
      return { { getName = function() return 'Fuji' end, getDevelopPresets = function()
        return { { getName = function() return 'Classic Chrome' end, getUuid = function() return 'uuid-cc' end } }
      end } }
    end,
    developPresetByUuid = function(u) return u == 'uuid-cc' and preset or nil end,
    activeCatalog = function()
      return {
        getTargetPhotos = function() return { original, jpeg } end,
        findPhotoByPath = function() return nil end,
        withWriteAccessDo = function(_, _, f) f() end,
        addPhoto = function(_, chemin, pile, position)
          releve.ajouts[#releve.ajouts + 1] = { chemin, pile == original, position }
          return nouvelle
        end,
      }
    end,
  },
}
function import(nom) return assert(SDK[nom], 'SDK simulé : ' .. nom .. ' manque') end

dofile(dossierModule .. '/Convertir.lua')

for _, m in ipairs(releve.messages) do print('message : ' .. m) end
local a = releve.ajouts[1]
assert(#releve.ajouts == 1, 'un seul import attendu (le JPEG est laissé de côté), relevé : ' .. #releve.ajouts)
assert(io.open(a[1]), 'le fichier importé n\'existe pas : ' .. a[1])
assert(parent(a[1]) == parent(brut) and a[1]:find('%.dng$'), 'DNG pas à côté de l\'original (pile) : ' .. a[1])
assert(a[2] and a[3] == 'above', 'pas empilé au-dessus de l\'original')
assert(releve.fenetre.reprendreReglages and releve.fenetre.empiler, 'cases cochées par défaut')
assert(releve.motsCles[1] == 'Copenhague' and releve.collections == 1, 'mots-clés ou collection non repris')
assert(releve.ecrit.rating == 4 and releve.ecrit.pickStatus == 1 and releve.ecrit.label == 'Rouge'
  and releve.ecrit.title == 'Nyhavn', 'note, drapeau, libellé ou titre non repris')
assert(releve.reglages and releve.reglages.Exposure2012 == 0.3 and releve.reglages.CameraProfile == nil
  and releve.reglages.Temperature == nil, 'réglages mal repris')
assert(releve.preset == preset, 'paramètre prédéfini non appliqué')
assert(releve.messages[1] and releve.messages[1]:find('1 DNG Fuji sur 1') and releve.messages[1]:find('1 laissée'),
  'bilan inattendu')

-- Le DNG se dit bien Fuji GFX 100S II (c'est ce que lit Lightroom pour proposer les simulations).
local exiftool = (app or (dossierModule .. '/bin/2FujiRaw.app')) .. '/Contents/Resources/bin/exiftool/exiftool'
local f = io.open(exiftool)
if f then
  f:close()
  local p = io.popen(string.format("'%s' -s3 -Make -Model -UniqueCameraModel '%s'", exiftool, a[1]))
  local tags = p:read('*a')
  p:close()
  assert(tags:find('FUJIFILM') and tags:find('GFX 100S II'), 'tags du DNG : ' .. tags)
  print('tags : ' .. tags:gsub('\n', ' / '))
end
print('importé et empilé : ' .. a[1])
