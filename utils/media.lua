-- DragonUI_AddOnSkins - utils/media.lua
-- Single source of truth for the colours and alphas a skin paints with.
--
-- Every skin reads its palette from here instead of repeating loose literals
-- like { 1, 0.82, 0, 1 } or { 0.094, 0.094, 0.094 }. That keeps the "DragonUI
-- look" in one place so a future palette change does not have to be chased
-- across every Skins/<Addon>/*.lua file.
--
-- IMPORTANT: DragonUI does NOT expose a `DragonUI.media` table today. Its
-- public colour/asset surface is `_G.DragonUI.config.assets` (fonts + the
-- actionbar icon-frame textures), which is not a general palette. So each
-- getter below first prefers a `_G.DragonUI.media.<field>` value IF DragonUI
-- ever grows one, and otherwise falls back to the values this addon already
-- shipped with. The fallbacks are the current visual source of truth; no new
-- DragonUI API is invented here. DragonUI also exposes no pixel scale and no
-- generic "normal/blank" fill texture, so no getter is offered for those.
--
-- Reviewed against the verified public surface (PLAN.md §11) and deliberately
-- NOT routed through it, because none of it fits a meter palette:
--   * config.assets = { font, normal, highlight } are the action-bar
--     icon-frame FONT + TEXTURES, not colours, and not a meter border/ground.
--   * DragonUI.api.SetAtlasTexture / SafeSetAtlas set a TEXTURE to a named
--     atlas; this module returns colours/alphas, and the Details sheet is cut
--     through AddOnSkins' own atlasinfo (utils/atlas.lua), not DragonUI's.
--   * GetDarkModeTint() returns the dark-mode DARKENING multiplier {r,g,b}
--     (~0.15) meant for SetVertexColor -- applying it here would repaint the
--     meter near-black, i.e. it is not the border/ground colour.

local ADDON_NAME, addon = ...

addon.media = addon.media or {}
local media = addon.media

-- Fallbacks: byte-for-byte the values that used to be hardcoded per skin.
-- Kept as the canonical tables; consumers copy the channels they need into
-- fresh literals rather than mutating these.
local DEFAULTS = {
    border = { 0, 0, 0, 1 },             -- neutral border; DragonUI draws borders from atlases
    backdrop = { 0.094, 0.094, 0.094, 1 }, -- DragonUI dark window ground (24/255)
    accent = { 1, 0.82, 0, 1 },          -- DragonUI gold, used for titles/highlights
    white = { 1, 1, 1, 1 },
    black = { 0, 0, 0 },
    rowStripAlpha = 0.55,                -- alpha of a row's shadow/edge strip
    panelAlpha = 1,                      -- default opacity of an overlay panel
}

-- Returns the upstream DragonUI override for `field`, or nil when DragonUI has
-- no media table / no such field. Never errors if DragonUI is not ready.
local function upstream(field)
    local DUI = _G.DragonUI
    local m = DUI and DUI.media
    return m and m[field]
end

local function upstreamNumber(field, fallback)
    local v = upstream(field)
    return (type(v) == "number") and v or fallback
end

-- Normalized [0,1] border colour, RGBA. Returns a shared table; read only.
function media:GetBorderColor()
    return upstream("bordercolor") or DEFAULTS.border
end

-- Normalized [0,1] window background colour, RGBA. Returns a shared table; read only.
function media:GetBackdropColor()
    return upstream("backdropcolor") or DEFAULTS.backdrop
end

-- Normalized [0,1] DragonUI accent (gold) colour, RGBA. Returns a shared table; read only.
function media:GetAccentColor()
    return upstream("accentcolor") or DEFAULTS.accent
end

-- Normalized [0,1] pure white, RGBA. Returns a shared table; read only.
function media:GetWhite()
    return upstream("white") or DEFAULTS.white
end

-- Normalized [0,1] pure black, RGB. Returns a shared table; read only.
function media:GetBlack()
    return upstream("black") or DEFAULTS.black
end

-- Alpha applied to a row's overlaid shadow/edge strip.
function media:GetRowStripAlpha()
    return upstreamNumber("rowStripAlpha", DEFAULTS.rowStripAlpha)
end

-- Default opacity for a skin's own overlay panel before the user tunes it.
function media:GetDefaultPanelAlpha()
    return upstreamNumber("panelAlpha", DEFAULTS.panelAlpha)
end
