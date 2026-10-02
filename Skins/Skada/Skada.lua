-- DragonUI_AddOnSkins — Skada-WoTLK skin.
--
-- Reskins the Skada damage meter to DragonUI's retail-style look: a gold title
-- header, a near-invisible background panel and class-coloured rows that wear
-- Skada has no skin registry (no D.skins). Everything it draws is read at paint
-- time out of `win.db` + LibSharedMedia through
-- Skada.displays.bar:ApplySettings(win), so this skin works by writing the keys
-- Skada reads and then overlaying the art it cannot be told to change.

local ADDON_NAME, addon = ...
local DUI = _G.DragonUI
local L = addon.L
local media = addon.media   -- centralized palette (utils/media.lua)

local DS = {}
addon.SkadaSkinAddon = DS

-- rows, panel and header out of.
local SHEET = addon._dir .. [[Details\uidamagemeters.blp]]

-- Skada fetches p.bartexture through LibSharedMedia ("statusbar"), and
-- MediaFetch has no path fallback, so the sheet needs a media NAME to be found
-- by. It is a new name for an existing file, not a copy of the file.
local MEDIA_FILL = "DragonUI Skada Bar Fill"

-- Named regions of the sheet (utils/atlas.lua).
local ATLAS_FILL   = "ui-hud-cooldownmanager-bar"
local ATLAS_ROW    = "ui-damagemeters-bar-shadowbg"
local ATLAS_EDGE   = "ui-damagemeters-bar-shadowedge"
local ATLAS_HEADER = "ui-damagemeters-header-bar"
local ATLAS_PANEL  = "damagemeters-background"

-- outset, panel feather trim) and leaves the icon layout entirely to Skada:
-- its reserved left strip already puts the class icon flush against the window
local HEADER_H        = 28
local HEADER_OVERHANG = 4
local PANEL_CROP_PX   = 3

local BAR_INSET_LT, BAR_INSET_T, BAR_INSET_RB, BAR_INSET_B = -2, 2, 2, -2

local ROW_FONT, ROW_FONT_SIZE = "Arial Narrow", 14
local TITLE_FONT, TITLE_FONT_SIZE = "Friz Quadrata TT", 13
local BAR_SPACING = 4

-- SpecializedLibBars-1.0: lib.LEFT_TO_RIGHT / RIGHT_TO_LEFT. Read as a literal
-- so the skin never has to name Skada's private library to learn them.
local LEFT_TO_RIGHT = 1
local RIGHT_TO_LEFT = 2

local ipairs, pairs, next, type, pcall, hooksecurefunc = ipairs, pairs, next, type, pcall, hooksecurefunc
local min, max = math.min, math.max


-- Points a texture at one of our named atlas regions. Same contract as the
-- behind it failed to load, because SetTexture() on a bad path paints nothing
-- instead of erroring.
local function setRegion(tex, name, cropX)
    if not tex then return false end
    local region = addon.atlasinfo and addon.atlasinfo[name]
    if not region then return false end
    local left, right = region[4], region[5]
    if cropX and cropX > 0 and region[2] and region[2] > 0 then
        local uPerPx = (region[5] - region[4]) / region[2]
        left, right = left + cropX * uPerPx, right - cropX * uPerPx
    end
    tex:SetTexture(region[1])
    if tex.GetTexture and not tex:GetTexture() then return false end
    tex:SetTexCoord(left, right, region[6], region[7])
    return true
end

-- Returns the Skada addon table once it is ready, or nil.
local function skada()
    local S = _G.Skada
    if S and S.windows and S.displays and S.displays.bar then return S end
    return nil
end

-- Calls fn(win) for every live window using the bar display. Returns how many
-- were visited. Other displays (inline, broker, legacy) have their own modules
-- and are out of scope.
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

-- Draws (or reuses) one of our overlaid strips and anchors it to the bar.
--
-- Skada reserves a strip on the group's left for the icons: SortBars offsets the
-- first bar by `thickness` and chains every later bar off it
-- (SpecializedLibBars-1.0.lua:1663), while updateSize shortens each bar by the
-- same amount (line 1980). Both read a `showIcon`, but the group's for the
-- position and the bar's for the width - so the strip has to be spanned, not
-- just the bar, or the icons would sit on bare panel with no row behind them.
local function rowStrip(bar, key, layer, region)
    local tex = bar[key]
    if not tex then
        tex = bar:CreateTexture(nil, layer)
        bar[key] = tex
    end
    if not setRegion(tex, region) then return false end
    tex:SetVertexColor(1, 1, 1, media:GetRowStripAlpha())
    tex:Show()
    local group = bar.ownerGroup
    local reserve = (group and group.showIcon and group.thickness) or 0
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", bar, "TOPLEFT", BAR_INSET_LT - reserve, BAR_INSET_T)
    tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", BAR_INSET_RB, BAR_INSET_B)
    return true
