-- DragonUI_AddOnSkins — CompactRaidFrame skin.
-- Scope: only the health FILL, swapped to flat white. Everything else stays stock.
-- Hook point is CompactUnitFrame_UpdateAll: the container keeps its setup functions in
-- a file-local `frameCreationSpecifiers` table and calls its own copies, so only the
-- globally resolved updater sees creation, reconfiguration and profile switches.

local ADDON_NAME, addon = ...
local DUI = _G.DragonUI
local L = addon.L

local DS = {}
addon.CompactRaidFrameSkinAddon = DS

local SKIN_KEY = "compactraidframe"

-- Flat, unlit and shipped with the client: the StatusBar multiplies it by the bar
-- colour, so a solid class-coloured block is the result. A region of the meter
-- atlas would need texcoord cropping that a width-driven bar never exercises.
local FILL_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- Exactly what CompactRaidFrame itself assigns, restored verbatim so that toggling
-- off returns the addon to stock rather than to a guess.
local STOCK_TEXTURE = "Interface\\AddOns\\!!!ClassicAPI\\Texture\\RaidFrame\\Raid-Bar-Hp-Fill"

-- Whether the skin is on. Hooking a global cannot be undone, so the wrapper stays
-- installed forever and `active` is what makes it inert after uninstall.
local active = false

-- Whether the global hook is already in place, so repeated installs never stack
-- wrappers.
local hooked = false

-- [frame] -> the health texture region WE stamped. Weak keys and session-local: a
-- widget's texture is rebuilt from XML every login and nothing is saved to disk.
-- The value is the region rather than a boolean so uninstall can tell our stamp from
-- a region the addon has since rebuilt; stampFrame also compares the live file,
-- because a profile change can put the stock texture back on the same region.
local stamped = setmetatable({}, { __mode = "k" })


-- True once CompactRaidFrame exposes its update entry point. Checked before every
-- hook install, because the target addon may not be loaded yet.
local function updaterExists()
    return type(_G.CompactUnitFrame_UpdateAll) == "function"
end

-- Every frame the hook has ever been handed, weak-keyed like `stamped`. Fed even
-- while the skin is off, because the registry has to be warm before the player
-- reaches the toggle -- the one moment no addon pass can rebuild it.
local seen = setmetatable({}, { __mode = "k" })

-- flowFrames mixes layout sentinels ("linebreak", numeric spacers, "beginatomic"),
-- and indexing a NUMBER raises in Lua 5.1.
local function isFrameLike(v)
    local t = type(v)
    return t == "userdata" or t == "table"
end

-- Calls fn(frame) for every frame this skin can reach: the registry first, then the
-- container's own lists. Those two are only a supplement -- flowFrames is transient
-- view state emptied on every layout, and frameUpdateList is appended to only when a
-- frame is created -- but they still catch frames set up before the hook was live.
-- Overlap is harmless, stamping is idempotent.
local function forEachFrame(fn)
    for frame in pairs(seen) do
        if frame then fn(frame) end
    end

    local container = _G.CompactRaidFrameContainer
    if not container then return end

    local flow = container.flowFrames
    if type(flow) == "table" then
        for i = 1, #flow do
            local frame = flow[i]
            if isFrameLike(frame) then fn(frame) end
        end
    end

    -- frameUpdateList holds every frame ever created, including ones not currently
    -- laid out. Group containers live here and have no healthBar, so every caller
    -- has to check before touching anything.
    local lists = container.frameUpdateList
    if type(lists) == "table" then
        for _, key in ipairs({ "normal", "mini", "group" }) do
            local list = lists[key]
            if type(list) == "table" then
                for _, frame in ipairs(list) do
                    if isFrameLike(frame) then fn(frame) end
                end
            end
        end
    end
end

-- The frame's health bar, its live texture region, or nil when it is not a frame
-- this skin can touch.
local function healthRegion(frame)
    local bar = frame and frame.healthBar
    if not bar or type(bar.GetStatusBarTexture) ~= "function" then return nil end
    local tex = bar:GetStatusBarTexture()
    if not tex then return nil end
    return bar, tex
end

