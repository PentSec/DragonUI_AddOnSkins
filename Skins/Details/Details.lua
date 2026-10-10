-- DragonUI_AddOnSkins — Details! skin.
-- Reskins the damage meter: gold header, near-invisible panel, class rows.
-- Registered with Details as the "DragonUI" skin.

local ADDON_NAME, addon = ...
local DUI = _G.DragonUI
local L = addon.L
local media = addon.media   -- centralized palette (utils/media.lua)

local DS = {}
addon.DetailsSkinAddon = DS

local SKIN_NAME = "DragonUI"

-- Shared helpers (utils/decorate.lua): setRegion, panel/header, panelAlpha.
local deco = addon.deco

-- Sheet for LibSharedMedia and row fallbacks; single definition in the helper.
local SHEET = deco.METER_SHEET

local MEDIA_FILL = "DragonUI Meter Fill"
local MEDIA_ROW  = "DragonUI Meter Row"
local MEDIA_EDGE = "DragonUI Meter Row Edge"
local ATLAS_FILL   = "ui-hud-cooldownmanager-bar"
local ATLAS_ROW    = "ui-damagemeters-bar-shadowbg"
local ATLAS_EDGE   = "ui-damagemeters-bar-shadowedge"

-- Geometry shared between the skin table and the manual anchors.
local HEADER_H      = 28     -- header band height, px
local BAR_CENTRE_Y  = HEADER_H / 2
local ROW_INSET_X    = 4
local BALL_INNER_X   = 21
local BALL_R_INNER_X = 32
local ICON_SIZE      = 16
local TITLE_SIZE     = 13
local floor = math.floor

-- Minimum height, px, kept for the class-coloured fill in the Thin layout.
local THIN_STRIP_MIN = 4

-- Details' own header pieces, hidden while our skin is on (saved and restored).
local HEADER_PIECES = { "ball", "emenda", "ball_r", "top_bg" }


-- Returns the Details addon table once it is ready, or nil.
local function details()
	local D = _G._detalhes or _G.Details
	if D and type(D.InstallSkin) == "function" and type(D.skins) == "table" then return D end
	return nil
end

-- Runs fn(instance, index) on every live Details window.
local function forEachInstance(D, fn)
	if not D then return end
	local count = (type(D.GetNumInstancesAmount) == "function" and D:GetNumInstancesAmount()) or 0
	for i = 1, count do
		local inst = D.GetInstance and D:GetInstance(i)
		if inst then fn(inst, i) end
	end
end

-- Tracks which windows wear our skin, keyed by Details' `meu_id`.
local function instKey(inst)
	return inst and (inst.meu_id or inst.id) or nil
end

local function windowMarks(create)
	local s = _G.DragonUI_AddOnSkinsSettings
	if type(s) ~= "table" then return nil end
	if create and type(s.detailsWindows) ~= "table" then s.detailsWindows = {} end
	return s.detailsWindows
end

local function markWindow(inst, on)
	local key = instKey(inst)
	if not key then return end
	local m = windowMarks(on)
	if m then m[key] = on and true or nil end
end

local function isMarked(inst)
	local m = windowMarks(false)
	local key = instKey(inst)
	return (m and key and m[key]) and true or false
end

-- Recursive copy so saved values never share sub-tables with the live instance.
local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = deepCopy(v) end
	return out
end

-- The window's config as Details' active profile still has it.
local function savedInstanceConfig(index)
	local D = details()
	if not D then return nil end
	if type(D.GetCurrentProfileName) ~= "function" or type(D.GetProfile) ~= "function" then return nil end
	local profile = D:GetProfile(D:GetCurrentProfileName(), false)
	local entry = profile and profile.instances and profile.instances[index]
	if type(entry) ~= "table" then return nil end
	return entry
end

-- Keys ApplyProfile handles itself are never copied back.
local function isPlayerOwnedKey(key)
	if type(key) ~= "string" then return false end
	if key == "skin" or key == "posicao" or key == "StatusBarSaved" then return false end
	return key:sub(1, 2) ~= "__"
end

-- Puts the saved config back on the instance and re-applies it.
local function adoptSavedConfig(inst, index)
	if inst.skin ~= SKIN_NAME or type(inst.ChangeSkin) ~= "function" then return false end
	local saved = savedInstanceConfig(index)
	if not saved then return false end

	for key, value in pairs(saved) do
		if isPlayerOwnedKey(key) then
			inst[key] = deepCopy(value)
		end
	end

	pcall(inst.ChangeSkin, inst)
	return true
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

