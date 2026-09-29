-- DragonUI_AddOnSkins — Core bootstrap and the central skin registry.


local ADDON_NAME, addon = ...
addon._dir = "Interface\\AddOns\\DragonUI_AddOnSkins\\Textures\\"

_G.DragonUI_AddOnSkins = addon

local _acl = LibStub("AceLocale-3.0-DragonUIAddOnSkins")
local _localeMeta = { __index = _acl:GetLocale("DragonUI_AddOnSkins", "enUS") }
addon.L = setmetatable({}, _localeMeta)

function addon.RefreshLocale()
    local DUI = _G.DragonUI
    local activeLocale = (DUI and DUI.GetActiveLocale and DUI.GetActiveLocale()) or "enUS"
    _localeMeta.__index = _acl:GetLocale("DragonUI_AddOnSkins", activeLocale)
end

-- One-shot snapshot of every addon the client knows about. Runs once, after
-- the SavedVariables are available, so callers can tell "the player does not
-- have this addon installed" from "installed but not loaded yet" without
-- re-querying GetAddOnInfo on every access. Kept `local` (not a global).
local function ScanInstalledAddons()
    local installed = {}
    local count = GetNumAddOns and GetNumAddOns() or 0

    for i = 1, count do
        local name, _, _, enabled = GetAddOnInfo(i)
        local loadable = enabled or (IsAddOnLoadOnDemand and IsAddOnLoadOnDemand(i))
        if name and loadable then
            installed[name] = enabled and "enabled" or "lod"
        end
    end

    addon.installedAddons = installed
end

addon.core = LibStub("AceAddon-3.0"):NewAddon("DragonUI_AddOnSkins")

function addon.core:OnInitialize()
    addon._dbWasLoaded = (type(_G.DragonUI_AddOnSkinsDB) == "table")
    addon._settingsWasLoaded = (type(_G.DragonUI_AddOnSkinsSettings) == "table")

    addon.settings = _G.DragonUI_AddOnSkinsSettings
    if type(addon.settings) ~= "table" then
        addon.settings = {}
        _G.DragonUI_AddOnSkinsSettings = addon.settings
    end

    addon.db = LibStub("AceDB-3.0"):New("DragonUI_AddOnSkinsDB", addon.defaults, true)

    addon.RefreshLocale()

    ScanInstalledAddons()
end

local skins = {}
local skinsOrder = {}   -- registration order, so the Options tab is stable
local watching = {}     -- real (folder) addon name -> skin key, for ADDON_LOADED

addon._loggedIn = false

function addon:GetSkinEnabled(key)
    local s = addon.settings
    if s and s[key] ~= nil then
        return s[key] and true or false
    end
    local profile = addon.db and addon.db.profile and addon.db.profile.skins
    local cfg = profile and profile[key]
    return (cfg and cfg.enabled) == true
end

function addon:SetSkinEnabled(key, value)
    value = value and true or false
    addon.settings = addon.settings or {}
    addon.settings[key] = value
    if addon.db and addon.db.profile then
        addon.db.profile.skins = addon.db.profile.skins or {}
        addon.db.profile.skins[key] = addon.db.profile.skins[key] or {}
        addon.db.profile.skins[key].enabled = value
    end
end

function addon:GetSkinOption(key, option)
    local s = addon.settings
    local opts = s and s.options and s.options[key]
    if opts and opts[option] ~= nil then
        return opts[option]
    end
    local profile = addon.db and addon.db.profile and addon.db.profile.skins
    local cfg = profile and profile[key]
    local def = cfg and cfg.options
    return def and def[option]
end

function addon:SetSkinOption(key, option, value)
    addon.settings = addon.settings or {}
    addon.settings.options = addon.settings.options or {}
    addon.settings.options[key] = addon.settings.options[key] or {}
    addon.settings.options[key][option] = value
    if addon.db and addon.db.profile then
        addon.db.profile.skins = addon.db.profile.skins or {}
        addon.db.profile.skins[key] = addon.db.profile.skins[key] or {}
        addon.db.profile.skins[key].options = addon.db.profile.skins[key].options or {}
        addon.db.profile.skins[key].options[option] = value
    end
end

local function IsSkinEnabled(key)
    return addon:GetSkinEnabled(key)
end

local function InstallSkin(key)
    local handlers = skins[key]
    if handlers and handlers.install then
        pcall(handlers.install, false)
    end
end

local function ApplySkin(key)
    local handlers = skins[key]
    if not handlers then return end
    if IsSkinEnabled(key) then
        InstallSkin(key)
        if handlers.apply then pcall(handlers.apply) end
    else
        if handlers.uninstall then pcall(handlers.uninstall) end
    end
end

