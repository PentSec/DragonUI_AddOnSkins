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
--
-- Availability: a skin whose target addon the player does not have cannot do
-- anything, so its whole section is presented dead — the toggle is disabled
-- (AceGUI greys the label, desaturates the box and swallows clicks), the title
-- is dimmed and a line says why. Installed-but-not-loaded targets stay usable:
-- Core applies the skin the moment ADDON_LOADED arrives, so the flag can be set
-- in advance. The same verdict is handed to `options` as a third argument, so a
-- skin dims its own extra controls instead of pretending they act on something.
local function BuildSkinSubTab(scroll, skin)
    if not _G.DragonUI or not _G.DragonUI.PanelControls then return end
    local C = _G.DragonUI.PanelControls

    local available = true
    if addon.IsSkinAvailable then
        available = addon:IsSkinAvailable(skin.key) and true or false
    end

    local section = C:AddSection(scroll, skin.label)

    if not available then
        if section.titletext then
            section.titletext:SetTextColor(0.5, 0.5, 0.5)
        end
        C:AddDescription(section, L["Target addon not found - this skin stays off until it is installed."]
            or "Target addon not found - this skin stays off until it is installed.")
    end

    if skin.desc then
        C:AddDescription(section, skin.desc)
    end

    C:AddToggle(section, {
        label = skin.toggleLabel or skin.label,
        desc = skin.toggleDesc,
        getFunc = function()
            -- Nothing is skinned while the target is missing, so show it off
            -- even if a flag written back when the addon was there is still
            -- stored: the UI must not claim an active skin that cannot exist.
            -- The stored flag is left untouched and applies again if the addon
            -- comes back.
            if not available then return false end
            return addon:GetSkinEnabled(skin.key)
        end,
        setFunc = function(val)
            -- SetSkinEnabled refuses to switch on a skin whose target is gone,
            -- so a refused write must not leave the checkbox lying about it.
            if not addon:SetSkinEnabled(skin.key, val) then return end
            if addon.RefreshSkin then addon:RefreshSkin(skin.key) end
        end,
        disabled = not available,
    })

    if type(skin.options) == "function" then
        skin.options(section, C, available)
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