end

-- Teaches bar.fg to reveal our fill region instead of the whole sheet.
--
-- Skada sets bar.fg's texture once to a single path and then drives the value
-- purely through texcoords: SetTexCoord(0, amt, 0, 1) left-to-right, or
-- SetTexCoord(1 - amt, 1, 0, 1) right-to-left (SpecializedLibBars-1.0.lua:2078).
-- Without this the bar would show the entire atlas as it filled.
--
-- Both forms span `amt` in u, so the width of the request is the value
-- fraction either way and one wrapper serves both orientations. Instanced once
-- per bar and never re-wrapped.
local function cropFillToRegion(bar)
    if bar._duiFillHooked then return end
    local region = addon.atlasinfo and addon.atlasinfo[ATLAS_FILL]
    if not region then return end
    local orig = bar.fg.SetTexCoord
    if type(orig) ~= "function" then return end

    local left, right, top, bottom = region[4], region[5], region[6], region[7]
    local span = right - left

    bar._duiFillHooked = true
    -- `ownerGroup` is a field of the BAR (SpecializedLibBars-1.0.lua:1033), and
    -- SetTextureValue is the only thing that reads it -- the fill texture never
    -- sees it. So orientation has to be resolved through the captured bar rather
    -- than through `self`, which here is bar.fg.
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

    -- Skada's own row art off. bg is the same sprite as the fill (it just gets
    -- tinted by SetBarBackgroundColor), hg is the hover highlight and spark is
    -- Skada's sparkline sprite.
    --
    -- Their visibility is captured ONCE, on the first stamp only. Capturing on
    -- every stamp would record what this skin had already hidden and hand back
    -- the wrong thing - and hg in particular is shown and hidden on hover, so
    -- "assume hidden" is wrong the moment the pointer crosses the bar.
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

-- Our background panel and header band on one window.
local function decorateWindow(win)
    local g = win.bargroup
    if not (g and g.CreateTexture) then return false end

    local panel = g._duiMeterPanel
    if not panel then
        panel = g:CreateTexture(nil, "BACKGROUND")
        g._duiMeterPanel = panel
    end
    if not setRegion(panel, ATLAS_PANEL, PANEL_CROP_PX) then
        panel:SetTexture(SHEET)
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", g, "TOPLEFT")
    panel:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT")
    panel:SetVertexColor(1, 1, 1, DS.GetPanelAlpha())
    panel:Show()

    -- The header band lives on the bargroup, not on the title button: a child
    -- frame and its ARTWORK children are drawn before a later sibling, so
    -- parenting it to the title button would bury the title text under it.
    -- Raising the title button one frame level puts the text back on top.
    local button = g.button
    if not button then return true end

    if not g._duiSavedTitleLevel then
        g._duiSavedTitleLevel = button:GetFrameLevel()
    end
    button:SetFrameLevel(g:GetFrameLevel() + 1)

    local hdr = g._duiMeterHeader
    if not hdr then
        hdr = g:CreateTexture(nil, "ARTWORK")
        g._duiMeterHeader = hdr
    end
    if not setRegion(hdr, ATLAS_HEADER) then
        hdr:SetTexture(SHEET)
    end
    hdr:ClearAllPoints()
    hdr:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -HEADER_OVERHANG, 0)
    hdr:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", HEADER_OVERHANG, 0)
    hdr:SetHeight(HEADER_H)
    hdr:Show()
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

-- Every key this skin writes. Both the pre-apply snapshot and the uninstall
-- restore walk this one list, so the two can never drift apart.
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

-- What the player had before the skin first touched a window. Uninstall hands
-- this back rather than Skada's stock defaults, which would silently discard a
-- profile the player had actually configured.
--
-- It has to be PERSISTED, not a local table. Our writes land in Skada's own
-- AceDB (SkadaDB), so they outlive the session, while a snapshot held only in
-- memory dies with it. The consequence of getting this wrong is not a cosmetic
-- glitch: after one /reload the snapshot is gone while our values are still in
-- SkadaDB, so Uninstall has nothing to restore and the player is left wearing
-- "Arial Narrow", barspacing 4 and our title font FOREVER, with no toggle that
-- can undo it.
--
-- Keyed the same two things Skada keys its own persisted window table by: the
-- AceDB profile name plus db.name. That is what lets the snapshot find its
-- window again on the next login without holding a reference to a table that no
-- longer exists.
local function snapshotStore()
    local s = addon.settings
    if type(s) ~= "table" then return nil end
    s.dbSnapshots = s.dbSnapshots or {}
    return s.dbSnapshots
