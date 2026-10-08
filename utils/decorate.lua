-- DragonUI_AddOnSkins - utils/decorate.lua
-- Shared decoration helpers for the meter skins (Details, Skada): setRegion,
-- meter panel, header band and the panelAlpha option.

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

-- Points a texture at a named atlas region (utils/atlas.lua); cropX trims
-- source px from each side. Returns false when the region or the sheet is
-- missing, so callers can fall back to the full sheet.
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

-- Draws (or reuses) the header band on host, hung off anchor's left/right
-- points. Anchor and layer differ per skin (Details: window top/OVERLAY,
-- Skada: title button/ARTWORK); extras around the band stay in the caller.
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
-- opts = { skinKey, label, desc, onChanged }; onChanged re-tints open windows
-- after the value is stored, `available` drives the disabled flag.
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