-- Points a texture at a named atlas region (utils/decorate.lua).
local setRegion = deco.setRegion

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

-- Draws (or reuses) one of our overlaid row strips and anchors it to the bar.
local function rowStrip(row, key, layer, region)
	local bar = row.statusbar
	if not bar then return false end
	local tex = row[key]
	if not tex then
		tex = bar:CreateTexture(nil, layer)
		row[key] = tex
	end
	return deco.meterStrip(tex, region, bar)
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

-- Row's name/value FontStrings (field names vary between Details builds).
local function detailsName(row) return row.texto_esquerdo or row.textleft end
local function detailsValue(row) return row.texto_direita or row.textright end

-- Full height: hands the fill and the texts back to Details' own anchors.
local function fullDetailsRow(row)
	local saved = row and row._duiThin
	if not saved then return end
	deco.restorePoints(row.statusbar, saved.bar)
	local name, value = detailsName(row), detailsValue(row)
	if name and saved.name then deco.restorePoints(name, saved.name) end
	if value and saved.value then deco.restorePoints(value, saved.value) end
	row._duiThin = nil
end

-- Thin: name/value on a top row, the fill keeps the strip below them.
local function thinDetailsRow(row)
	local bar = row.statusbar
	local name, value = detailsName(row), detailsValue(row)
	if not (bar and name) then return end
	if not row._duiThin then
		local barPts = deco.savePoints(bar)
		if not barPts then return end
		row._duiThin = {
			bar = barPts,
			name = deco.savePoints(name),
			value = value and deco.savePoints(value),
		}
	end
	local icon = row.icone_classe
	if icon then
		name:ClearAllPoints()
		name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 3, 0)
	else
		name:ClearAllPoints()
		name:SetPoint("TOPLEFT", row, "TOPLEFT", 3, 0)
	end
	if value then
		value:ClearAllPoints()
		value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, 0)
	end
	-- Keep a visible class-coloured strip even when Detail's rows are short.
	local textH = deco.fontRowHeight(name) + 1
	local rowHeight = row:GetHeight() or 0
	if rowHeight <= 0 then rowHeight = textH + THIN_STRIP_MIN end
	local rowH = rowHeight - THIN_STRIP_MIN
	if textH < rowH then rowH = textH end
	if rowH < 0 then rowH = 0 end
	bar:ClearAllPoints()
	if icon then
		bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 0, -rowH)
	else
		bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -rowH)
	end
	bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
end

-- Applies the stored row style. Full only undoes a previous Thin.
local function applyRowStyle(row)
	if not row then return end
	if deco.getBarBorder("details") == "thin" then
		thinDetailsRow(row)
	else
		fullDetailsRow(row)
	end
end

-- Applies the class bar fill and our two overlay strips to every row.
local function stampRows(inst)
	local border = deco.getBarBorder("details") == "borderer"
	return forEachRow(inst, function(row)
		if row.statusbar then
			rowStrip(row, "_duiBarBG", "BACKGROUND", ATLAS_ROW)
			rowStrip(row, "_duiBarEdge", "OVERLAY", ATLAS_EDGE)
			deco.meterBarBorder(row.statusbar, border)
			if row.background then row.background:Hide() end
			if row.overlayTexture then row.overlayTexture:Hide() end
			if row.lineBorder then row.lineBorder:Hide() end
			if row.textura then setRegion(row.textura, ATLAS_FILL) end
			applyRowStyle(row)
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
		if row.statusbar then deco.meterBarBorder(row.statusbar, false) end
		if row.lineBorder then row.lineBorder:Show() end
		fullDetailsRow(row)
	end)
end

-- Declared before resetPluginRows_impl, which calls it.
local function getTinyThreatPlugin()
	local D = details()
	if not D then return nil end
	local p = _G.DETAILS_PLUGIN_TINY_THREAT
	if type(p) == "table" and type(p.Rows) == "table" then return p end
	if type(D.GetPlugin) == "function" then
		p = D:GetPlugin("DETAILS_PLUGIN_TINY_THREAT")
		if type(p) == "table" and type(p.Rows) == "table" then return p end
	end
	return nil
end

local resetPluginRows

