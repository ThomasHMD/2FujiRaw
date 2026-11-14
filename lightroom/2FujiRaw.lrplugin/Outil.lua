--[[ Outil.lua : trouve l'app 2FujiRaw et lance sa CLI (`2FujiRaw --cli --mapping <id> <fichier>`).

L'app est cherchée dans cet ordre : chemin réglé dans le Gestionnaire de modules externes, copie embarquée
dans le module (bin/2FujiRaw.app, celle du zip de la release), /Applications, ~/Applications.
]]
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'

local Regles = require 'Regles'

local Outil = {}

local function enfant(dossier, ...)
  for _, nom in ipairs { ... } do dossier = LrPathUtils.child(dossier, nom) end
  return dossier
end

function Outil.appEmbarquee()
  return enfant(_PLUGIN.path, 'bin', '2FujiRaw.app')
end

function Outil.candidats()
  local liste = {}
  local regle = LrPrefs.prefsForPlugin().app
  if regle and regle ~= '' then liste[#liste + 1] = regle end
  liste[#liste + 1] = Outil.appEmbarquee()
  liste[#liste + 1] = '/Applications/2FujiRaw.app'
  liste[#liste + 1] = enfant(LrPathUtils.getStandardFilePath('home'), 'Applications', '2FujiRaw.app')
  return liste
end

-- Renvoie l'exécutable et l'app, ou nil et un message.
function Outil.trouver()
  for _, app in ipairs(Outil.candidats()) do
    local exe = enfant(app, 'Contents', 'MacOS', '2FujiRaw')
    if LrFileUtils.exists(exe) then return exe, app end
  end
  return nil, 'App 2FujiRaw introuvable. Cherchée dans :\n' .. table.concat(Outil.candidats(), '\n')
    .. '\n\nL\'installer dans /Applications, ou indiquer son chemin dans Fichier ▸ Gestionnaire de modules externes.'
end

local function statut(code)
  -- Sur Mac, LrTasks.execute rend le statut de wait() : le code de sortie × 256.
  if code and code > 255 then code = math.floor(code / 256) end
  return code
end

-- Le zip téléchargé marque l'app embarquée « en quarantaine » : macOS refuserait de la lancer depuis
-- Lightroom. Levée une fois par session, sur la copie embarquée seulement.
local quarantaineLevee = false
local function leverQuarantaine(app)
  if quarantaineLevee or app ~= Outil.appEmbarquee() then return end
  LrTasks.execute('/usr/bin/xattr -dr com.apple.quarantine ' .. Regles.guillemets(app) .. ' 2>/dev/null')
  quarantaineLevee = true
end

local compteur = 0
local function fichierTemporaire(suffixe)
  compteur = compteur + 1
  return LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'),
    string.format('2fujiraw-lr-%d-%d%s', os.time(), compteur, suffixe))
end

local function lireEtEffacer(chemin)
  if not LrFileUtils.exists(chemin) then return '' end
  local texte = LrFileUtils.readFile(chemin) or ''
  LrFileUtils.delete(chemin)
  return texte
end

-- Convertit un fichier. Renvoie le chemin du DNG écrit, ou nil et l'erreur. dossier : où l'écrire (nil = le
-- sous-dossier DNG-Fuji-Converted/ à côté de l'original, comme l'app).
function Outil.convertir(chemin, mapping, dossier)
  local exe, app = Outil.trouver()
  if not exe then return nil, app end
  leverQuarantaine(app)
  local sortie, journal = fichierTemporaire('.out'), fichierTemporaire('.log')
  local g = Regles.guillemets
  local morceaux = { g(exe), '--cli', '--mapping', g(mapping) }
  if dossier then
    morceaux[#morceaux + 1] = '--output-dir'
    morceaux[#morceaux + 1] = g(dossier)
  end
  morceaux[#morceaux + 1] = g(chemin)
  morceaux[#morceaux + 1] = '>' .. g(sortie)
  morceaux[#morceaux + 1] = '2>' .. g(journal)
  local code = statut(LrTasks.execute(table.concat(morceaux, ' ')))
  local texte, erreurs = lireEtEffacer(sortie), lireEtEffacer(journal)
  local fichier = Regles.fichierProduit(texte)
  if code ~= 0 or not fichier then return nil, Regles.erreurLisible(erreurs, code) end
  if not LrFileUtils.exists(fichier) then return nil, '2FujiRaw annonce ' .. fichier .. ', introuvable.' end
  return fichier
end

return Outil
