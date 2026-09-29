-- DragonUI_AddOnSkins - utils/frame.lua
-- Discovery helpers for frames a third-party addon builds dynamically without
-- giving them a global name. Instead of looking them up by name, a skin can
-- match them by the geometry the WoW frame API exposes: anchor point, size, or
-- the object types of their children.
--
-- Built on the documented frame API (GetChildren, GetPoint, GetWidth/GetHeight,
-- EnumerateFrames). No skin consumes these yet; they are addon-agnostic
-- infrastructure kept ready for the next target.

local ADDON_NAME, addon = ...

local ipairs = ipairs
local select = select
local type = type
local floor = math.floor

local EnumerateFrames = EnumerateFrames

-- Widths, heights and point offsets come back as floats. Every comparison in
-- this file is made on whole pixels, so callers can pass either 40 or 40.4.
local function toPixels(value)
    return floor((tonumber(value) or 0) + 0.5)
end

-- A frame with no global name and, when `wantedType` is given, of that widget
-- type. Unnamed frames are exactly what these helpers exist to find.
local function isUnnamed(child, wantedType)
    return child:GetName() == nil
        and (wantedType == nil or child:IsObjectType(wantedType))
end

-- The children of `parent` as a plain 1..n array.
local function childrenOf(parent)
    return { parent:GetChildren() }
end

-- Returns the child at 1-based `index`; a negative index counts back from the
-- end (-1 is the last child). Returns nil when the index is out of range.
function addon:GetChildAt(parent, index)
    if not parent or index == nil then return nil end

    local total = parent:GetNumChildren()
    local position = index < 0 and (total + index + 1) or index
    if position < 1 or position > total then return nil end

    return select(position, parent:GetChildren())
end

-- First unnamed child (optionally of `objType`) anchored at exactly
-- (point1, relativeTo, point2, x, y). Also returns that child's index.
function addon:FindChildAtAnchor(parent, objType, point1, relativeTo, point2, x, y)
    if not parent then return nil end

    local wantX, wantY = toPixels(x), toPixels(y)

    for index, child in ipairs(childrenOf(parent)) do
        if isUnnamed(child, objType) then
            local anchor, target, targetPoint, offX, offY = child:GetPoint(1)
            if anchor == point1
                and target == relativeTo
                and (point2 == nil or targetPoint == point2)
                and toPixels(offX) == wantX
                and toPixels(offY) == wantY then
                return child, index
            end
        end
    end

    return nil
end

-- First unnamed child (optionally of `objType`) whose width and height both
-- round to the requested values. Also returns that child's index.
function addon:FindChildBySize(parent, objType, width, height)
    if not parent then return nil end

    local wantW, wantH = toPixels(width), toPixels(height)

    for index, child in ipairs(childrenOf(parent)) do
        if isUnnamed(child, objType)
            and toPixels(child:GetWidth()) == wantW
            and toPixels(child:GetHeight()) == wantH then
            return child, index
        end
    end

    return nil
end

-- Scans every frame on screen for a top-level, unnamed window of the given
-- size whose children include every object type in `childTypes`. A single type
-- string counts as a one-element requirement list.
function addon:FindWindowBySizeAndChildren(childTypes, width, height)
    if childTypes == nil then return nil end

    local required = type(childTypes) == "table" and childTypes or { childTypes }
    local wantW, wantH = toPixels(width), toPixels(height)

    local frame = EnumerateFrames()
    while frame do
        local isWindow = frame.IsObjectType and frame:IsObjectType("Frame")
        local isTopLevel = not (frame:GetName() and frame:GetParent())

        if isWindow and isTopLevel
            and toPixels(frame:GetWidth()) == wantW
            and toPixels(frame:GetHeight()) == wantH then
            local kinds = {}
            for _, child in ipairs({ frame:GetChildren() }) do
                kinds[child:GetObjectType()] = true
            end

            local complete = true
            for _, wanted in ipairs(required) do
                if not kinds[wanted] then
                    complete = false
                    break
                end
            end

            if complete then return frame end
        end

        frame = EnumerateFrames(frame)
    end

    return nil
end

-- Scans every frame on screen for top-level, unnamed windows anchored at
-- exactly (point1, relativeTo, point2, x, y). Returns the first match, or an
-- array of all matches when `multiple` is true (an empty array when there are
-- none).
function addon:FindWindowAtAnchor(point1, relativeTo, point2, x, y, multiple)
    if not relativeTo then
        return multiple and {} or nil
    end

    local wantX, wantY = toPixels(x), toPixels(y)
    local matches = multiple and {} or nil

    local frame = EnumerateFrames()
    while frame do
        local isWindow = frame.IsObjectType and frame:IsObjectType("Frame")
        local isTopLevel = not (frame:GetName() and frame:GetParent())

        if isWindow and isTopLevel then
            local anchor, target, targetPoint, offX, offY = frame:GetPoint(1)
            if anchor == point1
                and target == relativeTo
                and (point2 == nil or targetPoint == point2)
                and toPixels(offX) == wantX
                and toPixels(offY) == wantY then
                if multiple then
                    matches[#matches + 1] = frame
                else
                    return frame
                end
            end
        end

        frame = EnumerateFrames(frame)
    end

    return matches
end
