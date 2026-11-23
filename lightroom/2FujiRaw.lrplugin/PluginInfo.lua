--[[ PluginInfo.lua : réglage du module dans Fichier ▸ Gestionnaire de modules externes.
Mac : le chemin de l'app 2FujiRaw. Windows : les deux outils embarqués, le journal et un bouton de test. ]]
local LrDialogs = import 'LrDialogs'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Outil = require 'Outil'

local function sectionWindows(f)
  local o = Outil.outilsWindows()
  local function etat(chemin)
    local manquant = false
    for _, m in ipairs(o.manquants) do if m == chemin then manquant = true end end
    return chemin .. '  [' .. Outil.t(manquant and 'info_manquant' or 'info_trouve') .. ']'
  end
  return {
    title = Outil.t('info_titre'),
    f:static_text { title = 'dnglab.exe :  ' .. etat(o.dnglab), width_in_chars = 80 },
    f:static_text { title = 'exiftool.exe :  ' .. etat(o.exiftool), width_in_chars = 80 },
    f:static_text { title = 'exiftool_files :  ' .. etat(o.exiftoolFiles), width_in_chars = 80 },
    f:static_text { title = Outil.t('info_journal') .. '  ' .. Outil.cheminJournal(), width_in_chars = 80 },
    f:static_text { title = Outil.t('info_journal_aide'), width_in_chars = 80 },
    f:push_button {
      title = Outil.t('info_tester'),
      action = function()
        LrTasks.startAsyncTask(function()
          LrDialogs.message(Outil.t('test_titre'), Outil.testerOutils(), 'info')
        end)
      end,
    },
  }
end

return {
  sectionsForTopOfDialog = function(f)
    if Outil.estWindows() then return { sectionWindows(f) } end
    local prefs = LrPrefs.prefsForPlugin()
    local exe, app = Outil.trouver()
    return {
      {
        title = '2FujiRaw',
        f:row {
          f:static_text { title = 'App 2FujiRaw :' },
          f:edit_field { value = LrView.bind { key = 'app', bind_to_object = prefs }, width_in_chars = 50 },
        },
        f:static_text {
          title = 'Vide = recherche automatique (copie embarquée dans le module, /Applications, ~/Applications).\n'
            .. (exe and ('Utilisée : ' .. app) or 'Aucune trouvée pour l\'instant.'),
          width_in_chars = 70, height_in_lines = 3,
        },
      },
    }
  end,
}
