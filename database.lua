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
                    barBorder = "borderless",
                },
            },
            skada = {
                enabled = false,
                options = {
                    panelAlpha = 1,
                    barBorder = "borderless",
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
            dbm = {
                enabled = false,
                options = {
                    barBorder = "borderless",
                },
            },
        }
    }
}

addon.db = { profile = addon.defaults.profile }
