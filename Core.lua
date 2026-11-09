local _, GP = ...
GP.name = "Gondor PvP"
GP.guildName = "Gondor Calls For Raid"
GP.defaults = { alerts = true, offers = true, channel = "gcfrpvp", expiry = 60, reducedMotion = false }

function GP.DisplayName(name)
    if issecretvalue and issecretvalue(name) then return "Unknown" end
    return type(name)=="string" and (name:match("^[^-]+") or name) or "Unknown"
end

function GP.Print(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffce75Gondor PvP|r: " .. text) end
end

-- Shared transport for both fare and backup prefixes.
GP.Comms={blocked={},recent={},offline={}}
local C=GP.Comms
local function clock() return (GetServerTime and GetServerTime()) or time() end
local function identity(name) return type(name)=="string" and name:lower():gsub("%s+","") end
function C.Online(target)
    if not GP.IsEligibleGuild() or not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local ok,count=pcall(GetNumGuildMembers,true)
    if not ok or (issecretvalue and issecretvalue(count)) then return end
    if type(count)~="number" or count<0 or count>2000 then return end
    local found,online=0,nil
    for i=1,count do
        local ok,name,_,_,_,_,_,_,_,connected=pcall(GetGuildRosterInfo,i)
        if not ok or (issecretvalue and (issecretvalue(name) or issecretvalue(connected))) then return end
        if identity(name)==identity(target) or (type(name)=="string" and not name:find("-",1,true) and identity(name)==identity(target:match("^[^-]+"))) then
            found=found+1
            if type(connected)=="boolean" and not (issecretvalue and issecretvalue(connected)) then online=connected end
        end
    end
    if found~=1 then return end
    local key=identity(target)
    if online==false then C.offline[key]=true
    elseif online==true and C.offline[key] then C.offline[key]=nil; C.blocked[key]=nil end
    return online
end
function C.Send(prefix,payload,target)
    if not GP.IsEligibleGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    if target then
        local online=C.Online(target)
        if online~=true or C.blocked[identity(target)] then
            if (not C.refreshAt or clock()>=C.refreshAt) and C_GuildInfo and C_GuildInfo.GuildRoster then
                C.refreshAt=clock()+15; pcall(C_GuildInfo.GuildRoster)
            end
            return false
        end
    end
    local transport=target
    if target then
        local name,realm=target:match("^(.*)%-([^%-]+)$")
        for _,fn in ipairs({GetNormalizedRealmName or false,GetRealmName or false}) do
            if type(fn)=="function" then
                local ok,own=pcall(fn)
                if ok and name and identity(own)==identity(realm) then transport=name end
            end
        end
        C.recent[identity(target)]={name=transport,at=clock()}
    end
    local ok,result=pcall(C_ChatInfo.SendAddonMessage,prefix,payload,target and "WHISPER" or "GUILD",transport)
    if ok and not (issecretvalue and issecretvalue(result)) and target and Enum and Enum.SendAddonMessageResult
        and Enum.SendAddonMessageResult.InvalidTarget and result==Enum.SendAddonMessageResult.InvalidTarget then C.blocked[identity(target)]=true end
    return ok and not (issecretvalue and issecretvalue(result)) and (result==nil or result==true or result==0)
end
function C.OnEvent(event,...)
    if event=="CHAT_MSG_SYSTEM" then
        local message=...
        if type(message)~="string" or not ERR_CHAT_PLAYER_NOT_FOUND_S then return end
        for key,entry in pairs(C.recent) do
            if clock()-entry.at<=5 and message==string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,entry.name) then C.blocked[key]=true end
        end
    elseif event=="CHAT_MSG_ADDON" then
        local prefix,_,_,sender=...
        if (prefix=="GONDPVP1" or prefix=="GONDPVPBACK1") and type(sender)=="string" then
            for key in pairs(C.blocked) do
                if key==identity(sender) then C.blocked[key]=nil end
            end
        end
    end
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
    if db.offerExpiryDefaultsVersion==nil then
        if tonumber(db.settings.expiry)==15 then db.settings.expiry=60 end
        db.offerExpiryDefaultsVersion=1
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
    local position=db.settings.awardPosition
    if type(position)~="table" or type(position.x)~="number" or type(position.y)~="number"
        or position.x~=position.x or position.y~=position.y or position.x<0 or position.x>1 or position.y<0 or position.y>1 then
        db.settings.awardPosition={x=0.8,y=0.6}
    end
    GP.db = db
end

function GP.MatchesGuild(name)
    if issecretvalue and issecretvalue(name) then return false end
    return type(name)=="string" and name:lower()==GP.guildName:lower()
end

function GP.GetPlayerGuild()
    if type(GetGuildInfo)~="function" then return nil,"unavailable" end
    local ok,name=pcall(GetGuildInfo,"player")
    if not ok then return nil,"unavailable" end
    if issecretvalue and issecretvalue(name) then return nil,"restricted" end
    if type(name)~="string" or name=="" then return nil,"unavailable" end
    return name
end

function GP.IsEligibleGuild()
    return GP.MatchesGuild(GP.GetPlayerGuild())
end

local frame = CreateFrame("Frame")
GP.eventFrame = frame
local function scheduleCardRefresh(delay)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function() if GP.db and GP.Cards then GP.Cards.Refresh() end end)
    end
end
for _, event in ipairs({"PLAYER_LOGOUT", "CHAT_MSG_SYSTEM", "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_PVP_KILLS_CHANGED", "CHAT_MSG_COMBAT_HONOR_GAIN",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE"}) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    local arg = ...
    if event == "ADDON_LOADED" and arg == "Gondor_PvP" then
        GP.Initialize()
    elseif event ~= "ADDON_LOADED" and GP.db then
        if event == "PLAYER_LOGIN" then GP.Map.Initialize(); GP.Network.Initialize(); GP.UI.BuildMinimap() end
        GP.Comms.OnEvent(event, ...)
        if GP.UI.OnEvent then GP.UI.OnEvent(event) end
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
    elseif command == "status" then GP.Network.PrintStatus()
    elseif command == "retry" then GP.Network.RetryAnnouncement()
    elseif command == "cancel" then GP.Network.CancelFare()
    elseif command == "cancelrequest" then GP.Network.CancelRequest()
    elseif command == "settings" then GP.UI.ToggleSettings()
    elseif command == "help" then GP.Print("/gpvp opens your binder. /gpvp request, retry, status, cancel, cancelrequest, or settings.")
    else GP.UI.Toggle() end
end

-- Reloads preserve fares; ordinary shutdowns withdraw them.
if hooksecurefunc then
    local function reload() GP.reloading=true end
    if type(ReloadUI)=="function" then pcall(hooksecurefunc,"ReloadUI",reload) end
    if C_UI and type(C_UI.Reload)=="function" then pcall(hooksecurefunc,C_UI,"Reload",reload) end
    for _,name in ipairs({"Logout","Quit"}) do
        if type(_G[name])=="function" then pcall(hooksecurefunc,name,function() GP.logoutPending=true end) end
    end
    if type(CancelLogout)=="function" then pcall(hooksecurefunc,"CancelLogout",function() GP.logoutPending=nil end) end
end
