-- ============================================================================
-- DragonUI_AddOnSkins - Atlas Definitions
-- Texture atlas lookup table mapping sprite names to texture coordinates.
-- ============================================================================

local addon = select(2,...);
addon._dir = addon._dir or "Interface\\AddOns\\DragonUI_AddOnSkins\\Textures\\"
local assets = addon._dir;
local unpack = unpack;
local rui_DamageMeters = assets..'Details\\uidamagemeters';

addon.atlasinfo = {
	['damagemeters-background'] = { rui_DamageMeters, 154, 148, 0.001953, 0.302734, 0.003906, 0.582031 },
	['ui-damagemeters-bar-shadowbg'] = { rui_DamageMeters, 128, 14, 0.427734, 0.677734, 0.121094, 0.175781 },
	['ui-damagemeters-bar-shadowedge'] = { rui_DamageMeters, 128, 14, 0.681641, 0.931641, 0.121094, 0.175781 },
	['ui-damagemeters-header-bar'] = { rui_DamageMeters, 263, 28, 0.306641, 0.820313, 0.003906, 0.113281 },
	['ui-hud-cooldownmanager-bar'] = { rui_DamageMeters, 124, 10, 0.4375, 0.679688, 0.195313, 0.234375 },
};

local C_Texture = {};
local CONST_ATLAS_TEXTUREPATH	= 1
local CONST_ATLAS_WIDTH			= 2
local CONST_ATLAS_HEIGHT		= 3
local CONST_ATLAS_LEFT			= 4
local CONST_ATLAS_RIGHT			= 5
local CONST_ATLAS_TOP			= 6
local CONST_ATLAS_BOTTOM		= 7
local CONST_ATLAS_TILESHORIZ	= 8
local CONST_ATLAS_TILESVERT		= 9

function C_Texture.GetAtlasInfo(atlas)
	assert(atlas, 'C_Texture.GetAtlasInfo: atlas must be specified');
	assert(addon.atlasinfo[atlas], 'C_Texture.GetAtlasInfo: atlas [ '..atlas..' ] does not exist');

	local atlas = addon.atlasinfo[atlas];
	local AtlasInfo = {};

	AtlasInfo.filename 			= atlas[CONST_ATLAS_TEXTUREPATH];
	AtlasInfo.width 			= atlas[CONST_ATLAS_WIDTH];
	AtlasInfo.height 			= atlas[CONST_ATLAS_HEIGHT];
	AtlasInfo.leftTexCoord 		= atlas[CONST_ATLAS_LEFT];
	AtlasInfo.rightTexCoord 	= atlas[CONST_ATLAS_RIGHT];
	AtlasInfo.topTexCoord 		= atlas[CONST_ATLAS_TOP];
	AtlasInfo.bottomTexCoord 	= atlas[CONST_ATLAS_BOTTOM];
	AtlasInfo.tilesHorizontally = atlas[CONST_ATLAS_TILESHORIZ];
	AtlasInfo.tilesVertically 	= atlas[CONST_ATLAS_TILESVERT];

	return AtlasInfo;
end

function C_Texture.GetFinalNameFromTextureKit(fmt, textureKits)
	if type(textureKits) == 'table' then
		return fmt:format(unpack(textureKits));
	else
		return fmt:format(textureKits);
	end
end
addon.c_texture = C_Texture;