-- Forces the bar to push its colour back onto the texture. Colour lives on the
-- StatusBar, not the region, and the health-colour updater only calls
-- SetStatusBarColor when the colour CHANGED, so a dropped colour would never
-- repaint. Guarded on r because the getters are optional and
-- SetStatusBarColor(nil, ...) is worse than doing nothing.
local function refreshColor(bar)
    if type(bar.GetStatusBarColor) ~= "function" then return end
    local r, g, b, a = bar:GetStatusBarColor()
    if r and type(bar.SetStatusBarColor) == "function" then
        bar:SetStatusBarColor(r, g, b, a)
    end
end

-- Puts the flat fill on one frame's health bar. Returns true only when it actually
-- changed something, so callers can stay cheap on every update tick.
local function stampFrame(frame)
    local bar, tex = healthRegion(frame)
    if not bar then return false end
    -- Region AND file must both match: a profile change can put the stock texture
    -- back on the very region we stamped, and that frame needs stamping again.
    if stamped[frame] == tex and tex:GetTexture() == FILL_TEXTURE then return false end
    tex:SetTexture(FILL_TEXTURE)
    tex:SetTexCoord(0, 1, 0, 1)
    stamped[frame] = tex
    refreshColor(bar)
    return true
end

-- Hands one frame's health bar back to CompactRaidFrame's own texture. Only acts
-- when the live region is the one WE stamped; a replaced region is already stock and
-- must not be written to.
local function unstampFrame(frame)
    local tex = stamped[frame]
    stamped[frame] = nil
    if not tex then return false end
    local bar, live = healthRegion(frame)
    if not bar or live ~= tex then return false end
    tex:SetTexture(STOCK_TEXTURE)
    tex:SetTexCoord(0, 1, 0, 1)
    refreshColor(bar)
    return true
end

-- Post-hook: runs after every frame setup, reconfiguration and profile apply. Records
-- the frame BEFORE the active check, so that registry write is the only work an
-- inactive skin does and the toggle can still enumerate real frames.
local function onUpdateAll(frame)
    if not frame then return end
    seen[frame] = true
    if not active then return end
    stampFrame(frame)
end


-- ============================================================================
-- PUBLIC API
-- ============================================================================

function DS.IsLoaded()
    return updaterExists()
end

-- True when some frame still wears the flat fill. Drives the boot-time cleanup in
-- Core, which calls uninstall only when this is true so a disabled skin never writes
-- anything.
function DS.IsWorn()
    for frame, tex in pairs(stamped) do
        local _, live = healthRegion(frame)
        if live == tex and tex:GetTexture() == FILL_TEXTURE then return true end
    end
    return false
end

-- Hooks CompactUnitFrame_UpdateAll, once. `force` is accepted for interface parity
-- with the other skins and ignored: the hook is idempotent.
function DS.Install(force)
    if not updaterExists() then return false end
    if not hooked then
        hooksecurefunc("CompactUnitFrame_UpdateAll", onUpdateAll)
        hooked = true
    end
    return true
end

-- Puts the hook in at LOAD rather than at toggle time. Core only calls InstallSkin
-- when the skin is ENABLED, so a skin that ships off has neither hook nor registry
-- until something installs it -- which is too late, because the toggle is the one
-- moment no addon pass can rebuild the registry. The watcher below goes in while the
-- skin is still off, inert behind the `active` guard, and touches no setting.
local function installHookAtLoad()
    if DS.Install(false) then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, _, loaded)
        if loaded ~= "CompactRaidFrame" then return end
        if DS.Install(false) then
            self:UnregisterEvent("ADDON_LOADED")
            self:SetScript("OnEvent", nil)
        end
    end)
    watcher:Hide()
end

-- Pushes every live frame back through the addon's own updater, so an already-drawn
-- bar repaints now instead of on the next stray health tick. Group containers have no
-- unitExists and UpdateAll on one would raise inside the addon, so they are skipped;
-- pcall keeps a cosmetic nudge from ever breaking the toggle that triggered it.
local function repaintFrames()
    local updateAll = _G.CompactUnitFrame_UpdateAll
    if type(updateAll) ~= "function" then return 0 end
    local nudged = 0
    forEachFrame(function(frame)
        if frame.unitExists then
            pcall(updateAll, frame)
            nudged = nudged + 1
        end
    end)
    return nudged
end

