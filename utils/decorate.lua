-- DragonUI_AddOnSkins - utils/decorate.lua
-- Shared decoration helpers for the meter skins (Details, Skada, DBM): setRegion,
-- meter panel, header band, panelAlpha option and the bar border (rim) option.

local ADDON_NAME, addon = ...
local media = addon.media   -- utils/media.lua

local deco = {}
addon.deco = deco

-- Sheet every meter region is cut from; skins read it back via METER_SHEET.
local SHEET = addon._dir .. [[Details\uidamagemeters.blp]]
local ATLAS_PANEL = "damagemeters-background"
local ATLAS_HEADER = "ui-damagemeters-header-bar"

-- Shared geometry in source px: panel feather trim, band height, overhang.
local PANEL_CROP_PX = 3
local HEADER_H = 28
local HEADER_OVERHANG = 4

deco.METER_SHEET = SHEET


-- ============================================================================
-- ATLAS
-- ============================================================================

-- Points a texture at a named atlas region; cropX trims px from each side.
-- Returns false when the region or sheet is missing.
function deco.setRegion(tex, name, cropX)
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


-- ============================================================================
-- PER-WINDOW DECORATION
-- ============================================================================

-- Draws (or reuses) the background panel on host at alpha, edge to edge.
-- Returns the texture, or nil when the host cannot hold one.
function deco.meterPanel(host, alpha)
    if not (host and host.CreateTexture) then return nil end

    local panel = host._duiMeterPanel
    if not panel then
        panel = host:CreateTexture(nil, "BACKGROUND")
        host._duiMeterPanel = panel
    end
    if not deco.setRegion(panel, ATLAS_PANEL, PANEL_CROP_PX) then
        panel:SetTexture(SHEET)
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", host, "TOPLEFT")
    panel:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT")
    panel:SetVertexColor(1, 1, 1, alpha)
    panel:Show()
    return panel
end

-- Draws (or reuses) the header band on host, hung off an anchor's sides.
function deco.meterHeader(host, anchor, leftPoint, rightPoint, layer)
    if not (host and host.CreateTexture and anchor) then return nil end

    local hdr = host._duiMeterHeader
    if not hdr then
        hdr = host:CreateTexture(nil, layer or "ARTWORK")
        host._duiMeterHeader = hdr
    end
    if not deco.setRegion(hdr, ATLAS_HEADER) then
        hdr:SetTexture(SHEET)
    end
    hdr:ClearAllPoints()
    hdr:SetPoint("BOTTOMLEFT", anchor, leftPoint, -HEADER_OVERHANG, 0)
    hdr:SetPoint("BOTTOMRIGHT", anchor, rightPoint, HEADER_OVERHANG, 0)
    hdr:SetHeight(HEADER_H)
    hdr:Show()
    return hdr
end


-- ============================================================================
-- SHARED BAR (meter rows + DBM bars)
-- ============================================================================

-- Fill and hairline edge shared with the meter rows.
local ATLAS_BAR_FILL = "ui-hud-cooldownmanager-bar"
local ATLAS_BAR_EDGE = "ui-damagemeters-bar-shadowedge"

-- Paints the shared bar look on a StatusBar: atlas fill plus edge strip.
function deco.meterBar(bar)
    if not (bar and bar.CreateTexture and bar.GetStatusBarTexture) then return false end
    local fill = bar:GetStatusBarTexture()
    if not (fill and fill.SetTexture) then return false end
    if not deco.setRegion(fill, ATLAS_BAR_FILL) then return false end

    local edge = bar._duiMeterEdge
    if not edge then
        edge = bar:CreateTexture(nil, "OVERLAY")
        bar._duiMeterEdge = edge
    end
    if deco.setRegion(edge, ATLAS_BAR_EDGE) then
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", bar, "TOPLEFT")
        edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
        edge:SetVertexColor(1, 1, 1, 1)
        edge:Show()
    end
    return true
end

-- Re-crops the fill after a value change.
function deco.meterBarRefreshFill(bar)
    if not (bar and bar.GetStatusBarTexture) then return end
    deco.setRegion(bar:GetStatusBarTexture(), ATLAS_BAR_FILL)
end

-- Hides the edge strip; the caller hands the fill back to its addon.
function deco.meterBarUnpaint(bar)
    if bar and bar._duiMeterEdge then bar._duiMeterEdge:Hide() end
