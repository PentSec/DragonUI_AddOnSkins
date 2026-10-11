-- DragonUI_AddOnSkins — BigWigs skin.
-- Hooks LibCandyBar-3.0's shared bar prototype and restyles BigWigs bars only,
-- told apart by the "bigwigs:anchor" tag. No BigWigs code is copied.

local ADDON_NAME, addon = ...
local L = addon.L

local DS = {}
addon.BigWigsSkinAddon = DS

local SKIN_KEY = "bigwigs"

-- Shared helpers (utils/decorate.lua): the meter bar fill/edge, the rim border
-- and the anchor snapshot used by the Thin layout.
local deco = addon.deco

-- BigWigs' shipped statusbar art, used when the live texture was not captured.
local FALLBACK_TEXTURE = "Interface\\AddOns\\BigWigs\\Textures\\default"

-- Height of the thin bar strip, in px, laid under the name/value row.
local THIN_STRIP = 6

-- Whether the skin is on; the prototype hook stays installed forever.
local active = false

-- Guard so repeated installs never stack the prototype hook.
local hookedPrototype = false

-- StatusBars WE painted (weak keys, session-local).
local stamped = setmetatable({}, { __mode = "k" })

-- Our fill is the shared meter region; BigWigs keeps choosing the bar colour.
local FILL_SHEET = deco.METER_SHEET
local FILL_KEY = string.lower(FILL_SHEET)

local function isOurFill(tex)
    if not tex or type(tex.GetTexture) ~= "function" then return false end
    local path = tex:GetTexture()
    return type(path) == "string" and string.lower(path) == FILL_KEY
end


-- ============================================================================
-- THIN LAYOUT
-- ============================================================================

-- Restores the pre-Thin anchors and height on one bar.
local function restoreThin(bar)
    local statusBar = bar and bar.candyBarBar
    local saved = statusBar and statusBar._duiBigWigsThin
    if not saved then return end
    deco.restorePoints(statusBar, saved.statusBar)
    if bar.candyBarLabel then deco.restorePoints(bar.candyBarLabel, saved.label) end
    if bar.candyBarDuration then deco.restorePoints(bar.candyBarDuration, saved.duration) end
    if saved.height then bar:SetHeight(saved.height) end
    statusBar._duiBigWigsThin = nil
end

-- Thin: the name and the time move to a top row and the bar keeps a slim strip
-- under them. BigWigs bars ship 14px tall, so the frame grows to fit both rows.
local function applyThin(bar)
    local statusBar = bar.candyBarBar
    if deco.getBarBorder(SKIN_KEY) ~= "thin" then
        restoreThin(bar)
        return
    end

    local saved = statusBar._duiBigWigsThin
    if not saved then
        local pts = deco.savePoints(statusBar)
        if not pts then return end
        saved = {
            statusBar = pts,
            label = deco.savePoints(bar.candyBarLabel),
            duration = deco.savePoints(bar.candyBarDuration),
            height = bar:GetHeight() or 14,
            rowH = deco.fontRowHeight(bar.candyBarLabel, 12) + 2,
        }
        statusBar._duiBigWigsThin = saved
    end

    local rowH = saved.rowH
    bar:SetHeight(rowH + THIN_STRIP)

    -- The icon stays pinned to the left, so the row and strip clear it.
    local icon = bar.candyBarIconFrame
    local iconShown = icon and icon:IsShown() and icon:GetTexture()
    local inset = iconShown and (bar.height or 14) or 0

    if bar.candyBarLabel then
        bar.candyBarLabel:ClearAllPoints()
        bar.candyBarLabel:SetPoint("TOPLEFT", bar, "TOPLEFT", inset + 3, 0)
    end
    if bar.candyBarDuration then
        bar.candyBarDuration:ClearAllPoints()
        bar.candyBarDuration:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -3, 0)
    end
    statusBar:ClearAllPoints()
    statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", inset, -rowH)
    statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
end


-- ============================================================================
-- BAR STYLING
-- ============================================================================

-- Paints the flat fill, the rim and the layout on one bigwigs bar.
local function styleBar(bar)
    local statusBar = bar.candyBarBar
    if not (statusBar and statusBar.SetStatusBarTexture) then return false end

    -- Remember BigWigs' own texture before the shared fill replaces it.
    local fill = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
    local path = fill and fill.GetTexture and fill:GetTexture()
    if type(path) == "string" and not isOurFill(fill) then
        statusBar._duiBigWigsStock = path
    end

    deco.meterBar(statusBar)
    deco.meterBarBorder(statusBar, deco.getBarBorder(SKIN_KEY) == "borderer")

    -- The flat look drops BigWigs' grey track behind the fill.
    if bar.candyBarBackground then bar.candyBarBackground:Hide() end

    -- 3.3.5 resets the fill TexCoord on value change and on show; re-apply.
    if not statusBar._duiBigWigsRestamp then
        statusBar._duiBigWigsRestamp = true
        statusBar:HookScript("OnValueChanged", function(self)
            if self._duiBigWigsPainted then deco.meterBarRefreshFill(self) end
        end)
        statusBar:HookScript("OnShow", function(self)
            if self._duiBigWigsPainted then deco.meterBarRefreshFill(self) end
        end)
    end
    statusBar._duiBigWigsPainted = true

    applyThin(bar)
    stamped[statusBar] = true
    return true
