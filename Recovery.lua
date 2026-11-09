local _, GP = ...
local R = { queue={}, queued={}, peers={}, elapsed=0, clock=0, nextQuery=0, recovered=0 }
GP.Recovery = R
local prefix = "GONDPVPBACK1"
local function safe(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
local function canonical(name)
    if type(name)~="string" or name=="" or #name>100 or name:find("[~|%c]") then return end
    if not name:find("-",1,true) then
        local realm=safe(GetNormalizedRealmName) or safe(GetRealmName)
        if type(realm)~="string" or realm=="" then return end
        name=name.."-"..realm
    end
    return name:lower():gsub("%s+","")
end
local function identity()
    local name,realm
    if UnitFullName then
        local ok,a,b=pcall(UnitFullName,"player")
        if ok and not (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then name,realm=a,b end
    else name=safe(UnitName,"player") end
    if type(name)~="string" then return end
    if type(realm)=="string" and realm~="" then name=name.."-"..realm end
    return canonical(name)
end
local function member(sender)
    local full=canonical(sender)
    if not full or not GP.IsEligibleGuild() then return end
    local count=safe(GetNumGuildMembers,true)
    if type(count)~="number" or count<0 or count>2000 then return end
    local match,found=nil,0
    local qualified=sender:find("-",1,true)
    for i=1,count do
        local name=safe(GetGuildRosterInfo,i)
        local key=canonical(name)
        if key and (key==full or (not qualified and key:match("^[^-]+")==full:match("^[^-]+"))) then
            match=key; found=found+1
        end
    end
    if found==1 then return match end
end
local function cache(owner)
    if type(GondorPvPBackups)~="table" then GondorPvPBackups={} end
    if type(GondorPvPBackups[owner])~="table" then GondorPvPBackups[owner]={} end
    return GondorPvPBackups[owner]
end
-- Canonicalize the legacy short-name alias without changing existing saves.
local function valid(id,record)
    if not GP.Network.ValidReceipt(record) or record.time~=math.floor(record.time) then return end
    local requester=canonical(record.requester)
    if not requester or type(id)~="string" then return end
    local who,incident,revision=id:match("^(.-):(%d+%-%d+):(%d+)$")
    if not who then who,incident=id:match("^(.-):(%d+%-%d+)$") end
    if not who or #incident>40 or (revision and (#revision>10 or tonumber(revision)<1 or tonumber(revision)>1000000000)) then return end
    if who~=requester and who~=requester:match("^[^-]+") then return end
    return requester..":"..incident..(revision and (":"..revision) or ""),requester
end
-- Summaries avoid resending complete histories when both copies already agree.
local function summary(rows)
    local entries={}
    for id,record in pairs(rows) do
        local key,requester=valid(id,record)
        if key then entries[#entries+1]=table.concat({key,requester,record.amount,record.time},"~") end
    end
    table.sort(entries)
    local a,b=1,0
    for _,entry in ipairs(entries) do
        for i=1,#entry do
            a=(a+entry:byte(i))%65521
            b=(b+a)%65521
        end
        a=(a+10)%65521; b=(b+a)%65521
    end
    return tostring(#entries).."-"..string.format("%.0f",b*65536+a)
end
local function merge(id,record)
    local key,requester=valid(id,record)
    if not key then return end
    local short=key:gsub("^[^:]+:",requester:match("^[^-]+")..":")
    local existing=GP.db.receipts[key] or GP.db.receipts[short]
    if existing and GP.Network.ValidReceipt(existing) then return end
    GP.db.receipts[key]={requester=requester,amount=record.amount,time=record.time}
    if record.amount>0 then
        GP.db.pairs[requester]=math.max(GP.db.pairs[requester] or 0,record.time)
    end
    R.recovered=R.recovered+1
    if GP.UI then GP.UI.Refresh() end
end
local function enqueue(payload,target)
    if #payload>240 then return end
    local key=(target or "").."|"..payload
    if R.queued[key] then return end
    R.queued[key]=true
    R.queue[#R.queue+1]={payload,target,key}
end
local function records(kind,owner,rows,target)
    for id,record in pairs(rows) do
        local key,requester=valid(id,record)
        if key then
            enqueue(table.concat({kind,owner,key,requester,tostring(record.amount),tostring(record.time)},"~"),target)
        end
    end
end
function R.BackupReceipt(id,record)
    local own=identity()
    local key,requester=valid(id,record)
    if not own or not key then return end
    cache(own)[key]={requester=requester,amount=record.amount,time=record.time}
    records("B",own,{[key]=record})
end
function R.Status()
    if not GP.IsEligibleGuild() then return "Guild recovery available to guild members." end
    if not R.checked then return "Known points shown. Waiting for guild backup copies." end
    return "Guild backup contacted. Restored "..R.recovered.." fare receipts this session."
end
function R.OnEvent(event,...)
    if event=="PLAYER_LOGIN" then
        if C_ChatInfo then safe(C_ChatInfo.RegisterAddonMessagePrefix,prefix) end
        R.nextQuery=0
    elseif event=="PLAYER_ENTERING_WORLD" or event=="GUILD_ROSTER_UPDATE" then
        if not R.started then R.nextQuery=0 end
    elseif event=="CHAT_MSG_ADDON" then
        local pre,message,distribution,sender=...
        if issecretvalue and (issecretvalue(pre) or issecretvalue(distribution)) then return end
        if pre~=prefix or type(message)~="string" or #message>240
            or (issecretvalue and (issecretvalue(message) or issecretvalue(sender))) then return end
        local peer=member(sender)
        local own=identity()
        if not peer or not own or peer==own then return end
        local digest=message:match("^Q~(%d+%-%d+)$")
        local stored=message:match("^S~(%d+%-%d+)$")
        if digest and distribution=="GUILD" then
            if R.peers[peer] and R.clock-R.peers[peer]<60 then return end
            R.peers[peer]=R.clock
            enqueue("S~"..summary(cache(peer)),peer)
            if digest~=summary(cache(peer)) then records("R",peer,cache(peer),peer) end
            enqueue("E",peer)
        elseif stored and distribution=="WHISPER" and R.started then
            if stored~=summary(GP.db.receipts) then records("B",own,GP.db.receipts,peer) end
        elseif message=="E" and distribution=="WHISPER" and R.started then
            R.checked=true
        else
            local kind,owner,id,requester,amount,stamp=message:match("^([BR])~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)$")
            if (distribution~="WHISPER" and distribution~="GUILD") or not kind then return end
            local record={requester=requester,amount=tonumber(amount),time=tonumber(stamp)}
            local key=valid(id,record)
            if not key then return end
            if kind=="B" and owner==peer then
                local rows=cache(owner)
                if not rows[key] or not GP.Network.ValidReceipt(rows[key]) then rows[key]=record end
            elseif kind=="R" and distribution=="WHISPER" and owner==own and R.started then
                merge(key,record)
            end
        end
    end
end
function R.Update(elapsed)
    R.clock=R.clock+elapsed
    if not GP.IsEligibleGuild() then R.queue={}; R.queued={}; return end
    local own=identity()
    if not own then return end
    if R.clock>=R.nextQuery then
        R.nextQuery=R.clock+120
        -- An account copy also protects against losing only the character save.
        local rows=cache(own)
        for id,record in pairs(rows) do merge(id,record) end
        for id,record in pairs(GP.db.receipts) do
            local key=valid(id,record)
            if key then rows[key]={requester=record.requester,amount=record.amount,time=record.time} end
        end
        if member(own) then enqueue("Q~"..summary(GP.db.receipts)); R.started=true end
    end
    R.elapsed=R.elapsed+elapsed
    if R.elapsed<0.5 then return end
    R.elapsed=0
    local entry=R.queue[1]
    if not entry or not C_ChatInfo then return end
    if entry[2] and not member(entry[2]) then
        R.queued[entry[3]]=nil; table.remove(R.queue,1); return
    end
    local ok,result=pcall(GP.Comms.Send,prefix,entry[1],entry[2])
    if ok and not (issecretvalue and issecretvalue(result)) and (result==nil or result==true or result==0) then
        R.queued[entry[3]]=nil; table.remove(R.queue,1)
    end
end
