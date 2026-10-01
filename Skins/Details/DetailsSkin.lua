-- DragonUI_AddOnSkins — Details! skin.
--
-- Reskins the Details! damage meter to DragonUI's retail-style look: a gold
-- title header, a near-invisible background panel and class-coloured rows.
-- The skin is registered with Details under the name "DragonUI"; our own


local ADDON_NAME, addon = ...
local DUI = _G.DragonUI
local L = addon.L
local media = addon.media   -- centralized palette (utils/media.lua)

local DS = {}
addon.DetailsSkinAddon = DS

local SKIN_NAME = "DragonUI"

-- Our atlas sheet and the named regions this skin cuts from it.
local SHEET = addon._dir .. [[Details\uidamagemeters.blp]]

local MEDIA_FILL = "DragonUI Meter Fill"
local MEDIA_ROW  = "DragonUI Meter Row"
local MEDIA_EDGE = "DragonUI Meter Row Edge"
local ATLAS_HEADER = "ui-damagemeters-header-bar"
local ATLAS_PANEL  = "damagemeters-background"
local ATLAS_FILL   = "ui-hud-cooldownmanager-bar"
local ATLAS_ROW    = "ui-damagemeters-bar-shadowbg"
local ATLAS_EDGE   = "ui-damagemeters-bar-shadowedge"

-- Geometry shared between the skin table and the manual anchors.
-- Colours, alphas and textures come from utils/media.lua (the single source of
-- truth); read them where used instead of repeating literals here.
local HEADER_H      = 28     -- header band height, px
local BAR_CENTRE_Y  = HEADER_H / 2
local HEADER_OVERHANG = 4    -- header overhangs the window ends by this much
local ROW_INSET_X    = 4
local BALL_INNER_X   = 21
local BALL_R_INNER_X = 32
local ICON_SIZE      = 16
local TITLE_SIZE     = 13
local floor = math.floor

-- damagemeters-background is a soft-edged sprite: its outer ~3px fade from
-- opaque to transparent, which reads as left/right padding once the panel is
-- stretched over a window. Trim that feather off each side (source px).
local PANEL_CROP_PX = 3

-- Outset of our row strips relative to the row's statusbar.
local BAR_INSET_LT, BAR_INSET_T, BAR_INSET_RB, BAR_INSET_B = -2, 2, 2, -2

-- Details' own header pieces, hidden while our skin is on (saved and restored).
local HEADER_PIECES = { "ball", "emenda", "ball_r", "top_bg" }


-- Returns the Details addon table once it is ready, or nil.
local function details()
	local D = _G._detalhes or _G.Details
	if D and type(D.InstallSkin) == "function" and type(D.skins) == "table" then return D end
	return nil
end

-- Calls fn(instance) for every live Details window. No-op if Details is not ready.
local function forEachInstance(D, fn)
	if not D then return end
	local count = (type(D.GetNumInstancesAmount) == "function" and D:GetNumInstancesAmount()) or 0
	for i = 1, count do
		local inst = D.GetInstance and D:GetInstance(i)
		if inst then fn(inst) end
	end
end

-- Calls fn(row) for every row of a window. Returns false when it has no rows yet.
local function forEachRow(inst, fn)
	local rows = inst and inst.barras
	if type(rows) ~= "table" then return false end
	for _, row in ipairs(rows) do
		if row then fn(row) end
	end
	return true
end

-- Points a texture at one of our named atlas regions (utils/atlas.lua). When
-- cropX is given, that many source pixels are trimmed off the left and right.
--
-- Returns false when the region is unknown OR when the sheet behind it did not
-- load. SetTexture() does not error on a bad path -- it just paints nothing --
-- so without the GetTexture() probe a typo in the atlas table would silently
-- draw invisible art instead of falling back to the full sheet.
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

