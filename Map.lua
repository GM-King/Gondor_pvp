local _, GP = ...
local M = {}
GP.Map = M
local function clean(v) return not (issecretvalue and issecretvalue(v)) end

function M.Initialize()
    M.hbd = LibStub and LibStub("HereBeDragonsGondorPvP-2.0", true)
    M.pins = LibStub and LibStub("HereBeDragonsGondorPvP-Pins-2.0", true)
    if M.pins and M.pins.worldmapProviderPin then M.pins.worldmapProviderPin.GetCenter = function() return nil end end
end

function M.Position()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not clean(map) or type(map)~="number" or map~=map or map<1 or map>100000 or map~=math.floor(map) then return end
    local positionOK, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not positionOK or not clean(pos) or not pos then return end
    if type(pos.GetXY) ~= "function" then return end
    local coordinatesOK, x, y = pcall(pos.GetXY, pos)
    if not coordinatesOK then return end
    if not clean(x) or not clean(y) or type(x) ~= "number" or type(y) ~= "number" or x~=x or y~=y or x < 0 or x > 1 or y < 0 or y > 1 then return end
    return map, x, y
end

function M.World(map, x, y)
    if not M.hbd or not clean(map) or not clean(x) or not clean(y) or type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return end
    local ok, wx, wy, instance = pcall(M.hbd.GetWorldCoordinatesFromZone, M.hbd, x, y, map)
    if ok and clean(wx) and clean(wy) and clean(instance) and type(wx) == "number" and type(wy) == "number" and type(instance) == "number"
        and wx==wx and wy==wy and wx~=math.huge and wx~=-math.huge and wy~=math.huge and wy~=-math.huge
        and instance==instance and instance~=math.huge and instance~=-math.huge then
        return wx, wy, instance
    end
end

function M.Quote(aMap, ax, ay, bMap, bx, by)
    local x1, y1, i1 = M.World(aMap, ax, ay)
    local x2, y2, i2 = M.World(bMap, bx, by)
    if not x1 or not x2 then return end
    if i1 ~= i2 then return GP.Fares.Quote(false, false) end
    local distance = ((x1-x2)^2 + (y1-y2)^2)^0.5
    return GP.Fares.Quote(aMap == bMap, true, distance)
end

function M.Clear()
    if M.pins then
        M.pins:RemoveAllWorldMapIcons(GP)
        M.pins:RemoveAllMinimapIcons(GP)
    end
    if M.worldIcon then M.worldIcon:Hide() end
    if M.miniIcon then M.miniIcon:Hide() end
end

local function icon()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(22,22)
    local t = f:CreateTexture(nil, "ARTWORK"); t:SetAllPoints()
    t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    return f
end

function M.Set(map, x, y)
    M.Clear()
    if not M.pins or not map or not x or not y then return end
    M.worldIcon = M.worldIcon or icon(); M.miniIcon = M.miniIcon or icon()
    M.worldIcon:Show(); M.miniIcon:Show()
    M.pins:AddWorldMapIconMap(GP, M.worldIcon, map, x, y, HBD_PINS_WORLDMAP_SHOW_WORLD)
    M.pins:AddMinimapIconMap(GP, M.miniIcon, map, x, y, true, false)
end
