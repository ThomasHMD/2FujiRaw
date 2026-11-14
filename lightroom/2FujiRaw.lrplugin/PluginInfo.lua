--[[ PluginInfo.lua : réglage du module dans Fichier ▸ Gestionnaire de modules externes. ]]
local LrPrefs = import 'LrPrefs'
local LrView = import 'LrView'

local Outil = require 'Outil'

return {
  sectionsForTopOfDialog = function(f)
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
