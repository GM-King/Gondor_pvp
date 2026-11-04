local _, GP = ...
local N = { offers = {}, elapsed = 0, sequence = 0, peers = {}, buffered = {}, seenRequests = {} }
GP.Network = N
local prefix = "GONDPVP1"
local function clean(v) return not (issecretvalue and issecretvalue(v)) end
local function safe2(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b=pcall(fn,...)
    if ok then return a,b end
end
function N.InInstance()
    if type(IsInInstance)~="function" then return false end
    local inside,kind=safe2(IsInInstance)
    if not clean(inside) or not clean(kind) then return true end
    return inside~=false or (kind~=nil and kind~="none")
end
local function now()
    local value=safe2(GetServerTime)
    if clean(value) and type(value)=="number" then return value end
    value=safe2(time)
    return clean(value) and type(value)=="number" and value or 0
end
local function number(v, min, max)
    local n = tonumber(v)
    if not n or n ~= n or n < min or n > max then return end
    return n
end
local function parseRevision(value)
    if value==nil or value=="" then return nil,true end
    local revision=number(value,1,1000000000)
    if not revision or revision~=math.floor(revision) then return nil,false end
    return revision,true
end
local function revisionFields(fields,revision)
    if revision then fields[#fields+1]=tostring(revision) end
    return fields
end
local function fullKey(name)
    if not clean(name) or type(name)~="string" then return end
    return name:lower():gsub("%s+", "")
end
local function key(name) return fullKey(name) end
local function shortKey(name)
    local full=fullKey(name)
    return full and full:gsub("%-.+$", "")
end
local function localRealm()
    local realm=safe2(GetNormalizedRealmName)
    if not clean(realm) or type(realm)~="string" or realm=="" then realm=safe2(GetRealmName) end
    if clean(realm) and type(realm)=="string" and realm~="" then return realm end
end
local function canonicalName(name)
    local full=fullKey(name)
    if not full then return end
    if full:find("-",1,true) then return name end
    local realm=localRealm()
    return realm and (name.."-"..realm) or name
end
local function selfName()
    local name, realm
    if UnitFullName then name, realm = safe2(UnitFullName,"player")
    elseif UnitName then name, realm = safe2(UnitName,"player") end
    if not clean(name) or type(name)~="string" then return "" end
    if not clean(realm) or type(realm)~="string" or realm=="" then
        realm=localRealm()
    end
    if clean(realm) and type(realm)=="string" and realm~="" then return name.."-"..realm end
    return name
end
local function same(a,b)
    local x,y=fullKey(a),fullKey(b)
    if not x or not y then return false end
    if x:find("-",1,true) and y:find("-",1,true) then return x==y end
    return shortKey(a)==shortKey(b)
end
local function split(s)
    local t = {}
    if not clean(s) or type(s) ~= "string" or #s > 240 then return t end
    for part in (s .. "~"):gmatch("(.-)~") do t[#t+1] = part end
    return t
end
local function send(kind, parts, target)
    if N.InInstance() and kind~="X" and kind~="Z" and kind~="K" then return false end
    if not GP.IsEligibleGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    local payload = kind .. "~" .. table.concat(parts, "~")
    if #payload > 240 then return false end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, payload, target and "WHISPER" or "GUILD", target)
    if not ok or not clean(result) then return false end
    -- Modern clients return an enum (zero is Success); older clients may
    -- return true or no value. Nonzero enum values include throttling,
    -- unavailable targets, and communication lockdown.
    return result == 0 or result == true or result == nil
end
local function rosterMember(sender)
    if not GP.IsEligibleGuild() or not sender or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    local expected = shortKey(sender)
    local senderFull = fullKey(sender)
    if not expected then return false end
    local count=safe2(GetNumGuildMembers,true)
    if not clean(count) or type(count)~="number" or count<0 then return end
    local found, resolved = 0, nil
    for i = 1, count do
        local name = safe2(GetGuildRosterInfo,i)
        local candidate=fullKey(canonicalName(name))
        if candidate and shortKey(name)==expected then
            if senderFull:find("-",1,true) then
                if candidate==senderFull then found=found+1; resolved=canonicalName(name) end
            else found=found+1; resolved=name end
        end
    end
    return found == 1 and canonicalName(resolved) or nil
end
local function chat(text)
    local setting = GP.db.settings.channel or "gcfrpvp"
    local kind, target = "CHANNEL", nil
    local upper = setting:upper()
    if upper == "GUILD" or upper == "PARTY" or upper == "RAID" then kind = upper
    else
        if JoinPermanentChannel then pcall(JoinPermanentChannel, setting) end
        target = safe2(GetChannelName,setting)
        if not target or target == 0 then GP.Print("Channel unavailable: " .. setting); return false end
    end
    local fn = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if not fn then GP.Print("Chat sending is unavailable."); return false end
    local ok = pcall(fn, text, kind, nil, target)
    if not ok then GP.Print("Could not send the announcement in " .. setting .. ".") end
    return ok
end
local function zone(map)
    local info = C_Map and safe2(C_Map.GetMapInfo,map)
    if not clean(info) or not info then return "Unknown zone" end
    local name=info.name
    return clean(name) and type(name)=="string" and name or "Unknown zone"
end
local function showDeferredOffers()
    if N.InInstance() then return end
    if N.active or not GP.db.settings.offers then return end
    for token,offer in pairs(N.offers) do
        if offer.deferred then
            offer.deferred=nil
            if now()<offer.expires then
                local map,x,y=GP.Map.Position()
                offer.quote=map and GP.Map.Quote(map,x,y,offer.map,offer.x,offer.y) or nil
                local previous=GP.db.pairs[key(offer.sender)] or GP.db.pairs[shortKey(offer.sender)]
                if offer.quote and not GP.Fares.PairEligible(previous,now()) then offer.quote=0 end
                if GP.UI.ShowOffer then GP.UI.ShowOffer(token,offer,zone(offer.map)) end
            else N.offers[token]=nil end
        end
    end
end
local function positionFields()
    local map, x, y = GP.Map.Position()
    if not map then return end
    return tostring(map), string.format("%.7f",x), string.format("%.7f",y)
end
local function position(parts, offset)
    local map = number(parts[offset], 1, 100000)
    local x, y = number(parts[offset+1], 0, 1), number(parts[offset+2], 0, 1)
    if map and map==math.floor(map) and x and y then return map,x,y end
end
local function alive()
    if not UnitIsDeadOrGhost then return false end
    local ok, dead = pcall(UnitIsDeadOrGhost,"player")
    return ok and clean(dead) and not dead
end
local function rosterGUID(name)
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local count=safe2(GetNumGuildMembers,true)
    if not clean(count) or type(count)~="number" or count<0 then return end
    for i=1,count do
        local data={pcall(GetGuildRosterInfo,i)}
        if data[1] and fullKey(canonicalName(data[2]))==fullKey(canonicalName(name)) then
            local guid=data[18]
            if clean(guid) and type(guid)=="string" and guid~="" then return guid end
        end
    end
end
local function visible(name)
    local function matches(unit)
        if not UnitExists or not UnitName then return false end
        local existsOK,exists=pcall(UnitExists,unit)
        if not existsOK or not clean(exists) or not exists then return false end
        local nameOK,n,realm = pcall(UnitName,unit)
        if not nameOK then return false end
        if clean(realm) and type(realm)=="string" and realm~="" and clean(n) and type(n)=="string" then n=n.."-"..realm end
        if not same(n, name) then return false end
        local expected=rosterGUID(name)
        local ok, actual = false, nil
        if UnitGUID then ok,actual=pcall(UnitGUID,unit) end
        if not clean(actual) then return false end
        if expected and ok and type(actual)=="string" and actual~="" then
            if actual~=expected then return false end
        elseif not fullKey(n):find("-",1,true) then
            -- An unqualified nearby name is safe only if it resolves uniquely.
            local resolved=rosterMember(n)
            if not resolved or not same(resolved,name) then return false end
        end
        if UnitIsVisible then local ok,v=pcall(UnitIsVisible,unit); if not ok or not clean(v) or not v then return false end end
        if UnitInPhase then local ok,v=pcall(UnitInPhase,unit); if not ok or not clean(v) or not v then return false end end
        if UnitIsDeadOrGhost then local ok,v=pcall(UnitIsDeadOrGhost,unit); if not ok or not clean(v) or v then return false end end
        return true
    end
    if matches("target") then return "target" end
    for i = 1, 40 do
        if matches("nameplate" .. i) then return "nameplate" .. i end
        if matches("raid" .. i) then return "raid" .. i end
    end
    for i = 1, 4 do if matches("party" .. i) then return "party" .. i end end
    return false
end
local function distance(map1,x1,y1,map2,x2,y2)
    local a,b,i = GP.Map.World(map1,x1,y1)
    local c,d,j = GP.Map.World(map2,x2,y2)
    if not a or not c or i ~= j then return end
    return ((a-c)^2+(b-d)^2)^0.5
end
local function within(map,x,y,name)
    local own, ox, oy = GP.Map.Position()
    if not own then return false end
    local dist = distance(own,ox,oy,map,x,y)
    local unit=visible(name)
    if not dist or dist > 5/3 or not unit then return false end
    if UnitDistanceSquared then
        local ok, squared, checked = pcall(UnitDistanceSquared,unit)
        if ok and clean(squared) and clean(checked) and checked and type(squared)=="number" and squared>=0 then
            return squared <= (5/3)^2
        end
    end
    if not UnitPosition then return false end
    local ok1,a,b,c,i = pcall(UnitPosition,"player")
    local ok2,d,e,f,j = pcall(UnitPosition,unit)
    if not ok1 or not ok2 then return false end
    if not clean(a) or not clean(b) or not clean(c) or not clean(i) or not clean(d) or not clean(e) or not clean(f) or not clean(j)
        or type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" or type(d) ~= "number" or type(e) ~= "number" or type(f) ~= "number" or not i or i ~= j then return false end
    return GP.Fares.WithinMeetingDistance(a,b,c,d,e,f)
end
local function receipt(id, requester, amount)
    if GP.db.receipts[id] then return false end
    local previous=GP.db.pairs[key(requester)] or GP.db.pairs[shortKey(requester)]
    if not GP.Fares.PairEligible(previous, now()) then amount = 0 end
    GP.db.receipts[id] = { requester=requester, amount=amount, time=now() }
    if GP.Recovery then GP.Recovery.BackupReceipt(id,GP.db.receipts[id]) end
    if amount > 0 then GP.db.pairs[key(requester)] = now() end
    GP.Print("Kill Share completed: +" .. amount .. " PvP Points.")
    if GP.UI then GP.UI.Refresh() end
    return true
end
function N.ValidReceipt(record)
    return type(record)=="table" and type(record.requester)=="string" and record.requester~=""
        and type(record.time)=="number" and record.time==record.time and record.time>=0 and record.time<=4102444800
        and type(record.amount)=="number" and record.amount>=0 and record.amount<=50 and record.amount==math.floor(record.amount)
end
local function acknowledgeReceipt(sender,id,revision,amount)
    local suffix=revision and (":"..revision) or ""
    local current=GP.db.receipts[key(sender)..":"..id..suffix]
    local legacy=GP.db.receipts[shortKey(sender)..":"..id..suffix]
    if (N.ValidReceipt(current) and current.amount==amount) or (N.ValidReceipt(legacy) and legacy.amount==amount) then
        send("K",revisionFields({id},revision),sender)
        return true
    end
    return false
end
function N.Points()
    local sum = 0
    for _, record in pairs(GP.db and GP.db.receipts or {}) do
        if N.ValidReceipt(record) then sum = sum + record.amount end
    end
    return sum
end
local function validId(id)
    return type(id)=="string" and #id<=40 and id:match("^%d+%-%d+$")~=nil
end
local function validPosition(map,x,y)
    return type(map)=="number" and map==math.floor(map) and map>=1 and map<=100000
        and type(x)=="number" and x==x and x>=0 and x<=1
        and type(y)=="number" and y==y and y>=0 and y<=1
end
local function validAmount(value)
    return type(value)=="number" and value>=0 and value<=50 and value==math.floor(value)
end
function N.Initialize()
    N.initialized=true
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix) end
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    local channel=GP.db.settings.channel
    if type(channel)=="string" and channel~="" and channel:upper()~="GUILD" and channel:upper()~="PARTY" and channel:upper()~="RAID" and JoinPermanentChannel then
        pcall(JoinPermanentChannel,channel)
    end
    local dead = safe2(UnitIsDeadOrGhost,"player")
    N.wasDead = clean(dead) and dead or false
    N.active=nil; N.request=nil
    for id,entry in pairs(GP.db.cancelOutbox) do
        local revision,revisionValid
        if type(entry)=="table" then revision,revisionValid=parseRevision(entry.revision and tostring(entry.revision) or nil) end
        if type(id)~="string" or type(entry)~="table" or type(entry.peer)~="string" or entry.peer=="" or #entry.peer>100
            or entry.peer:find("[|~]") or not validId(entry.id) or not revisionValid
            or (entry.role~="H" and entry.role~="R") or type(entry.expires)~="number"
            or entry.expires~=entry.expires or entry.expires<0 or entry.expires>4102444800
            or id~=key(entry.peer).."|"..entry.id.."|"..(revision and tostring(revision) or "0").."|"..entry.role then
            GP.db.cancelOutbox[id]=nil
        else
            entry.revision=revision
            if type(entry.nextAt)~="number" or entry.nextAt~=entry.nextAt or entry.nextAt<0 or entry.nextAt>4102444800 then entry.nextAt=0 end
        end
    end
    local fare=GP.db.activeFare
    if type(fare)=="table" and validId(fare.id) and type(fare.requester)=="string" and fare.requester~=""
        and validPosition(fare.map,fare.x,fare.y) and validAmount(fare.amount) then
        N.active = GP.db.activeFare; N.active.confirmedAt = nil; N.active.acceptedAt = nil
        if type(N.active.revision)~="number" or N.active.revision<1 or N.active.revision>1000000000
            or N.active.revision~=math.floor(N.active.revision) then N.active.revision=nil end
        if type(N.active.started)~="number" or N.active.started~=N.active.started or N.active.started<0 or N.active.started>4102444800 then N.active.started=now() end
        if not validPosition(N.active.originMap,N.active.originX,N.active.originY) then
            N.active.originMap=nil; N.active.originX=nil; N.active.originY=nil
        end
        if N.active.map and N.active.x and N.active.y then GP.Map.Set(N.active.map,N.active.x,N.active.y) end
    elseif fare~=nil then
        GP.db.activeFare=nil; GP.Print("A saved fare could not be restored.")
    end
    local request=GP.db.outgoingRequest
    if type(request)=="table" and validId(request.id) and validPosition(request.map,request.x,request.y)
        and type(request.created)=="number" and request.created>=0 and request.created<=4102444800 and type(request.helpers)=="table" then
        if type(request.revisions)~="table" then request.revisions={} end
        if type(request.finished)~="table" then request.finished={} end
        if type(request.cancelled)~="table" then request.cancelled={} end
        for revision,snapshot in pairs(request.revisions) do
            if type(revision)~="string" or not revision:match("^%d+$") or type(snapshot)~="table"
                or not validPosition(snapshot.map,snapshot.x,snapshot.y) or type(snapshot.created)~="number"
                or snapshot.created~=snapshot.created or snapshot.created<0 or snapshot.created>4102444800 then
                request.revisions[revision]=nil
            end
        end
        for peer,value in pairs(request.finished) do
            if value==true then value=0; request.finished[peer]=0 end
            if type(peer)~="string" or type(value)~="number" or value<0 or value>1000000000 or value~=math.floor(value) then request.finished[peer]=nil end
        end
        for peer,value in pairs(request.cancelled) do
            if type(peer)~="string" or type(value)~="number" or value<0 or value>1000000000 or value~=math.floor(value) then request.cancelled[peer]=nil end
        end
        for peer,helper in pairs(request.helpers) do
            if type(peer)~="string" or type(helper)~="table" or type(helper.name)~="string" or helper.name=="" or not validAmount(helper.amount) then
                request.helpers[peer]=nil
            else
                if type(helper.completedAt)~="number" or helper.completedAt~=helper.completedAt or helper.completedAt<0 or helper.completedAt>4102444800 then helper.completedAt=nil end
                if type(helper.lastD)~="number" or helper.lastD~=helper.lastD or helper.lastD<0 or helper.lastD>4102444800 then helper.lastD=nil end
                if helper.revision~=nil then
                    local revision,valid=parseRevision(tostring(helper.revision))
                    if valid then helper.revision=revision else request.helpers[peer]=nil end
                end
                local pos=helper.position
                if type(pos)~="table" or not validPosition(pos[1],pos[2],pos[3]) or type(pos.at)~="number" or type(pos.alive)~="boolean" then helper.position=nil end
            end
        end
        N.request=request
    elseif request~=nil then
        GP.db.outgoingRequest=nil; GP.Print("A saved request could not be restored.")
    end
    N.CheckInstance()
end
function N.Request(manual, death)
    if N.InInstance() then GP.Print("Kill Share is disabled in instances."); return false end
    if not GP.IsEligibleGuild() then GP.Print("Kill Share is available to Gondor Calls for Raid members."); return false end
    if manual and now() < (GP.db.manualReadyAt or 0) then GP.Print("Request available in " .. math.ceil(((GP.db.manualReadyAt or 0)-now())/60) .. " min."); return false end
    local map, x, y
    if death then
        if not N.deathPosition then GP.Print("The death location was unavailable; no coordinates were announced."); return false end
        map,x,y=unpack(N.deathPosition)
    else map,x,y=GP.Map.Position() end
    if not map then GP.Print("Your map position is unavailable. Try again outdoors."); return false end
    -- The same quantized destination is sent to helpers and retained for
    -- requester-side quote verification at reward-band boundaries.
    x=tonumber(string.format("%.7f",x)); y=tonumber(string.format("%.7f",y))
    if N.request and not next(N.request.helpers) and now() - (N.request.created or 0) > 65 then
        N.request=nil; GP.db.outgoingRequest=nil
    end
    GP.db.requestSequence = ((tonumber(GP.db.requestSequence) or 0) % 1000000000) + 1
    N.sequence = GP.db.requestSequence
    local id = N.request and N.request.id or (tostring(now()) .. "-" .. tostring(N.sequence))
    local race = safe2(UnitRace,"player")
    local class = safe2(UnitClass,"player")
    if not clean(race) or type(race) ~= "string" then race = "Unknown" end
    if not clean(class) or type(class) ~= "string" then class = "Unknown" end
    local previous=N.request
    if not N.request then N.request = { id=id, map=map, x=x, y=y, helpers={}, revisions={}, finished={}, cancelled={}, created=now() } end
    local created=now()
    local payload = {id,tostring(map),string.format("%.7f",x),string.format("%.7f",y),race,class,tostring(created),tostring(N.sequence)}
    local action = death and "was killed in PvP" or "needs PvP help"
    local announcement=string.format("[Gondor PvP] %s %s in %s (%.1f, %.1f).",selfName(),action,zone(map),100*x,100*y)
    if not send("R",payload) then
        N.request=previous
        local announced=chat(announcement)
        if manual and announced then GP.db.manualReadyAt=now()+600 end
        GP.Print("Addon messaging is unavailable; automatic Kill Share offers could not be sent.")
        return false
    end
    N.request.map,N.request.x,N.request.y,N.request.created=map,x,y,created
    N.request.revisions=N.request.revisions or {}
    N.request.finished=N.request.finished or {}
    N.request.cancelled=N.request.cancelled or {}
    for revision,snapshot in pairs(N.request.revisions) do
        if created-snapshot.created>65 then N.request.revisions[revision]=nil end
    end
    N.request.revisions[tostring(N.sequence)]={map=map,x=x,y=y,created=created}
    GP.db.outgoingRequest = N.request
    chat(announcement)
    if manual then GP.db.manualReadyAt = now()+600 end
    return true
end
function N.Accept(id)
    if N.InInstance() then GP.Print("Kill Share is disabled in instances."); return false end
    if N.active then GP.Print("Cancel or complete your current fare first."); return false end
    local offer = N.offers[id]
    if not offer or now() >= offer.expires then GP.Print("That request has expired."); return false end
    if not rosterMember(offer.sender) then
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        GP.Print("The requester could not be verified in the guild roster. Please try again.")
        return false
    end
    local map,x,y=GP.Map.Position()
    if not map then GP.Print("Your location is unavailable."); return false end
    -- Quote from the exact origin the requester will receive, not a more
    -- precise local value that can fall on the other side of a point band.
    x=tonumber(string.format("%.7f",x)); y=tonumber(string.format("%.7f",y))
    local quote=GP.Map.Quote(map,x,y,offer.map,offer.x,offer.y)
    if not quote then GP.Print("Travel distance is unavailable."); return false end
    local previous=GP.db.pairs[key(offer.sender)] or GP.db.pairs[shortKey(offer.sender)]
    if not GP.Fares.PairEligible(previous,now()) then quote=0 end
    local fields={offer.id,tostring(map),string.format("%.7f",x),string.format("%.7f",y),tostring(quote)}
    revisionFields(fields,offer.revision)
    if not send("A",fields,offer.sender) then
        GP.Print("Could not reach the requester. Please try again."); return false
    end
    N.active={id=offer.id, requester=offer.sender, map=offer.map, x=offer.x, y=offer.y, amount=quote,
        originMap=map,originX=x,originY=y,revision=offer.revision,started=now()}
    GP.db.activeFare=N.active
    chat("[Gondor PvP] " .. selfName() .. " is responding to " .. offer.sender .. ".")
    GP.Map.Set(offer.map,offer.x,offer.y)
    N.offers[id]=nil
    GP.Print("Fare accepted. Meet " .. offer.sender .. " after resurrection.")
    return true
end
local function cancellationKey(peer,id,revision,role)
    return key(peer).."|"..id.."|"..(revision and tostring(revision) or "0").."|"..role
end
local function cancellationFields(id,revision,role)
    return {id,revision and tostring(revision) or "",role}
end
local function sendCancellation(entry)
    local peer=rosterMember(entry.peer)
    if not peer then return false end
    return send("X",cancellationFields(entry.id,entry.revision,entry.role),peer)
end
local function queueCancellation(peer,id,revision,role)
    local entry={peer=peer,id=id,revision=revision,role=role,expires=now()+86400,nextAt=now()+15}
    GP.db.cancelOutbox[cancellationKey(peer,id,revision,role)]=entry
    sendCancellation(entry)
end
function N.CancelFare()
    if not N.active then GP.Print("No active fare."); return end
    queueCancellation(N.active.requester,N.active.id,N.active.revision,"H")
    N.active=nil; GP.db.activeFare=nil; GP.Map.Clear(); GP.Print("Fare cancelled."); showDeferredOffers()
end
function N.CancelRequest()
    if not N.request then GP.Print("No open request."); return end
    send("X",{N.request.id})
    for _,helper in pairs(N.request.helpers) do
        queueCancellation(helper.name,N.request.id,helper.revision,"R")
    end
    N.request=nil; GP.db.outgoingRequest=nil; GP.Print("Request withdrawn.")
end

function N.CheckInstance()
    local blocked=N.InInstance()
    if blocked and not N.suspended then
        N.suspended=true
        N.offers={}; N.buffered={}; N.seenRequests={}
        N.deathSerial=(N.deathSerial or 0)+1
        N.deathPosition=nil; N.lastAlive=nil
        if GP.UI.ClearOffers then GP.UI.ClearOffers() end
        if StaticPopup_Hide then pcall(StaticPopup_Hide,"GONDOR_PVP_DEATH") end
        if N.active then N.CancelFare() end
        if N.request then N.CancelRequest() end
        GP.Map.Clear()
    elseif not blocked then
        N.suspended=false
    end
    return blocked
end

-- Forever's recap may arrive after PLAYER_DEAD. Inspect only accessible flags:
-- hostile player attacks and hostile player-controlled pets/guardians count.
local function hasFlag(flags, mask)
    return math.floor(flags / mask) % 2 >= 1
end
local function classifyRecap(deathAt)
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then return "unknown" end
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if not ok or not clean(events) or type(events) ~= "table" or #events == 0 then return "unknown" end
    -- A previous recap may still be returned while the new one is loading.
    -- When epoch timestamps are present, require a recent event before using
    -- any entries. Older hits in the same recent recap remain eligible.
    local latest
    for _, entry in ipairs(events) do
        if clean(entry) and type(entry) == "table" then
            local stamp = entry.timestamp
            if clean(stamp) and type(stamp) == "number" and stamp > 1000000000 and stamp < 4102444800 then
                latest = math.max(latest or stamp, stamp)
            end
        end
    end
    if latest and latest < deathAt - 5 then return "unknown" end
    local sawFlags, incomplete = false, false
    for _, entry in ipairs(events) do
        if not clean(entry) or type(entry) ~= "table" then
            incomplete = true
        else
            local explicit
            for _, field in ipairs({"isPvp", "isPvP", "isPVP"}) do
                local flag = entry[field]
                if not clean(flag) then incomplete = true
                elseif flag == true then explicit = true end
            end
            if explicit then return "pvp" end
            local flags = entry.sourceFlags
            if clean(flags) and type(flags) == "number" and flags >= 0 and flags < 4294967296 and flags == math.floor(flags) then
                sawFlags = true
                local hostile = hasFlag(flags, 0x40)
                local player = hasFlag(flags, 0x400)
                local controlledPet = hasFlag(flags, 0x100) and (hasFlag(flags, 0x1000) or hasFlag(flags, 0x2000))
                if hostile and (player or controlledPet) then return "pvp" end
            else
                incomplete = true
            end
        end
    end
    if sawFlags and not incomplete then return "pve" end
    return "unknown"
end

local function inspectDeath(serial, attempt, deathAt)
    if N.InInstance() then return end
    if serial ~= N.deathSerial or not GP.db.settings.alerts or not GP.IsEligibleGuild() then return end
    local result = classifyRecap(deathAt)
    if result == "pvp" then
        N.Request(false, true)
    elseif result == "unknown" then
        local delays = {0.3, 0.7, 1}
        if attempt < #delays then
            local callback = function() inspectDeath(serial, attempt + 1, deathAt) end
            if C_Timer and C_Timer.After then C_Timer.After(delays[attempt + 1], callback) else callback() end
        elseif GP.UI.ConfirmDeath then
            GP.UI.ConfirmDeath()
        end
    end
end

local function onMessage(message,sender,distribution)
    local resolved=rosterMember(sender)
    if not resolved or same(resolved,selfName()) then return end
    sender=resolved
    local p=split(message)
    local kind,id=p[1],p[2]
    if N.InInstance() and kind~="X" and kind~="Z" and kind~="K" then return end
    if not id or #id>40 or not id:match("^%d+%-%d+$") then return end
    if kind == "R" and distribution == "GUILD" and GP.db.settings.offers then
        local alreadyActive=N.active and N.active.id==id and same(sender,N.active.requester)
        local map,x,y=position(p,3)
        local stamp=number(p[8],0,4102444800)
        if not map or not stamp or now()-stamp>60 or stamp-now()>5 then return end
        local revision,revisionValid=parseRevision(p[9])
        if not revisionValid then return end
        local own=GP.Map.Position()
        local party=safe2(UnitInParty,sender)
        local raid=safe2(UnitInRaid,sender)
        if own == map and ((clean(party) and party) or (clean(raid) and raid)) then return end
        local expiry=stamp+math.max(5,math.min(60,tonumber(GP.db.settings.expiry) or 15))
        if now()>=expiry then return end
        local om,ox,oy=GP.Map.Position()
        local quote=om and GP.Map.Quote(om,ox,oy,map,x,y)
        local previous=GP.db.pairs[key(sender)] or GP.db.pairs[shortKey(sender)]
        if quote and not GP.Fares.PairEligible(previous,now()) then quote=0 end
        local token=key(sender)..":"..id
        local seen=N.seenRequests[token]
        if seen then
            if seen.cancelled then return end
            if revision and seen.revision and revision<=seen.revision then return end
            if not revision and seen.revision and stamp<=seen.stamp then return end
            if (not revision or not seen.revision) and (message==seen.message or stamp<seen.stamp) then return end
        end
        N.seenRequests[token]={revision=revision,stamp=stamp,message=message,at=now()}
        N.offers[token]={id=id,sender=sender,map=map,x=x,y=y,race=p[6],class=p[7],quote=quote,expires=expiry,revision=revision}
        if alreadyActive then N.offers[token].deferred=true; return end
        if GP.UI.ShowOffer then GP.UI.ShowOffer(token,N.offers[token],zone(map)) end
    elseif kind == "A" and distribution == "WHISPER" and N.request and N.request.id==id then
        local map,x,y=position(p,3); local proposed=number(p[6],0,50)
        local revision,revisionValid=parseRevision(p[7])
        if not map or not proposed or not revisionValid then return end
        local existing=N.request.helpers[key(sender)]
        if existing then
            if existing.amount~=proposed or existing.revision~=revision then return end
        else
            local cancelled=N.request.cancelled and N.request.cancelled[key(sender)]
            if cancelled and (not revision or revision<=cancelled) then return end
            local finished=N.request.finished and N.request.finished[key(sender)]
            if finished==true then finished=0 end
            if finished and (not revision or revision<=finished) then return end
            local snapshot=N.request
            if revision then
                snapshot=N.request.revisions and N.request.revisions[tostring(revision)]
            end
            if not snapshot or now()-(snapshot.created or 0)>65 then return end
            local quote=GP.Map.Quote(map,x,y,snapshot.map,snapshot.x,snapshot.y)
            if not quote or (proposed ~= quote and proposed ~= 0) then return end
            N.request.helpers[key(sender)]={name=sender,amount=proposed,revision=revision}
            GP.Print(sender .. " accepted your Kill Share.")
        end
    elseif kind == "P" and distribution == "WHISPER" then
        local map,x,y=position(p,3); local isAlive=p[6]=="1"
        local revision,revisionValid=parseRevision(p[7])
        local role=p[8]
        if not map or not revisionValid or (role and role~="" and role~="H" and role~="R") then return end
        if role~="H" and N.active and N.active.id==id and same(sender,N.active.requester) then
            if revision~=N.active.revision then return end
            N.active.acceptedAt=now()
            N.active.map,N.active.x,N.active.y=map,x,y; GP.Map.Set(map,x,y)
            if isAlive and alive() and within(map,x,y,sender) and visible(sender) then
                if send("C",revisionFields({id},revision),sender) then N.active.confirmedAt=now() end
            elseif isAlive and alive() and not N.active.rangeHint then
                local own,ox,oy=GP.Map.Position()
                local separation=own and distance(own,ox,oy,map,x,y)
                if separation and separation<=10 then
                    N.active.rangeHint=true
                    GP.Print("Both players should target each other and stand within five feet. Precise positions must be available to the addon.")
                end
            end
        elseif role~="R" and N.request and N.request.id==id and N.request.helpers[key(sender)] then
            local helper=N.request.helpers[key(sender)]
            if revision~=helper.revision then return end
            helper.position={map,x,y,at=now(),alive=isAlive}
        end
    elseif kind == "C" and distribution == "WHISPER" and N.request and N.request.id==id then
        local helper=N.request.helpers[key(sender)]
        local revision,revisionValid=parseRevision(p[3])
        if not revisionValid or not helper or revision~=helper.revision then return end
        local pos=helper and helper.position
        if pos and now()-pos.at<=8 and pos.alive and alive() and visible(sender) and within(pos[1],pos[2],pos[3],sender) then
            if send("D",revisionFields({id,tostring(helper.amount)},helper.revision),sender) then
                if not helper.completedAt then GP.Print(sender .. " fulfilled your Kill Share.") end
                helper.completedAt=helper.completedAt or now()
                helper.lastD=now()
            end
        end
    elseif kind == "D" and distribution == "WHISPER" and N.active and N.active.id==id and same(sender,N.active.requester) then
        local amount=number(p[3],0,50)
        local revision,revisionValid=parseRevision(p[4])
        if not revisionValid or not amount then return end
        if revision~=N.active.revision then
            acknowledgeReceipt(sender,id,revision,amount)
            return
        end
        if amount==N.active.amount and N.active.confirmedAt and now()-N.active.confirmedAt<=8 and alive() and visible(sender) and within(N.active.map,N.active.x,N.active.y,sender) then
            local suffix=revision and (":"..revision) or ""
            local current=key(sender)..":"..id..suffix
            local legacy=shortKey(sender)..":"..id..suffix
            if not GP.db.receipts[legacy] then receipt(current,sender,amount) end
            send("K",revisionFields({id},revision),sender)
            N.active=nil; GP.db.activeFare=nil; GP.Map.Clear(); showDeferredOffers()
        end
    elseif kind == "D" and distribution == "WHISPER" then
        local revision,revisionValid=parseRevision(p[4])
        local amount=number(p[3],0,50)
        if not revisionValid or not amount then return end
        acknowledgeReceipt(sender,id,revision,amount)
    elseif kind == "K" and distribution == "WHISPER" and N.request and N.request.id==id then
        local helper=N.request.helpers[key(sender)]
        local revision,revisionValid=parseRevision(p[3])
        if helper and helper.completedAt and revisionValid and revision==helper.revision then
            N.request.finished=N.request.finished or {}
            N.request.finished[key(sender)]=revision or 0
            N.request.helpers[key(sender)]=nil
        end
    elseif kind == "Z" and distribution=="WHISPER" then
        local revision,revisionValid=parseRevision(p[3])
        local role=p[4]
        if revisionValid and (role=="H" or role=="R") then
            GP.db.cancelOutbox[cancellationKey(sender,id,revision,role)]=nil
        end
    elseif kind == "X" and (distribution=="WHISPER" or distribution=="GUILD") then
        local role=p[4]
        if distribution=="WHISPER" and role and role~="" and role~="H" and role~="R" then return end
        if distribution=="WHISPER" and (role=="H" or role=="R") then
            local revision,revisionValid=parseRevision(p[3])
            if not revisionValid then return end
            if role=="R" then
                if N.active and N.active.id==id and same(sender,N.active.requester) and revision==N.active.revision then
                    N.offers[key(sender)..":"..id]=nil
                    N.active=nil; GP.db.activeFare=nil; GP.Map.Clear(); GP.Print("The requester withdrew the fare."); showDeferredOffers()
                end
            elseif N.request and N.request.id==id then
                local helper=N.request.helpers[key(sender)]
                N.request.cancelled=N.request.cancelled or {}
                local peer=key(sender)
                N.request.cancelled[peer]=math.max(N.request.cancelled[peer] or 0,revision or 0)
                if helper and revision==helper.revision then N.request.helpers[key(sender)]=nil end
            end
            send("Z",cancellationFields(id,revision,role),sender)
            return
        end
        if distribution=="GUILD" then
            local token=key(sender)..":"..id
            N.offers[token]=nil
            -- A withdrawal can arrive before the corresponding guild offer.
            -- Remember it through the offer's maximum age so a delayed R
            -- cannot resurrect a request the owner has already withdrawn.
            N.seenRequests[token]={cancelled=true,at=now()}
            if GP.UI.RemoveOffer then GP.UI.RemoveOffer(token) end
        end
        if N.active and N.active.id==id and same(sender,N.active.requester) then
            if distribution=="WHISPER" then
                local revision,revisionValid=parseRevision(p[3])
                if not revisionValid or revision~=N.active.revision then return end
            end
            N.active=nil; GP.db.activeFare=nil; GP.Map.Clear(); GP.Print("The requester withdrew the fare."); showDeferredOffers()
        elseif distribution=="WHISPER" and N.request and N.request.id==id then
            local helper=N.request.helpers[key(sender)]
            local revision,revisionValid=parseRevision(p[3])
            if revisionValid then
                N.request.cancelled=N.request.cancelled or {}
                local peer=key(sender)
                N.request.cancelled[peer]=math.max(N.request.cancelled[peer] or 0,revision or 0)
                if helper and revision==helper.revision then N.request.helpers[peer]=nil end
            end
        end
    end
end
function N.OnEvent(event,...)
    if N.CheckInstance() then
        if event~="CHAT_MSG_ADDON" then return end
        local _,message=...
        if not clean(message) or type(message)~="string" or not message:match("^[XZK]~") then return end
    end
    if event=="CHAT_MSG_ADDON" then
        local pre,msg,distribution,sender=...
        if clean(pre) and clean(msg) and clean(distribution) and clean(sender) and pre==prefix then
            if not rosterMember(sender) and not rosterMember(selfName()) and type(msg)=="string" and #msg<=240
                and msg:match("^[RAX]~") and type(sender)=="string" and #sender<=100 then
                if #N.buffered>=50 then table.remove(N.buffered,1) end
                N.buffered[#N.buffered+1]={message=msg,sender=sender,distribution=distribution,at=now()}
                if C_GuildInfo and C_GuildInfo.GuildRoster and now()-(N.rosterRequested or 0)>=3 then
                    N.rosterRequested=now(); pcall(C_GuildInfo.GuildRoster)
                end
            else onMessage(msg,sender,distribution) end
        end
    elseif event=="GUILD_ROSTER_UPDATE" then
        local buffered=N.buffered; N.buffered={}
        for _,entry in ipairs(buffered) do
            if now()-entry.at<=60 then
                if rosterMember(entry.sender) then onMessage(entry.message,entry.sender,entry.distribution)
                elseif not rosterMember(selfName()) then N.buffered[#N.buffered+1]=entry end
            end
        end
    elseif event=="PLAYER_GUILD_UPDATE" then
        local unit=...
        local guild=safe2(GetGuildInfo,"player")
        local inGuild=safe2(IsInGuild)
        local knownOther=clean(guild) and type(guild)=="string" and guild~="" and guild~=GP.guildName
        local knownNone=IsInGuild and clean(inGuild) and inGuild==false
        if clean(unit) and (not unit or unit=="player") and (knownOther or knownNone) then
            N.active=nil; N.request=nil; N.offers={}; N.buffered={}; N.seenRequests={}; GP.db.cancelOutbox={}
            GP.db.activeFare=nil; GP.db.outgoingRequest=nil; GP.Map.Clear()
            if GP.UI.ClearOffers then GP.UI.ClearOffers() end
        end
    elseif event=="PLAYER_DEAD" then
        if not N.initialized then N.wasDead=true; return end
        if not N.wasDead then
            N.wasDead=true; GP.db.manualReadyAt=GP.Fares.ReduceManualCooldown(GP.db.manualReadyAt,now())
            local map,x,y=GP.Map.Position()
            if not map and N.lastAlive and now()-N.lastAlive.at<=5 then
                map,x,y=N.lastAlive.map,N.lastAlive.x,N.lastAlive.y
            end
            N.deathPosition=map and {map,x,y} or nil
            N.deathSerial=(N.deathSerial or 0)+1
            if GP.db.settings.alerts then
                local serial=N.deathSerial
                local deathAt=now()
                local callback=function() inspectDeath(serial, 1, deathAt) end
                if C_Timer and C_Timer.After then C_Timer.After(0.3,callback) else callback() end
            end
        end
    elseif event=="PLAYER_ALIVE" or event=="PLAYER_UNGHOST" then N.wasDead=false end
end
function N.Update(elapsed)
    local blocked=N.CheckInstance()
    N.elapsed=N.elapsed+elapsed
    if N.elapsed<3 then return end
    N.elapsed=0
    for id,entry in pairs(GP.db.cancelOutbox) do
        if now()>=entry.expires then GP.db.cancelOutbox[id]=nil
        elseif now()>=entry.nextAt then
            sendCancellation(entry)
            entry.nextAt=now()+15
        end
    end
    if blocked then return end
    for token,offer in pairs(N.offers) do
        if offer.expires and now()>=offer.expires then N.offers[token]=nil end
    end
    for token,seen in pairs(N.seenRequests) do
        if now()-seen.at>65 then N.seenRequests[token]=nil end
    end
    if N.request and not next(N.request.helpers) and now() - (N.request.created or 0) > 65 then
        N.request=nil; GP.db.outgoingRequest=nil
    end
    if N.request and N.request.revisions then
        for revision,snapshot in pairs(N.request.revisions) do
            if now()-snapshot.created>65 then N.request.revisions[revision]=nil end
        end
    end
    -- These messages use saved acceptance/completion data and do not depend
    -- on a current map position. Keep retrying them even in mapless areas.
    if N.active and not N.active.acceptedAt and N.active.originMap and N.active.originX and N.active.originY then
        local fields={N.active.id,tostring(N.active.originMap),string.format("%.7f",N.active.originX),
            string.format("%.7f",N.active.originY),tostring(N.active.amount)}
        revisionFields(fields,N.active.revision)
        send("A",fields,N.active.requester)
        if not N.active.waitHint and now()-(N.active.started or now())>=15 then
            N.active.waitHint=true; GP.Print("Waiting for the requester to confirm your fare. You can cancel with /gpvp cancel.")
        end
    end
    if N.request then
        for _,helper in pairs(N.request.helpers) do
            if helper.completedAt and (not helper.lastD or now()-helper.lastD>=15) then
                if send("D",revisionFields({N.request.id,tostring(helper.amount)},helper.revision),helper.name) then helper.lastD=now() end
            end
        end
    end
    local aliveFlag=alive() and "1" or "0"
    local map,x,y=positionFields()
    if not map and aliveFlag=="0" and N.request then
        map=tostring(N.request.map); x=string.format("%.7f",N.request.x); y=string.format("%.7f",N.request.y)
    end
    if not map then return end
    if aliveFlag=="1" then N.lastAlive={map=tonumber(map),x=tonumber(x),y=tonumber(y),at=now()} end
    if N.active then
        send("P",{N.active.id,map,x,y,aliveFlag,N.active.revision and tostring(N.active.revision) or "","H"},N.active.requester)
    end
    if N.request then
        if aliveFlag=="0" then
            map=tostring(N.request.map); x=string.format("%.7f",N.request.x); y=string.format("%.7f",N.request.y)
        end
        for peer,helper in pairs(N.request.helpers) do
            send("P",{N.request.id,map,x,y,aliveFlag,helper.revision and tostring(helper.revision) or "","R"},helper.name)
        end
    end
end
