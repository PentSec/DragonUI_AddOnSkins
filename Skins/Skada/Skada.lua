-- DragonUI_AddOnSkins — Skada-WoTLK skin.
-- Reskins the damage meter: gold header, near-invisible panel, class rows.
-- Skada has no skin registry: this skin writes win.db and overlays its own art.

local ADDON_NAME, addon = ...
local DUI = _G.DragonUI
local L = addon.L
local media = addon.media   -- centralized palette (utils/media.lua)

local DS = {}
addon.SkadaSkinAddon = DS

-- Shared helpers (utils/decorate.lua): meter strips, panel/header, panelAlpha.
local deco = addon.deco

-- Sheet for LibSharedMedia and row fallbacks; single definition in the helper.
local SHEET = deco.METER_SHEET

-- Statusbar name for the shared fill sheet; LSM resolves it by name.
local MEDIA_FILL = "DragonUI Skada Bar Fill"

-- Named regions of the sheet (utils/atlas.lua).
local ATLAS_FILL   = "ui-hud-cooldownmanager-bar"
local ATLAS_ROW    = "ui-damagemeters-bar-shadowbg"
local ATLAS_EDGE   = "ui-damagemeters-bar-shadowedge"

-- Band/title height; the band geometry lives in the helper.
local HEADER_H        = 28

local ROW_FONT, ROW_FONT_SIZE = "Arial Narrow", 14
local TITLE_FONT, TITLE_FONT_SIZE = "Friz Quadrata TT", 13
local BAR_SPACING = 4

-- Lib orientation literals (SpecializedLibBars-1.0).
local LEFT_TO_RIGHT = 1
local RIGHT_TO_LEFT = 2

local ipairs, pairs, next, type, pcall, hooksecurefunc = ipairs, pairs, next, type, pcall, hooksecurefunc
local min, max = math.min, math.max


-- Returns the Skada addon table once it is ready, or nil.
local function skada()
    local S = _G.Skada
    if S and S.windows and S.displays and S.displays.bar then return S end
    return nil
end

-- Runs fn(win) on every live bar-display window; returns how many were visited.
local function forEachBarWindow(fn)
    local S = skada()
    if not S then return 0 end
    local seen = 0
    for _, win in ipairs(S.windows) do
        if type(win) == "table" and win.db and win.bargroup and win.db.display == "bar" then
            seen = seen + 1
            if fn then fn(win) end
        end
    end
    return seen
end

-- Registers the sheet as a LibSharedMedia statusbar so Skada can name it.
-- Silently no-ops if LSM is unavailable.
local function registerMedia()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not (LSM and LSM.Register) then return false end
    pcall(LSM.Register, LSM, "statusbar", MEDIA_FILL, SHEET)
    return true
end


-- ============================================================================
-- PER-BAR DECORATION
-- ============================================================================

-- Extra left inset when Skada draws a per-row icon.
local function stripReserve(bar)
    local group = bar and bar.ownerGroup
    return (group and group.showIcon and group.thickness) or 0
end

-- Draws (or reuses) one of our overlaid strips, anchored to the bar.
local function rowStrip(bar, key, layer, region, target)
    local tex = bar[key]
    if not tex then
        tex = bar:CreateTexture(nil, layer)
        bar[key] = tex
    end
    return deco.meterStrip(tex, region, target or bar, stripReserve(bar))
end

-- Full height: hands the fill and the labels back to Skada's own layout.
local function fullSkadaBar(bar)
    if type(bar.UpdateOrientationLayout) == "function" and bar.ownerGroup then
        bar:UpdateOrientationLayout(bar.ownerGroup.orientation)
    end
    if bar._duiBarBG then deco.anchorStrip(bar._duiBarBG, bar, stripReserve(bar)) end
    if bar._duiBarEdge then deco.anchorStrip(bar._duiBarEdge, bar, stripReserve(bar)) end
end

