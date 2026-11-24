--[[ Outil.lua : lance la conversion.

Mac : trouve l'app 2FujiRaw et lance sa CLI (`2FujiRaw --cli --mapping <id> <fichier>`). L'app est cherchée dans cet
ordre : chemin réglé dans le Gestionnaire de modules externes, copie embarquée dans le module (bin/2FujiRaw.app,
celle du zip de la release), /Applications, ~/Applications.

Windows (globale du SDK WIN_ENV) : pas d'app. Le module enchaîne lui-même les deux outils embarqués,
bin\windows\dnglab.exe puis bin\windows\exiftool.exe (+ exiftool_files\), comme ConversionEngine.swift. Les
décisions pures (commandes, guillemets, nom de sortie) sont dans ChaineWindows.lua ; la raison du fichier .cmd y est
expliquée.

Dans les deux cas, chaque conversion est consignée dans 2FujiRaw.log (dossier temporaire de l'utilisateur).
]]
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'

local Regles = require 'Regles'
local Win = require 'ChaineWindows'
local Textes = require 'Textes'

local Outil = {}

function Outil.estWindows()
  return WIN_ENV == true
end

local function plateforme()
  if Outil.estWindows() then return 'Windows' end
  return 'Mac'
end

local function enfant(dossier, ...)
  for _, nom in ipairs { ... } do dossier = LrPathUtils.child(dossier, nom) end
  return dossier
end

-- Langue des messages Windows : celle de Lightroom (fr sinon en).
local function langue()
  local ok, L = pcall(import, 'LrLocalization')
  if ok and type(L) == 'table' and L.currentLanguage then
    local ok2, l = pcall(L.currentLanguage)
    if ok2 then return Textes.langue(l) end
  end
  return 'en'
end

function Outil.t(cle, ...)
  return Textes.t(cle, langue(), ...)
end

local function version()
  local ok, info = pcall(function() return dofile(enfant(_PLUGIN.path, 'Info.lua')) end)
  return Win.versionTexte(ok and type(info) == 'table' and info.VERSION or nil)
end

----------------------------------------------------------------------------------------------------
-- Fichiers temporaires et journal
----------------------------------------------------------------------------------------------------

-- Dossier des fichiers de travail (.cmd, .out, .log) et du journal : le dossier temporaire de l'utilisateur. Sous
-- Windows, si son chemin a des accents (C:\Users\Léa\…), io.open et cmd risquent de ne pas le lire : repli sur un
-- dossier public sans accent.
local function dossierTravail()
  local temp = LrPathUtils.getStandardFilePath('temp')
  if Outil.estWindows() and not Win.estAscii(temp) then
    local ok, public = pcall(os.getenv, 'PUBLIC')
    if not ok or not public or public == '' or not Win.estAscii(public) then public = 'C:\\Users\\Public' end
    return public
  end
  return temp
end

local compteur = 0
local function fichierTemporaire(suffixe)
  compteur = compteur + 1
  return LrPathUtils.child(dossierTravail(), string.format('2fujiraw-lr-%d-%d%s', os.time(), compteur, suffixe))
end

local function lireEtEffacer(chemin)
  if not LrFileUtils.exists(chemin) then return '' end
  local texte = LrFileUtils.readFile(chemin) or ''
  LrFileUtils.delete(chemin)
  return texte
end

function Outil.cheminJournal()
  return LrPathUtils.child(dossierTravail(), '2FujiRaw.log')
end

-- Ajoute une entrée au journal (borné aux ~200 derniers Ko). Ne lève jamais d'erreur.
local function journaliser(etapes)
  pcall(function()
    local chemin = Outil.cheminJournal()
    local ancien = LrFileUtils.exists(chemin) and LrFileUtils.readFile(chemin) or ''
    local entree = Win.entreeJournal(os.date('%Y-%m-%d %H:%M:%S'), plateforme(), version(), etapes)
    local f = io.open(chemin, 'wb')
    if not f then return end
    f:write(Win.borner((ancien or '') .. entree))
    f:close()
  end)
end

local function avecJournal(message)
  return message .. '\n\n' .. Outil.t('journal', Outil.cheminJournal())
end

----------------------------------------------------------------------------------------------------
-- Mac
----------------------------------------------------------------------------------------------------

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

local function trouverMac()
  for _, app in ipairs(Outil.candidats()) do
    local exe = enfant(app, 'Contents', 'MacOS', '2FujiRaw')
    if LrFileUtils.exists(exe) then return exe, app end
  end
  return nil, 'App 2FujiRaw introuvable. Cherchée dans :\n' .. table.concat(Outil.candidats(), '\n')
    .. '\n\nL\'installer dans /Applications, ou indiquer son chemin dans Fichier ▸ Gestionnaire de modules externes.'
end

local function statut(code)
  return Win.statut(code, Outil.estWindows())
end

-- Le zip téléchargé marque l'app embarquée « en quarantaine » : macOS refuserait de la lancer depuis
-- Lightroom. Levée une fois par session, sur la copie embarquée seulement.
local quarantaineLevee = false
local function leverQuarantaine(app)
  if quarantaineLevee or app ~= Outil.appEmbarquee() then return end
  LrTasks.execute('/usr/bin/xattr -dr com.apple.quarantine ' .. Regles.guillemets(app) .. ' 2>/dev/null')
  quarantaineLevee = true
end

local function convertirMac(chemin, mapping, dossier)
  local exe, app = trouverMac()
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
  local commande = table.concat(morceaux, ' ')
  morceaux[#morceaux + 1] = '>' .. g(sortie)
  morceaux[#morceaux + 1] = '2>' .. g(journal)
  local code = statut(LrTasks.execute(table.concat(morceaux, ' ')))
  local texte, erreurs = lireEtEffacer(sortie), lireEtEffacer(journal)
  journaliser { { nom = '2FujiRaw --cli', commande = commande, code = code, sortie = texte, erreurs = erreurs } }
  local fichier = Regles.fichierProduit(texte)
  if code ~= 0 or not fichier then return nil, avecJournal(Regles.erreurLisible(erreurs, code)) end
  if not LrFileUtils.exists(fichier) then return nil, '2FujiRaw annonce ' .. fichier .. ', introuvable.' end
  return fichier
end

----------------------------------------------------------------------------------------------------
-- Windows
----------------------------------------------------------------------------------------------------

-- Les deux outils embarqués (chemins fixes) et ce qui manque.
function Outil.outilsWindows()
  local dossier = enfant(_PLUGIN.path, 'bin', 'windows')
  local o = {
    dnglab = enfant(dossier, 'dnglab.exe'),
    exiftool = enfant(dossier, 'exiftool.exe'),
    exiftoolFiles = enfant(dossier, 'exiftool_files'),
  }
  o.manquants = {}
  if not LrFileUtils.exists(o.dnglab) then o.manquants[#o.manquants + 1] = o.dnglab end
  if not LrFileUtils.exists(o.exiftool) then o.manquants[#o.manquants + 1] = o.exiftool end
  if not LrFileUtils.exists(o.exiftoolFiles) then o.manquants[#o.manquants + 1] = o.exiftoolFiles end
  return o
end

-- Écrit un .cmd qui lance `commande` (déjà guillemetée) et redirige ses deux sorties, l'exécute, renvoie
-- { commande, code, sortie, erreurs } ; erreurEcriture si le .cmd n'a pas pu être écrit.
function Outil.executerCmd(commande)
  local cmd, sortie, erreurs = fichierTemporaire('.cmd'), fichierTemporaire('.out'), fichierTemporaire('.log')
  local ligne = Win.ligneAvecRedirections(commande, sortie, erreurs)
  local f, raison = io.open(cmd, 'wb')
  if not f then
    return { commande = ligne, erreurEcriture = Outil.t('script_impossible', cmd, tostring(raison)) }
  end
  f:write(Win.scriptCmd { ligne })
  f:close()
  local code = statut(LrTasks.execute(Win.lancerCmd(cmd)))
  local r = { commande = ligne, code = code, sortie = lireEtEffacer(sortie), erreurs = lireEtEffacer(erreurs) }
  LrFileUtils.delete(cmd)
  return r
end

local function fin(c)
  return (tostring(c or ''):gsub('^%s+', ''):gsub('%s+$', '')):sub(-600)
end

local function convertirWindows(chemin, mapping, dossier)
  if mapping == Regles.MAPPING_LEICA then return nil, Outil.t('leica_win') end
  local outils = Outil.outilsWindows()
  if outils.manquants[1] then
    return nil, Outil.t('outils_manquants', table.concat(outils.manquants, '\n'))
  end
  if not LrFileUtils.exists(chemin) then return nil, Outil.t('source_introuvable', chemin) end

  local dossierSource, _, base = Win.decouper(chemin)
  local destination = dossier or enfant(dossierSource, Win.DOSSIER_SORTIE)
  if not LrFileUtils.exists(destination) then
    LrFileUtils.createAllDirectories(destination)
    if not LrFileUtils.exists(destination) then return nil, Outil.t('dossier_impossible', destination) end
  end
  local sortie = Win.choisirSortie(destination, base, LrFileUtils.exists, LrPathUtils.child)

  local etapes = {}
  local function echec(message)
    journaliser(etapes)
    return nil, avecJournal(message)
  end

  local r1 = Outil.executerCmd(Win.commandeDnglab(outils.dnglab, chemin, sortie))
  etapes[1] = { nom = 'dnglab', commande = r1.commande, code = r1.code, sortie = r1.sortie, erreurs = r1.erreurEcriture or r1.erreurs }
  if r1.erreurEcriture then return echec(r1.erreurEcriture) end
  if r1.code ~= 0 then
    if LrFileUtils.exists(sortie) then LrFileUtils.delete(sortie) end
    local detail = fin(r1.erreurs)
    if detail == '' then detail = fin(r1.sortie) end
    if detail == '' then detail = Outil.t('aucun_detail') end
    return echec(Outil.t('echec_dnglab', tostring(r1.code), detail))
  end
  if not LrFileUtils.exists(sortie) then return echec(Outil.t('pas_de_dng', sortie)) end

  local arguments = fichierTemporaire('.args')
  local contenu = Win.argumentsExiftool(sortie, version(), chemin)
  local fa = io.open(arguments, 'wb')
  if not fa then return echec(Outil.t('dossier_impossible', arguments)) end
  fa:write(contenu)
  fa:close()
  local r2 = Outil.executerCmd(Win.commandeExiftool(outils.exiftool, arguments))
  LrFileUtils.delete(arguments)
  etapes[2] = { nom = 'exiftool', commande = r2.commande .. '   [-@ : ' .. contenu:gsub('\n', ' | ') .. ']', code = r2.code,
    sortie = r2.sortie, erreurs = r2.erreurEcriture or r2.erreurs }
  if r2.erreurEcriture or r2.code ~= 0 then
    -- Un DNG qui ne se dit pas Fuji n'a rien à faire dans le catalogue : on ne le laisse pas.
    if LrFileUtils.exists(sortie) then LrFileUtils.delete(sortie) end
    if r2.erreurEcriture then return echec(r2.erreurEcriture) end
    local detail = fin(r2.erreurs)
    if detail == '' then detail = fin(r2.sortie) end
    if detail == '' then detail = Outil.t('aucun_detail') end
    return echec(Outil.t('echec_exiftool', tostring(r2.code), detail))
  end
  journaliser(etapes)
  return sortie
end

-- « Tester les outils » (PluginInfo) : dnglab.exe --version et exiftool.exe -ver. Renvoie le texte à afficher.
function Outil.testerOutils()
  local outils = Outil.outilsWindows()
  if outils.manquants[1] then return Outil.t('outils_manquants', table.concat(outils.manquants, '\n')) end
  local g = Win.guillemets
  local lignes, etapes = {}, {}
  for _, essai in ipairs {
    { 'dnglab.exe', g(outils.dnglab) .. ' --version' },
    { 'exiftool.exe', g(outils.exiftool) .. ' -ver' },
  } do
    local r = Outil.executerCmd(essai[2])
    etapes[#etapes + 1] = { nom = 'test ' .. essai[1], commande = r.commande, code = r.code, sortie = r.sortie,
      erreurs = r.erreurEcriture or r.erreurs }
    local resultat = r.erreurEcriture or (r.code == 0 and (fin(r.sortie) ~= '' and fin(r.sortie) or Outil.t('test_ok'))
      or (Outil.t('test_echec', tostring(r.code)) .. ' ' .. fin(r.erreurs)))
    lignes[#lignes + 1] = essai[1] .. ' : ' .. resultat
  end
  journaliser(etapes)
  return table.concat(lignes, '\n')
end

----------------------------------------------------------------------------------------------------

-- Renvoie un indicateur de réussite (Mac : l'exécutable ; Windows : le chemin de dnglab) et l'app / exiftool, ou nil
-- et un message.
function Outil.trouver()
  if Outil.estWindows() then
    local o = Outil.outilsWindows()
    if o.manquants[1] then return nil, Outil.t('outils_manquants', table.concat(o.manquants, '\n')) end
    return o.dnglab, o.exiftool
  end
  return trouverMac()
end

-- Convertit un fichier. Renvoie le chemin du DNG écrit, ou nil et l'erreur. dossier : où l'écrire (nil = le
-- sous-dossier DNG-Fuji-Converted/ à côté de l'original, comme l'app).
function Outil.convertir(chemin, mapping, dossier)
  if Outil.estWindows() then return convertirWindows(chemin, mapping, dossier) end
  return convertirMac(chemin, mapping, dossier)
end

return Outil
