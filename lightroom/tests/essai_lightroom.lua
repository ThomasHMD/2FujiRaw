--[[ Essai dans le vrai Lightroom, sans interface : envoyé par tests/essai_lightroom.py à l'action `lua` du pilote
de SpektraLR (Photographie/logiciels/spektra-lr/outils/essai-lr), qui l'exécute dans Lightroom.

Charge les .lua du module 2FujiRaw installé (require remplacé localement, rien de global touché), importe la COPIE
d'un .3FR, lui donne une note, un mot-clé, une exposition, puis lance Conversion.convertir comme le menu le ferait.
Relève ce que Lightroom voit du DNG, et exporte de petits JPEG sous plusieurs profils pour vérifier que les
simulations Fuji existent (un profil inconnu retombe sur le rendu par défaut : export identique).

Gabarits remplacés par le script : %MODULE%, %SOURCE%, %EXPORTS%, %PROFILS% (liste Lua de chaînes).
]]
local LrApplication = import 'LrApplication'
local LrExportSession = import 'LrExportSession'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

local MODULE, SOURCE, EXPORTS = '%MODULE%', '%SOURCE%', '%EXPORTS%'
local PROFILS = %PROFILS%
local TITRE = '2FujiRaw (essai)'

local charges = {}
local function charger(nom)
  if charges[nom] == nil then
    local texte = assert(LrFileUtils.readFile(LrPathUtils.child(MODULE, nom .. '.lua')), 'lecture ' .. nom)
    local f = assert(loadstring('local require = ...\n' .. texte, nom))
    charges[nom] = f(charger)
  end
  return charges[nom]
end

local Outil = charger('Outil')
-- Le code tourne dans le module d'essai : son _PLUGIN n'est pas celui de 2FujiRaw.
Outil.appEmbarquee = function() return LrPathUtils.child(LrPathUtils.child(MODULE, 'bin'), '2FujiRaw.app') end
local Conversion = charger('Conversion')

local cat = LrApplication.activeCatalog()
local function ecrire(f) cat:withWriteAccessDo(TITRE, f, { timeout = 30 }) end

local original = cat:findPhotoByPath(SOURCE)
if not original then ecrire(function() original = cat:addPhoto(SOURCE) end) end
local collection
ecrire(function()
  collection = cat:createCollection('2FujiRaw (essai) - à retirer', nil, true)
  collection:addPhotos { original }
  original:setRawMetadata('rating', 4)
  original:addKeyword(cat:createKeyword('essai-2fujiraw', {}, false, nil, true))
  original:applyDevelopSettings({ Exposure2012 = 0.3 }, TITRE)
end)

local fichier, erreur, refus = Conversion.convertir(cat, original, { reprendreReglages = true, empiler = true })
if not fichier then return { etape = 'convertir', erreur = erreur } end
local dng = cat:findPhotoByPath(fichier)
if not dng then return { etape = 'catalogue', erreur = 'DNG écrit mais absent du catalogue : ' .. fichier } end

local d = dng:getDevelopSettings()
local r = {
  fichier = fichier,
  refus = refus,
  marque = dng:getFormattedMetadata('cameraMake'),
  modele = dng:getFormattedMetadata('cameraModel'),
  note = dng:getRawMetadata('rating'),
  motsCles = dng:getFormattedMetadata('keywordTags'),
  exposition = d.Exposure2012,
  profilParDefaut = d.CameraProfile,
  enPile = dng:getRawMetadata('isInStackInFolder'),
  positionPile = dng:getRawMetadata('stackPositionInFolder'),
  originalEnPile = original:getRawMetadata('isInStackInFolder'),
  collections = #(dng:getContainedCollections() or {}),
  exports = {},
}

-- Un petit JPEG par profil.
LrFileUtils.createAllDirectories(EXPORTS)
for i, profil in ipairs(PROFILS) do
  ecrire(function() dng:applyDevelopSettings({ CameraProfile = profil }, TITRE) end)
  local s = {
    LR_export_destinationType = 'specificFolder', LR_export_destinationPathPrefix = EXPORTS,
    LR_export_useSubfolder = false, LR_collisionHandling = 'overwrite', LR_reimportExportedPhoto = false,
    LR_renamingTokensOn = true, LR_tokens = 'profil-' .. i, LR_extensionCase = 'lowercase', LR_useWatermark = false,
    LR_outputSharpeningOn = false, LR_embeddedMetadataOption = 'copyrightOnly', LR_removeLocationMetadata = true,
    LR_size_doConstrain = true, LR_size_resizeType = 'wh', LR_size_units = 'pixels',
    LR_size_maxWidth = 600, LR_size_maxHeight = 600, LR_size_doNotEnlarge = true,
    LR_size_resolution = 72, LR_size_resolutionUnits = 'inch',
    LR_format = 'JPEG', LR_jpeg_quality = 0.9, LR_export_colorSpace = 'sRGB', LR_export_bitDepth = 8,
  }
  local session = LrExportSession { photosToExport = { dng }, exportSettings = s }
  session:doExportOnCurrentTask()
  for _, rendu in session:renditions() do
    local fait, chemin = rendu:waitForRender()
    r.exports[#r.exports + 1] = { profil = profil, lu = dng:getDevelopSettings().CameraProfile,
      fichier = fait and chemin or nil, erreur = (not fait) and tostring(chemin) or nil }
  end
end
ecrire(function() dng:applyDevelopSettings({ CameraProfile = r.profilParDefaut }, TITRE) end)
return r