function addon:RefreshSkin(key)
    ApplySkin(key)
end

local function ApplyAll()
    for key in pairs(skins) do
        ApplySkin(key)
    end
end

-- targetAddonName is the name this skin uses for display/config. When the real
-- folder name the client loads differs from it (e.g. a friendly label mapped to
-- an internal folder), pass that real name as the optional 4th argument; every
-- client lookup (IsAddOnLoaded, ADDON_LOADED, IsTargetInstalled) uses it.
function addon:RegisterSkin(key, targetAddonName, handlers, realAddonName)
    handlers = handlers or {}
    handlers.key = key
    handlers.targetAddonName = targetAddonName
    handlers.realAddonName = realAddonName or targetAddonName

    if not skins[key] then
        skinsOrder[#skinsOrder + 1] = key
    end
    skins[key] = handlers

    local checkName = realAddonName or targetAddonName
    if checkName then
        watching[checkName] = key
    end

    if checkName and IsAddOnLoaded(checkName) then
        local DUI = _G.DragonUI
        if DUI and DUI.After then
            DUI:After(0, function()
                if not IsSkinEnabled(key) then return end
                InstallSkin(key)
                if addon._loggedIn then ApplySkin(key) end
            end)
        end
    end
end

-- Ordered snapshot of every registered skin, for data-driven UI (the Options
-- tab) and diagnostics. Entries expose only the declared display metadata, not
-- the live handler table. `label` defaults to the target addon name so a skin
-- that declares nothing still produces a usable row.
function addon:GetRegisteredSkins()
    local list = {}
    for _, key in ipairs(skinsOrder) do
        local h = skins[key]
        if h then
            list[#list + 1] = {
                key             = key,
                label           = h.label or h.targetAddonName or key,
                tabLabel        = h.tabLabel,
                desc            = h.desc,
                toggleLabel     = h.toggleLabel,
                toggleDesc      = h.toggleDesc,
                options         = h.options,
                targetAddonName = h.targetAddonName,
                realAddonName   = h.realAddonName,
            }
        end
    end
    return list
end

-- True when the target is installed, regardless of whether it has loaded yet.
-- Accepts the real folder name directly, or a registered skin's visible
-- targetAddonName (resolved to its realAddonName). Returns false before the
-- one-shot scan has run.
function addon:IsTargetInstalled(targetAddonName)
    if not targetAddonName or not addon.installedAddons then
        return false
    end

    if addon.installedAddons[targetAddonName] then
        return true
    end

    for _, h in pairs(skins) do
        if h.targetAddonName == targetAddonName
            and h.realAddonName
            and addon.installedAddons[h.realAddonName]
        then
            return true
        end
    end

    return false
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        local key = watching[name]
        if not key then return end
        if not IsSkinEnabled(key) then return end
        InstallSkin(key)
        if addon._loggedIn then ApplySkin(key) end
        return
    end

    if event == "PLAYER_LOGIN" then
        addon._loggedIn = true
    end

    if addon._settingsAtLogin == nil then
        local s = _G.DragonUI_AddOnSkinsSettings
        addon._settingsAtLogin = (type(s) == "table") and tostring(s.details) or "noTable"
    end

    ApplyAll()

    local DUI = _G.DragonUI
    if DUI and DUI.After then
        DUI:After(1, ApplyAll)
        DUI:After(5, ApplyAll)
    end
end)

SLASH_DUIADDONSKINS1 = "/duiaddonskins"
SlashCmdList["DUIADDONSKINS"] = function()
    local DUI = _G.DragonUI
    local function out(msg)
        if DUI and DUI.Print then
            DUI:Print(msg)
        else
            print("DragonUI AddOnSkins: " .. tostring(msg))
        end
    end
    out("AddOnSkins: db=" .. tostring(addon.db ~= nil) ..
        " settingsGlobal=" .. tostring(_G.DragonUI_AddOnSkinsSettings ~= nil) ..
        " dbLoaded=" .. tostring(addon._dbWasLoaded) ..
        " settingsLoaded=" .. tostring(addon._settingsWasLoaded) ..
        " settingsAtLogin=" .. tostring(addon._settingsAtLogin) ..
        " lsm=" .. tostring(LibStub("LibSharedMedia-3.0", true) ~= nil))
    for key in pairs(skins) do
        out("AddOnSkins: skin '" .. key .. "' enabled=" .. tostring(addon:GetSkinEnabled(key)))
    end
    if type(_G.DragonUI_AddOnSkinsSettings) == "table" then
        for k, v in pairs(_G.DragonUI_AddOnSkinsSettings) do
            out("AddOnSkins: settings." .. tostring(k) .. "=" .. tostring(v))
        end
    end
end