end


-- ============================================================================
-- BAR BORDER (DragonUI rim)
-- ============================================================================

-- The rim PersonalResource wears around its bar, from the central registry.
-- Geometry mirrors modules/personalresource.lua; the frame overhangs 1/2/4/5.
local RIM_SHEET = addon:GetDuiTexture("rim")
local RIM_SHEET_W, RIM_SHEET_H = 512, 64
local RIM_SLICE_X = { 0, 242, 244, 264 }
local RIM_SLICE_Y = { 0, 14, 16, 38 }
local RIM_LEFT = RIM_SLICE_X[2] / 2
local RIM_RIGHT = (RIM_SLICE_X[4] - RIM_SLICE_X[3]) / 2
local RIM_TOP = RIM_SLICE_Y[2] / 2
local RIM_BOTTOM = (RIM_SLICE_Y[4] - RIM_SLICE_Y[3]) / 2
local RIM_OVER_L, RIM_OVER_T, RIM_OVER_R, RIM_OVER_B = 1, 2, 4, 5

-- Texel range for a slice; the middle strip samples half texels.
local function rimSlice(edges, index)
    local from, to = edges[index], edges[index + 1]
    if index == 2 then return from + 0.5, to - 0.5 end
    return from, to
end

-- Stretches a strip between two corners, replacing any previous anchors.
local function rimBetween(tex, from, fromPoint, to, toPoint)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", from, fromPoint, 0, 0)
    tex:SetPoint("BOTTOMRIGHT", to, toPoint, 0, 0)
end

-- Draws (or reuses) the eight rim pieces around bar. Idempotent; enabled=false
-- hides the border without creating it.
function deco.meterBarBorder(bar, enabled)
    if not (bar and bar.CreateTexture) then return false end
    if not RIM_SHEET then return false end

    local rim = bar._duiRim
    if not rim then
        if not enabled then return false end
        rim = {}
        bar._duiRim = rim
        for row = 1, 3 do
            rim[row] = {}
            for col = 1, 3 do
                if not (row == 2 and col == 2) then
                    local tex = bar:CreateTexture(nil, "OVERLAY")
                    tex:SetTexture(RIM_SHEET)
                    local left, right = rimSlice(RIM_SLICE_X, col)
                    local top, bottom = rimSlice(RIM_SLICE_Y, row)
                    tex:SetTexCoord(left / RIM_SHEET_W, right / RIM_SHEET_W,
                                    top / RIM_SHEET_H, bottom / RIM_SHEET_H)
                    rim[row][col] = tex
                end
            end
        end
    end

    if not enabled then
        for row = 1, 3 do
            for col = 1, 3 do
                local tex = rim[row][col]
                if tex then tex:Hide() end
            end
        end
        return true
    end

    local tl, tr, bl, br = rim[1][1], rim[1][3], rim[3][1], rim[3][3]
    tl:ClearAllPoints()
    tl:SetPoint("TOPLEFT", bar, "TOPLEFT", -RIM_OVER_L, RIM_OVER_T)
    tr:ClearAllPoints()
    tr:SetPoint("TOPRIGHT", bar, "TOPRIGHT", RIM_OVER_R, RIM_OVER_T)
    bl:ClearAllPoints()
    bl:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -RIM_OVER_L, -RIM_OVER_B)
    br:ClearAllPoints()
    br:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", RIM_OVER_R, -RIM_OVER_B)

    rimBetween(rim[1][2], tl, "TOPRIGHT", tr, "BOTTOMLEFT")
    rimBetween(rim[3][2], bl, "TOPRIGHT", br, "BOTTOMLEFT")
    rimBetween(rim[2][1], tl, "BOTTOMLEFT", bl, "TOPRIGHT")
    rimBetween(rim[2][3], tr, "BOTTOMLEFT", br, "TOPRIGHT")

    -- Corner size; side slices shrink on narrow bars.
    local width = bar:GetWidth() or 0
    local shrink = width > 0 and min(1, width / (RIM_LEFT + RIM_RIGHT)) or 1
    tl:SetSize(RIM_LEFT * shrink, RIM_TOP)
    tr:SetSize(RIM_RIGHT * shrink, RIM_TOP)
    bl:SetSize(RIM_LEFT * shrink, RIM_BOTTOM)
    br:SetSize(RIM_RIGHT * shrink, RIM_BOTTOM)

    for row = 1, 3 do
        for col = 1, 3 do
            local tex = rim[row][col]
            if tex then tex:Show() end
        end
    end
    return true