-- Thin: name/value on a top row, the fill keeps the strip below them.
local function thinSkadaBar(bar)
    if not (bar.fg and bar.label) then return end
    local group = bar.ownerGroup
    local rtl = group and group.orientation == RIGHT_TO_LEFT
    local label, timer = bar.label, bar.timerLabel
    label:ClearAllPoints()
    if timer then timer:ClearAllPoints() end
    if rtl then
        if timer then
            timer:SetPoint("TOPLEFT", bar, "TOPLEFT", 3, 0)
            timer:SetJustifyH("LEFT")
        end
        label:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -3, 0)
        label:SetJustifyH("RIGHT")
        if timer then label:SetPoint("LEFT", timer, "RIGHT") end
    else
        label:SetPoint("TOPLEFT", bar, "TOPLEFT", 3, 0)
        label:SetJustifyH("LEFT")
        if timer then
            timer:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -3, 0)
            timer:SetJustifyH("RIGHT")
            label:SetPoint("RIGHT", timer, "LEFT")
        end
    end
    local top = -(deco.fontRowHeight(label, 11) + 1)
    bar.fg:ClearAllPoints()
    if rtl then
        bar.fg:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, top)
        bar.fg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    else
        bar.fg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, top)
        bar.fg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    end
    if bar._duiBarBG then deco.anchorStrip(bar._duiBarBG, bar.fg, stripReserve(bar)) end
    if bar._duiBarEdge then deco.anchorStrip(bar._duiBarEdge, bar.fg, stripReserve(bar)) end
end

-- Applies the stored bar border/style to one bar. Full is a no-op unless we had
-- overridden Skada's layout, so Skada keeps owning its own geometry.
local function applyBarStyle(bar)
    if not bar then return end
    if deco.getBarBorder("skada") == "thin" then
        thinSkadaBar(bar)
        bar._duiThinApplied = true
    elseif bar._duiThinApplied then
        fullSkadaBar(bar)
        bar._duiThinApplied = nil
    end
end

-- Teaches bar.fg to reveal only our fill region of the sheet.
local function cropFillToRegion(bar)
    if bar._duiFillHooked then return end
    local region = addon.atlasinfo and addon.atlasinfo[ATLAS_FILL]
    if not region then return end
    local orig = bar.fg.SetTexCoord
    if type(orig) ~= "function" then return end

    local left, right, top, bottom = region[4], region[5], region[6], region[7]
    local span = right - left

    bar._duiFillHooked = true
    -- Orientation is read from the captured bar, never from self (bar.fg).
    bar.fg.SetTexCoord = function(_, u1, u2)
        local amt = u2 - u1
        if amt < 0 then
            amt = 0
        elseif amt > 1 then
            amt = 1
        end
        local group = bar.ownerGroup
        if group and group.orientation == RIGHT_TO_LEFT then
            orig(bar.fg, right - span * amt, right, top, bottom)
        else
            orig(bar.fg, left, left + span * amt, top, bottom)
        end
    end
end

-- Everything this skin does to a single bar. Idempotent: safe to run on every
-- display update, and safe on a bar Skada recycled from its own pool.
local function stampBar(bar)
    if not (bar and bar.fg) then return false end

    cropFillToRegion(bar)

    -- Hides Skada's own row art (bg/hg/spark), capturing its visibility once.
    if not bar._duiArtSaved then
        bar._duiArtSaved = true
        local art = { "bg", "hg", "spark" }
        for i = 1, #art do
            local key = art[i]
            local tex = bar[key]
            bar["_duiSaved" .. key:gsub("^%a", string.upper)] = tex ~= nil and tex:IsShown() or false
        end
    end
    for _, key in ipairs({ "bg", "hg", "spark" }) do
        local tex = bar[key]
        if tex then tex:Hide() end
    end

    rowStrip(bar, "_duiBarBG", "BACKGROUND", ATLAS_ROW)
    rowStrip(bar, "_duiBarEdge", "OVERLAY", ATLAS_EDGE)
    deco.meterBarBorder(bar, deco.getBarBorder("skada") == "borderer")
    applyBarStyle(bar)
    return true
end

-- Undoes stampBar for one bar.
local function resetBar(bar)
    if not (bar and bar.fg) then return end

    if bar._duiFillHooked then
        bar.fg.SetTexCoord = nil
        bar._duiFillHooked = nil
    end

    if bar._duiBarBG then bar._duiBarBG:Hide() end
    if bar._duiBarEdge then bar._duiBarEdge:Hide() end
    deco.meterBarBorder(bar, false)

    -- Hand the row layout back to Skada before hiding our strips.
    if bar._duiThinApplied then
        fullSkadaBar(bar)
        bar._duiThinApplied = nil
    end

    -- Restore Skada's own art to the visibility captured on the first stamp.
    for _, key in ipairs({ "Bg", "Hg", "Spark" }) do
        local saved = bar["_duiSaved" .. key]
        if saved ~= nil then
            local tex = bar[key:lower()]
            if tex then
                if saved then tex:Show() else tex:Hide() end
            end
            bar["_duiSaved" .. key] = nil
        end
    end
    bar._duiArtSaved = nil
end

local function stampBars(win)
    local group = win.bargroup
    if not (group and group.GetBars) then return end
    for _, bar in pairs(group:GetBars() or {}) do
        stampBar(bar)
    end