-- Forward-declare for clearDecoration (called before declaration point).
local function resetPluginRows_impl(force)
	local p = getTinyThreatPlugin()
	if not p or type(p.Rows) ~= "table" then return end
	local touched = false
	for _, row in ipairs(p.Rows) do
		if row and row._duiSkinActive then touched = true; break end
	end
	if not touched and not force then return end

	for _, row in ipairs(p.Rows) do
		if row then
			row._duiSkinActive = false
			if row._duiBarBG then row._duiBarBG:Hide() end
			if row._duiBarEdge then row._duiBarEdge:Hide() end
			if row.background then row.background:Show() end
			if row._texture then row._texture:SetTexCoord(0, 1, 0, 1) end
		end
	end

	-- RefreshRows hands the rows back to TinyThreat's own texture.
	if type(p.RefreshRows) == "function" then
		pcall(p.RefreshRows, p)
	end
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
	resetPluginRows_impl()
end

-- ============================================================================
-- TINYTHREAT PLUGIN SUPPORT
-- ============================================================================

local stampTinyThreatRow

local function hookTinyThreatRow(row, inst)
	if row._duiHooksApplied or not row.statusbar then return end
	row._duiHooksApplied = true

	-- Re-stamp on show: the StatusBar can reset TexCoord.
	row.statusbar:HookScript("OnShow", function(self)
		local r = self.MyObject
		if r and r._duiSkinActive and r._texture then
			setRegion(r._texture, ATLAS_FILL)
		end
	end)

	-- Re-apply the crop on value change (3.3.5 resets fill TexCoord).
	row.statusbar:HookScript("OnValueChanged", function(self)
		local r = self.MyObject
		if r and r._duiSkinActive and r._texture then
			setRegion(r._texture, ATLAS_FILL)
		end
	end)
end

function stampTinyThreatRow(row, inst)
	if not row or not row.statusbar then return end
	row._duiSkinActive = true
	rowStrip(row, "_duiBarBG", "BACKGROUND", ATLAS_ROW)
	rowStrip(row, "_duiBarEdge", "OVERLAY", ATLAS_EDGE)
	if row.background then row.background:Hide() end
	if row._texture then setRegion(row._texture, ATLAS_FILL) end
	hookTinyThreatRow(row, inst)
end

local function stampPluginRows(inst)
	local p = getTinyThreatPlugin()
	if not p then return end

	if type(p.GetPluginInstance) == "function" then
		local pInst = p:GetPluginInstance()
		if pInst and pInst.skin ~= SKIN_NAME then return end
	end

	if type(p.Rows) == "table" then
		for _, row in ipairs(p.Rows) do
			stampTinyThreatRow(row, inst)
		end
	end
end

function resetPluginRows()
	resetPluginRows_impl()
end

local function hookTinyThreatPlugin()
	local p = getTinyThreatPlugin()
	if not p or p._duiHooked then return end
	p._duiHooked = true

	if type(p.NewRow) == "function" then
		hooksecurefunc(p, "NewRow", function(self, i)
			local pInst = type(self.GetPluginInstance) == "function" and self:GetPluginInstance()
			if pInst and pInst.skin == SKIN_NAME then
				local row = type(self.Rows) == "table" and self.Rows[i]
				if row then
					stampTinyThreatRow(row, pInst)
				end
			end
		end)
	end

	if type(p.RefreshRow) == "function" then
		hooksecurefunc(p, "RefreshRow", function(self, row)
			local pInst = type(self.GetPluginInstance) == "function" and self:GetPluginInstance()
			if pInst and pInst.skin == SKIN_NAME then
				stampTinyThreatRow(row, pInst)
			end
		end)
	end

	-- First pass over the plugin window's existing rows.
	if type(p.GetPluginInstance) == "function" then
		local pInst = p:GetPluginInstance()
		if pInst and pInst.skin == SKIN_NAME then
			stampPluginRows(pInst)
		end
	end
end

local function hookInstallPlugin(D)
	if DS._ourInstallPluginHooked or type(D.InstallPlugin) ~= "function" then return end
	DS._ourInstallPluginHooked = true
	hooksecurefunc(D, "InstallPlugin", function(self, hook_type, plugin_name, icon, plugin_object, plugin_absolute_name, ...)
		if plugin_absolute_name == "DETAILS_PLUGIN_TINY_THREAT" then
			hookTinyThreatPlugin()
			local pInst = type(plugin_object.GetPluginInstance) == "function" and plugin_object:GetPluginInstance()
			if pInst and pInst.skin == SKIN_NAME then
				stampPluginRows(pInst)
			end
		end
	end)
