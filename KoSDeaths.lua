local _, GP = ...
local K, P, S = GP.KoS, GP.PersonalKoS, GP.KoSSync
local safe = K.Safe
local D = {clock=0, units={}, samples={}, announcements={}}
GP.KoSDeaths = D

local function finite(n)
    return not (issecretvalue and issecretvalue(n)) and type(n)=='number'
        and n==n and n~=math.huge and n~=-math.huge
end

local function storage()
    K.store.deathObservations=K.store.deathObservations or {}
    return K.store.deathObservations
end

function D.EachObservation(visit)
    for _, observation in pairs(storage()) do
        for _, record in pairs(observation) do visit(record) end
    end
end

-- Keep original observation IDs so a delayed packet or backup can be merged
-- regardless of arrival order. Each client derives the same death groups.
local function index()
    local source=storage()
    if D.indexSource==source and D.indexed then return D.indexed end
    local byVictim={}
    for _, observation in pairs(source) do
        local first=next(observation)
        if first then
            local sample=observation[first]
            local rows=byVictim[sample.victim] or {}
            byVictim[sample.victim]=rows
            rows[#rows+1]=sample
        end
    end
    local indexed={}
    for victim, rows in pairs(byVictim) do
        table.sort(rows,function(a,b) if a.time~=b.time then return a.time<b.time end return a.id<b.id end)
        local groups={}
        for _,r in ipairs(rows) do
            local group
            for i=#groups,1,-1 do
                local candidate=groups[i]
                if r.time-candidate.time>2 or r.previous>candidate.time then break end
                if candidate.listing==r.listing and not candidate.reporters[r.reporter] then
                    group=candidate
                end
            end
            if not group then
                group={id=r.id,owner=r.reporter,victim=victim,time=r.time,listing=r.listing,author=r.author,
                    reporter=r.reporter,members={},reporters={}}
                groups[#groups+1]=group
            end
            group.reporters[r.reporter]=true
            for member in pairs(source[r.id]) do group.members[member]=true end
        end
        indexed[victim]=groups
    end
    D.indexed=indexed; D.indexSource=source
    return indexed
end

function D.Each(victim,visit)
    if not K.store then return end
    for _,r in ipairs(index()[victim] or {}) do visit(r) end
end

function D.EachDeath(visit)
    for _,rows in pairs(index()) do
        for _,r in ipairs(rows) do visit(r) end
    end
end

function D.EachReward(visit)
    local own=K.Own()
    if not K.store or not own then return end
    for _,rows in pairs(index()) do
        for _,r in ipairs(rows) do if r.members[own] then visit(r) end end
    end
end

function D.Merge(r, peer, recovery)
    if not K.store or type(r)~='table' or type(r.victim)~='string' or type(r.author)~='string'
        or type(r.member)~='string' or type(r.reporter)~='string' or type(r.listing)~='string'
        or type(r.id)~='string' or K.Name(r.victim)~=r.victim or K.Name(r.author)~=r.author
        or K.Name(r.member)~=r.member or K.Name(r.reporter)~=r.reporter
        or #r.listing==0 or #r.listing>160 or r.listing:find('[|%c]')
        or not finite(r.time) or r.time<0 or r.time~=math.floor(r.time) or r.time>K.Now()+60
        or not finite(r.previous) or r.previous<0 or r.previous>r.time
        or #r.id>160 or r.id:match('^(.-):%d+:%d+$')~=r.reporter
        or (not recovery and (r.reporter~=peer or r.member~=peer)) then return false end
    local all=storage()
    local observation=all[r.id] or {}
    if observation[r.member] then return false end
    local first=next(observation)
    if first then
        local old=observation[first]
        for _,field in ipairs({'victim','listing','author','time','previous'}) do
            if old[field]~=r[field] then return false end
        end
    end
    observation[r.member]=r
    all[r.id]=observation
    D.indexed=nil
    K.statsRevision=K.statsRevision+1
    if r.member==K.Own() and GP.UI and GP.UI.Refresh then GP.UI.Refresh() end
    return true
end

local function listingFor(key)
    local row=GP.IsEligibleGuild() and K.rows[key]
    if K.Active(row) then return K.store.listings[row.gen] or row.gen,row end
end

local function personalRow(key)
    local row=P.rows and P.rows[key]
    return row and row.verified and row
end

local function listedKeyForGuid(guid)
    if GP.IsEligibleGuild() then
        for key,row in pairs(K.rows) do
            if row.guid==guid and K.Active(row) then return key end
        end
    end
    for key,row in pairs(P.rows or {}) do
        if row.verified and row.guid==guid then return key end
    end
end

local function recordDeath(guid,key,signal)
    local sample=D.samples[guid]
    if sample and sample.death and sample.key==key then
        -- Keep the useful outcome when two death events describe the same kill.
        return
    end
    local own=K.Own()
    if not own then D.status=signal..' did not credit a kill because your character identity was unavailable.'; return end
    local listing,row=listingFor(key)
    if not row and not personalRow(key) then
        D.status=signal..' did not match a current KoS listing.'
        return
    end

    local now=K.Now()
    if row then
        GP.db.kosSequence=(GP.db.kosSequence or 0)+1
        local id=string.format('%s:%010d:%012d',own,now,GP.db.kosSequence)
        local report={id=id,victim=key,reporter=own,member=own,time=now,
            previous=sample and sample.key==key and sample.previous or 0,listing=listing,author=row.author}
        if not D.Merge(report,own) then D.status=signal..' could not save the Guild KoS death.'; return end
        S.Death(report)
        D.announcements[id]={key=key,at=D.clock+4}
    else
        P.RecordDeath(key,own,now)
    end
    D.samples[guid]={key=key,death=now,at=D.clock}
    D.status=signal..' recorded '..GP.DisplayName(key)..(row and ' on Guild KoS. You earned 5 PvP points.' or ' on Personal KoS.')
end

local function observe(unit)
    if safe(UnitIsVisible,unit)~=true or safe(UnitInPhase,unit)==false then return end
    local guid=safe(UnitGUID,unit)
    if type(guid)~='string' or guid=='' then return end
    local sample=D.samples[guid]
    local dead=safe(UnitIsDeadOrGhost,unit)
    if dead==nil then dead=safe(UnitIsDead,unit) end
    local feign=safe(UnitIsFeignDeath,unit)
    if dead==true then
        if sample and not sample.death and (feign==false or not UnitIsFeignDeath) then
            recordDeath(guid,sample.key,'Observed death')
        end
        if D.samples[guid] and D.samples[guid].death then D.samples[guid].corpse=true end
        return
    end
    if dead~=false or feign==true then return end
    if sample and sample.death and not sample.corpse and D.clock-sample.at<=2 then return end

    local id=K.Identity(unit)
    local key=id and K.Name(id.name)
    if not key or (not listingFor(key) and not personalRow(key)) then return end
    local previous=sample and sample.key==key and (sample.death or sample.previous)
    D.samples[guid]={key=key,at=D.clock,previous=previous}
end

local function handleDeath(guid,signal)
    if issecretvalue and issecretvalue(guid) then
        D.status=signal..' withheld the victim identity.'
        return
    end
    if type(guid)~='string' or guid=='' then D.status=signal..' did not supply a victim identity.'; return end
    local sample=D.samples[guid]
    local key=sample and sample.key or listedKeyForGuid(guid)
    if not key then
        -- The death can arrive before polling sees the unit or before its GUID
        -- is saved on the listing.
        for unit in pairs(D.units) do
            if safe(UnitGUID,unit)==guid then
                local id=K.Identity(unit)
                key=id and K.Name(id.name)
                if key then break end
            end
        end
    end
    if key then recordDeath(guid,key,signal) else D.status=signal..' did not match a known KoS victim.' end
end

function D.PrintStatus()
    local metadata=C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version=safe(metadata,'Gondor_PvP','Version') or '0.9.21-beta'
    local registered={}
    for _,event in ipairs({'UNIT_DIED','PARTY_KILL','UNIT_HEALTH','UNIT_FLAGS'}) do
        if D.events[event] then registered[#registered+1]=event end
    end
    GP.Print('KoS '..version..' | Listening: '..(#registered>0 and table.concat(registered,', ') or 'none'))
    GP.Print(D.status or 'No local KoS death signal received since login or reload.')
end

local frame=CreateFrame('Frame')
D.frame=frame
local fixed={target=true,focus=true,mouseover=true,targettarget=true,focustarget=true}
local function reset()
    D.samples={}; D.units={}
    for unit in pairs(fixed) do D.units[unit]=true end
    for i=1,40 do
        D.units['raid'..i]=true
        if i<=4 then D.units['party'..i]=true end
    end
end
reset()
D.events={}
for _,event in ipairs({'PLAYER_ENTERING_WORLD','NAME_PLATE_UNIT_ADDED','NAME_PLATE_UNIT_REMOVED',
    'PLAYER_TARGET_CHANGED','PLAYER_FOCUS_CHANGED','UPDATE_MOUSEOVER_UNIT','UNIT_FLAGS','UNIT_HEALTH','UNIT_DIED','PARTY_KILL'}) do
    local ok,result=pcall(frame.RegisterEvent,frame,event)
    D.events[event]=ok and result~=false
end
frame:SetScript('OnEvent',function(_,event,a,b)
    if event=='PLAYER_ENTERING_WORLD' then reset(); return end
    if not GP.db or not K.rows then return end
    if event=='UNIT_DIED' or event=='PARTY_KILL' then
        if GP.Network.InInstance() then D.status=event..' occurred outside open-world KoS tracking.'; return end
        if event=='UNIT_DIED' then handleDeath(a,event) else handleDeath(b,event) end
        return
    end
    if GP.Network.InInstance() then return end
    if event=='NAME_PLATE_UNIT_ADDED' then
        if not (issecretvalue and issecretvalue(a)) and type(a)=='string' then D.units[a]=true; observe(a) end
    elseif event=='NAME_PLATE_UNIT_REMOVED' then
        if not (issecretvalue and issecretvalue(a)) and type(a)=='string' then D.units[a]=nil end
    elseif event=='UNIT_FLAGS' or event=='UNIT_HEALTH' then
        if not (issecretvalue and issecretvalue(a)) and type(a)=='string' and D.units[a] then observe(a) end
    else
        for unit in pairs(fixed) do observe(unit) end
    end
end)
frame:SetScript('OnUpdate',function(_,elapsed)
    D.clock=D.clock+elapsed
    if not GP.db or not K.rows or D.clock<(D.nextCheck or 0) then return end
    D.nextCheck=D.clock+.2
    if GP.Network.InInstance() then D.samples={}; D.announcements={}; return end
    for _,plate in ipairs(safe(C_NamePlate and C_NamePlate.GetNamePlates) or {}) do
        local unit=plate.namePlateUnitToken
        if not (issecretvalue and issecretvalue(unit)) and type(unit)=='string' then D.units[unit]=true end
    end
    for unit in pairs(D.units) do
        if not unit:match('^raid%d+$') and not unit:match('^party%d+$') then observe(unit) end
    end
    for guid,sample in pairs(D.samples) do
        if D.clock-sample.at>30 then D.samples[guid]=nil end
    end
    for id,pending in pairs(D.announcements) do
        if D.clock>=pending.at then
            D.announcements[id]=nil
            D.Each(pending.key,function(r)
                if r.id==id then
                    S.Chat('Gondor KoS target '..GP.DisplayName(r.victim)..' died. Guildmates who witnessed the death earned +5 PvP Points each.')
                end
            end)
        end
    end
end)
