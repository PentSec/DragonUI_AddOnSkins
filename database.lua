-- DragonUI_AddOnSkins — Database defaults (schema only).
--


local ADDON_NAME, addon = ...

addon.defaults = {
    profile = {
        skins = {
            details = {
                enabled = false,
                options = {
                    panelAlpha = 1,
                },
            },
            skada = {
                enabled = false,
                options = {
                    panelAlpha = 1,
                },
            },
            wim = {
                enabled = false,
                options = {},
            },
            compactraidframe = {
                enabled = false,
                options = {},
            },
        }
    }
}

addon.db = { profile = addon.defaults.profile }
