--[[ ChaineWindows.lua : les décisions pures de la chaîne Windows (dnglab.exe puis exiftool.exe), sans appel au SDK.
Testées hors de Lightroom par tests/test_hors_lr.lua.

Pourquoi un fichier .cmd temporaire plutôt qu'une ligne de commande passée à LrTasks.execute :
  - LrTasks.execute passe par cmd.exe, qui retire la première et la dernière paire de guillemets d'une commande
    qui en contient plus de deux (le piège de « cmd /c ») : un chemin à espaces entre guillemets suivi d'arguments
    entre guillemets est alors cassé. Avec un .cmd, la seule commande passée à cmd est « "<script>.cmd" »
    (entourée d'une paire de guillemets en plus, lancerCmd) ;
  - les accents, apostrophes et & des chemins (Développement, L'été, Müller & Fils) sont écrits en UTF-8 dans le
    script, que `chcp 65001` fait lire correctement : aucun passage des caractères par la page de codes de la console ;
  - les redirections vers des fichiers .out/.log sont dans le script, pas à deviner côté Lua.
Dans un .cmd, seuls `%` (doublé) et `"` (impossible dans un nom de fichier Windows) demandent un traitement :
`& ^ ( ) !` sont inertes entre guillemets (l'expansion retardée est coupée par setlocal).
]]
local W = {}

W.VERSION_DEFAUT = '0.3.0'
W.TAILLE_JOURNAL = 200 * 1024
W.DOSSIER_SORTIE = 'DNG-Fuji-Converted'

-- Guillemets pour cmd.exe, dans un fichier .cmd : % doublé, " retiré (interdit dans un nom Windows).
function W.guillemets(s)
  s = tostring(s):gsub('"', ''):gsub('%%', '%%%%')
  return '"' .. s .. '"'
end

-- Code de sortie de LrTasks.execute. Mac : statut de wait(), soit le code × 256. Windows : le code tel quel.
function W.statut(code, windows)
  if not windows and code and code > 255 then code = math.floor(code / 256) end
  return code
end

function W.estAscii(s)
  return not tostring(s):find('[\128-\255]')
end

-- Dossier, nom et base (sans extension) d'un chemin, avec / ou \ comme séparateur.
function W.decouper(chemin)
  chemin = tostring(chemin)
  local dossier, nom = chemin:match('^(.*)[/\\]([^/\\]*)$')
  if not dossier then dossier, nom = '', chemin end
  local base = nom:match('^(.*)%.[^.]*$') or nom
  if base == '' then base = nom end
  return dossier, nom, base
end

-- Nom du DNG : <base>.dng, sinon <base>_converted.dng, <base>_converted-2.dng, etc.
-- existe : function(chemin) -> bool ; joindre : function(dossier, nom) -> chemin.
function W.choisirSortie(dossier, base, existe, joindre)
  local chemin = joindre(dossier, base .. '.dng')
  local n = 0
  while existe(chemin) do
    n = n + 1
    local suffixe = n == 1 and '_converted' or ('_converted-' .. n)
    chemin = joindre(dossier, base .. suffixe .. '.dng')
    if n > 9999 then break end
  end
  return chemin
end

-- 1. dnglab convert --compression lossless <source> <sortie> (ConversionEngine.convertNativeHasselbladToFuji)
function W.commandeDnglab(dnglab, source, sortie)
  local g = W.guillemets
  return table.concat({ g(dnglab), 'convert', '--compression', 'lossless', g(source), g(sortie) }, ' ')
end

-- 2. exiftool : le DNG se dit Fuji GFX 100S II (ConversionEngine.spoofDNGIdentity)
-- Le nom du DNG passe par un fichier d'arguments UTF-8 (-@), pas par la ligne de commande : exiftool.exe lit sa ligne
-- de commande dans la page de code ANSI et perd les accents (« File not found », vu sur la CI Windows le 23/11/2026),
-- alors qu'il lit un fichier d'arguments en UTF-8 avec -charset filename=UTF8 (méthode recommandée par sa doc).
-- Le fichier d'arguments lui-même est dans le dossier de travail, au nom ASCII.
function W.argumentsExiftool(dng, version)
  return table.concat({
    '-Make=FUJIFILM', '-Model=GFX 100S II', '-UniqueCameraModel=Fujifilm GFX 100S II',
    '-PreviewApplicationName=2FujiRaw', '-PreviewApplicationVersion=' .. tostring(version),
    '-PreviewDateTime=now', '-PreviewColorSpace=sRGB', '-overwrite_original', dng,
  }, '\n') .. '\n'
end

function W.commandeExiftool(exiftool, fichierArguments)
  local g = W.guillemets
  return table.concat({ g(exiftool), '-charset', 'filename=UTF8', '-@', g(fichierArguments) }, ' ')
end

function W.ligneAvecRedirections(commande, sortie, erreurs)
  return commande .. ' > ' .. W.guillemets(sortie) .. ' 2> ' .. W.guillemets(erreurs)
end

-- Contenu du .cmd (UTF-8 sans BOM, fins de ligne CRLF). Le code de sortie est celui de la dernière commande.
function W.scriptCmd(lignes)
  local t = { '@echo off', 'chcp 65001 >nul', 'setlocal DisableDelayedExpansion' }
  for _, l in ipairs(lignes) do t[#t + 1] = l end
  t[#t + 1] = 'exit /b %ERRORLEVEL%'
  return table.concat(t, '\r\n') .. '\r\n'
end

-- Commande à passer à LrTasks.execute : le .cmd entre guillemets, le tout entouré d'une paire de plus.
function W.lancerCmd(cheminCmd)
  return '"' .. W.guillemets(cheminCmd) .. '"'
end

function W.versionTexte(v)
  if type(v) ~= 'table' then return W.VERSION_DEFAUT end
  return string.format('%d.%d.%d', v.major or 0, v.minor or 0, v.revision or 0)
end

-- Une entrée du journal. etapes : { { nom, commande, code, sortie, erreurs }, ... }
function W.entreeJournal(date, plateforme, version, etapes)
  local t = { string.format('=== %s | %s | 2FujiRaw %s', date, plateforme, version) }
  for _, e in ipairs(etapes) do
    t[#t + 1] = '-- ' .. tostring(e.nom)
    if e.commande then t[#t + 1] = '> ' .. e.commande end
    t[#t + 1] = 'code de sortie / exit code : ' .. tostring(e.code)
    local sortie = tostring(e.sortie or ''):gsub('%s+$', '')
    local erreurs = tostring(e.erreurs or ''):gsub('%s+$', '')
    if sortie ~= '' then t[#t + 1] = 'sortie / output :\n' .. sortie end
    if erreurs ~= '' then t[#t + 1] = 'erreurs / errors :\n' .. erreurs end
  end
  return table.concat(t, '\n') .. '\n\n'
end

-- Garde la fin du journal (les dernières entrées), coupée à une ligne entière.
function W.borner(texte, max)
  max = max or W.TAILLE_JOURNAL
  if #texte <= max then return texte end
  local fin = texte:sub(#texte - max + 1)
  local coupe = fin:find('\n', 1, true)
  return coupe and fin:sub(coupe + 1) or fin
end

return W