end


-- ============================================================================
-- PANEL ALPHA OPTION
-- ============================================================================

-- Stored panel opacity for skinKey, clamped to [0,1]; default from the palette.
function deco.getPanelAlpha(skinKey)
    local v = addon:GetSkinOption(skinKey, "panelAlpha")
    if type(v) ~= "number" then v = media:GetDefaultPanelAlpha() end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return v
end

function deco.setPanelAlpha(skinKey, v)
    v = tonumber(v) or media:GetDefaultPanelAlpha()
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    addon:SetSkinOption(skinKey, "panelAlpha", v)
end

-- Shared "Background Opacity" slider for the Options tab.
-- opts: { skinKey, label, desc, onChanged }; `available` drives the disabled flag.
function deco.addPanelAlphaSlider(section, C, available, opts)
    if not (section and C and C.AddSlider and opts and opts.skinKey) then return end
    C:AddSlider(section, {
        label = opts.label,
        desc = opts.desc,
        min = 0, max = 1, step = 0.05, isPercent = true,
        disabled = not available,
        getFunc = function()
            return deco.getPanelAlpha(opts.skinKey)
        end,
        setFunc = function(val)
            deco.setPanelAlpha(opts.skinKey, val)
            if opts.onChanged then opts.onChanged(val) end
        end,
    })
end


-- ============================================================================
-- BAR BORDER OPTION
-- ============================================================================

-- Stored bar border choice for skinKey: "borderless" (default), "borderer", or
-- "thin" (a thin bar with the name and value on a row above it).
function deco.getBarBorder(skinKey)
    local v = addon:GetSkinOption(skinKey, "barBorder")
    if v ~= "borderer" and v ~= "thin" then v = "borderless" end
    return v
end

function deco.setBarBorder(skinKey, v)
    if v ~= "borderer" and v ~= "thin" then v = "borderless" end
    addon:SetSkinOption(skinKey, "barBorder", v)
end

-- Shared "Bar Border" dropdown: borderless (default), borderer or thin.
-- opts: { skinKey, label, desc, borderlessLabel, bordererLabel, thinLabel, onChanged };
-- `available` drives the disabled flag.
function deco.addBarBorderDropdown(section, C, available, opts)
    if not (section and C and C.AddDropdown and opts and opts.skinKey) then return end
    C:AddDropdown(section, {
        label = opts.label,
        desc  = opts.desc,
        values = {
            ["borderless"] = opts.borderlessLabel or "Borderless",
            ["borderer"]   = opts.bordererLabel or "Borderer",
            ["thin"]       = opts.thinLabel or "Thin",
        },
        disabled = not available,
        getFunc = function()
            return deco.getBarBorder(opts.skinKey)
        end,
        setFunc = function(v)
            deco.setBarBorder(opts.skinKey, v)
            if opts.onChanged then opts.onChanged(v) end
        end,
    })
end


-- ============================================================================
-- ANCHOR SNAPSHOT (used by the Thin bar layout)
-- ============================================================================

-- Snapshot of a region's anchors, for the Full <-> Thin layout swap.
-- Each point is stored field by field: a raw GetPoint tuple drops trailing
-- offsets when relativeTo is nil. Returns nil when there is no anchor to take
-- (a bare SetAllPoints reports none), so restore never blanks the region.
function deco.savePoints(region)
    if not (region and region.GetNumPoints) then return nil end
    local n = region:GetNumPoints()
    if not n or n == 0 then return nil end
    local pts = {}
    for i = 1, n do
        local point, rel, relPoint, x, y = region:GetPoint(i)
        pts[i] = { point, rel, relPoint, x or 0, y or 0 }
    end
    return pts
end

-- Re-applies anchors captured by savePoints.
function deco.restorePoints(region, pts)
    if not (region and pts) then return false end
    region:ClearAllPoints()
    for i = 1, #pts do
        local p = pts[i]
        if p[2] then
            region:SetPoint(p[1], p[2], p[3], p[4], p[5])
        else
            region:SetPoint(p[1], p[4], p[5])
        end
    end
    return true
end