end


-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- True when Details is loaded and ready to accept a skin.
function DS.IsDetailsLoaded()
	return IsAddOnLoaded("Details") and details() ~= nil
end

-- Background panel opacity, 0..1 (stored by the shared helper, key "details").
function DS.GetPanelAlpha()
	return deco.getPanelAlpha("details")
end

function DS.SetPanelAlpha(v)
	deco.setPanelAlpha("details", v)
end

-- Re-tints just the background panel on the open windows (no full re-apply).
function DS.RefreshPanelAlpha()
	local alpha = DS.GetPanelAlpha()
	forEachInstance(details(), function(inst)
		local panel = inst.baseframe and inst.baseframe._duiMeterPanel
		if panel then panel:SetVertexColor(1, 1, 1, alpha) end
	end)
end

-- Re-applies the bar border/style choice to the open rows (no full re-apply).
function DS.RefreshBarBorder()
	local border = deco.getBarBorder("details") == "borderer"
	forEachInstance(details(), function(inst)
		forEachRow(inst, function(row)
			if row.statusbar then
				deco.meterBarBorder(row.statusbar, border)
				applyRowStyle(row)
			end
		end)
	end)
end

-- Panel + header band (shared) plus Details' row art and native-header hiding.
function DS.DecorateWindow(inst)
	local base = inst and inst.baseframe
	if not (base and base.CreateTexture) then return end

	deco.meterPanel(base, DS.GetPanelAlpha())
	-- OVERLAY so the band covers Details' title row.
	deco.meterHeader(base, base, "TOPLEFT", "TOPRIGHT", "OVERLAY")
	detailsHeaderShown(inst, false)
	stampRows(inst)
	stampPluginRows(inst)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

-- Wraps ChangeSkin: keeps decoration in sync, turns the toggle off on other skins.
local function hookChangeSkin(D)
	if DS._ourChangeSkin or type(D.ChangeSkin) ~= "function" then return end
	local orig = D.ChangeSkin
	DS._origChangeSkin = orig
	DS._ourChangeSkin = function(self, skinName, ...)
		local wasOurs = (type(self) == "table" and self.skin == SKIN_NAME) or false
		local asked = skinName ~= nil and skinName or (type(self) == "table" and self.skin) or nil
		local explicit = (skinName ~= nil and skinName ~= SKIN_NAME)
		local installed = (D.skins and D.skins[SKIN_NAME] ~= nil) and true or false
		local a, b, c = orig(self, skinName, ...)
		if type(self) ~= "table" then return a, b, c end

		if self.skin == SKIN_NAME then
			if installed then DS.DecorateWindow(self) end
			markWindow(self, true)
		else
			clearDecoration(self)
			-- Forget the window only on an explicit skin change.
			if wasOurs and explicit then markWindow(self, false) end
			-- Turn the toggle off only when no other window wears our skin.
			if wasOurs and explicit and installed then
				local anyOurs = false
				forEachInstance(D, function(inst)
					if inst.skin == SKIN_NAME then anyOurs = true; end
				end)
				if not anyOurs then
					addon:SetSkinEnabled("details", false)
					if DUI and DUI.After then DUI:After(0, DS.Uninstall) end
				end
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
				height = 16,
				space = { left = ROW_INSET_X, right = -4, between = 4 },
				alpha = 1,
				no_icon = false,
				icon_file = "Interface\\AddOns\\Details\\images\\classes_small",
				icon_offset = { 0, 0 },
				start_after_icon = true,
				use_spec_icons = true,
				spec_file = "Interface\\AddOns\\Details\\images\\spec_icons_normal",
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

-- True when any Details window still wears our skin (boot-time cleanup check).
function DS.IsWorn()
	local D = details()
	local worn = false
	forEachInstance(D, function(inst)
		if inst.skin == SKIN_NAME then worn = true end
	end)
	return worn
end