-- Registers the sheet as LibSharedMedia statusbars so Details can reference it
-- by media name. Silently no-ops if LSM is unavailable.
local function registerMedia()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if not (LSM and LSM.Register) then return false end
	pcall(LSM.Register, LSM, "statusbar", MEDIA_FILL, SHEET)
	pcall(LSM.Register, LSM, "statusbar", MEDIA_ROW,  SHEET)
	pcall(LSM.Register, LSM, "statusbar", MEDIA_EDGE, SHEET)
	return true
end

-- Stretches a texture over a row's statusbar with a small outset.
local function anchorToBar(tex, bar)
	if not (tex and bar) then return false end
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", bar, "TOPLEFT", BAR_INSET_LT, BAR_INSET_T)
	tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", BAR_INSET_RB, BAR_INSET_B)
	return true
end

-- Draws (or reuses) one of our overlaid row strips and anchors it to the bar.
local function rowStrip(row, key, layer, region)
	local bar = row.statusbar
	if not bar then return false end
	local tex = row[key]
	if not tex then
		tex = bar:CreateTexture(nil, layer)
		row[key] = tex
	end
	if not setRegion(tex, region) then return false end
	tex:SetVertexColor(1, 1, 1, media:GetRowStripAlpha())
	tex:Show()
	return anchorToBar(tex, bar)
end

-- Hides Details' own header art (remembering what was shown), or puts it back
-- exactly as it was when shown == true.
local function detailsHeaderShown(inst, shown)
	local cab = inst and inst.baseframe and inst.baseframe.cabecalho
	if not cab then return end
	local saved = inst._duiSavedHeader
	if shown then
		if not saved then return end
		for _, key in ipairs(HEADER_PIECES) do
			local piece = cab[key]
			if piece and saved[key] ~= nil then
				if saved[key] then piece:Show() else piece:Hide() end
			end
		end
		inst._duiSavedHeader = nil
	else
		if saved then return end
		saved = {}
		for _, key in ipairs(HEADER_PIECES) do
			local piece = cab[key]
			if piece then
				saved[key] = (piece.IsShown and piece:IsShown()) and true or false
				piece:Hide()
			end
		end
		inst._duiSavedHeader = saved
	end
end

-- Applies the class bar fill and our two overlay strips to every row.
local function stampRows(inst)
	return forEachRow(inst, function(row)
		if row.statusbar then
			rowStrip(row, "_duiBarBG", "BACKGROUND", ATLAS_ROW)
			rowStrip(row, "_duiBarEdge", "OVERLAY", ATLAS_EDGE)
			if row.background then row.background:Hide() end
			if row.overlayTexture then row.overlayTexture:Hide() end
			if row.lineBorder then row.lineBorder:Hide() end
			if row.textura then setRegion(row.textura, ATLAS_FILL) end
		end
	end)
end

-- Undoes stampRows: hides our strips and gives Details' own row art back.
local function resetRows(inst)
	forEachRow(inst, function(row)
		if row.background then row.background:Show() end
		if row.overlayTexture then row.overlayTexture:Show() end
		if row._duiBarBG then row._duiBarBG:Hide() end
		if row._duiBarEdge then row._duiBarEdge:Hide() end
		if row.lineBorder then row.lineBorder:Show() end
	end)
end

-- Removes everything our skin drew on a window and hands its header and rows
-- back to Details. Used when the player picks another skin and on Uninstall.
local function clearDecoration(inst)
	local base = inst and inst.baseframe
	if not base then return end
	if base._duiMeterHeader then base._duiMeterHeader:Hide() end
	if base._duiMeterPanel then base._duiMeterPanel:Hide() end
	detailsHeaderShown(inst, true)
	resetRows(inst)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- True when Details is loaded and ready to accept a skin.
function DS.IsDetailsLoaded()
	return IsAddOnLoaded("Details") and details() ~= nil
end

