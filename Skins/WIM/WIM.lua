-- DragonUI_AddOnSkins — WIM skin. Puts retail's metal frame on WIM's whisper windows,
-- cut live out of DragonUI's runtime atlas (_G.DragonUI.atlasinfo), so a DragonUI update
-- that moves the art leaves this skin working. Only obj.type == "whisper" wears it; WIM
-- recycles one pool of frames across whisper/chat/w2w/demo, so a frame is handed back the
-- moment its type stops being a whisper.

local ADDON_NAME, addon = ...
local DUI = _G.DragonUI
local L = addon.L

local DS = {}
addon.WIMSkinAddon = DS

local SKIN_KEY = "wim"

-- All eight pieces are DragonUI regions (DragonUI/utils/atlas.lua) -- the same set
-- nineslice's PortraitFrameTemplate picks (DragonUI/utils/nineslice.lua:62-71), so
-- this window and the reference layout cannot drift apart. Top corners are the 75px
-- portrait pair, the rest the 32px pair; "_"/"!" is retail's convention for which way
-- each strip tiles.
local ATLAS = {
	tl = "UI-Frame-PortraitMetal-CornerTopLeft",
	tr = "UI-Frame-Metal-CornerTopRight",
	bl = "UI-Frame-Metal-CornerBottomLeft",
	br = "UI-Frame-Metal-CornerBottomRight",
	t  = "_UI-Frame-Metal-EdgeTop",
	b  = "_UI-Frame-Metal-EdgeBottom",
	l  = "!UI-Frame-Metal-EdgeLeft",
	r  = "!UI-Frame-Metal-EdgeRight",
}

-- class_icon size and its centre in the 75px top-left corner, both measured: WIM's
-- class_icons.tga is a 4x4 grid of 64px cells whose disc spans only px 13..50, so the
-- disc is always size * 38/64, while the corner's baked gold ring measures outer 59.5,
-- inner 54.0, midline 56.75 at (38, 38). 95 * 38/64 = 56.4 puts the disc on the midline
-- so the gold band crops it into a clean circle. The overhang is deliberate: the surplus
-- is transparent.
local PORTRAIT_ICON = 95
local PORTRAIT_ICON_X, PORTRAIT_ICON_Y = 38, -38

-- Only its FILE is used; the button's texcoord windows below are literal.
local ATLAS_CLOSE = "redbutton-expand"

-- Texcoord windows into redbutton2x's second column for the X button: normal on
-- top, pressed below. The atlas entry describes the sheet, not this button.
local CLOSE_NORMAL = { 0.152344, 0.292969, 0.0078125, 0.304688 }
local CLOSE_PUSHED = { 0.152344, 0.292969, 0.320312, 0.617188 }

-- Optional hover glow; absent from a trimmed atlas, where the button keeps WIM's.
local ATLAS_CLOSE_HIGHLIGHT = "redbutton-highlight"

-- Retail's inner trim, which the Default skin bakes into message_window.tga and
-- which we lose when the nine native textures are hidden. Same eight regions
-- nineslice's InsetFrameTemplate picks (DragonUI/utils/nineslice.lua:100-109).
local ATLAS_INSET = {
	tl = "UI-Frame-InnerTopLeft",
	tr = "UI-Frame-InnerTopRight",
	bl = "UI-Frame-InnerBotLeftCorner",
	br = "UI-Frame-InnerBotRight",
	t  = "_UI-Frame-InnerTopTile",
	b  = "_UI-Frame-InnerBotTile",
	l  = "!UI-Frame-InnerLeftTile",
	r  = "!UI-Frame-InnerRightTile",
}

-- How far the trim sits outside the box it frames.
local INSET_PAD = 3

