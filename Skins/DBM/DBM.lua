-- DragonUI_AddOnSkins — DBM skin.
-- Hooks DBM's in-combat surface only: DBT timer bars, boss health, range check.
-- Reached through hooks on DBM's public tables; no DBM code is copied.

local ADDON_NAME, addon = ...
local L = addon.L
local media = addon.media

local DS = {}
addon.DBMSkinAddon = DS

local SKIN_KEY = "dbm"

-- Shared helpers (utils/decorate.lua): the meter bar fill/edge and setRegion.
local deco = addon.deco

-- The fill is our sheet's meter region; DBM keeps choosing the bar colour.
local FILL_SHEET = deco.METER_SHEET
local FILL_KEY = string.lower(FILL_SHEET)

-- Interface\Buttons\WHITE8X8 is the blank every panel edge is drawn from.
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- DBM's stock textures, restored verbatim on uninstall.
local DBT_STOCK_TEXTURE = "Interface\\AddOns\\DBM-StatusBarTimers\\textures\\default.blp"
local BOSS_STOCK_TEXTURE = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
local BOSS_STOCK_BORDER = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder"
-- DBT's bar track, set once at bar creation; restored verbatim on uninstall.
local DBT_STOCK_BACKDROP = { bgFile = WHITE_TEXTURE }
local RANGE_STOCK_BACKDROP = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    tile     = true,
    tileSize = 16,
}

-- The range-check panel is the only nine-slice this skin draws.
local PANEL_BACKDROP = {
    bgFile   = WHITE_TEXTURE,
    edgeFile = WHITE_TEXTURE,
    edgeSize = 1,
}

-- Opacity of the range-check radar ground.
local TRANSLUCENT_ALPHA = 0.6

-- Whether the skin is on; the wrappers stay installed forever.
local active = false

-- Per-group hook flags, so repeated installs never stack.
local hookedCreateBar = false
local hookedBoss = false
local hookedRange = false
local hookedPrototype = false

-- Timer bars WE stamped (weak keys, session-local).
local stamped = setmetatable({}, { __mode = "k" })

-- [outerFrame] -> true: the boss-health bars WE stamped.
local stampedBoss = setmetatable({}, { __mode = "k" })


-- True once DBT and DBM both exist.
local function dbmReady()
    return type(_G.DBT) == "table" and type(_G.DBM) == "table"
end

local function isOurFill(tex)
    if not tex or type(tex.GetTexture) ~= "function" then return false end
    local path = tex:GetTexture()
    return type(path) == "string" and string.lower(path) == FILL_KEY
end

-- The texture to restore: the player's live choice, or the shipped default.
local function stockTimerTexture()
    local options = _G.DBT and _G.DBT.Options
    local path = options and options.Texture
    if type(path) == "string" and path ~= "" then return path end
    return DBT_STOCK_TEXTURE
end

-- Pushes the StatusBar's colour back onto the fill region.
local function refreshColor(statusBar)
    if type(statusBar.GetStatusBarColor) ~= "function" then return end
    local r, g, b, a = statusBar:GetStatusBarColor()
    if r and type(statusBar.SetStatusBarColor) == "function" then
        statusBar:SetStatusBarColor(r, g, b, a)
    end
end


-- ============================================================================
-- TIMER BARS
-- ============================================================================

-- The StatusBar is the bar's "$parentBar" child, resolved by name.
local function timerStatusBar(bar)
    local frame = bar and bar.frame
    if not frame or type(frame.GetName) ~= "function" then return nil end
    local name = frame:GetName()
    local statusBar = name and _G[name .. "Bar"]
    if not statusBar or type(statusBar.SetStatusBarTexture) ~= "function" then return nil end
    return statusBar, name
end

-- Height of the label row in the Thin layout; falls back to the font size.
local function rowHeight(nameFs)
    local h = nameFs and nameFs.GetHeight and nameFs:GetHeight()
    if h and h > 0 then return h end
    local size
    if nameFs and nameFs.GetFont then size = select(2, nameFs:GetFont()) end
    return size or 12
