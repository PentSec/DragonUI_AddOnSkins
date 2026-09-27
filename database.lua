-- DragonUI_AddOnSkins — Database defaults (schema only).
--


local ADDON_NAME, addon = ...

addon.defaults = {
    profile = {
        skins = {
            details = {
                enabled = true,
                options = {
                    panelAlpha = 1,
                },
            },
        }
    }
}

addon.db = { profile = addon.defaults.profile }