end

-- True only for a BigWigs bar: other adds share the same bar prototype, and
-- reading bar.data directly avoids the prototype Get on a bar that never Set.
local function styleBigWigsBar(bar)
    if not bar then return false end
    local data = bar.data
    if type(data) ~= "table" or not data["bigwigs:anchor"] then return false end
    return styleBar(bar)
end

local function onBarStart(bar)
    if active then styleBigWigsBar(bar) end
end

-- Hands one bar back to BigWigs: track, layout, border and fill texture.
local function unstamp(statusBar)
    stamped[statusBar] = nil
    if not statusBar then return end

    statusBar._duiBigWigsPainted = nil
    local bar = statusBar.GetParent and statusBar:GetParent()
    if bar then
        restoreThin(bar)
        if bar.candyBarBackground and bar.candyBarBackground.Show then
            bar.candyBarBackground:Show()
        end
    end

    deco.meterBarUnpaint(statusBar)
    deco.meterBarBorder(statusBar, false)

    local stock = statusBar._duiBigWigsStock
    statusBar._duiBigWigsStock = nil
    if statusBar.SetStatusBarTexture then
        statusBar:SetStatusBarTexture(stock or FALLBACK_TEXTURE)
    end
end

-- BigWigs keeps live bars as KEYS in each anchor's .bars set.
local function forEachBigWigsBar(fn)
    local names = { "BigWigsAnchor", "BigWigsEmphasizeAnchor" }
    for i = 1, #names do
        local anchor = _G[names[i]]
        local bars = anchor and anchor.bars
        if type(bars) == "table" then
            for bar in pairs(bars) do fn(bar) end
        end
    end
end


-- ============================================================================
-- PUBLIC API
-- ============================================================================

function DS.IsLoaded()
    return LibStub ~= nil and LibStub("LibCandyBar-3.0", true) ~= nil
end

-- Installs the shared bar-prototype hook; safe to call repeatedly.
function DS.Install()
    if not LibStub then return false end
    local lib = LibStub("LibCandyBar-3.0", true)
    local proto = lib and lib.barPrototype
    if type(proto) ~= "table" or type(proto.Start) ~= "function" then return false end
    if not hookedPrototype then
        hooksecurefunc(proto, "Start", onBarStart)
        hookedPrototype = true
    end
    return true
end

-- True while some bar still wears our paint; drives boot cleanup.
function DS.IsWorn()
    for statusBar in pairs(stamped) do
        local tex = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
        if isOurFill(tex) then return true end
    end
    return false
end

-- Styles every bar that exists now; true when at least one was painted.
local function styleEverything()
    local changed = false
    DS.Install()
    forEachBigWigsBar(function(bar)
        if styleBigWigsBar(bar) then changed = true end
    end)
    return changed
end

-- The toggle's path: marks on and paints every bar in existence.
function DS.Apply()
    active = true
    DS.Install()
    return styleEverything()
end

-- BOOT ONLY: installs the hook and re-paints; never applies or writes settings.
function DS.Restore()
    DS.Install()
    if addon:GetSkinEnabled(SKIN_KEY) then
        active = true
        styleEverything()
    end
    return true
end

-- Toggle-off path: goes inert, then hands every bar back to BigWigs.
function DS.Uninstall()
    active = false
    local list = {}
    for statusBar in pairs(stamped) do list[#list + 1] = statusBar end
    for i = 1, #list do unstamp(list[i]) end
end

-- Re-applies the border choice and the Thin layout to the live bars.
function DS.RefreshBarBorder()
    if not active then return end
    local border = deco.getBarBorder(SKIN_KEY) == "borderer"
    forEachBigWigsBar(function(bar)
        local statusBar = bar.candyBarBar
        if statusBar then
            deco.meterBarBorder(statusBar, border)
            applyThin(bar)
        end
    end)
end


-- Core installs only enabled skins; this puts the inert hook in at load so the
-- prototype is watched even before the player enables the skin.
local function installHookAtLoad()
    if DS.Install() then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, _, loaded)
        if loaded ~= "BigWigs" then return end
        if DS.Install() then
            self:UnregisterEvent("ADDON_LOADED")
            self:SetScript("OnEvent", nil)
        end
    end)
    watcher:Hide()
end

installHookAtLoad()

addon:RegisterSkin("bigwigs", "BigWigs", {
    install   = DS.Install,
    apply     = DS.Apply,
    restore   = DS.Restore,
    isWorn    = DS.IsWorn,
    uninstall = DS.Uninstall,

    label       = function() return L["BigWigs Skin"] end,
    desc        = function() return L["Flat DragonUI bars for BigWigs timers."] end,
    toggleLabel = function() return L["Enable BigWigs Skin"] end,
    toggleDesc  = function() return L["Enable the DragonUI skin for BigWigs."] end,

    options = function(section, C, available)
        deco.addBarBorderDropdown(section, C, available, {
            skinKey         = "bigwigs",
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
