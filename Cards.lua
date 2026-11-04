local _, GP = ...
local Cards = { count = 69 }
GP.Cards = Cards

Cards.thresholds = {5,10,15,21,26,32,38,44,50,57,63,70,77,84,91,99,107,115,123,131,140,148,158,167,176,186,196,207,218,229,240,251,263,276,288,301,314,328,342,356,371,386,402,418,435,451,469,487,505,524,543,563,584,605,627,649,672,695,719,744,770,796,823,850,879,908,938,968,1000}

function Cards.GetKills()
    if not GetPVPLifetimeStats then return nil end
    local ok, kills = pcall(GetPVPLifetimeStats)
    if not ok or (issecretvalue and issecretvalue(kills)) or type(kills) ~= "number"
        or kills ~= kills or kills == math.huge or kills == -math.huge or kills < 0 then return nil end
    return math.floor(kills)
end

function Cards.Refresh()
    if not GP.db then return end
    local kills = Cards.GetKills()
    if not kills then return end
    Cards.kills = kills
    if GP.IsEligibleGuild() then
        for index, threshold in ipairs(Cards.thresholds) do
            if kills >= threshold and not GP.db.presented[index] and not GP.db.pendingCards[index] then
                GP.db.pendingCards[index] = true
            end
        end
    end
    if GP.UI then GP.UI.Refresh(); GP.UI.ShowNextAward() end
end

function Cards.IsUnlocked(index)
    return Cards.kills ~= nil and Cards.thresholds[index] ~= nil
        and Cards.kills >= Cards.thresholds[index] and (GP.db.presented[index] == true or GP.db.pendingCards[index] == true)
end