end

local function resetBars(win)
    local group = win.bargroup
    if not (group and group.GetBars) then return end
    for _, bar in pairs(group:GetBars() or {}) do
        resetBar(bar)
    end
end


-- ============================================================================
-- PER-WINDOW DECORATION
-- ============================================================================

-- Adds the shared panel and header band to one window.
local function decorateWindow(win)
    local g = win.bargroup
    if not (g and g.CreateTexture) then return false end

    deco.meterPanel(g, DS.GetPanelAlpha())

    local button = g.button
    if not button then return true end

    if not g._duiSavedTitleLevel then
        g._duiSavedTitleLevel = button:GetFrameLevel()
    end
    button:SetFrameLevel(g:GetFrameLevel() + 1)

    deco.meterHeader(g, button, "BOTTOMLEFT", "BOTTOMRIGHT", "ARTWORK")
    return true
end

-- Removes our panel and header from one window and puts the title level back.
local function clearDecoration(win)
    local g = win and win.bargroup
    if not g then return end

    if g._duiMeterHeader then g._duiMeterHeader:Hide() end
    if g._duiMeterPanel then g._duiMeterPanel:Hide() end
    if g._duiSavedTitleLevel and g.button then
        g.button:SetFrameLevel(g._duiSavedTitleLevel)
        g._duiSavedTitleLevel = nil
    end
end


-- ============================================================================
-- SETTINGS
-- ============================================================================

-- Every key this skin writes; snapshot and restore walk the same list.
local OWNED_KEYS = {
    "bartexture", "barfont", "barfontsize", "barfontflags",
    "barspacing", "classcolorbars", "classicons", "spexicons",
    "roleicons", "spark", "disablehighlight", "enabletitle",
    "background", "title",
}

