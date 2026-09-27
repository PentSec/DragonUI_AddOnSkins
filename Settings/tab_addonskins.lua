-- tab registration.

local ADDON_NAME, addon = ...
local L = addon.L

local function BuildDetailsSubTab(scroll)
    if not _G.DragonUI or not _G.DragonUI.PanelControls then return end
    local C = _G.DragonUI.PanelControls

    local section = C:AddSection(scroll, L["Details! Skin"] or "Details! Skin")

    C:AddDescription(section, L["Retail damage-meter theme for Details!."] or
                     "Retail damage-meter theme for Details!.")

    C:AddToggle(section, {
        label = L["Enable Details! Skin"] or "Enable Details! Skin",
        desc = L["Enable the DragonUI skin for Details!."] or
               "Enable the DragonUI skin for Details!.",
        getFunc = function()
            return addon:GetSkinEnabled("details")
        end,
        setFunc = function(val)
            addon:SetSkinEnabled("details", val)
            if addon.RefreshSkin then addon:RefreshSkin("details") end
        end,
    })

    C:AddSlider(section, {
        label = L["Background Opacity"] or "Background Opacity",
        desc = L["Opacity of the Details! meter background texture."] or
               "Opacity of the Details! meter background texture.",
        min = 0, max = 1, step = 0.05, isPercent = true,
        getFunc = function()
            local DS = addon.DetailsSkinAddon
            return (DS and DS.GetPanelAlpha and DS.GetPanelAlpha()) or 1
        end,
        setFunc = function(val)
            local DS = addon.DetailsSkinAddon
            if DS and DS.SetPanelAlpha then
                DS.SetPanelAlpha(val)
                if DS.RefreshPanelAlpha then DS.RefreshPanelAlpha() end
            end
        end,
    })

end

local function BuildOtherSubTab(scroll)
    if not _G.DragonUI or not _G.DragonUI.PanelControls then return end
    local C = _G.DragonUI.PanelControls
    local section = C:AddSection(scroll, L["Other Skins"] or "Other Skins")
    C:AddDescription(section, L["Future addon skins will appear here."] or
                     "Future addon skins will appear here.")
end

local activeSubTab = "details"
local subTabs = {
    { key = "details",   label = L["Details!"] or "Details!" },
    { key = "other",     label = L["Other"] or "Other" },
}
local subTabBuilders = { details = BuildDetailsSubTab, other = BuildOtherSubTab }

local function BuildAddonSkinsTab(scroll)
    if not _G.DragonUI or not _G.DragonUI.PanelControls then return end
    local C = _G.DragonUI.PanelControls
    local Panel = _G.DragonUI.OptionsPanel

    C:AddSubTabs(scroll, subTabs, activeSubTab, function(key)
        activeSubTab = key
        if Panel and Panel.SelectTab then Panel:SelectTab("addonskins") end
    end, subTabBuilders)

    if not Panel.indexing then
        local b = subTabBuilders[activeSubTab]
        if b then b(scroll) end
    end
end

local function TryRegister()
    if _G.DragonUI and _G.DragonUI.OptionsPanel then
        _G.DragonUI.OptionsPanel:RegisterTab("addonskins", "Addons Skin", BuildAddonSkinsTab, 1.5)
        return true
    end
    return false
end

if not TryRegister() then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, name)
        if name == "DragonUI_Options" and TryRegister() then
            f:UnregisterEvent("ADDON_LOADED")
        end
    end)
end