end

-- store[profile][windowName] -> snapshot. Two levels rather than one joined key,
-- so no window name can ever collide with a separator.
--
-- profile is Skada's own AceDB profile name, which is also how Skada scopes its
-- persisted windows: window #1 in profile "Raid" is a different table from
-- window #1 in profile "PvP", and the player's settings for each are different.
-- db.name is unique among live windows (CreateWindow runs CheckDuplicate), so
-- the pair identifies one window across sessions.
local function snapshotKey(p)
    local S = skada()
    local data = S and S.data
    local profile = (data and data.GetCurrentProfile and data:GetCurrentProfile()) or "?"
    return tostring(profile), tostring(p and p.name or "?")
end

-- Returns the [profile] bucket, or nil when there is nothing stored for it and
-- `create` is false.
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

-- Only ever captures ONCE per window. On the first apply of a session the db
-- still holds the player's values; from then on it holds ours, so re-capturing
-- would snapshot the skin over itself and Uninstall would "restore" our own
-- settings.
--
-- Deliberately covers ONLY what writeSettings actually writes. Restoring a key
-- this skin never touched would hand back a stale value and silently discard
-- whatever the player changed during the skinned session - and now that the
-- snapshot is persisted, "during the skinned session" can stretch across many
-- logins. p.buttons is the concrete case: Skada owns button visibility, we only
-- rely on enabletitle to make Skada draw the header at all.
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
        -- Written out rather than the `cond and v or nil` shorthand: a stored
        -- `false` is a real setting (disablehighlight), and the shorthand would
        -- drop it to nil.
        local saved = snap[key]
        if saved == nil then
            -- A key that was absent before (a table this skin invented, say) is
            -- removed outright rather than left holding a value nobody chose.
            p[key] = nil
        else
            p[key] = copyValue(saved)
        end
    end
    -- Consumed: a later re-apply must snapshot afresh, from whatever the player
    -- has by then, rather than resurrect this capture.
    bucket[name] = nil
    return true
end

-- Drops captures whose window no longer exists, so a deleted or renamed Skada
-- window cannot leave its snapshot behind forever in the SavedVariables.
-- `liveKeys` is a set of [profile]/windowName pairs of windows still open.
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

-- Writes the keys Skada reads. Called BEFORE mod:ApplySettings, because that
-- function only reads win.db - it never writes it. Colours come from
-- utils/media.lua and are read here, at apply time, so a palette change is not
-- baked in at file load.
local function writeSettings(win)
    local p = win.db
    if type(p) ~= "table" then return false end
    snapshotDb(p)

    local accent = media:GetAccentColor()

    -- Rows: our fill, revealed through the atlas crop installed by stampBar.
    p.bartexture = MEDIA_FILL

    -- Skada's own stretched ground and Armory header art are switched fully
    -- transparent rather than replaced: both are a single stretched texture, so
    -- there is no region to point them at. decorateWindow draws ours over them.
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

    -- The icon pipeline stays ON: bar_seticon keeps computing class/spec/role
    -- icons, and Skada's own reserved strip keeps them flush against the window
    -- edge with the bar starting after them. This skin never touches showIcon:
    -- the group uses it to offset the bars and the bar uses it to size the fill,
    -- and clearing only one of the two pushes the bars past the right edge.
    p.classicons = true
    p.spexicons = true
    p.roleicons = true

    -- Skada's sparkline sprite and hover highlight have no place in the
    p.spark = false
    p.disablehighlight = true

    -- The header stays on, which is what makes Skada call g:ShowAnchor() and
    -- the g:ShowButton(...) block at all (Bar.lua:1104). Which anchor buttons
    -- appear is left to Skada's own defaults (menu/reset/report/mode/segment
    -- on, phase/split/stop off) and to whatever the player configures, so this
    -- skin never writes p.buttons.
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