end

-- Restores the pre-Thin anchors on one bar (used on Full and on uninstall).
local function restoreBarStyle(statusBar)
    local saved = statusBar and statusBar._duiThin
    if not saved then return end
    local host = statusBar.GetParent and statusBar:GetParent()
    local name = host and host.GetName and host:GetName()
    deco.restorePoints(statusBar, saved.statusBar)
    if name then
        local nameFs = _G[name .. "BarName"]
        local timerFs = _G[name .. "BarTimer"]
        if nameFs then deco.restorePoints(nameFs, saved.name) end
        if timerFs then deco.restorePoints(timerFs, saved.timer) end
    end
    if saved.w and saved.h then statusBar:SetSize(saved.w, saved.h) end
    statusBar._duiThin = nil
end

-- Thin: name/value on a top row, the bar keeps the strip below them. The width
-- is preserved because boss bars carry their icon as a child of the bar.
local function applyBarStyle(statusBar, name)
    if not (statusBar and name) then return end
    if deco.getBarBorder("dbm") ~= "thin" then
        restoreBarStyle(statusBar)
        return
    end
    local host = statusBar.GetParent and statusBar:GetParent()
    if not host then return end
    local nameFs = _G[name .. "BarName"]
    local timerFs = _G[name .. "BarTimer"]
    if not statusBar._duiThin then
        local barPts = deco.savePoints(statusBar)
        if not barPts then return end
        local w, h = statusBar:GetSize()
        statusBar._duiThin = {
            statusBar = barPts,
            name = nameFs and deco.savePoints(nameFs),
            timer = timerFs and deco.savePoints(timerFs),
            w = w, h = h,
        }
    end
    local w = statusBar._duiThin.w
    local rowH = rowHeight(nameFs) + 1
    if nameFs then
        nameFs:ClearAllPoints()
        nameFs:SetPoint("TOPLEFT", host, "TOPLEFT", 3, 0)
    end
    if timerFs then
        timerFs:ClearAllPoints()
        timerFs:SetPoint("TOPRIGHT", host, "TOPRIGHT", -3, 0)
    end
    statusBar:ClearAllPoints()
    statusBar:SetPoint("TOP", host, "TOP", 0, -rowH)
    statusBar:SetPoint("BOTTOM", host, "BOTTOM", 0, 0)
    statusBar:SetWidth(w)
end

-- Puts the shared bar look and the restamp hooks on one StatusBar. Returns true
-- when it ran, so callers can report that something was actually painted.
local function styleBar(statusBar, name)
    if not statusBar then return false end

    deco.meterBar(statusBar)
    deco.meterBarBorder(statusBar, deco.getBarBorder("dbm") == "borderer")

    -- Clears DBT's black track behind the fill.
    if type(statusBar.SetBackdrop) == "function" then
        statusBar:SetBackdrop(nil)
    end

    -- 3.3.5 resets fill TexCoord on value change; re-apply via the bar's events.
    if not statusBar._duiDBMRestamp then
        statusBar._duiDBMRestamp = true
        statusBar:HookScript("OnValueChanged", function(self)
            if self._duiDBMPainted then deco.meterBarRefreshFill(self) end
        end)
        statusBar:HookScript("OnShow", function(self)
            if self._duiDBMPainted then deco.meterBarRefreshFill(self) end
        end)
    end
    statusBar._duiDBMPainted = true

    -- DBM's glowing leading edge is additive art from the addon, not DragonUI.
    local spark = name and _G[name .. "BarSpark"]
    if spark then spark:Hide() end

    refreshColor(statusBar)
    applyBarStyle(statusBar, name)
    return true
end

