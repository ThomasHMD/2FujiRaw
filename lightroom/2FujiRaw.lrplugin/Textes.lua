--[[ Textes.lua : les messages du chemin Windows, en français et en anglais (le testeur est anglophone).
Langue : celle de Lightroom (LrLocalization.currentLanguage()) ; français si elle commence par « fr », sinon anglais.
Les messages du chemin Mac et de la fenêtre de conversion restent en français.
]]
local Textes = {}

local T = {
  leica_win = {
    fr = 'Conversion Leica disponible sur Mac seulement pour l\'instant.',
    en = 'Leica conversion is only available on Mac for now.',
  },
  outils_titre = {
    fr = '2FujiRaw : outils Windows introuvables.',
    en = '2FujiRaw: Windows tools not found.',
  },
  outils_manquants = {
    fr = 'Éléments manquants dans le module :\n%s\n\nRéinstaller le module : le zip Windows contient bin\\windows\\dnglab.exe, '
      .. 'bin\\windows\\exiftool.exe et le dossier bin\\windows\\exiftool_files.',
    en = 'Missing from the plug-in:\n%s\n\nReinstall the plug-in: the Windows zip contains bin\\windows\\dnglab.exe, '
      .. 'bin\\windows\\exiftool.exe and the bin\\windows\\exiftool_files folder.',
  },
  source_introuvable = {
    fr = 'Fichier source introuvable : %s',
    en = 'Source file not found: %s',
  },
  dossier_impossible = {
    fr = 'Impossible de créer le dossier de sortie : %s',
    en = 'Could not create the output folder: %s',
  },
  script_impossible = {
    fr = 'Impossible d\'écrire le script temporaire (%s) : %s',
    en = 'Could not write the temporary script (%s): %s',
  },
  echec_dnglab = {
    fr = 'dnglab a échoué (code %s) : %s',
    en = 'dnglab failed (exit code %s): %s',
  },
  echec_exiftool = {
    fr = 'exiftool a échoué (code %s) : %s',
    en = 'exiftool failed (exit code %s): %s',
  },
  pas_de_dng = {
    fr = 'dnglab n\'a pas produit le fichier attendu : %s',
    en = 'dnglab did not produce the expected file: %s',
  },
  aucun_detail = {
    fr = '(aucun message d\'erreur)',
    en = '(no error message)',
  },
  journal = {
    fr = 'Journal de diagnostic : %s',
    en = 'Diagnostic log: %s',
  },
  -- Gestionnaire de modules externes (PluginInfo.lua)
  info_titre = { fr = '2FujiRaw (Windows)', en = '2FujiRaw (Windows)' },
  info_trouve = { fr = 'trouvé', en = 'found' },
  info_manquant = { fr = 'MANQUANT', en = 'MISSING' },
  info_journal = { fr = 'Journal de diagnostic :', en = 'Diagnostic log:' },
  info_journal_aide = {
    fr = 'En cas de problème, envoyer ce fichier.',
    en = 'If something goes wrong, please send this file.',
  },
  info_tester = { fr = 'Tester les outils', en = 'Test the tools' },
  test_titre = { fr = 'Test des outils 2FujiRaw', en = '2FujiRaw tools test' },
  test_ok = { fr = 'OK', en = 'OK' },
  test_echec = { fr = 'ÉCHEC (code %s)', en = 'FAILED (exit code %s)' },
}

function Textes.langue(code)
  if tostring(code or ''):lower():sub(1, 2) == 'fr' then return 'fr' end
  return 'en'
end

-- Textes.t(cle, langue, ...) : le message, mis en forme avec string.format.
function Textes.t(cle, langue, ...)
  local entree = T[cle]
  if not entree then return cle end
  local modele = entree[langue] or entree.en
  if select('#', ...) == 0 then return modele end
  return string.format(modele, ...)
end

return Textes