-- Background panel opacity, 0..1 (persisted per-skin via Core's option store).
function DS.GetPanelAlpha()
    local v = addon:GetSkinOption("skada", "panelAlpha")
    if type(v) ~= "number" then v = media:GetDefaultPanelAlpha() end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return v
end

function DS.SetPanelAlpha(v)
    v = tonumber(v) or media:GetDefaultPanelAlpha()
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    addon:SetSkinOption("skada", "panelAlpha", v)
end

-- Re-tints just the background panel on the open windows (no full re-apply).
function DS.RefreshPanelAlpha()
    local alpha = DS.GetPanelAlpha()
    forEachBarWindow(function(win)
        local panel = win.bargroup and win.bargroup._duiMeterPanel
        if panel then panel:SetVertexColor(1, 1, 1, alpha) end
    end)
end

-- Writes our settings into a window and then runs Skada's own ApplySettings,
-- so it reads them. Also stamps the rows afterwards.
function DS.ApplyToWindow(win)
    if type(win) ~= "table" or not win.db or not win.bargroup then return false end
    if win.db.display ~= "bar" then return false end

    writeSettings(win)
    -- Rows are stamped BEFORE Skada applies, not after: SetTextureValue() reads
    -- bar.showIcon when it sizes the fill, so a bar stamped only afterwards
    -- paints its first frame short by the icon width and only corrects itself on
    -- the next update. The icon re-anchor Skada does inside ApplySettings
    -- (SetThickness -> UpdateOrientationLayout) is undone by the after-hook on
    -- ApplySettings, which re-stamps every bar once Skada is done.
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

-- Wraps a method so our work runs with the right ordering around it.
-- `before` runs first (settings Skada is about to read), `after` runs once the
-- original returned (art Skada is not able to draw). Never double-wraps, and
-- the original is captured once so teardown can put it back by identity.
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

    -- The display's ApplySettings is where Skada turns win.db into frames, so
    -- our keys go in before it and our art goes on after it.
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

    -- Update is what creates bars for newly seen modes, so a bar Skada has
    -- just made is stamped as soon as it exists.
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
    -- Decorate existing windows that still wear our skin. Writes nothing.
    --
    -- Nothing to write, in fact: our values went into Skada's AceDB, so they are
    -- already sitting in win.db when this runs. Re-asserting them would be a
    -- no-op at best. What matters is NOT snapshotting here either - by boot time
    -- win.db holds our settings, not the player's, so a capture taken now would
    -- snapshot the skin over itself and Uninstall would later "restore" our own
    -- values while believing it was giving the player's back.
    --
    -- This is also why Skada has no equivalent of the Details reload bug: there,
    -- ChangeSkin rewrote the live instance on every login and destroyed the
    -- player's config. Here the config IS the persisted table, so there is
    -- nothing separate to clobber and nothing separate to re-adopt from.
    forEachBarWindow(function(win)
        if win and win.db and win.db.display == "bar" then
            -- Only stamp bars and decorate; do NOT writeSettings or snapshotDb.
            stampBars(win)
            decorateWindow(win)
        end
    end)
    return true
end

-- Registers the media entry and the hooks. Deliberately does NOT force a
-- re-apply: Skada may be part way through its own ApplySettings while it
-- restores windows, and re-entering it from here is how skins corrupt db.
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

-- Hands Skada back its own look: our settings are dropped, our art removed, our
-- fill crop and icon hooks unhooked, our panel and header hidden, and the
-- window repainted from the player's own profile.
function DS.Uninstall()
    addon:SetSkinEnabled("skada", false)

    local S = skada()
    if not S then
        removeHooks()
        return
    end

    removeHooks()

    -- Collected across every Skada window, not just the bar ones: a window whose
    -- display is not "bar" never got our art, but it can still hold a snapshot
    -- from when it did, and pruning must not mistake it for a deleted window.
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
        -- Hand back the values this window had before the skin wrote anything,
        -- not Skada's stock defaults: a configured profile is the player's, and
        -- resetting it to defaults would throw that away.
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


-- Core.lua owns the ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD wiring
-- for every skin, so this file needs no boot frame of its own.
--
-- The display strings are FUNCTIONS on purpose. This registration runs at file
-- load, before OnInitialize() re-points the addon.L proxy at the player's
-- active locale; a plain L["..."] evaluated here would be captured in the
-- load-time language and the Options tab would keep showing English.
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
        C:AddSlider(section, {
            label = L["Background Opacity"] or "Background Opacity",
            desc = L["Opacity of the Skada meter background texture."] or
                   "Opacity of the Skada meter background texture.",
            min = 0, max = 1, step = 0.05, isPercent = true,
            disabled = not available,
            getFunc = function()
                return DS.GetPanelAlpha()
            end,
            setFunc = function(val)
                DS.SetPanelAlpha(val)
                if DS.RefreshPanelAlpha then DS.RefreshPanelAlpha() end
            end,
        })
    end,
})