function DS.Restore()
	local D = details()
	if not D then return false end
	registerMedia()
	hookChangeSkin(D)
	hookInstallPlugin(D)
	hookTinyThreatPlugin()
	DS.Install(false)
	forEachInstance(D, function(inst, index)
		if not inst.baseframe then return end
		if inst.skin == SKIN_NAME then
			DS.DecorateWindow(inst)
			markWindow(inst, true)
		elseif isMarked(inst) and D.skins[SKIN_NAME] and type(inst.ChangeSkin) == "function" then
			-- Details restored this window before our skin was registered and
			-- dropped it to its default skin. Put back just the windows that
			-- were ours; the hook decorates them.
			pcall(inst.ChangeSkin, inst, SKIN_NAME)
			-- ...and hand the player's own settings back before this session can
			-- save the window again with our defaults in it.
			adoptSavedConfig(inst, index)
		end
	end)
	return true
end

-- Registers (or, when force, re-registers) the skin with Details. Never forced
-- automatically: Details may be reading the slot while it restores its windows.
function DS.Install(force)
	local D = details()
	if not D then return false end
	registerMedia()
	hookChangeSkin(D)
	hookInstallPlugin(D)
	hookTinyThreatPlugin()
	if D.skins[SKIN_NAME] and not force then return true end
	if force then D.skins[SKIN_NAME] = nil end
	local ok, installed = pcall(D.InstallSkin, D, SKIN_NAME, skinTable())
	return (ok and installed) and true or false
end

-- Installs, marks the skin chosen and pushes it to every open window.
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
			-- Clear the name first to force a real re-apply (Details' own trick).
			inst.skin = ""
			pcall(inst.ChangeSkin, inst, SKIN_NAME)
			DS.DecorateWindow(inst)
			markWindow(inst, true)
			applied = applied + 1
		end
	end)
	return applied > 0
end

-- Hands every window back to a real skin, then drops ours from D.skins.
function DS.Uninstall()
	local D = details()
	if D then unhookChangeSkin(D) end

	addon:SetSkinEnabled("details", false)

	if not D then
		unhookChangeSkin(nil)
		return
	end

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

	-- Toggle is off: no window is "ours" any more.
	local marks = windowMarks(false)
	if marks then for k in pairs(marks) do marks[k] = nil end end

	-- All windows are on their new skin now: make TinyThreat re-read it.
	resetPluginRows_impl(true)

	-- If a window could not be re-skinned, keep ours registered so GetSkin() stays valid.
	if not stillWorn then
		D.skins[SKIN_NAME] = nil
	end
end


SLASH_DUIDETAILS1 = "/duidetails"
SlashCmdList["DUIDETAILS"] = function(msg)
	if type(msg) == "string" and msg:lower():find("status") then
		local D = details()
		DUI:Print("|cff1784d1DragonUI|r Details status: toggle=" .. tostring(addon:GetSkinEnabled("details")) ..
			" registered=" .. tostring(D and D.skins and D.skins[SKIN_NAME] ~= nil))
		forEachInstance(D, function(inst, index)
			local ri = inst.row_info
			local saved = savedInstanceConfig(index)
			local savedRi = saved and saved.row_info
			DUI:Print(("  window %s: skin=%s marked=%s barHeight=%s savedHeight=%s"):format(
				tostring(instKey(inst)), tostring(inst.skin), tostring(isMarked(inst)),
				tostring(ri and ri.height), tostring(savedRi and savedRi.height)))
		end)
		return
	end
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


-- Core.lua wires the boot events for every skin; metadata here feeds the Options tab.
-- Display strings are FUNCTIONS so they resolve in the player's locale.
addon:RegisterSkin("details", "Details", {
	install   = DS.Install,
	apply     = DS.Apply,
	restore   = DS.Restore,
	isWorn    = DS.IsWorn,
	uninstall = DS.Uninstall,

	label       = function() return L["Details! Skin"] end,
	desc        = function() return L["Retail damage-meter theme for Details!."] end,
	toggleLabel = function() return L["Enable Details! Skin"] end,
	toggleDesc  = function() return L["Enable the DragonUI skin for Details!."] end,

	-- `available` gates these controls on Details being installed.
	options = function(section, C, available)
		deco.addPanelAlphaSlider(section, C, available, {
			skinKey   = "details",
			label     = L["Background Opacity"] or "Background Opacity",
			desc      = L["Opacity of the Details! meter background texture."] or
			           "Opacity of the Details! meter background texture.",
			onChanged = DS.RefreshPanelAlpha,
		})

		deco.addBarBorderDropdown(section, C, available, {
			skinKey         = "details",
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