-- The toggle's path. Marks the skin on, stamps every frame in existence and forces a
-- repaint. Does NOT call addon:SetSkinEnabled: the Options toggle already wrote the
-- flag before Core routed it here.
function DS.Apply()
    active = true
    DS.Install(false)
    local applied = 0
    forEachFrame(function(frame)
        if stampFrame(frame) then applied = applied + 1 end
    end)
    local nudged = repaintFrames()
    return applied > 0 or nudged > 0
end

-- BOOT ONLY. Installs the hook and re-stamps whatever already exists; never calls
-- Apply and never writes a player setting. No frame carries our texture across a
-- login, so there is nothing to restore.
function DS.Restore()
    if not updaterExists() then return false end
    DS.Install(false)
    if addon:GetSkinEnabled(SKIN_KEY) then
        active = true
        forEachFrame(function(frame)
            stampFrame(frame)
        end)
    end
    return true
end

-- The toggle's off path. Goes inert first, then gives the stock texture back; the
-- hook stays installed and does nothing from here on. Frames are collected up front
-- because unstampFrame clears entries as it goes.
function DS.Uninstall()
    active = false
    local frames = {}
    for frame in pairs(stamped) do
        frames[#frames + 1] = frame
    end
    for i = 1, #frames do
        unstampFrame(frames[i])
    end
end


SLASH_DUICRF1 = "/duicrf"
SlashCmdList["DUICRF"] = function(msg)
    if type(msg) == "string" and msg:lower():find("status") then
        DUI:Print("|cff1784d1DragonUI|r CompactRaidFrame status: toggle=" ..
            tostring(addon:GetSkinEnabled(SKIN_KEY)) ..
            " hook=" .. tostring(hooked) ..
            " active=" .. tostring(active) ..
            " worn=" .. tostring(DS.IsWorn()))
        -- Reports every enumeration source separately, because an empty one is the
        -- only evidence of where a frame is coming from.
        local registry = 0
        for _ in pairs(seen) do registry = registry + 1 end
        DUI:Print("  hook registry (authoritative): " .. registry .. " frame(s)")

        local container = _G.CompactRaidFrameContainer
        if not container then
            DUI:Print("  container: _G.CompactRaidFrameContainer is nil")
        else
            local flow = container.flowFrames
            local real = 0
            if type(flow) == "table" then
                for i = 1, #flow do if isFrameLike(flow[i]) then real = real + 1 end end
            end
            DUI:Print("  flowFrames: " .. real .. " frame(s)")
            local lists = container.frameUpdateList
            if type(lists) == "table" then
                for _, key in ipairs({ "normal", "mini", "group" }) do
                    DUI:Print("  " .. key .. ": " .. tostring(#(lists[key] or {})) .. " frame(s)")
                end
            else
                DUI:Print("  frameUpdateList: " .. tostring(type(lists)))
            end
        end
        return
    end
    if not DS.IsLoaded() then
        DUI:Print("|cff1784d1DragonUI|r: " .. (L["CompactRaidFrame is not installed."] or "CompactRaidFrame is not installed."))
        return
    end
    if DS.Apply() then
        DUI:Print("|cff1784d1DragonUI|r: " .. (L["CompactRaidFrame skin applied."] or "CompactRaidFrame skin applied."))
    else
        DUI:Print("|cff1784d1DragonUI|r: " .. (L["Could not apply the skin - CompactRaidFrame is not ready yet."] or
            "Could not apply the skin - CompactRaidFrame is not ready yet."))
    end
end


-- Core.lua owns the ADDON_LOADED / PLAYER_LOGIN wiring for every skin; the only
-- exception is the hook watcher above, which exists because Core does not install a
-- disabled skin. The display strings below are FUNCTIONS on purpose: this runs at file
-- load, before OnInitialize() re-points addon.L at the player's locale, so an
-- L["..."] evaluated here would freeze the load-time language.
installHookAtLoad()

addon:RegisterSkin("compactraidframe", "CompactRaidFrame", {
    install   = DS.Install,
    apply     = DS.Apply,
    restore   = DS.Restore,
    isWorn    = DS.IsWorn,
    uninstall = DS.Uninstall,

    label       = function() return L["CompactRaidFrame Skin"] end,
    desc        = function() return L["Flat, solid health-bar fill for the compact frames."] end,
    toggleLabel = function() return L["Enable CompactRaidFrame Skin"] end,
    toggleDesc  = function() return L["Enable the DragonUI skin for CompactRaidFrame."] end,
})
