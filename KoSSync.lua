local _,GP=...
local K=GP.KoS
local S={queue={},queued={},parts={},peers={},clock=0,sequence=0}
GP.KoSSync=S
local prefix='GONDPVPKOS1'
local fields={'key','author','editor','gen','added','seen','rev','alert','reason','guid','observer','zone','deleted','expired'}
local rewardFields={'id','owner','victim','time'}
local metadataFields={'key','value'}
local detailFields={'key','gen','seen','race','class','level'}
local function encode(s) return (tostring(s or ''):gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
local function decode(s) if #s%2~=0 or s:find('[^%da-f]') then return end return (s:gsub('..',function(c) return string.char(tonumber(c,16)) end)) end
local function pack(r,keys) local t={}; for _,k in ipairs(keys) do t[#t+1]=encode(r[k]) end return table.concat(t,'~') end
local function unpackRecord(s,keys)
    local r={}; local i=0
    for v in (s..'~'):gmatch('(.-)~') do i=i+1; if not keys[i] then return end; r[keys[i]]=decode(v); if r[keys[i]]==nil then return end end
    if i~=#keys then return end
    return r
end
function S.Member(sender)
    if not GP.IsEligibleGuild() then return end
    if not S.roster or S.clock>=(S.rosterAt or 0) then
        S.roster={}; S.rosterAt=S.clock+15
        local count=K.Safe(GetNumGuildMembers,true)
        if type(count)~='number' or count<0 or count>2000 then return end
        for i=1,count do local n=K.Name(K.Safe(GetGuildRosterInfo,i)); if n then S.roster[n]=true end end
    end
    local key=K.Name(sender); return key and S.roster[key] and key
end
local function enqueue(payload,target,priority)
    local key=(target or '')..'|'..payload
    if #payload>240 or S.queued[key] or #S.queue>=2048 then return end
    S.queued[key]=true; local entry={payload=payload,target=target,key=key,priority=priority or 2}
    local pos=#S.queue+1; for i,v in ipairs(S.queue) do if entry.priority<v.priority then pos=i; break end end
    table.insert(S.queue,pos,entry)
end
local function record(kind,r,keys,target,priority)
    local data=pack(r,keys); if #data>4096 then return end
    S.sequence=S.sequence+1; local id=tostring(S.sequence); local count=math.ceil(#data/180)
    for i=1,count do enqueue(table.concat({'D',kind,id,i,count,data:sub((i-1)*180+1,i*180)},'|'),target,priority) end
end
local function details(r,target,priority)
    record('M',{key=r.key,gen=r.gen,seen=r.detailsAt or 0,race=r.race or '',class=r.class or '',level=r.level or 0},detailFields,target,priority)
end
function S.Record(r) record('L',r,fields,nil,1); details(r,nil,1); if K.store.listings[r.gen] then record('I',{key=r.gen,value=K.store.listings[r.gen]},metadataFields,nil,1) end end
function S.Reward(r)
    local author=K.store.killAuthors[r.id]
    if author then record('A',{key=r.id,value=author},metadataFields,nil,0) end
    record('R',r,rewardFields,nil,1)
    if K.store.attribution[r.id] then record('T',{key=r.id,value=K.store.attribution[r.id]},metadataFields,nil,1) end
    for member in pairs(K.store.killMembers[r.id] or {}) do
        record('P',{key=r.id,value=member},metadataFields,nil,1)
    end
end

local function addMember(id,member)
    local members=K.store.killMembers[id] or {}
    K.store.killMembers[id]=members
    if members[member] then return false end
    members[member]=true
    K.statsRevision=K.statsRevision+1
    return true
end
function S.HistoryTarget(key)
    K.statsRevision=(K.statsRevision or 0)+1
    K.store.historyTargets=K.store.historyTargets or {}; K.store.historyTargets[key]=true
    record('J',{key=key,value='true'},metadataFields,nil,1)
end
function S.Statistic(r)
    K.statsRevision=(K.statsRevision or 0)+1
    if not K.ValidReceipt(r) then return end
    K.store.statistics=K.store.statistics or {}
    local rows=K.store.statistics[r.victim] or {}; K.store.statistics[r.victim]=rows
    rows[r.id]=r
    record('H',r,rewardFields,nil,1)
end
function S.Claim(key,gen) enqueue('C|'..encode(key)..'|'..encode(gen),nil,0) end
function S.Chat(text,management)
    if (GP.Network.InInstance() and not management) or not GP.IsEligibleGuild() then return end
    S.chat=S.chat or {}; if #S.chat<100 then local text=text:gsub('[%c]',' '):gsub('|',''); if #text>240 then text=text:sub(1,240):gsub('[\194-\244][\128-\191]*$','') end; S.chat[#S.chat+1]={text=text,at=S.clock,management=management} end
end
function S.GuildReport(kind,lines)
    if not GP.IsEligibleGuild() then return end
    S.reports=S.reports or {}
    for _,report in ipairs(S.reports) do if report.kind==kind then return end end
    local chunks={}
    for _,line in ipairs(lines) do
        line=line:gsub('[%c|]',' ')
        while #line>240 do
            local stop=240
            while line:byte(stop+1)>=128 and line:byte(stop+1)<192 do stop=stop-1 end
            local wordEnd=line:sub(1,stop):match('^.*() ')
            if wordEnd and wordEnd>=120 then stop=wordEnd end
            chunks[#chunks+1]=line:sub(1,stop)
            line=line:sub(stop+1):gsub('^ +','')
        end
        chunks[#chunks+1]=line
    end
    S.reports[#S.reports+1]={kind=kind,lines=chunks,index=1}
end

local function eachKillMetadata(visit)
    for id,author in pairs(K.store.killAuthors) do visit('A',id,author) end
    for id,members in pairs(K.store.killMembers) do
        for member in pairs(members) do visit('P',id,member) end
    end
end
local function digest()
    local rows={}
    for _,r in pairs(K.rows) do rows[#rows+1]=pack(r,fields)..'~'..pack({key=r.key,gen=r.gen,seen=r.detailsAt or 0,race=r.race or '',class=r.class or '',level=r.level or 0},detailFields) end
    for _,rs in pairs(K.store.backups) do for _,r in pairs(rs) do rows[#rows+1]=pack(r,rewardFields) end end
    for key in pairs(K.store.historyTargets or {}) do rows[#rows+1]='J'..key end
    for _,rs in pairs(K.store.statistics or {}) do for _,r in pairs(rs) do rows[#rows+1]='H'..pack(r,rewardFields) end end
    for key,value in pairs(K.store.listings) do rows[#rows+1]='I'..key..value end
    for key,value in pairs(K.store.attribution) do rows[#rows+1]='T'..key..value end
    eachKillMetadata(function(kind,id,value)
        rows[#rows+1]=kind..pack({key=id,value=value},metadataFields)
    end)
    table.sort(rows); local a,b=1,0
    for _,r in ipairs(rows) do for i=1,#r do a=(a+r:byte(i))%65521; b=(b+a)%65521 end end
    return #rows..'-'..string.format('%.0f',b*65536+a)
end
function S.Init()
    K.Safe(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix,prefix)
    S.nextQuery=S.clock+3; K.Safe(JoinPermanentChannel,'gcfrpvp')
    for _,r in pairs(K.store.backups[K.Own()] or {}) do K.Receipt(r) end
    for _,r in pairs(GP.db.kosReceipts) do K.Receipt(r) end
end
function S.Message(message,distribution,sender)
    if issecretvalue and (issecretvalue(message) or issecretvalue(distribution) or issecretvalue(sender)) then return end
    if type(message)~='string' or #message>240 or (distribution~='GUILD' and distribution~='WHISPER') then return end
    local peer=S.Member(sender); if not peer or peer==K.Own() or not K.rows then return end
    if message:sub(1,2)=='Q|' and distribution=='GUILD' then
        if message:sub(3)~=digest() then enqueue('O',peer,3) end
    elseif message=='O' and distribution=='WHISPER' and not S.requested then S.requested=peer; enqueue('F',peer,3)
    elseif message=='F' and distribution=='WHISPER' then
        if S.peers[peer] and S.clock-S.peers[peer]<60 then return end; S.peers[peer]=S.clock
        for _,r in pairs(K.rows) do record('L',r,fields,peer,3); details(r,peer,3) end
        for _,rs in pairs(K.store.backups) do for _,r in pairs(rs) do record('R',r,rewardFields,peer,3) end end
    for key,value in pairs(K.store.listings) do record('I',{key=key,value=value},metadataFields,peer,3) end
        for key in pairs(K.store.historyTargets or {}) do record('J',{key=key,value='true'},metadataFields,peer,3) end
        for _,rs in pairs(K.store.statistics or {}) do for _,r in pairs(rs) do record('H',r,rewardFields,peer,3) end end
        for key,value in pairs(K.store.attribution) do record('T',{key=key,value=value},metadataFields,peer,3) end
        eachKillMetadata(function(kind,id,value)
            record(kind,{key=id,value=value},metadataFields,peer,3)
        end)
    elseif message:sub(1,2)=='C|' then
        local key,gen=message:match('^C|([^|]+)|([^|]+)$'); key=key and decode(key); gen=gen and decode(gen)
        if key and gen then local c=K.claims[key]; if not c or c.gen~=gen or K.clock>=c.expires or peer<c.reporter then K.claims[key]={gen=gen,reporter=peer,expires=K.clock+5} end end
        local p=key and K.pending[key]; if p and gen==p.gen and peer<p.reporter then p.reporter=peer end
    else
        local kind,id,index,count,chunk=message:match('^D|([LRMITHJAP])|(%d+)|(%d+)|(%d+)|(.*)$')
        index=tonumber(index); count=tonumber(count)
        if not kind or #id>10 or not count or count<1 or count>24 or not index or index<1 or index>count or #chunk>180 then return end
        local token=peer..':'..id; local part=S.parts[token]
        if not part then local n=0; for _ in pairs(S.parts) do n=n+1 end; if n>=64 then return end; part={chunks={},count=count,kind=kind,expires=S.clock+30}; S.parts[token]=part end
        if part.count~=count or part.kind~=kind then return end
        part.chunks[index]=chunk
        for i=1,count do if not part.chunks[i] then return end end
        S.parts[token]=nil; local data=table.concat(part.chunks)
        K.statsRevision=(K.statsRevision or 0)+1
        local metadata=kind=='I' or kind=='T' or kind=='J' or kind=='A' or kind=='P'
        local r=unpackRecord(data,metadata and metadataFields or kind=='L' and fields or kind=='M' and detailFields or rewardFields)
        if not r then return end
        if kind=='A' or kind=='P' then
            local owner,stamp=r.key:match('^(.-):(%d+):%d+$')
            stamp=tonumber(stamp)
            if not owner or #r.key>220 or K.Name(owner)~=owner or K.Name(r.value)~=r.value
                or not stamp or stamp>K.Now()+60 then return end
            if kind=='A' then
                if distribution=='GUILD' and peer~=owner then return end
                if distribution=='GUILD' or not K.store.killAuthors[r.key] then
                    K.store.killAuthors[r.key]=r.value
                end
                local own=K.Own()
                if own and distribution=='GUILD' and K.WasNearby(owner,stamp) and addMember(r.key,own) then
                    record('P',{key=r.key,value=own},metadataFields,nil,1)
                end
            elseif distribution=='WHISPER' or peer==owner or peer==r.value then
                addMember(r.key,r.value)
            end
        elseif kind=='J' then
            if K.Name(r.key)==r.key and r.value=='true' then K.store.historyTargets=K.store.historyTargets or {}; K.store.historyTargets[r.key]=true end
        elseif kind=='H' then
            r.time=tonumber(r.time)
            if K.ValidReceipt(r) then
                K.store.statistics=K.store.statistics or {}
                local rows=K.store.statistics[r.victim] or {}; K.store.statistics[r.victim]=rows; rows[r.id]=r
                if GP.PersonalKoS then GP.PersonalKoS.Receipt(r) end
            end
        elseif kind=='I' or kind=='T' then
            if #r.key<=220 and #r.value<=160 and not (r.key..r.value):find('[|%c]') then
                local target=kind=='I' and K.store.listings or K.store.attribution
                if not target[r.key] then target[r.key]=r.value end
            end
        elseif kind=='M' then r.seen=tonumber(r.seen); r.level=tonumber(r.level); K.MergeDetails(r)
        elseif kind=='L' then
            for _,f in ipairs({'added','seen','rev','alert','expired'}) do r[f]=tonumber(r[f]) end
            r.deleted=r.deleted=='true'; K.Merge(r)
        else r.time=tonumber(r.time); K.Receipt(r) end
    end
end
function S.Update(elapsed)
    S.clock=S.clock+elapsed
    if not K.rows or not GP.IsEligibleGuild() then
        K.pending={}; K.units={}; K.presence={}
        S.queue={}; S.queued={}; S.parts={}; S.chat={}; S.reports={}
        return
    end
    if S.clock>=(S.nextQuery or math.huge) then S.nextQuery=S.clock+120; S.requested=nil; enqueue('Q|'..digest(),nil,3) end
    for key,p in pairs(S.parts) do if S.clock>=p.expires then S.parts[key]=nil end end
    if S.clock>=(S.nextSend or 0) then
        S.nextSend=S.clock+0.5; local e=S.queue[1]
        if e then
            if e.target and not S.Member(e.target) then table.remove(S.queue,1); S.queued[e.key]=nil
            elseif GP.Comms.Send(prefix,e.payload,e.target) then table.remove(S.queue,1); S.queued[e.key]=nil end
        end
    end
    if S.clock<(S.nextChat or 0) then return end
    local report=S.reports and S.reports[1]
    if report then
        S.nextChat=S.clock+1
        local fn=C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
        local ok,result=pcall(fn,report.lines[report.index],'GUILD')
        if ok and not (issecretvalue and issecretvalue(result)) and (result==nil or result==true or result==0) then
            report.index=report.index+1
            report.attempts=0
            if report.index>#report.lines then table.remove(S.reports,1) end
        else
            report.attempts=(report.attempts or 0)+1
            if report.attempts>=5 then
                table.remove(S.reports,1)
                GP.Print('Could not finish posting the Guild KoS report.')
            end
        end
        return
    end
    if S.chat and S.chat[1] then
        S.nextChat=S.clock+1; local e=S.chat[1]
        if (GP.Network.InInstance() and not e.management) or S.clock-e.at>(e.management and 60 or 10) then table.remove(S.chat,1); return end
        local channel=K.Safe(GetChannelName,'gcfrpvp')
        if type(channel)=='number' and channel>0 then
            local fn=C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
            local target=C_ChatInfo and fn==C_ChatInfo.SendChatMessage and tostring(channel) or channel
            if type(fn)=='function' then local ok,result=pcall(fn,e.text,'CHANNEL',nil,target); if ok and result~=false then table.remove(S.chat,1) end end
        else K.Safe(JoinPermanentChannel,'gcfrpvp') end
    end
end
local f=CreateFrame('Frame'); f:RegisterEvent('CHAT_MSG_ADDON'); f:RegisterEvent('GUILD_ROSTER_UPDATE')
f:SetScript('OnEvent',function(_,event,p,m,d,s) if event=='GUILD_ROSTER_UPDATE' then S.roster=nil elseif not (issecretvalue and issecretvalue(p)) and p==prefix then S.Message(m,d,s) end end)
