return {
  LrSdkVersion = 13.0,
  LrSdkMinimumVersion = 10.0,
  LrToolkitIdentifier = 'com.thomashmd.twofujiraw',
  LrPluginName = '2FujiRaw',
  LrPluginInfoUrl = 'https://github.com/ThomasHMD/2FujiRaw',
  LrPluginInfoProvider = 'PluginInfo.lua',
  LrLibraryMenuItems = {
    { title = 'Convertir en Fuji GFX 100S II…', file = 'Convertir.lua', enabledWhen = 'photosSelected' },
  },
  LrExportMenuItems = {
    { title = 'Convertir en Fuji GFX 100S II…', file = 'Convertir.lua', enabledWhen = 'photosSelected' },
  },
  VERSION = { major = 0, minor = 3, revision = 0 },
}
