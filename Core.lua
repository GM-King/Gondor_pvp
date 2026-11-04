local _, GP = ...
GP.name = "Gondor PvP"
GP.guildName = "Gondor Calls for Raid"
GP.defaults = { alerts = false, offers = false, channel = "gcfrpvp", expiry = 15, reducedMotion = false }

function GP.Print(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffce75Gondor PvP|r: " .. text) end
end

function GP.Initialize()
    if type(GondorPvPCharacter) ~= "table" then GondorPvPCharacter = {} end
    local db = GondorPvPCharacter
    -- Existing beta saves are the initial schema. Preserve a later schema
    -- marker if a character loads an older addon after an upgrade.
    local version=db.schemaVersion
    if type(version)~="number" or version~=version or version<1 or version~=math.floor(version) or version==math.huge then
        db.schemaVersion=1
    end
    if type(db.settings) ~= "table" then db.settings = {} end
    for key, value in pairs(GP.defaults) do
        if db.settings[key] == nil then db.settings[key] = value end
    end
    for _, key in ipairs({"alerts","offers","reducedMotion"}) do
        if type(db.settings[key]) ~= "boolean" then db.settings[key] = GP.defaults[key] end
    end
    local channel=db.settings.channel
    if type(channel)=="string" then channel=channel:match("^%s*(.-)%s*$"); db.settings.channel=channel end
    if type(channel) ~= "string" or channel=="" or #channel>30 or channel:find("[^%w ]") then
        db.settings.channel=GP.defaults.channel
    end
    local expiry=tonumber(db.settings.expiry)
    if not expiry or expiry~=expiry or expiry<5 or expiry>60 then expiry=GP.defaults.expiry end
    db.settings.expiry=math.floor(expiry)
    local angle=db.settings.minimapAngle
    if type(angle)~="number" or angle~=angle or angle==math.huge or angle==-math.huge then db.settings.minimapAngle=215 end
    if type(db.manualReadyAt)~="number" or db.manualReadyAt~=db.manualReadyAt or db.manualReadyAt<0 or db.manualReadyAt>4102444800 then
        db.manualReadyAt=0
    end
    local sequence=tonumber(db.requestSequence)
    if not sequence or sequence~=sequence or sequence<0 or sequence>1000000000 then sequence=0 end
    db.requestSequence=math.floor(sequence)
    if type(db.presented) ~= "table" then db.presented = {} end
    if type(db.pendingCards) ~= "table" then db.pendingCards = {} end
    if type(db.receipts) ~= "table" then db.receipts = {} end
    if type(db.pairs) ~= "table" then db.pairs = {} end
    if type(db.cancelOutbox) ~= "table" then db.cancelOutbox = {} end
    for name,stamp in pairs(db.pairs) do
        if type(name)~="string" or type(stamp)~="number" or stamp~=stamp or stamp<0 or stamp>4102444800 then
            db.pairs[name]=nil
        end
    end
    GP.db = db
end

function GP.IsEligibleGuild()
    if not GetGuildInfo then return false end
    local ok, name = pcall(GetGuildInfo, "player")
    if not ok then return false end
    if issecretvalue and issecretvalue(name) then return false end
    return name == GP.guildName
end

local frame = CreateFrame("Frame")
GP.eventFrame = frame
local function scheduleCardRefresh(delay)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function() if GP.db and GP.Cards then GP.Cards.Refresh() end end)
    end
end
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_PVP_KILLS_CHANGED", "CHAT_MSG_COMBAT_HONOR_GAIN",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE"}) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    local arg = ...
    if event == "ADDON_LOADED" and arg == "Gondor_PvP" then
        GP.Initialize()
    elseif event ~= "ADDON_LOADED" and GP.db then
        if event == "PLAYER_LOGIN" then GP.Map.Initialize(); GP.Network.Initialize(); GP.UI.BuildMinimap() end
        GP.Network.OnEvent(event, ...)
        if GP.Recovery then GP.Recovery.OnEvent(event, ...) end
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_PVP_KILLS_CHANGED" or event == "CHAT_MSG_COMBAT_HONOR_GAIN" or event == "GUILD_ROSTER_UPDATE" then
            GP.Cards.Refresh()
            if event == "PLAYER_LOGIN" then
                scheduleCardRefresh(1); scheduleCardRefresh(5); scheduleCardRefresh(15); scheduleCardRefresh(30)
            elseif event == "PLAYER_PVP_KILLS_CHANGED" or event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
                scheduleCardRefresh(0.25); scheduleCardRefresh(1)
            end
        end
    end
end)
frame:SetScript("OnUpdate", function(_, elapsed)
    if GP.db and GP.Network then GP.Network.Update(elapsed) end
    if GP.db and GP.Recovery then GP.Recovery.Update(elapsed) end
end)

SLASH_GONDORPVP1 = "/gpvp"
SLASH_GONDORPVP2 = "/gondorpvp"
SlashCmdList.GONDORPVP = function(message)
    local command = (message or ""):lower():match("^%s*(%S*)")
    if command == "request" then GP.Network.Request(true)
    elseif command == "cancel" then GP.Network.CancelFare()
    elseif command == "cancelrequest" then GP.Network.CancelRequest()
    elseif command == "settings" then GP.UI.ToggleSettings()
    elseif command == "help" then GP.Print("/gpvp opens your binder. /gpvp request, cancel, cancelrequest, or settings.")
    else GP.UI.Toggle() end
end