local function unstampTimerBar(statusBar)
    stamped[statusBar] = nil
    if not statusBar then return end

    statusBar._duiDBMPainted = nil
    deco.meterBarUnpaint(statusBar)
    deco.meterBarBorder(statusBar, false)
    restoreBarStyle(statusBar)

    -- SetStatusBarTexture also resets the crop, handing the fill back to DBM.
    if type(statusBar.SetStatusBarTexture) == "function" then
        statusBar:SetStatusBarTexture(stockTimerTexture())
    end

    if type(statusBar.SetBackdrop) == "function" then
        statusBar:SetBackdrop(DBT_STOCK_BACKDROP)
        statusBar:SetBackdropColor(0, 0, 0, 0.3)
    end

    local name = type(statusBar.GetName) == "function" and statusBar:GetName()
    local spark = name and _G[name .. "BarSpark"]
    if spark then spark:Show() end

    refreshColor(statusBar)
end

-- Puts the flat fill and the dark track on one timer bar.
local function styleTimerBar(bar)
    local statusBar, name = timerStatusBar(bar)
    if not statusBar then return false end
    if not styleBar(statusBar, name) then return false end
    stamped[statusBar] = true
    return true
end

-- DBT keeps live bars as KEYS in DBT.bars.
local function forEachTimerBar(fn)
    local bars = _G.DBT and _G.DBT.bars
    if type(bars) ~= "table" then return end
    for bar in pairs(bars) do
        if type(bar) == "table" then fn(bar) end
    end
end

-- Reaches the shared bar prototype through a live bar's metatable.
local function hookPrototype()
    if hookedPrototype then return true end
    local bars = _G.DBT and _G.DBT.bars
    if type(bars) ~= "table" then return false end
    local sample = next(bars)
    if sample == nil then return false end
    local mt = getmetatable(sample)
    local prototype = mt and mt.__index
    if type(prototype) ~= "table" or type(prototype.ApplyStyle) ~= "function" then return false end
    hooksecurefunc(prototype, "ApplyStyle", function(bar)
        if active then styleTimerBar(bar) end
    end)
    hookedPrototype = true
    return true
end


-- ============================================================================
-- BOSS HEALTH
-- ============================================================================

-- Boss bars are named DBM_BossHealth_Bar_<n> in a gap-free run.
local function forEachBossBar(fn)
    local index = 1
    local outer = _G["DBM_BossHealth_Bar_1"]
    while outer do
        fn(outer, index)
        index = index + 1
        outer = _G["DBM_BossHealth_Bar_" .. index]
    end
end

local function styleBossBar(outer)
    if not outer or type(outer.GetName) ~= "function" then return false end
    local name = outer:GetName()
    if not name then return false end

    local statusBar = _G[name .. "Bar"]
    if statusBar and type(statusBar.SetStatusBarTexture) == "function" then
        styleBar(statusBar, name)
    end

    -- The boss track is hidden; our edge strip is the border.
    local track = _G[name .. "BarBackground"]
    if track and type(track.Hide) == "function" then track:Hide() end

    -- The border button keeps its drag scripts; only its art is cleared.
    local border = _G[name .. "BarBorder"]
    if border and type(border.SetNormalTexture) == "function" then
        border:SetNormalTexture(nil)
    end

    stampedBoss[outer] = true
    return true
end

local function unstampBossBar(outer)
    stampedBoss[outer] = nil
    if not outer or type(outer.GetName) ~= "function" then return end
    local name = outer:GetName()
    if not name then return end

    local statusBar = _G[name .. "Bar"]
    if statusBar and type(statusBar.SetStatusBarTexture) == "function" then
        statusBar._duiDBMPainted = nil
        deco.meterBarUnpaint(statusBar)
        deco.meterBarBorder(statusBar, false)
        restoreBarStyle(statusBar)
        statusBar:SetStatusBarTexture(BOSS_STOCK_TEXTURE)
        refreshColor(statusBar)
    end

    local track = _G[name .. "BarBackground"]
    if track and type(track.Show) == "function" then track:Show() end

    local border = _G[name .. "BarBorder"]
    if border and type(border.SetNormalTexture) == "function" then
        border:SetNormalTexture(BOSS_STOCK_BORDER)
    end