-- Geometry for the two text boxes, imposed by the hook after WIM's own layout -- WIM
-- re-applies its anchors on every ApplySkinToWindow (Skinner.lua:52) and nothing else
-- moves these boxes, so nothing needs undoing on teardown. Measured on the default
-- 333x220 window: equal margins give both boxes the same width, ~6px clears the left and
-- bottom rails, and the 32px right gap is WIM's scroll buttons. To shrink the boxes, raise
-- all four margins by the same amount.
local BOX = {
	chat_display = {
		{ "TOPLEFT",     "TOPLEFT",     12, -65 },
		{ "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 56 },
	},
	msg_box = {
		{ "TOPLEFT",     "BOTTOMLEFT",  12,  40 },
		{ "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 16 },
	},
}

-- WIM's Default skin asks for 256x128, which squeezes chat_display to 16px under
-- the geometry above. WIM re-imposes its own value on the next apply.
local BOX_MIN_HEIGHT = 152
local BOX_MIN_WIDTH_FALLBACK = 256

-- Flat fill behind each box so the text sits on black instead of on the rock.
-- WHITE8X8 needs no atlas entry, so the fill draws even without the inner trim.
local BOX_FILL_TEXTURE = [[Interface\Buttons\WHITE8X8]]
local BOX_FILL_ALPHA = 0.55

-- Breathing room for msg_box's text, applied only while the window wears our frame
-- and handed back on teardown. chat_display's text is already inset.
local MSG_TEXT_INSET_L, MSG_TEXT_INSET_R = 3, 3
local MSG_TEXT_INSET_T, MSG_TEXT_INSET_B = 0, 0

-- WIM's own frame art, all nine on obj.widgets.Backdrop. Hidden with :Hide() rather
-- than SetTexture(nil) so a re-apply mid-teardown still paints skin, not a hole.
local NATIVE = { "tl", "tr", "bl", "br", "t", "b", "l", "r", "bg" }

-- Corner placement from DragonUI's PortraitFrameTemplate (DragonUI/utils/nineslice.lua
-- layoutRegistry). Unlike MetalFrameTemplate the top corners are the 75px pair and
-- overhang 13px left, so the top strip needs its own 4px inset to close the join.
local TL_X, TL_Y = -13, 16
local TR_X, TR_Y = 4, 16
local BL_X, BL_Y = -13, -3
local BR_X, BR_Y = 4, -3
local TOP_EDGE_X, TOP_EDGE_X1 = -4, 4

-- Rock inset, relative to the window. The top one matters: the rock is a BACKGROUND
-- texture and class_icon is lifted to BORDER above it, so rock over the top-left
-- would still crowd the portrait.
local BG_LT_X, BG_LT_Y = 2, -18
local BG_RB_X, BG_RB_Y = -3, 3
local BG_ALPHA = 0.8

-- Windows currently wearing the frame, held weakly so a closed window does not leak.
local seen = setmetatable({}, { __mode = "k" })

-- False until Apply (or a boot Restore of an enabled skin) turns it on; every hook and
-- enumeration stays inert behind it, which lets the hook ship installed while off.
local active = false

local unskin -- forward declaration: skin() calls it

-- ============================================================================
-- ATLAS
-- ============================================================================

local metalAtlas -- resolved once DragonUI's atlas is reachable

-- Resolves every region the frame draws from, plus the two plain file paths. Returns
-- nil -- never errors -- while DragonUI is missing, still loading, or missing a region;
-- callers read that as "draw nothing", so a half-loaded DragonUI degrades to WIM's own skin.
local function resolveAtlas()
	if metalAtlas then return metalAtlas end

	local info = _G.DragonUI and _G.DragonUI.atlasinfo
	if type(info) ~= "table" then return nil end

	local regions, sheetPath = {}, nil
	for key, name in pairs(ATLAS) do
		local entry = info[name]
		if type(entry) ~= "table" or type(entry[1]) ~= "string" then return nil end
		regions[key] = entry
		sheetPath = sheetPath or entry[1]
	end

	local close = info[ATLAS_CLOSE]
	if type(close) ~= "table" or type(close[1]) ~= "string" then return nil end

	-- Optional extras: a trimmed atlas just means WIM's hover glow and plain inner boxes.
	local highlight = info[ATLAS_CLOSE_HIGHLIGHT]
	if type(highlight) ~= "table" or type(highlight[1]) ~= "string" then
		highlight = nil
	end

	local inset = {}
	for key, name in pairs(ATLAS_INSET) do
		local entry = info[name]
		if type(entry) ~= "table" or type(entry[1]) ~= "string" then
			inset = nil
			break
		end
		inset[key] = entry
	end

	-- The rock is a plain file beside the frame sheets, not a region. Rebuilding the
	-- directory off a region's path keeps that working if DragonUI moves its folder.
	local dir = sheetPath:match("^(.*\\)")
	if not dir then return nil end

	metalAtlas = {
		regions = regions,
		close   = close[1],
		closeHighlight = highlight,
		inset   = inset,
		rock    = dir .. "ui-background-rock.blp",
	}
	return metalAtlas
end


-- ============================================================================
-- PER-WINDOW FRAME
-- ============================================================================

-- Creates (once) our art on one WIM window. Returns nil while the atlas is unavailable.

-- Textures go directly on obj.widgets.Backdrop as siblings of WIM's own art: a child
-- frame would inherit its alpha multiplicatively, and every widget we must not cover is a
-- region of that same Backdrop pinned to a fixed draw layer, so ordering comes from the
-- layer, not creation order:
--     rock BACKGROUND | box fills BORDER | class_icon BORDER | 9 natives BORDER (hidden)
--     box trims ARTWORK | frame metal OVERLAY | from/char_info OVERLAY
-- A child frame cannot sort against its parent's regions: frame levels are unsigned.

-- Pieces live on the window (obj._duiWim) so a second apply reuses them.
local function buildParts(obj)
	local mine = obj._duiWim
	if mine then return mine end

	local backdrop = obj.widgets and obj.widgets.Backdrop
	local atlas = backdrop and resolveAtlas()
	if not backdrop or not atlas then return nil end

	local bg = backdrop:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(atlas.rock)
	bg:SetAlpha(BG_ALPHA)
	bg:SetPoint("TOPLEFT", backdrop, "TOPLEFT", BG_LT_X, BG_LT_Y)
	bg:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", BG_RB_X, BG_RB_Y)

	-- Sizes come from the atlas entry, so the geometry below stays pure anchoring.
	local function piece(key)
		local entry = atlas.regions[key]
		local tex = backdrop:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(entry[1])
		tex:SetTexCoord(entry[4], entry[5], entry[6], entry[7])
		tex:SetWidth(entry[2])
		tex:SetHeight(entry[3])
		tex:Show()
		return tex
	end

	local tl, tr = piece("tl"), piece("tr")
	local bl, br = piece("bl"), piece("br")
	local t, b, l, r = piece("t"), piece("b"), piece("l"), piece("r")

	tl:SetPoint("TOPLEFT",     backdrop, "TOPLEFT",     TL_X, TL_Y)
	tr:SetPoint("TOPRIGHT",    backdrop, "TOPRIGHT",    TR_X, TR_Y)
	bl:SetPoint("BOTTOMLEFT",  backdrop, "BOTTOMLEFT",  BL_X, BL_Y)
	br:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", BR_X, BR_Y)

	-- Each strip anchors on the SAME-named edge of the two corners it joins; the opposite
	-- edge would skew it diagonally. Only the top strip is inset -- only the top corners
	-- overhang (PortraitFrameTemplate).
	t:SetPoint("TOPLEFT",  tl, "TOPRIGHT", TOP_EDGE_X,  0)
	t:SetPoint("TOPRIGHT", tr, "TOPLEFT",  TOP_EDGE_X1, 0)
	b:SetPoint("TOPLEFT",  bl, "TOPRIGHT", 0, 0)
	b:SetPoint("TOPRIGHT", br, "TOPLEFT",  0, 0)
	l:SetPoint("TOPLEFT",     tl, "BOTTOMLEFT",  0, 0)
	l:SetPoint("BOTTOMLEFT",  bl, "TOPLEFT",     0, 0)
	r:SetPoint("TOPRIGHT",    tr, "BOTTOMRIGHT", 0, 0)
	r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT",    0, 0)

	-- Centre the class icon on the top-left corner's portrait circle.
	local icon = obj.widgets and obj.widgets.class_icon
	local iconLayer
	if icon then
		-- WIM creates it on BACKGROUND (WindowHandler.lua:778) and never re-layers it.
		iconLayer = icon.GetDrawLayer and icon:GetDrawLayer() or nil
		icon:ClearAllPoints()
		icon:SetWidth(PORTRAIT_ICON)
		icon:SetHeight(PORTRAIT_ICON)
		icon:SetPoint("CENTER", tl, "TOPLEFT", PORTRAIT_ICON_X, PORTRAIT_ICON_Y)
		-- BORDER: above the rock (BACKGROUND), below the cutout corner (OVERLAY).
		icon:SetDrawLayer("BORDER")
		icon:Show()
	end

	-- Shift WIM's user name (`from` widget, default at 50,-8) 5px right so it clears the portrait.
	local fromName = obj.widgets and obj.widgets.from
	if fromName then
		fromName:ClearAllPoints()
		fromName:SetPoint("TOPLEFT", obj, "TOPLEFT", 55, -8)
	end

	-- Move scroll buttons up 10px (relative to window, like WIM's anchors).
	local scrollUp = obj.widgets and obj.widgets.scroll_up
	if scrollUp then
		scrollUp:ClearAllPoints()
		scrollUp:SetPoint("TOPRIGHT", obj, "TOPRIGHT", -3, -43)
	end
	local scrollDown = obj.widgets and obj.widgets.scroll_down
	if scrollDown then
		scrollDown:ClearAllPoints()
		scrollDown:SetPoint("BOTTOMRIGHT", obj, "BOTTOMRIGHT", -3, 50)
	end

	-- One box: a flat fill plus retail's inner trim, replicating nineslice's
	-- InsetFrameTemplate (nineslice.lua:100-109). The fill is created first and never
	-- depends on the atlas, so the box still reads as a box without the trim. Corners take
	-- their own point at 0 offset, except the bottom pair which the template pins 1px low;
	-- every strip spans corner-to-corner on the SAME-named edge at 0,0. chat_display and
	-- msg_box are sibling frames ABOVE the Backdrop, so the text always draws over both.
	local function insetBox(host)
		if not host then return nil end

		local fill = backdrop:CreateTexture(nil, "BORDER")
		fill:SetTexture(BOX_FILL_TEXTURE)
		fill:SetVertexColor(0, 0, 0, BOX_FILL_ALPHA)

		-- Without a trim there is nothing to frame the fill against, so it takes the corners'
		-- outward pad.
		if not atlas.inset then
			fill:SetPoint("TOPLEFT", host, "TOPLEFT", -INSET_PAD, INSET_PAD)
			fill:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", INSET_PAD, -INSET_PAD - 1)
			fill:Show()
			return { fill = fill, list = { fill } }
		end

		local set = {}
		local function trim(key)
			local e = atlas.inset[key]
			-- ARTWORK, not BORDER, so the layer puts the trim above the fill regardless of
			-- creation order.
			local tx = backdrop:CreateTexture(nil, "ARTWORK")
			tx:SetTexture(e[1])
			tx:SetTexCoord(e[4], e[5], e[6], e[7])
			-- Tile flags at [8]/[9] make the 256px strips repeat instead of stretching
			-- (core.lua setAtlas).
			tx:SetHorizTile(e[8] or false)
			tx:SetVertTile(e[9] or false)
			tx:SetWidth(e[2])
			tx:SetHeight(e[3])
			tx:Show()
			return tx
		end

		set.tl, set.tr = trim("tl"), trim("tr")
		set.bl, set.br = trim("bl"), trim("br")
		set.t, set.b, set.l, set.r = trim("t"), trim("b"), trim("l"), trim("r")

		-- Outward by INSET_PAD on every side, then the template's -1 on the bottom.
		set.tl:SetPoint("TOPLEFT",     host, "TOPLEFT",     -INSET_PAD,  INSET_PAD)
		set.tr:SetPoint("TOPRIGHT",    host, "TOPRIGHT",     INSET_PAD,  INSET_PAD)
		set.bl:SetPoint("BOTTOMLEFT",  host, "BOTTOMLEFT",  -INSET_PAD, -INSET_PAD - 1)
		set.br:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT",  INSET_PAD, -INSET_PAD - 1)

		set.t:SetPoint("TOPLEFT",     set.tl, "TOPRIGHT", 0, 0)
		set.t:SetPoint("TOPRIGHT",    set.tr, "TOPLEFT",  0, 0)
		set.l:SetPoint("TOPLEFT",     set.tl, "BOTTOMLEFT",  0, 0)
		set.l:SetPoint("BOTTOMLEFT",  set.bl, "TOPLEFT",     0, 0)
		set.r:SetPoint("TOPRIGHT",    set.tr, "BOTTOMRIGHT", 0, 0)
		set.r:SetPoint("BOTTOMRIGHT", set.br, "TOPRIGHT",    0, 0)

		-- The bottom strip runs BESIDE the bottom corners on their bottom edge, per the
		-- retail rule; hanging it off their tops strands the corner's bottom row below the box.
		set.b:SetPoint("BOTTOMLEFT",  set.bl, "BOTTOMRIGHT", 0, 0)
		set.b:SetPoint("BOTTOMRIGHT", set.br, "BOTTOMLEFT",  0, 0)

		-- Outer corner to outer corner, so the fill reaches the trim's edges and
		-- no seam is left where the corners meet the strips.
		fill:SetPoint("TOPLEFT", set.tl, "TOPLEFT", 0, 0)
		fill:SetPoint("BOTTOMRIGHT", set.br, "BOTTOMRIGHT", 0, 0)
		fill:Show()

		set.fill = fill
		set.list = { fill, set.tl, set.tr, set.bl, set.br, set.t, set.b, set.l, set.r }
		return set
	end

	local insetChat = insetBox(obj.widgets and obj.widgets.chat_display)
	local insetMsg  = insetBox(obj.widgets and obj.widgets.msg_box)

	-- One flat list drives setShown, so the trims hide and re-show with the rest
	-- of the frame and cost nothing extra per toggle.
	local textures = { bg, tl, tr, bl, br, t, b, l, r }
	if insetChat then
		for i = 1, #insetChat.list do textures[#textures + 1] = insetChat.list[i] end
	end
	if insetMsg then
		for i = 1, #insetMsg.list do textures[#textures + 1] = insetMsg.list[i] end
	end

	obj._duiWim = {
		textures = textures,
		bg = bg,
		tl = tl, tr = tr, bl = bl, br = br,
		t = t, b = b, l = l, r = r,
		insetChat = insetChat,
		insetMsg = insetMsg,
		iconLayer = iconLayer,
	}
	return obj._duiWim
end

-- There is no container frame to hide, so the whole frame toggles texture by texture.
local function setShown(mine, shown)
	local list = mine.textures
	for i = 1, #list do
		if shown then
			list[i]:Show()
		else
			list[i]:Hide()
		end
	end
end

local function native(obj, shown)
	local backdrop = obj and obj.widgets and obj.widgets.Backdrop
	if not backdrop then return end
	for i = 1, #NATIVE do
		local tex = backdrop[NATIVE[i]]
		if tex then
			if shown then tex:Show() else tex:Hide() end
		end
	end
end

-- WIM repaints the close button's texture paths on every apply but never its
-- texcoords (Skinner.lua:157-165), so ours would leak past teardown. Captured
-- once here, restored on every teardown.
local function saveCloseTex(close)
	if close._duiSavedTex then return end
	local function coord(region)
		if not region then return false end -- absent region: restore resets to full rect
		local l, r, t, b = region:GetTexCoord()
		if type(l) ~= "number" then return { 0, 1, 0, 1 } end -- userdata matrix: WIM never sets one
		return { l, r, t, b }
	end
	close._duiSavedTex = {
		normal    = coord(close:GetNormalTexture()),
		pushed    = coord(close:GetPushedTexture()),
		highlight = coord(close:GetHighlightTexture()),
	}
end

-- Puts the three texcoords back. Runs on every teardown and keeps the saved
-- table: a re-apply mutates the regions again and must find the originals here.
local function restoreCloseTex(close)
	local saved = close._duiSavedTex
	if not saved then return end
	local function put(region, coord)
		if not region then return end
		if type(coord) == "table" then
			region:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
		else
			region:SetTexCoord(0, 1, 0, 1)
		end
	end
	put(close:GetNormalTexture(), saved.normal)
	put(close:GetPushedTexture(), saved.pushed)
	put(close:GetHighlightTexture(), saved.highlight)
end

-- Paints our red art onto the button; size and position stay exactly as WIM set them.
-- Nothing here touches the draw layer: a Button's HIGHLIGHT-layer regions only render
-- under the pointer, so visibility is solved by frame level instead (see styleClose).
local function applyCloseArt(close, atlas)
	close:SetNormalTexture(atlas.close)
	close:SetPushedTexture(atlas.close)

	local normal, pushed = close:GetNormalTexture(), close:GetPushedTexture()
	if normal then
		normal:SetTexCoord(CLOSE_NORMAL[1], CLOSE_NORMAL[2], CLOSE_NORMAL[3], CLOSE_NORMAL[4])
	end
	if pushed then
		pushed:SetTexCoord(CLOSE_PUSHED[1], CLOSE_PUSHED[2], CLOSE_PUSHED[3], CLOSE_PUSHED[4])
	end

	-- WIM swaps in its own yellow minimise glow on every state change, which reads as a
	-- different colour of button; give it this sheet's highlight cell so the widget stays red.
	-- Unverified in-game: ADD blending is the one thing here only eyeballing can confirm.
	if atlas.closeHighlight then
		close:SetHighlightTexture(atlas.closeHighlight[1], "ADD")
		local hl = close:GetHighlightTexture()
		if hl then
			hl:SetTexCoord(atlas.closeHighlight[4], atlas.closeHighlight[5],
				atlas.closeHighlight[6], atlas.closeHighlight[7])
		end
	end
end

-- Repaints over the top of WIM's own skinning, which runs first and would put its path
-- and texcoords back on every apply. The hook alone is not enough: WIM also has a
-- per-frame handler on this button (WindowHandler.lua:1673) and rewrites the state
-- textures on every apply (Skinner.lua:152-165). That handler only writes when
-- curTextureIndex flips, so we chain onto OnUpdate and repaint on a flip -- one integer
-- compare per frame otherwise.
local function styleClose(obj, atlas)
	local close = obj.widgets and obj.widgets.close
	if not (close and atlas) then return false end

	-- Make the close button smaller than WIM's default.
	close:SetSize(24, 24)

	local mine = obj._duiWim
	local backdrop = obj.widgets and obj.widgets.Backdrop

	saveCloseTex(close)
	applyCloseArt(close, atlas)

	if mine then
		mine.lastCloseIndex = close.curTextureIndex

		-- The button is a child of the window and a SIBLING of the Backdrop, so only
		-- frame level decides the winner -- the 75px top-right corner overlaps its whole
		-- 32x32 rect. +3 clears the Backdrop without reaching any other widget WIM stacks
		-- on the window.
		if backdrop and mine.closeLevel == nil then
			mine.closeLevel = close:GetFrameLevel()
			close:SetFrameLevel(backdrop:GetFrameLevel() + 3)
		end

		if not mine.ownsCloseUpdate then
			mine.ownsCloseUpdate = true
			local prev = close:GetScript("OnUpdate")
			mine.closeUpdate = prev
			close:SetScript("OnUpdate", function(...)
				if prev then prev(...) end
				if close.curTextureIndex ~= mine.lastCloseIndex then
					local a = resolveAtlas()
					if a then
						mine.lastCloseIndex = close.curTextureIndex
						applyCloseArt(close, a)
					end
				end
			end)
		end
	end
	return true
end

-- Hands the button's OnUpdate and frame level back to WIM so a recycled frame behaves
-- as it did before.
local function releaseCloseUpdate(obj)
	local mine = obj and obj._duiWim
	if not mine then return end
	local close = obj.widgets and obj.widgets.close
	if not close then return end
	if mine.ownsCloseUpdate then
		close:SetScript("OnUpdate", mine.closeUpdate)
		mine.ownsCloseUpdate = nil
		mine.closeUpdate = nil
	end
	if mine.closeLevel ~= nil then
		close:SetFrameLevel(mine.closeLevel)
		mine.closeLevel = nil
	end
	mine.lastCloseIndex = nil
	-- Texcoords first: release() re-applies WIM's skin right after unskin and WIM
	-- sets paths without touching texcoords, so ours must already be back.
	restoreCloseTex(close)
end

-- WIM's minimum width for this skin, or 256 when the table cannot be read: its
-- sources may not have run yet and GetSelectedSkin returns nil before a skin is chosen.
local function boxMinWidth()
	local WIM = _G.WIM
	if WIM and type(WIM.GetSelectedSkin) == "function" then
		local ok, skinTable = pcall(WIM.GetSelectedSkin, WIM)
		if ok and type(skinTable) == "table" then
			local mw = skinTable.message_window
			if type(mw) == "table" and type(mw.min_width) == "number" then
				return mw.min_width
			end
		end
	end
	return BOX_MIN_WIDTH_FALLBACK
end

-- Puts BOX on the two text boxes and raises the window's minimum size. Idempotent:
-- WIM re-applies its own anchors before us on every apply, so re-running this is the
-- only way the geometry survives. The trim is anchored to the boxes, so moving them
-- carries it along without touching it.
local function applyBoxGeometry(obj, mine)
	local widgets = obj.widgets
	if not widgets then return end

	for name, points in pairs(BOX) do
		local box = widgets[name]
		if box then
			box:ClearAllPoints()
			for i = 1, #points do
				local point, relPoint, offX, offY = points[i][1], points[i][2],
					points[i][3], points[i][4]
				box:SetPoint(point, obj, relPoint, offX, offY)
			end
		end
	end

	-- Saved once, so teardown hands back whatever WIM had rather than a guess.
	local msg = widgets.msg_box
	if msg and type(msg.SetTextInsets) == "function"
		and type(msg.GetTextInsets) == "function" then
		if not mine.msgInsets then
			local ok, l, r, t, b = pcall(msg.GetTextInsets, msg)
			mine.msgInsets = (ok and { l, r, t, b }) or { 0, 0, 0, 0 }
		end
		pcall(msg.SetTextInsets, msg, MSG_TEXT_INSET_L, MSG_TEXT_INSET_R,
			MSG_TEXT_INSET_T, MSG_TEXT_INSET_B)
	end

	pcall(obj.SetMinResize, obj, boxMinWidth(), BOX_MIN_HEIGHT)
end

-- Hands msg_box's text insets back: unlike the anchors this must be undone by hand.
local function restoreBoxGeometry(obj, mine)
	local msg = obj and obj.widgets and obj.widgets.msg_box
	if not (msg and mine.msgInsets and type(msg.SetTextInsets) == "function") then
		return
	end
	local insets = mine.msgInsets
	pcall(msg.SetTextInsets, msg, insets[1], insets[2], insets[3], insets[4])
	mine.msgInsets = nil
end

-- Takes the metal down without asking WIM to repaint; used when a window is only
-- being reclassified (recycled to chat).
function unskin(obj)
	local mine = obj and obj._duiWim
	if not mine then return false end
	releaseCloseUpdate(obj)
	restoreBoxGeometry(obj, mine)
	-- Restore the original draw layer (saved in buildParts, kept for re-applies).
	if mine.iconLayer then
		local icon = obj.widgets and obj.widgets.class_icon
		if icon and icon.SetDrawLayer then icon:SetDrawLayer(mine.iconLayer) end
	end
	setShown(mine, false)
	native(obj, true)
	seen[obj] = nil
	return true
end

-- One window, one verdict: whisper windows get the frame, everything else hands it
-- back. Called from the hook on every ApplySkinToWindow, so it must be cheap and
-- idempotent -- WIM re-applies on creation, on recycling and on every skin change.
local function skin(obj)
	if not active or type(obj) ~= "table" or obj.type ~= "whisper" then
		return unskin(obj)
	end

	local mine = buildParts(obj)
	if not mine then return false end

	applyBoxGeometry(obj, mine)
	native(obj, false)
	setShown(mine, true)
	styleClose(obj, resolveAtlas())
	seen[obj] = true
	return true
end

-- Full teardown: down, then hand the window back to WIM so its real skin and close
-- button return. The hook is inert behind `active` at that point, so this only touches WIM.
local function release(obj)
	if not unskin(obj) then return false end
	local WIM = _G.WIM
	if WIM and type(WIM.ApplySkinToWindow) == "function" then
		pcall(WIM.ApplySkinToWindow, obj)
	end
	return true
end

-- WIM names its frames WIM3_msgFrame1..N and recycles them in place, so the numbering
-- stays contiguous while the frames live.
local function forEachWindow(fn)
	local i = 1
	while _G["WIM3_msgFrame" .. i] do
		fn(_G["WIM3_msgFrame" .. i])
		i = i + 1
	end
end


-- ============================================================================
-- PUBLIC API
-- ============================================================================

function DS.IsWIMLoaded()
	local WIM = _G.WIM
	return WIM ~= nil and type(WIM.ApplySkinToWindow) == "function"
end

-- Hooks WIM. Idempotent and safe before WIM exists: it reports "not ready" and the
-- watcher retries on WIM's ADDON_LOADED. One hook suffices because WIM's sources run
-- under setfenv(1, WIM) (WindowHandler.lua, Skinner.lua), so their internal calls land
-- on our wrapper.
function DS.Install(force)
	local WIM = _G.WIM
	if not WIM or type(WIM.ApplySkinToWindow) ~= "function" then return false end

	if not DS._hooked then
		DS._hooked = true
		hooksecurefunc(WIM, "ApplySkinToWindow", function(obj)
			skin(obj)
		end)
	end
	return true
end

-- True while a window still wears the frame. Core only calls uninstall on a boot where
-- the toggle is off WHEN this says yes, so an off skin never writes anything by being present.
function DS.IsWorn()
	return next(seen) ~= nil
end

-- The toggle's on path: go live first, then stamp every window in existence.
function DS.Apply()
	if not DS.Install(false) then return false end
	active = true
	forEachWindow(skin)
	return true
end

-- BOOT ONLY. Installs the hook and re-stamps whatever already exists. Never calls
-- Apply and never writes a player setting; `active` is only raised when the
-- player's own toggle says the skin is on.
function DS.Restore()
	if not DS.Install(false) then return false end
	if addon:GetSkinEnabled(SKIN_KEY) then
		active = true
		forEachWindow(skin)
	end
	return true
end

-- The toggle's off path. Goes inert first, then gives each window back to WIM.
-- The hook stays installed and does nothing from here on.
function DS.Uninstall()
	active = false
	local windows = {}
	for window in pairs(seen) do
		windows[#windows + 1] = window
	end
	for i = 1, #windows do
		release(windows[i])
	end
end


-- Puts the hook in at LOAD rather than at toggle time. Core only installs a skin when it
-- is already enabled, so a skin that ships off would have no hook until the player opens
-- the toggle -- the one moment no addon pass can re-skin the windows. The watcher below
-- goes in while the skin is still off, inert behind `active`, and touches no setting.
local function installHookAtLoad()
	if DS.Install(false) then return end
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:SetScript("OnEvent", function(self, _, loaded)
		if loaded ~= "WIM" then return end
		if DS.Install(false) then
			self:UnregisterEvent("ADDON_LOADED")
			self:SetScript("OnEvent", nil)
		end
	end)
	watcher:Hide()
end


SLASH_DUIWIM1 = "/duiwim"
SlashCmdList["DUIWIM"] = function(msg)
	if type(msg) == "string" and msg:lower():find("status") then
		DUI:Print("|cff1784d1DragonUI|r WIM status: toggle=" .. tostring(addon:GetSkinEnabled(SKIN_KEY)) ..
			" hook=" .. tostring(DS._hooked) ..
			" active=" .. tostring(active) ..
			" atlas=" .. tostring(metalAtlas ~= nil) ..
			" worn=" .. tostring(DS.IsWorn()))
		local total, skinned = 0, 0
		forEachWindow(function(obj)
			total = total + 1
			if obj._duiWim and obj._duiWim.bg:IsShown() then skinned = skinned + 1 end
		end)
		DUI:Print("  windows: " .. skinned .. "/" .. total .. " wearing the metal frame")
		return
	end

	if not DS.IsWIMLoaded() then
		DUI:Print("|cff1784d1DragonUI|r: " .. (L["WIM is not installed."] or "WIM is not installed."))
		return
	end
	if not resolveAtlas() then
		DUI:Print("|cff1784d1DragonUI|r: " ..
			(L["Could not apply the skin - DragonUI is not ready yet."] or
			 "Could not apply the skin - DragonUI is not ready yet."))
		return
	end
	if DS.Apply() then
		DUI:Print("|cff1784d1DragonUI|r: " .. (L["WIM skin applied."] or "WIM skin applied."))
	else
		DUI:Print("|cff1784d1DragonUI|r: " ..
			(L["Could not apply the skin - WIM is not ready yet."] or
			 "Could not apply the skin - WIM is not ready yet."))
	end
end


-- Core.lua owns the ADDON_LOADED / PLAYER_LOGIN wiring for every skin; the only
-- exception is the watcher above, which exists because Core does not install a
-- disabled skin. The display strings below are FUNCTIONS on purpose: this runs at
-- file load, before OnInitialize() re-points addon.L at the player's locale, so an
-- L["..."] evaluated here would freeze the load-time language.
installHookAtLoad()

addon:RegisterSkin("wim", "WIM", {
	install   = DS.Install,
	apply     = DS.Apply,
	restore   = DS.Restore,
	isWorn    = DS.IsWorn,
	uninstall = DS.Uninstall,

	label       = function() return L["WIM Skin"] end,
	desc        = function() return L["Retail metal frame for WIM whisper windows."] end,
	toggleLabel = function() return L["Enable WIM Skin"] end,
	toggleDesc  = function() return L["Enable the DragonUI skin for WIM."] end,
})
