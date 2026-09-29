-- DragonUI_AddOnSkins — the "Addons Skin" Options tab.
--
-- The tab is data-driven: it renders one sub-tab per skin registered in
-- Core.lua (via addon:GetRegisteredSkins()), using the display metadata each
-- skin declared at registration time. Adding a skin therefore needs NO edit to
-- this file — only the skin's own RegisterSkin call.

local ADDON_NAME, addon = ...
local L = addon.L

-- Placeholder sub-tab for skins that do not exist yet.
local function BuildOtherSubTab(scroll)
    if not _G.DragonUI or not _G.DragonUI.PanelControls then return end
    local C = _G.DragonUI.PanelControls
    local section = C:AddSection(scroll, L["Other Skins"] or "Other Skins")
    C:AddDescription(section, L["Future addon skins will appear here."] or
                     "Future addon skins will appear here.")
end

-- Generic builder: a section, an optional description, the on/off toggle
-- (always driven by the shared enable API) and any extra controls the skin
-- declared through its `options(section, C)` callback.
local function BuildSkinSubTab(scroll, skin)
    if not _G.DragonUI or not _G.DragonUI.PanelControls then return end
    local C = _G.DragonUI.PanelControls

    local section = C:AddSection(scroll, skin.label)

    if skin.desc then
        C:AddDescription(section, skin.desc)
    end

    C:AddToggle(section, {
        label = skin.toggleLabel or skin.label,
        desc = skin.toggleDesc,
        getFunc = function()
            return addon:GetSkinEnabled(skin.key)
        end,
        setFunc = function(val)
            addon:SetSkinEnabled(skin.key, val)
            if addon.RefreshSkin then addon:RefreshSkin(skin.key) end
        end,
    })

    if type(skin.options) == "function" then
        skin.options(section, C)
    end
end

local activeSubTab = "details"

local function BuildAddonSkinsTab(scroll)
    if not _G.DragonUI or not _G.DragonUI.PanelControls then return end
    local C = _G.DragonUI.PanelControls
    local Panel = _G.DragonUI.OptionsPanel

    local subtabs = {}
    local builders = {}

    for _, skin in ipairs(addon:GetRegisteredSkins()) do
        subtabs[#subtabs + 1] = { key = skin.key, label = skin.tabLabel or skin.label }
        builders[skin.key] = function(s) BuildSkinSubTab(s, skin) end
    end

    subtabs[#subtabs + 1] = { key = "other", label = L["Other"] or "Other" }
    builders.other = BuildOtherSubTab

    if not builders[activeSubTab] then
        activeSubTab = subtabs[1] and subtabs[1].key or "other"
    end

    C:AddSubTabs(scroll, subtabs, activeSubTab, function(key)
        activeSubTab = key
        if Panel and Panel.SelectTab then Panel:SelectTab("addonskins") end
    end, builders)

    if not Panel.indexing then
        local b = builders[activeSubTab]
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
