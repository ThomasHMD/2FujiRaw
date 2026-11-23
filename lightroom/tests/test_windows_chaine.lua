--[[ Essai de bout en bout de la chaîne Windows (dnglab.exe puis exiftool.exe), À LANCER SOUS WINDOWS (la CI).
Convertir.lua tourne sur un SDK simulé, comme dans test_avec_cli.lua, avec WIN_ENV = true ; LrTasks.execute est
os.execute (qui passe par cmd.exe comme dans Lightroom) et rend le code brut, sans × 256.

  lua lightroom/tests/test_windows_chaine.lua <dossier du module empaqueté contenant bin\windows\> <fichier .3FR>

Le .3FR est COPIÉ dans un dossier temporaire au nom difficile (essai 2FujiRaw é'ü & co) ; trois conversions :
sans pile (DNG-Fuji-Converted\<base>.dng), sans pile encore (<base>_converted.dng), avec pile (à côté de l'original).
Chaque DNG est relu par exiftool.exe : Make = FUJIFILM, Model = GFX 100S II. Le test rejoue aussi « Tester les outils ».
Code de sortie 0 si tout va bien, 1 sinon, avec un rapport lisible. Tout ce qui est créé (dossier de travail, journal
s'il n'existait pas) est supprimé à la fin.

Les chemins touchés par les accents passent par des .cmd UTF-8 (chcp 65001), comme dans le module : le Lua natif de
Windows lirait ces noms avec la page de codes ANSI. Si le dossier accentué ne peut pas être créé, le test refait avec un
nom à espaces et apostrophe seulement, le signale en sortie (« ATTENTION ») et n'échoue pas pour cela.
]]
local SEP = package.config:sub(1, 1)
local function joindre(d, n) return d .. SEP .. n end

local moduleDir, brut = arg[1], arg[2]
if not (moduleDir and brut) then
  io.stderr:write('usage : lua lightroom/tests/test_windows_chaine.lua <dossier du module empaquete avec bin\\windows\\> <fichier .3FR>\n')
  os.exit(2)
end
-- Lightroom donne des chemins absolus à antislashs : cmd.exe (copy, if exist) ne lit pas « sample/x.3FR ».
local function absolu(p)
  p = p:gsub('/', '\\')
  if p:match('^%a:\\') or p:match('^\\\\') then return p end
  local cwd = (os.getenv('CD') or io.popen('cd'):read('*l') or '.'):gsub('[\\]+$', '')
  return cwd .. '\\' .. p
end
moduleDir, brut = absolu(moduleDir), absolu(brut)
local dossierTests = arg[0]:match('^(.*)[/\\][^/\\]*$') or '.'
local sources = dossierTests .. '/../2FujiRaw.lrplugin'
package.path = moduleDir .. '/?.lua;' .. sources .. '/?.lua;' .. package.path

WIN_ENV = true -- comme le SDK Lightroom sous Windows
_PLUGIN = { path = moduleDir }

local Win = require 'ChaineWindows'

local TEMP = os.getenv('TEMP') or os.getenv('TMP') or os.getenv('TMPDIR') or '/tmp'

-- Rapport -------------------------------------------------------------------------------------------------------
local rapport, echecs = {}, 0
local function note(texte) rapport[#rapport + 1] = texte end
local function verifie(condition, message)
  if condition then
    note('  OK      ' .. message)
  else
    echecs = echecs + 1
    note('  ECHEC   ' .. message)
  end
  return condition
end

-- os.execute sans piège de version (Lua 5.1 rend un nombre, 5.2+ rend true/nil, "exit", code)
local function executer(cmd)
  local a, _, c = os.execute(cmd)
  if type(a) == 'number' then return a end
  return c or (a and 0 or 1)
end

-- Aides qui passent par un .cmd UTF-8 (insensibles aux accents) ----------------------------------------------------
local seq = 0
local function cmdRun(lignes)
  seq = seq + 1
  local chemin = joindre(TEMP, string.format('2fujiraw-test-%d-%d.cmd', os.time(), seq))
  local f = assert(io.open(chemin, 'wb'))
  f:write(Win.scriptCmd(lignes))
  f:close()
  local code = executer(Win.lancerCmd(chemin))
  os.remove(chemin)
  return code
end
local g = Win.guillemets

local function existe(p)
  return cmdRun { 'if exist ' .. g(p) .. ' exit /b 0', 'exit /b 1' } == 0
end

local function lire(p)
  if Win.estAscii(p) then
    local f = io.open(p, 'rb')
    if not f then return nil end
    local t = f:read('*a')
    f:close()
    return t
  end
  seq = seq + 1
  local copie = joindre(TEMP, string.format('2fujiraw-test-lu-%d-%d.txt', os.time(), seq))
  if cmdRun { 'copy /y ' .. g(p) .. ' ' .. g(copie) .. ' >nul' } ~= 0 then return nil end
  local t = lire(copie)
  os.remove(copie)
  return t
end

local function parent(p) return (p:gsub('[/\\][^/\\]*$', '')) end

local function tagsDe(dng, exiftool)
  seq = seq + 1
  local sortie = joindre(TEMP, string.format('2fujiraw-test-tags-%d-%d.txt', os.time(), seq))
  -- Même méthode que le module : le nom accentué passe par un fichier d'arguments UTF-8.
  local args = joindre(TEMP, string.format('2fujiraw-test-args-%d-%d.txt', os.time(), seq))
  local fa = assert(io.open(args, 'wb'))
  fa:write('-s3\n-Make\n-Model\n' .. dng .. '\n')
  fa:close()
  local ligne = g(exiftool) .. ' -charset filename=UTF8 -@ ' .. g(args)
  cmdRun { ligne .. ' > ' .. g(sortie) .. ' 2>&1' }
  os.remove(args)
  local t = lire(sortie) or ''
  os.remove(sortie)
  local lignes = {}
  for l in t:gmatch('[^\r\n]+') do lignes[#lignes + 1] = l end
  return lignes, t
end

-- Dossier de travail ----------------------------------------------------------------------------------------------
local racine = joindre(TEMP, '2fujiraw-test-' .. os.time())
local journalExistait
local journal

local function nettoyer()
  cmdRun { 'rmdir /s /q ' .. g(racine) }
  if journal and not journalExistait then os.remove(journal) end
end

local function principal()
  local outils = joindre(joindre(moduleDir, 'bin'), 'windows')
  local dnglab, exiftool = joindre(outils, 'dnglab.exe'), joindre(outils, 'exiftool.exe')
  note('Module        : ' .. moduleDir)
  note('Fichier source: ' .. brut)
  note('Dossier temp. : ' .. TEMP .. (Win.estAscii(TEMP) and '' or '   ATTENTION : chemin avec accents'))
  verifie(existe(dnglab), 'dnglab.exe present : ' .. dnglab)
  verifie(existe(exiftool), 'exiftool.exe present : ' .. exiftool)
  verifie(existe(joindre(outils, 'exiftool_files')), 'dossier exiftool_files present')
  verifie(existe(brut), 'le .3FR de depart existe')
  if echecs > 0 then return end

  local _, nomFichier, base = Win.decouper(brut)
  assert(cmdRun { 'mkdir ' .. g(racine) } == 0 and existe(racine), 'dossier temporaire non cree : ' .. racine)

  local dossier = joindre(racine, "essai 2FujiRaw é'ü & co")
  local copie = joindre(dossier, nomFichier)
  local function preparer(d)
    local c = joindre(d, nomFichier)
    cmdRun { 'mkdir ' .. g(d), 'copy /y ' .. g(brut) .. ' ' .. g(c) .. ' >nul' }
    return existe(c)
  end
  if preparer(dossier) then
    note('Dossier d\'essai : ' .. dossier .. ' (accents, apostrophe, &, espaces)')
  else
    note('ATTENTION : dossier accentue impossible a creer ici, essai refait avec espaces et apostrophe seulement.')
    dossier = joindre(racine, "essai 2FujiRaw d'essai co")
    copie = joindre(dossier, nomFichier)
    assert(preparer(dossier), 'meme le dossier simple ne peut pas etre cree : ' .. dossier)
  end

  -- SDK simule ------------------------------------------------------------------------------------------------------
  local releve
  local modeEmpiler = false
  local nouvelle = {
    addKeyword = function() end, setRawMetadata = function() end,
    applyDevelopSettings = function() end, applyDevelopPreset = function() end,
  }
  local original = {
    getRawMetadata = function(_, cle) return ({ path = copie, fileFormat = 'RAW', rating = 3, keywords = {} })[cle] end,
    getFormattedMetadata = function(_, cle) return ({ fileName = nomFichier, cameraMake = 'Hasselblad' })[cle] end,
    getContainedCollections = function() return {} end,
    getDevelopSettings = function() return { Exposure2012 = 0.3 } end,
  }
  local leica = {
    getRawMetadata = function(_, cle) return ({ path = joindre(dossier, 'L1000123.DNG'), fileFormat = 'DNG' })[cle] end,
    getFormattedMetadata = function(_, cle) return ({ fileName = 'L1000123.DNG', cameraMake = 'Leica Camera AG' })[cle] end,
  }
  journalExistait = nil
  local SDK = {
    LrTasks = { execute = executer, pcall = pcall },
    LrFileUtils = {
      exists = existe,
      readFile = lire,
      delete = function(p) if Win.estAscii(p) then os.remove(p) else cmdRun { 'del /f /q ' .. g(p) } end end,
      createAllDirectories = function(p) return cmdRun { 'mkdir ' .. g(p) } == 0 end,
    },
    LrPathUtils = {
      child = joindre,
      parent = parent,
      getStandardFilePath = function(quoi) return quoi == 'home' and (os.getenv('USERPROFILE') or TEMP) or TEMP end,
    },
    LrPrefs = { prefsForPlugin = (function() local prefs = {} return function() return prefs end end)() },
    LrLocalization = { currentLanguage = function() return 'en' end },
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
        p.empiler, p.preset = modeEmpiler, ''
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
      developPresetFolders = function() return {} end,
      developPresetByUuid = function() return nil end,
      activeCatalog = function()
        return {
          getTargetPhotos = function() return { original, leica } end,
          findPhotoByPath = function() return nil end,
          withWriteAccessDo = function(_, _, f) f() end,
          addPhoto = function(_, chemin, pile, position)
            releve.ajouts[#releve.ajouts + 1] = { chemin = chemin, pile = pile == original, position = position }
            return nouvelle
          end,
        }
      end,
    },
  }
  function import(nom) return assert(SDK[nom], 'SDK simule : ' .. nom .. ' manque') end
  local fichierConvertir = package.searchpath and package.searchpath('Convertir', package.path)
    or joindre(moduleDir, 'Convertir.lua')

  local Outil = require 'Outil'
  journal = Outil.cheminJournal()
  journalExistait = existe(journal)

  local function lancer(empiler)
    releve = { ajouts = {}, messages = {} }
    modeEmpiler = empiler
    dofile(fichierConvertir)
    return releve
  end

  -- 1. sans pile ; 2. sans pile encore ; 3. avec pile ---------------------------------------------------------------
  local sorties = {}
  for i, empiler in ipairs { false, false, true } do
    note('')
    note(string.format('Conversion %d (%s)', i, empiler and 'avec pile' or 'sans pile'))
    local r = lancer(empiler)
    for _, m in ipairs(r.messages) do note('  message : ' .. m:gsub('\n', ' | ')) end
    local a = r.ajouts[1]
    if verifie(#r.ajouts == 1 and a, 'un seul DNG importe (le DNG Leica est laisse de cote)') then
      sorties[i] = a.chemin
      note('  DNG : ' .. a.chemin)
      verifie(existe(a.chemin), 'le DNG existe')
      verifie(a.pile == empiler and (not empiler or a.position == 'above'), empiler and 'empile au-dessus de l\'original' or 'importe sans pile')
      local lignes, brutTags = tagsDe(a.chemin, exiftool)
      verifie(lignes[1] == 'FUJIFILM' and lignes[2] == 'GFX 100S II',
        'exiftool lit Make=FUJIFILM et Model=GFX 100S II (lu : ' .. brutTags:gsub('[\r\n]+', ' | ') .. ')')
    end
    verifie(r.messages[1] and r.messages[1]:find('1 DNG Fuji sur 1', 1, true) and r.messages[1]:find('1 laiss', 1, true),
      'bilan : 1 DNG Fuji sur 1, 1 laisse de cote')
  end
  local attendu = {
    joindre(joindre(dossier, 'DNG-Fuji-Converted'), base .. '.dng'),
    joindre(joindre(dossier, 'DNG-Fuji-Converted'), base .. '_converted.dng'),
    joindre(dossier, base .. '.dng'),
  }
  note('')
  verifie(sorties[1] == attendu[1], 'sans pile : DNG-Fuji-Converted\\<base>.dng')
  verifie(sorties[2] == attendu[2], 'deuxieme conversion identique : <base>_converted.dng')
  verifie(sorties[3] == attendu[3], 'avec pile : a cote de l\'original')

  -- Source absente, outil de test, journal --------------------------------------------------------------------------
  local f, erreur = Outil.convertir(joindre(dossier, 'absent.3FR'), 'hassy-x2d2-to-fuji-gfx100s2', nil)
  verifie(f == nil and tostring(erreur):find('not found', 1, true), 'source absente : refus propre (' .. tostring(erreur):gsub('%s+', ' ') .. ')')
  local leicaRefus = select(2, Outil.convertir(joindre(dossier, 'L1000123.DNG'), 'leica-dng-to-fuji-gfx100s2', nil))
  verifie(tostring(leicaRefus):find('only available on Mac', 1, true), 'Leica : refus propre')
  local essai = Outil.testerOutils()
  note('Tester les outils :\n    ' .. essai:gsub('\n', '\n    '))
  verifie(essai:find('dnglab.exe : ', 1, true) and essai:find('exiftool.exe : ', 1, true)
    and not essai:find('FAILED', 1, true) and not essai:find('MISSING', 1, true) and not essai:find('Missing', 1, true),
    'tester les outils : dnglab --version et exiftool -ver repondent')
  local texteJournal = lire(journal) or ''
  verifie(texteJournal:find('Windows', 1, true) and texteJournal:find('dnglab', 1, true)
    and texteJournal:find('exiftool', 1, true) and texteJournal:find('exit code : 0', 1, true),
    'journal 2FujiRaw.log : plateforme, commandes, codes de sortie (' .. journal .. ')')
  verifie(#texteJournal <= Win.TAILLE_JOURNAL + 4096, 'journal borne')
end

local ok, erreur = xpcall(principal, debug.traceback)
if not ok then
  echecs = echecs + 1
  note('  ECHEC   exception : ' .. tostring(erreur))
end
pcall(nettoyer)

print(table.concat(rapport, '\n'))
print('')
print(echecs == 0 and 'TOUT EST OK' or (echecs .. ' ECHEC(S)'))
os.exit(echecs == 0 and 0 or 1, true)