end


-- ============================================================================
-- RANGE CHECK
-- ============================================================================

-- Both frames are lazily created in RangeCheck:Show; every access is guarded.
local function styleRangeCheck()
    local changed = false

    local textFrame = _G.DBMRangeCheck
    if textFrame and not textFrame._duiDBMSkin and type(textFrame.SetBackdrop) == "function" then
        textFrame:SetBackdrop(PANEL_BACKDROP)
        local c = media:GetBackdropColor()
        textFrame:SetBackdropColor(c[1], c[2], c[3], c[4])
        local b = media:GetBorderColor()
        textFrame:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
        textFrame._duiDBMSkin = true
        changed = true
    end

    local radar = _G.DBMRangeCheckRadar
    local ground = radar and radar.background
    if radar and ground and not radar._duiDBMSkin and type(ground.SetTexture) == "function" then
        local c = media:GetBackdropColor()
        ground:SetTexture(c[1], c[2], c[3], TRANSLUCENT_ALPHA)
        radar._duiDBMSkin = true
        changed = true
    end

    return changed
end

local function unstampRangeCheck()
    local textFrame = _G.DBMRangeCheck
    if textFrame and textFrame._duiDBMSkin then
        textFrame:SetBackdrop(RANGE_STOCK_BACKDROP)
        textFrame:SetBackdropColor(1, 1, 1, 1)
        textFrame:SetBackdropBorderColor(1, 1, 1, 1)
        textFrame._duiDBMSkin = nil
    end

    local radar = _G.DBMRangeCheckRadar
    if radar and radar._duiDBMSkin then
        if radar.background and type(radar.background.SetTexture) == "function" then
            radar.background:SetTexture(0, 0, 0, 0.3)
        end
        radar._duiDBMSkin = nil
    end
end


-- ============================================================================
-- HOOKS
-- ============================================================================

-- The first bar predates the prototype hook; sweep it.
local function onBarCreated()
    if not active then return end
    hookPrototype()
    forEachTimerBar(styleTimerBar)
end

-- Sweeps at the entry points that recycle and position boss bars.
local function onBossChanged()
    if not active then return end
    forEachBossBar(styleBossBar)
end

local function onRangeShown()
    if not active then return end
    styleRangeCheck()
end


-- ============================================================================
-- PUBLIC API
-- ============================================================================

function DS.IsLoaded()
    return dbmReady()
end

function DS.Install(force)
    if not dbmReady() then return false end

    local DBT = _G.DBT
    if not hookedCreateBar and type(DBT.CreateBar) == "function" then
        hooksecurefunc(DBT, "CreateBar", onBarCreated)
        hookedCreateBar = true
    end

    if not hookedBoss then
        local boss = _G.DBM.BossHealth
        if boss and type(boss.AddBoss) == "function" then
            hooksecurefunc(boss, "AddBoss", onBossChanged)
            if type(boss.UpdateSettings) == "function" then
                hooksecurefunc(boss, "UpdateSettings", onBossChanged)
            end
            hookedBoss = true
        end
    end

    if not hookedRange then
        local range = _G.DBM.RangeCheck
        if range and type(range.Show) == "function" then
            hooksecurefunc(range, "Show", onRangeShown)
            hookedRange = true
        end
    end

    hookPrototype()

    return hookedCreateBar or hookedBoss or hookedRange
end

-- True while some widget still wears our paint; drives boot cleanup.
function DS.IsWorn()
    for statusBar in pairs(stamped) do
        local tex = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
        if isOurFill(tex) then return true end
    end

    for outer in pairs(stampedBoss) do
        local name = type(outer.GetName) == "function" and outer:GetName()
        local statusBar = name and _G[name .. "Bar"]
        local tex = statusBar and statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
        if isOurFill(tex) then return true end
    end

    local textFrame = _G.DBMRangeCheck
    if textFrame and textFrame._duiDBMSkin then return true end
    local radar = _G.DBMRangeCheckRadar
    if radar and radar._duiDBMSkin then return true end

    return false
