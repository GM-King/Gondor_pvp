local _, GP = ...
local K, P, S = GP.KoS, GP.PersonalKoS, GP.KoSSync
local safe = K.Safe
local D = {clock=0, units={}, samples={}, announcements={}}
GP.KoSDeaths = D

local function finite(n)
    return not (issecretvalue and issecretvalue(n)) and type(n)=='number'
        and n==n and n~=math.huge and n~=-math.huge
end

local function position(unit)
    if type(UnitPosition)~='function' then return end
    local ok,x,y,z,map=pcall(UnitPosition,unit)
    if ok and finite(x) and finite(y) and finite(z) and finite(map) then
        return {x=x,y=y,z=z,map=map}
    end
end

local function visible(unit)
    return safe(UnitIsVisible,unit)==true and safe(UnitInPhase,unit)~=false
end

local function within(a,b)
    if a and b then
        return a.map==b.map and (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<=1600
    end
end

local hunterRangeSpells={75,5116,466930} -- Auto Shot, Concussive Shot, Black Arrow
local function hunterSpellInRange(unit)
    local _,class=safe(UnitClass,'player')
    if class~='HUNTER' or not C_Spell then return end
    local isKnown=C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell or IsSpellKnown
    for _,spell in ipairs(hunterRangeSpells) do
        if safe(isKnown,spell)==true and safe(C_Spell.IsSpellHarmful,spell)==true then
            local info=safe(C_Spell.GetSpellInfo,spell)
            local maximum=type(info)=='table' and info.maxRange
            if finite(maximum) and maximum>0 and maximum<=40 and safe(C_Spell.IsSpellInRange,spell,unit)==true then
                return true
            end
        end
    end
end

local function selfInRange(unit, enemy, living)
    local squared, checked=safe(UnitDistanceSquared,unit)
    if checked==true and finite(squared) and squared>=0 then return squared<=1600 end
    local range=within(position('player'),enemy)
    if range~=nil then return range end
    if living then return hunterSpellInRange(unit) end
end

local function collect(unit, own, guild, living)
    local result={}
    local enemy=position(unit)
    result[own]=selfInRange(unit,enemy,living)
    if not guild or not enemy then return result end
    local victimGuid=safe(UnitGUID,unit)
    for token in pairs(D.units) do
        if token~=unit and safe(UnitIsPlayer,token)==true then
            local guid=safe(UnitGUID,token)
            if guid and guid~=victimGuid then
                local name,realm=safe(UnitName,token)
                local member=type(name)=='string' and S.Member(realm and realm~='' and name..'-'..realm or name)
                if member and member~=own and result[member]~=true then
                    local range
                    if visible(token) then range=within(position(token),enemy) else range=false end
                    if range~=nil then result[member]=range end
                end
            end
        end
    end
    return result
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
                group={id=r.id,victim=victim,time=r.time,listing=r.listing,author=r.author,
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
        or (not recovery and (r.reporter~=peer or (r.member~=peer and not S.Member(r.member)))) then return false end
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

local function record(sample)
    local death=sample.death
    local key,own=sample.key,K.Own()
    if not own then return end
    local guild=GP.IsEligibleGuild() and K.rows[key]
    if K.Active(guild) then
        local listing=K.store.listings[guild.gen] or guild.gen
        if listing~=sample.listing then return end
        for member,close in pairs(death.ranges) do
            if close then
                if not death.id then
                    GP.db.kosSequence=(GP.db.kosSequence or 0)+1
                    death.id=string.format('%s:%010d:%012d',own,death.time,GP.db.kosSequence)
                    D.announcements[death.id]={key=key,at=death.at+4}
                end
                local r={id=death.id,victim=key,reporter=own,member=member,time=death.time,previous=sample.previous or 0,
                    listing=listing,author=guild.author}
                if D.Merge(r,own) then S.Death(r) end
            end
        end
    elseif not sample.listing and death.ranges[own] and not death.personalRecorded and P.rows and P.rows[key] then
        P.RecordDeath(key,own,death.time)
        death.personalRecorded=true
    end
end

local function confirmDeath(guid,unit)
    local sample=D.samples[guid]
    if not sample or (not sample.death and D.clock-sample.at>1) then return end
    local own=K.Own()
    if not own then return end
    local death=sample.death
    if death and D.clock-death.at>2 then return end
    local current={}
    -- Further signals can provide a second reading in the death frame. A later
    -- position can reflect someone walking up to the corpse.
    if (not death or D.clock==death.at) and unit and safe(UnitGUID,unit)==guid then
        if safe(UnitInPhase,unit)==false then return end
        if visible(unit) then current=collect(unit,own,sample.listing~=nil,false) end
    end
    if not death then
        death={at=D.clock,time=K.Now(),ranges=current}
        sample.death=death
        for member,range in pairs(sample.ranges) do
            if death.ranges[member]==nil and D.clock-range.at<=1 then
                death.ranges[member]=range.close
            end
        end
    else
        local added=false
        for member,close in pairs(current) do
            if death.ranges[member]==nil then
                death.ranges[member]=close
                if close then added=true end
            end
        end
        if not added then return end
    end
    record(sample)
end

local function observe(unit)
    if not visible(unit) then return end
    local guid=safe(UnitGUID,unit)
    if type(guid)~='string' or guid=='' then return end
    local sample=D.samples[guid]
    local dead=safe(UnitIsDeadOrGhost,unit)
    if dead==nil or (UnitIsFeignDeath and safe(UnitIsFeignDeath,unit)~=false) then return end
    if dead then
        if sample then
            confirmDeath(guid,unit)
            sample.corpse=true
        end
        return
    end
    local id=K.Identity(unit)
    if not id then return end
    local key=K.Name(id.name)
    local guild=key and GP.IsEligibleGuild() and K.rows[key]
    local listing=K.Active(guild) and (K.store.listings[guild.gen] or guild.gen) or nil
    if not listing and not (P.rows and P.rows[key]) then return end
    local own=K.Own()
    if not own then return end
    if sample and sample.death and not sample.corpse then return end
    if not sample or sample.key~=key or sample.listing~=listing or sample.death then
        local previous=sample and sample.death and sample.death.time or nil
        sample={key=key,listing=listing,ranges={},previous=previous}
        D.samples[guid]=sample
    end
    sample.at=D.clock
    if not sample.unit or unit=='target' or safe(UnitGUID,sample.unit)~=guid then sample.unit=unit end
    for member,close in pairs(collect(unit,own,listing~=nil,true)) do
        sample.ranges[member]={close=close,at=D.clock}
    end
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
for _,event in ipairs({'PLAYER_ENTERING_WORLD','NAME_PLATE_UNIT_ADDED','NAME_PLATE_UNIT_REMOVED',
    'PLAYER_TARGET_CHANGED','PLAYER_FOCUS_CHANGED','UPDATE_MOUSEOVER_UNIT','UNIT_FLAGS','UNIT_HEALTH','UNIT_DIED','PARTY_KILL'}) do
    pcall(frame.RegisterEvent,frame,event)
end
frame:SetScript('OnEvent',function(_,event,a,b)
    if event=='PLAYER_ENTERING_WORLD' then reset(); return end
    if not GP.db or not K.rows or GP.Network.InInstance() then return end
    if event=='UNIT_DIED' or event=='PARTY_KILL' then
        local guid=b
        if event=='UNIT_DIED' then guid=a end
        if not (issecretvalue and issecretvalue(guid)) and type(guid)=='string' then
            local sample=D.samples[guid]
            if sample then confirmDeath(guid,sample.unit) end
        end
    elseif event=='NAME_PLATE_UNIT_ADDED' then
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
                    S.Chat('Gondor KoS target '..GP.DisplayName(r.victim)..' died. Nearby guildmates earned +5 PvP Points each.')
                end
            end)
        end
    end
end)
