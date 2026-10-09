-- DragonUI_AddOnSkins - utils/duitextures.lua
-- Central registry of DragonUI single textures consumed by the skins.

local ADDON_NAME, addon = ...

-- Path literal to the DragonUI texture folder.
addon.duiDir = [[Interface\AddOns\DragonUI\Textures\]]

-- Registered single textures, keyed for the skins.
addon.duitextures = {
    rim = addon.duiDir .. "PersonalResource\\rim",
}

-- Returns the registered path for a DragonUI texture, or nil when unknown.
function addon:GetDuiTexture(key)
    return addon.duitextures[key]
end