-- Background panel opacity, 0..1 (persisted per-skin via Core's option store).
function DS.GetPanelAlpha()
	local v = addon:GetSkinOption("details", "panelAlpha")
	if type(v) ~= "number" then v = media:GetDefaultPanelAlpha() end
	if v < 0 then v = 0 elseif v > 1 then v = 1 end
	return v
end

function DS.SetPanelAlpha(v)
	v = tonumber(v) or media:GetDefaultPanelAlpha()
	if v < 0 then v = 0 elseif v > 1 then v = 1 end
	addon:SetSkinOption("details", "panelAlpha", v)
end

-- Re-tints just the background panel on the open windows (no full re-apply).
function DS.RefreshPanelAlpha()
	local alpha = DS.GetPanelAlpha()
	forEachInstance(details(), function(inst)
		local panel = inst.baseframe and inst.baseframe._duiMeterPanel
		if panel then panel:SetVertexColor(1, 1, 1, alpha) end
	end)
end

-- Draws our background panel, header band and row art on one window.
function DS.DecorateWindow(inst)
	local base = inst and inst.baseframe
	if not (base and base.CreateTexture) then return end

	local panel = base._duiMeterPanel
	if not panel then
		panel = base:CreateTexture(nil, "BACKGROUND")
		base._duiMeterPanel = panel
	end
	if not setRegion(panel, ATLAS_PANEL, PANEL_CROP_PX) then
		panel:SetTexture(SHEET)
	end
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", base, "TOPLEFT")
	panel:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT")
	panel:SetVertexColor(1, 1, 1, DS.GetPanelAlpha())
	panel:Show()

	local hdr = base._duiMeterHeader
	if not hdr then
		hdr = base:CreateTexture(nil, "OVERLAY")
		base._duiMeterHeader = hdr
	end
	if not setRegion(hdr, ATLAS_HEADER) then
		hdr:SetTexture(SHEET)
	end
	hdr:ClearAllPoints()
	hdr:SetPoint("BOTTOMLEFT",  base, "TOPLEFT",  -HEADER_OVERHANG, 0)
	hdr:SetPoint("BOTTOMRIGHT", base, "TOPRIGHT", HEADER_OVERHANG, 0)
	hdr:SetHeight(HEADER_H)
	hdr:Show()
	detailsHeaderShown(inst, false)
	stampRows(inst)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

-- Wraps Details' ChangeSkin. Keeps our decoration in sync while a window wears
-- our skin, and turns the addon toggle OFF when the player picks another skin.
-- It never turns the toggle ON (that is what made a disabled skin come back).
local function hookChangeSkin(D)
	if DS._ourChangeSkin or type(D.ChangeSkin) ~= "function" then return end
	local orig = D.ChangeSkin
	DS._origChangeSkin = orig
	DS._ourChangeSkin = function(self, skinName, ...)
		local asked = skinName or (type(self) == "table" and self.skin) or nil
		local installed = (D.skins and D.skins[SKIN_NAME] ~= nil) and true or false
		local a, b, c = orig(self, skinName, ...)
		if type(self) ~= "table" then return a, b, c end

		if self.skin == SKIN_NAME then
			if installed then DS.DecorateWindow(self) end
		else
			clearDecoration(self)
			if installed and asked ~= SKIN_NAME then
				addon:SetSkinEnabled("details", false)
				if DUI and DUI.After then DUI:After(0, DS.Uninstall) end
			end
		end
		return a, b, c
	end
	D.ChangeSkin = DS._ourChangeSkin
end

-- Restores Details' original ChangeSkin.
local function unhookChangeSkin(D)
	if not DS._ourChangeSkin then return end
	if D and D.ChangeSkin == DS._ourChangeSkin then
		D.ChangeSkin = DS._origChangeSkin
	end
	DS._ourChangeSkin, DS._origChangeSkin = nil, nil
end

-- The skin definition handed to Details' InstallSkin.
local function skinTable()
	-- Palette read once per install from the shared media source.
	local accent   = media:GetAccentColor()
	local white    = media:GetWhite()
	local black    = media:GetBlack()
	local backdrop = media:GetBackdropColor()

	return {
		file    = [[Interface\AddOns\Details\images\skins\flat_skin.blp]],
		author  = "DragonUI",
		version = "1.0",
		site    = "https://github.com/PentSec/DragonUI_AddOnSkins",
		desc    = "DragonUI — retail damage-meter look, with art from retail's",

		micro_frames = { color = { white[1], white[2], white[3], white[4] }, font = "Arial Narrow", size = 10, textymod = 1 },
		can_change_alpha_head = true,
		icon_anchor_main    = { -1, -5 },
		icon_anchor_plugins = { -7, -13 },
		icon_plugins_size   = { 19, 18 },
		icon_point_anchor        = { -37, 0 },
		left_corner_anchor       = { -107, 0 },
		right_corner_anchor      = { 96, 0 },
		icon_point_anchor_bottom  = { -37, 12 },
		left_corner_anchor_bottom = { -107, 0 },
		right_corner_anchor_bottom = { 96, 0 },
		icon_on_top      = true,
		icon_ignore_alpha = true,
		icon_titletext_position = { 3, 3 },

		instance_cprops = {
			color = { backdrop[1], backdrop[2], backdrop[3], 0 },
			bg_r = backdrop[1], bg_g = backdrop[2], bg_b = backdrop[3], bg_alpha = 0,
			backdrop_texture = "Details Ground",
			show_statusbar = false,
			statusbar_info = { alpha = 0, overlay = { backdrop[1], backdrop[2], backdrop[3] } },
			show_sidebars = false,
			wallpaper = { enabled = false },
			hide_icon = true,

			toolbar_side = 1,
			menu_anchor = { BALL_R_INNER_X - ICON_SIZE - ROW_INSET_X, floor(BAR_CENTRE_Y - ICON_SIZE / 2),
			                side = 2 },
			plugins_grow_direction = 1,
			instance_button_anchor = { -27, 1 },
			menu_icons_size = 1.0,
			desaturated_menu = false,
			color_buttons = { white[1], white[2], white[3], white[4] },
			attribute_text = {
				enabled = true, side = 1, shadow = true,
				show_timer = { true, true, true },
				text_size = TITLE_SIZE, text_face = "Friz Quadrata TT",
				text_color = { accent[1], accent[2], accent[3], accent[4] },
				custom_text = "{name}", enable_custom_text = false,
				anchor = { ROW_INSET_X - BALL_INNER_X, floor(BAR_CENTRE_Y - TITLE_SIZE / 2) },
			},

			row_info = {
				texture      = MEDIA_FILL,
				texture_file = SHEET,
				texture_class_colors = true,
				texture_background      = MEDIA_ROW,
				texture_background_file = SHEET,
				texture_background_class_color = false,
				fixed_texture_color = { black[1], black[2], black[3] },
				fixed_texture_background_color = { white[1], white[2], white[3], white[4] },
				overlay_texture = MEDIA_EDGE,
				overlay_color   = { white[1], white[2], white[3], white[4] },
				texture_highlight = "Interface\\FriendsFrame\\UI-FriendsList-Highlight",
				backdrop = {
					enabled = false,
					size = 12,
					color = { white[1], white[2], white[3], white[4] },
					use_class_colors = false,
				},
				height = 24,
				space = { left = ROW_INSET_X, right = -4, between = 4 },
				alpha = 1,
				no_icon = false,
				icon_file = "Interface\\AddOns\\Details\\images\\classes_small",
				icon_offset = { 0, 0 },
				start_after_icon = true,
				use_spec_icons = false,
				font_face = "Arial Narrow",
				font_face_file = "Fonts\\ARIALN.TTF",
				font_size = 14,
				textL_show_number = true,
				textL_outline = true,
				textL_class_colors = false,
				textL_enable_custom_text = false,
				textR_outline = true,
				textR_class_colors = false,
				textR_enable_custom_text = true,
				textR_custom_text = "{data1} ({data2})",
				textR_separator = ",",
				percent_type = 1,
			},
		},

		callback = function(skin, instance, just_updating)
			if DS and DS.DecorateWindow then
				DS.DecorateWindow(instance)
			end
		end,
	}
end

-- Registers (or, when force, re-registers) the skin with Details. Never forced
-- automatically: Details may be reading the slot while it restores its windows.
function DS.Install(force)
	local D = details()
	if not D then return false end
	registerMedia()
	hookChangeSkin(D)
	if D.skins[SKIN_NAME] and not force then return true end
	if force then D.skins[SKIN_NAME] = nil end
	local ok, installed = pcall(D.InstallSkin, D, SKIN_NAME, skinTable())
	return (ok and installed) and true or false
end

-- Installs the skin, marks it chosen and pushes it to every open window. This is
-- the button's path and the path the boot runs, so the two can never diverge.
function DS.Apply()
	local D = details()
	if not D then return false end
	DS.Install(true)
	addon:SetSkinEnabled("details", true)

	-- Retail-style K/M abbreviation (Details caches the chosen formatter).
	D.ps_abbreviation, D.total_abbreviation = 2, 2
	if type(D.UpdateToKFunctions) == "function" then pcall(D.UpdateToKFunctions, D) end

	local applied = 0
	forEachInstance(D, function(inst)
		if inst.ChangeSkin then
			pcall(inst.ChangeSkin, inst, SKIN_NAME)
			DS.DecorateWindow(inst)
			applied = applied + 1
		end
	end)
	return applied > 0
end

-- Removes the skin. Every window is handed back to a REAL Details skin before we
-- drop ours from D.skins: a window left pointing at SKIN_NAME while the table
-- entry is nil makes Details' options window crash on GetSkin().
function DS.Uninstall()
	addon:SetSkinEnabled("details", false)
	local D = details()
	if not D then
		unhookChangeSkin(nil)
		return
	end
	unhookChangeSkin(D)

	local fallback = D.default_skin_to_use or "Minimalistic"
	local stillWorn = false
	forEachInstance(D, function(inst)
		if not inst.baseframe then return end
		if inst.skin == SKIN_NAME and type(inst.ChangeSkin) == "function" then
			pcall(inst.ChangeSkin, inst, fallback)
		end
		if inst.skin == SKIN_NAME then stillWorn = true end
		clearDecoration(inst)
	end)

	-- If a window could not be re-skinned, keep ours registered so GetSkin() stays valid.
	if not stillWorn then
		D.skins[SKIN_NAME] = nil
	end
end


SLASH_DUIDETAILS1 = "/duidetails"
SlashCmdList["DUIDETAILS"] = function()
	if not DS.IsDetailsLoaded() then
		DUI:Print("|cff1784d1DragonUI|r: " .. L["Details! is not installed."])
		return
	end
	if DS.Apply() then
		DUI:Print("|cff1784d1DragonUI|r: " .. L["Details! skin applied."])
	else
		DUI:Print("|cff1784d1DragonUI|r: " .. L["Could not apply the skin - Details! is not ready yet."])
	end
end


-- Core.lua owns the ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD wiring
-- for every skin, so this file needs no boot frame of its own. The display
-- metadata below is what the data-driven Options tab reads via
-- addon:GetRegisteredSkins(); `options` renders this skin's extra controls.
--
-- The five display strings are FUNCTIONS on purpose. This registration runs at
-- file load, before OnInitialize() re-points the addon.L proxy at the player's
-- active locale; a plain L["..."] evaluated here would be captured in the
-- load-time language and the Options tab would keep showing English to a
-- Spanish player. Functions are resolved when the tab asks for the metadata.
addon:RegisterSkin("details", "Details", {
	install   = DS.Install,
	apply     = DS.Apply,
	uninstall = DS.Uninstall,

	label       = function() return L["Details! Skin"] end,
	desc        = function() return L["Retail damage-meter theme for Details!."] end,
	toggleLabel = function() return L["Enable Details! Skin"] end,
	toggleDesc  = function() return L["Enable the DragonUI skin for Details!."] end,

	-- `available` is the Options tab's verdict on whether Details! is installed
	-- at all; without it the slider would happily tune a skin nothing can wear.
	options = function(section, C, available)
		C:AddSlider(section, {
			label = L["Background Opacity"] or "Background Opacity",
			desc = L["Opacity of the Details! meter background texture."] or
			       "Opacity of the Details! meter background texture.",
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
