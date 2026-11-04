local _, GP = ...
local F = {}
GP.Fares = F

-- Distances supplied here are straight-line yards, measured at acceptance.
function F.Quote(sameZone, sameContinent, distance)
    if sameContinent == false then return 50 end
    if sameContinent ~= true or type(distance) ~= "number" or distance < 0 or distance ~= distance then return nil end
    if sameZone then return math.min(20, 10 + math.floor(distance / 200)) end
    return math.min(49, 21 + math.floor(distance / 500))
end

function F.WithinMeetingDistance(x1, y1, z1, x2, y2, z2)
    if type(x1) ~= "number" or type(y1) ~= "number" or type(z1) ~= "number"
        or type(x2) ~= "number" or type(y2) ~= "number" or type(z2) ~= "number" then return false end
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return dx * dx + dy * dy + dz * dz <= (5 / 3) ^ 2
end

function F.ReduceManualCooldown(readyAt, now)
    return math.max(now, (readyAt or now) - 300)
end

function F.PairEligible(lastCompleted, now)
    return not lastCompleted or now - lastCompleted >= 600
end