local function copyValue(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copyValue(v) end
    return out
end

-- Persisted snapshot of a window's player values, keyed by profile and db.name.
local function snapshotStore()
    local s = addon.settings
    if type(s) ~= "table" then return nil end
    s.dbSnapshots = s.dbSnapshots or {}
    return s.dbSnapshots
end

-- Returns the [profile, db.name] pair that identifies a window.
local function snapshotKey(p)
    local S = skada()
    local data = S and S.data
    local profile = (data and data.GetCurrentProfile and data:GetCurrentProfile()) or "?"
    return tostring(profile), tostring(p and p.name or "?")
end

-- Returns the [profile] bucket, creating it when asked.
local function snapshotBucket(profile, create)
    local store = snapshotStore()
    if not store then return nil end
    local bucket = store[profile]
    if not bucket and create then
        bucket = {}
        store[profile] = bucket
    end
    return bucket
end

-- Captures a window's player values ONCE, before our writes land in the db.
local function snapshotDb(p)
    local profile, name = snapshotKey(p)
    local bucket = snapshotBucket(profile, true)
    if not bucket or bucket[name] then return end
    local snap = {}
    for _, key in ipairs(OWNED_KEYS) do
        snap[key] = copyValue(p[key])
    end
    bucket[name] = snap
end

local function restoreDb(p)
    local profile, name = snapshotKey(p)
    local bucket = snapshotBucket(profile, false)
    local snap = bucket and bucket[name]
    if not snap then return false end
    for _, key in ipairs(OWNED_KEYS) do
        local saved = snap[key]
        if saved == nil then
            p[key] = nil
        else
            p[key] = copyValue(saved)
        end
    end
    bucket[name] = nil
    return true
end

-- Drops captures whose window no longer exists; liveKeys is the open set.
local function pruneSnapshots(liveKeys)
    local store = snapshotStore()
    if not store then return end
    for profile, bucket in pairs(store) do
        for name in pairs(bucket) do
            if not liveKeys[profile .. "/" .. name] then bucket[name] = nil end
        end
        if next(bucket) == nil then store[profile] = nil end
    end
end

-- Writes the keys Skada reads, before ApplySettings; colours come from media.
local function writeSettings(win)
    local p = win.db
    if type(p) ~= "table" then return false end
    snapshotDb(p)

    local accent = media:GetAccentColor()

    -- Rows: our fill, revealed through the atlas crop installed by stampBar.
    p.bartexture = MEDIA_FILL

    -- Skada's stretched ground/header art is made transparent; ours draws over it.
    p.background = p.background or {}
    p.background.color = p.background.color or { r = 0, g = 0, b = 0, a = 1 }
    p.background.color.a = 0
    p.background.borderthickness = 0

    p.title = p.title or {}
    p.title.color = p.title.color or { r = 0, g = 0, b = 0, a = 1 }
    p.title.color.a = 0
    p.title.borderthickness = 0
    p.title.height = HEADER_H
    p.title.font = TITLE_FONT
    p.title.fontsize = TITLE_FONT_SIZE
    p.title.fontflags = ""
    p.title.textcolor = { r = accent[1], g = accent[2], b = accent[3], a = accent[4] }

    p.barfont = ROW_FONT
    p.barfontsize = ROW_FONT_SIZE
    p.barfontflags = ""
    p.barspacing = BAR_SPACING
    p.classcolorbars = true

    -- The icon pipeline stays on; showIcon is never written.
    p.classicons = true
    p.spexicons = true
    p.roleicons = true

    -- Skada's sparkline and hover highlight are turned off.
    p.spark = false
    p.disablehighlight = true

    -- Keeps the title on, which draws Skada's anchor buttons; p.buttons is never written.
    p.enabletitle = true

    return true
end


-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- True when Skada is loaded and its bar display is ready to be skinned.
function DS.IsSkadaLoaded()
    return IsAddOnLoaded("Skada") and skada() ~= nil
end

-- Background panel opacity, 0..1 (stored by the shared helper, key "skada").
function DS.GetPanelAlpha()
    return deco.getPanelAlpha("skada")
end

function DS.SetPanelAlpha(v)
    deco.setPanelAlpha("skada", v)
end

-- Re-tints just the background panel on the open windows (no full re-apply).
function DS.RefreshPanelAlpha()
    local alpha = DS.GetPanelAlpha()
    forEachBarWindow(function(win)
        local panel = win.bargroup and win.bargroup._duiMeterPanel
        if panel then panel:SetVertexColor(1, 1, 1, alpha) end
    end)
end

-- Re-applies the bar border/style choice to the open windows (no full re-apply).
function DS.RefreshBarBorder()
    local border = deco.getBarBorder("skada") == "borderer"
    forEachBarWindow(function(win)
        local group = win.bargroup
        if group and group.GetBars then
            for _, bar in pairs(group:GetBars() or {}) do
                deco.meterBarBorder(bar, border)
                applyBarStyle(bar)
            end
        end
    end)
end

-- Writes our keys, runs Skada's ApplySettings, then stamps and decorates.
function DS.ApplyToWindow(win)
    if type(win) ~= "table" or not win.db or not win.bargroup then return false end
    if win.db.display ~= "bar" then return false end

    writeSettings(win)
    -- Stamp before apply: SetTextureValue reads bar.showIcon when sizing the fill.
    stampBars(win)
    if type(win.display) == "table" and type(win.display.ApplySettings) == "function" then
        pcall(win.display.ApplySettings, win.display, win)
    end
    decorateWindow(win)
    return true
end


-- ============================================================================
-- HOOKS
-- ============================================================================

local hooked = {}
local originals = {}

-- Wraps a method with before/after callbacks; captures the original once.
local function wrapMethod(owner, name, before, after)
    if not (owner and owner[name] and type(owner[name]) == "function") then return false end
    if hooked[name] then return false end

    local orig = owner[name]
    originals[name] = orig
    hooked[name] = true

    owner[name] = function(...)
        if before then before(...) end
        local a, b, c = orig(...)
        if after then after(...) end
        return a, b, c
    end
    return true
end

local function unwrapMethod(owner, name)
    if not hooked[name] then return false end
    owner[name] = originals[name]
    hooked[name] = nil
    originals[name] = nil
    return true
end

local function installHooks()
    local S = skada()
    if not S then return false end

    -- ApplySettings turns win.db into frames: keys before, art after.
    wrapMethod(S.displays.bar, "ApplySettings",
        function(self, win)
            if type(win) == "table" and win.db and win.db.display == "bar" then
                writeSettings(win)
            end
        end,
        function(self, win)
            if type(win) == "table" and win.db and win.db.display == "bar" then
                decorateWindow(win)
                stampBars(win)
            end
        end)

    -- Update creates bars for newly seen modes; stamp them as soon as they exist.
    wrapMethod(S.displays.bar, "Update", nil,
        function(self, win)
            if type(win) == "table" and win.db and win.db.display == "bar" then
                stampBars(win)
            end
        end)

    wrapMethod(S, "CreateWindow", nil,
        function(self, name)
            if addon:GetSkinEnabled("skada") then
                local created = S.windows and S.windows[#S.windows]
                if created and created.db and created.db.name == name then
                    DS.ApplyToWindow(created)
                end
            end
        end)

    return true
end

local function removeHooks()
    local S = skada()
    if not S then
        hooked, originals = {}, {}
        return
    end
    unwrapMethod(S.displays.bar, "ApplySettings")
    unwrapMethod(S.displays.bar, "Update")
    unwrapMethod(S, "CreateWindow")
end


-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function DS.Restore()
    local S = skada()
    if not S then return false end
    registerMedia()
    installHooks()
    DS.Install(false)
    -- Decorates existing windows that still wear our skin; writes nothing.
    forEachBarWindow(function(win)
        if win and win.db and win.db.display == "bar" then
            -- Only stamp bars and decorate; do NOT writeSettings or snapshotDb.
            stampBars(win)
            decorateWindow(win)
        end
    end)
    return true
end

-- Registers the media entry and the hooks; never forces a re-apply.
function DS.Install(force)
    local S = skada()
    if not S then return false end
    registerMedia()
    installHooks()
    return true
end

-- Installs, marks the skin on, and paints every open bar window.
function DS.Apply()
    local S = skada()
    if not S then return false end
    DS.Install(true)
    addon:SetSkinEnabled("skada", true)

    local applied = 0
    forEachBarWindow(function(win)
        if DS.ApplyToWindow(win) then applied = applied + 1 end
    end)

    -- Push the values out to the frames.
    if type(S.UpdateDisplay) == "function" then
        pcall(S.UpdateDisplay, S, true)
    end
    return applied > 0
end

-- Drops our settings and art, then repaints the window from the player's profile.
function DS.Uninstall()
    addon:SetSkinEnabled("skada", false)

    local S = skada()
    if not S then
        removeHooks()
        return
    end

    removeHooks()

    -- Collect live keys across every window, bar or not, so pruning keeps them.
    local liveKeys = {}
    for _, win in ipairs(S.windows or {}) do
        local p = win and win.db
        if type(p) == "table" then
            local profile, name = snapshotKey(p)
            liveKeys[profile .. "/" .. name] = true
        end
    end

    forEachBarWindow(function(win)
        local p = win.db
        resetBars(win)
        clearDecoration(win)
        -- Restores the window's pre-skin values, not Skada's defaults.
        if type(p) == "table" then
            restoreDb(p)
        end

        if type(win.display) == "table" and type(win.display.ApplySettings) == "function" then
            pcall(win.display.ApplySettings, win.display, win)
        end
    end)

    pruneSnapshots(liveKeys)

    if type(S.UpdateDisplay) == "function" then
        pcall(S.UpdateDisplay, S, true)
    end
end


SLASH_DUISKADA1 = "/duiskada"
SlashCmdList["DUISKADA"] = function()
    if not DS.IsSkadaLoaded() then
        if DUI and DUI.Print then
            DUI:Print("|cff1784d1DragonUI|r: " .. L["Skada is not installed."])
        end
        return
    end
    if DS.Apply() then
        if DUI and DUI.Print then
            DUI:Print("|cff1784d1DragonUI|r: " .. L["Skada skin applied."])
        end
    elseif DUI and DUI.Print then
        DUI:Print("|cff1784d1DragonUI|r: " .. L["Could not apply the skin - Skada is not ready yet."])
    end
end


-- Core.lua wires the boot events for every skin; this file just registers it.
-- Display strings are FUNCTIONS so they resolve in the player's locale.
addon:RegisterSkin("skada", "Skada", {
    install   = DS.Install,
    apply     = DS.Apply,
    restore   = DS.Restore,
    uninstall = DS.Uninstall,

    label       = function() return L["Skada Skin"] end,
    desc        = function() return L["Skada meter theme."] end,
    toggleLabel = function() return L["Enable Skada Skin"] end,
    toggleDesc  = function() return L["Enable the DragonUI skin for Skada."] end,

    options = function(section, C, available)
        deco.addPanelAlphaSlider(section, C, available, {
            skinKey   = "skada",
            label     = L["Background Opacity"] or "Background Opacity",
            desc      = L["Opacity of the Skada meter background texture."] or
                       "Opacity of the Skada meter background texture.",
            onChanged = DS.RefreshPanelAlpha,
        })

        deco.addBarBorderDropdown(section, C, available, {
            skinKey         = "skada",
            label           = L["Bar Border"] or "Bar Border",
            desc            = L["Draw the DragonUI rim border around the bars."] or
                              "Draw the DragonUI rim border around the bars.",
            borderlessLabel = L["Borderless"] or "Borderless",
            bordererLabel   = L["Borderer"] or "Borderer",
            thinLabel       = L["Thin"] or "Thin",
            onChanged       = DS.RefreshBarBorder,
        })
    end,
})