end

-- Re-applies the border choice to the live bars.
function DS.RefreshBarBorder()
    local border = deco.getBarBorder("dbm") == "borderer"
    forEachTimerBar(function(bar)
        local statusBar, name = timerStatusBar(bar)
        if statusBar then
            deco.meterBarBorder(statusBar, border)
            applyBarStyle(statusBar, name)
        end
    end)
    forEachBossBar(function(outer)
        local name = type(outer.GetName) == "function" and outer:GetName()
        local statusBar = name and _G[name .. "Bar"]
        if statusBar and name then
            deco.meterBarBorder(statusBar, border)
            applyBarStyle(statusBar, name)
        end
    end)
end

-- Styles every widget that exists now; true when at least one was painted.
local function styleEverything()
    local changed = false
    hookPrototype()
    forEachTimerBar(function(bar)
        if styleTimerBar(bar) then changed = true end
    end)
    forEachBossBar(function(outer)
        if styleBossBar(outer) then changed = true end
    end)
    if styleRangeCheck() then changed = true end
    return changed
end

-- The toggle's path: marks on and paints everything in existence.
function DS.Apply()
    if not dbmReady() then return false end
    active = true
    DS.Install(false)
    return styleEverything()
end

-- BOOT ONLY: installs hooks and re-paints; never applies or writes settings.
function DS.Restore()
    if not dbmReady() then return false end
    DS.Install(false)
    if addon:GetSkinEnabled(SKIN_KEY) then
        active = true
        styleEverything()
    end
    return true
end

-- Toggle-off path: goes inert, then hands every widget back to DBM.
function DS.Uninstall()
    active = false

    local timerBars = {}
    for statusBar in pairs(stamped) do
        timerBars[#timerBars + 1] = statusBar
    end
    for i = 1, #timerBars do
        unstampTimerBar(timerBars[i])
    end

    local bossBars = {}
    for outer in pairs(stampedBoss) do
        bossBars[#bossBars + 1] = outer
    end
    for i = 1, #bossBars do
        unstampBossBar(bossBars[i])
    end

    unstampRangeCheck()
end


-- Core installs only enabled skins; this puts the inert hooks in at load.
local function installHookAtLoad()
    if DS.Install(false) then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, _, loaded)
        if loaded ~= "DBM-Core" then return end
        if DS.Install(false) then
            self:UnregisterEvent("ADDON_LOADED")
            self:SetScript("OnEvent", nil)
        end
    end)
    watcher:Hide()
end


-- Core.lua wires the boot events for every skin; the watcher above is the
-- exception (Core does not install a disabled skin). Display strings are
-- FUNCTIONS so they resolve in the player's locale.
installHookAtLoad()

addon:RegisterSkin("dbm", "DBM", {
    install   = DS.Install,
    apply     = DS.Apply,
    restore   = DS.Restore,
    isWorn    = DS.IsWorn,
    uninstall = DS.Uninstall,

    label       = function() return L["DBM Skin"] end,
    desc        = function() return L["Flat DragonUI bars for DBM timers, boss health and the range check."] end,
    toggleLabel = function() return L["Enable DBM Skin"] end,
    toggleDesc  = function() return L["Enable the DragonUI skin for DBM."] end,

    options = function(section, C, available)
        deco.addBarBorderDropdown(section, C, available, {
            skinKey         = "dbm",
            label           = L["Bar Border"] or "Bar Border",
            desc            = L["Draw the DragonUI rim border around the bars."] or
                              "Draw the DragonUI rim border around the bars.",
            borderlessLabel = L["Borderless"] or "Borderless",
            bordererLabel   = L["Borderer"] or "Borderer",
            thinLabel       = L["Thin"] or "Thin",
            onChanged       = DS.RefreshBarBorder,
        })
    end,
}, "DBM-Core")
