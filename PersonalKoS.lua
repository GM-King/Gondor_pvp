local _, GP = ...
local K = GP.KoS
local P = {encounters = {}, revision = 0}
GP.PersonalKoS = P
local safe = K.Safe
local personalFields={'rows','imported'}

function P.Init()
    local realm=K.Realm()
    if not GP.db or not K.rows or not realm then return end
    GondorPvPPersonalKoS = type(GondorPvPPersonalKoS)=='table' and GondorPvPPersonalKoS or {}
    local store = GondorPvPPersonalKoS[realm]
    if type(store)~='table' then store={}; GondorPvPPersonalKoS[realm]=store end
    P.scope='personal@'..realm
    K.Restore(P.scope,store,personalFields)
    store.rows=type(store.rows)=='table' and store.rows or {}
    store.imported=type(store.imported)=='table' and store.imported or {}
    store.sequence=tonumber(store.sequence) or 0
    P.store=store; P.rows=store.rows; P.count=0
    for key,row in pairs(P.rows) do
        if type(row)~='table' or type(row.name)~='string' or K.Name(key)~=key then P.rows[key]=nil
        else row.history=type(row.history)=='table' and row.history or {}; P.count=P.count+1 end
    end
    local own=K.Own()
    if own and not store.imported[own] and K.rows then
        local rows={}
        for _,r in pairs(K.rows) do if r.author==own then rows[#rows+1]=r end end
        table.sort(rows,function(a,b) return a.added>b.added end)
        for _,r in ipairs(rows) do
            if not P.rows[r.key] and P.count<1000 then
                P.rows[r.key]={key=r.key,name=(GP.UI and GP.UI.KoSPlayerName and GP.UI.KoSPlayerName(r.key) or r.key:gsub('-',' ')),reason=r.reason,author=r.author,added=r.added,seen=r.seen,history={}}
                P.count=P.count+1
            end
        end
        store.imported[own]=true
    end
    for _,rs in pairs(K.store and K.store.backups or {}) do for _,r in pairs(rs) do P.Receipt(r) end end
    for _,rs in pairs(K.store and K.store.statistics or {}) do for _,r in pairs(rs) do P.Receipt(r) end end
    for key in pairs(K.rows or {}) do P.VerifyGuild(key) end
    P.revision=P.revision+1
    K.SaveSnapshot(P.scope,store,personalFields)
end

function P.Remove(key)
    if not P.rows[key] then return end
    P.rows[key]=nil
    P.count=P.count-1
    P.revision=P.revision+1
    K.SaveSnapshot(P.scope,P.store,personalFields)
end

function P.Key(name)
    if type(name)~='string' or #name>100 or name:find('[|~%c]') then return end
    name=name:match('^%s*(.-)%s*$'):gsub('%s+',' ')
    local first,last=name:match('^([^%s%-]+) ([^%s%-]+)$')
    if not first then first,last=name:match('^([^%s%-]+)%-([^%s%-]+)$') end
    if not first then return end
    return K.Name(first..'-'..last), first..' '..last
end

function P.Add(name,reason,identity)
    if not P.rows then P.Init() end
    local key,display=P.Key(name)
    if identity then key=K.Name(identity.name); display=identity.name:gsub('-',' ') end
    if not key then GP.Print('Enter both a first and last name.'); return false end
    if P.rows[key] then GP.Print('This player is already on the Personal KoS list.'); return false end
    if P.count>=1000 then GP.Print('Personal KoS is full (1000 enemies).'); return false end
    local proof=P.encounters[key]
    P.rows[key]={key=key,name=display,reason=K.Reason(reason),author=K.Own(),added=K.Now(),history={}}
    P.count=P.count+1
    if proof then P.Verify(P.rows[key],proof) end
    P.VerifyGuild(key)
    for _,rs in pairs(K.store and K.store.backups or {}) do for _,r in pairs(rs) do if r.victim==key then P.Receipt(r) end end end
    P.revision=P.revision+1
    K.SaveSnapshot(P.scope,P.store,personalFields)
    return true
end

function P.Verify(row,id)
    row.guid=id.guid; row.verified=true; row.identity=id; row.seen=K.Now()
    P.revision=P.revision+1
end

function P.VerifyGuild(key)
    local row=P.rows and P.rows[key]
    local guild=K.rows and K.rows[key]
    if not row or not K.Active(guild) then return end
    if row.verified and row.identity then return end
    row.verified=true
    row.identity=row.identity or {name=guild.key,faction='Alliance',guid=guild.guid,race=guild.race,class=guild.class,level=guild.level}
    row.guid=row.guid or guild.guid
    row.seen=row.seen or guild.seen
    P.revision=P.revision+1
end

function P.Observe(unit)
    if not P.rows or GP.Network.InInstance() then return end
    local id=K.Identity(unit)
    if not id or type(id.guid)~='string' or not id.guid:match('^Player%-') or safe(UnitIsVisible,unit)~=true or safe(UnitIsDeadOrGhost,unit)~=false then return end
    local key=K.Name(id.name); if not key then return end
    P.encounters[key]=id
    local row=P.rows[key]
    if row then
        if not row.verified or row.guid~=id.guid then P.Verify(row,id) end
        row.seen=K.Now(); row.identity=id
        if not (GP.IsEligibleGuild() and K.Active(K.rows[key])) and K.Now()-(GP.db.kosSoundAt[key] or 0)>=600 then
            GP.db.kosSoundAt[key]=K.Now()
            if GP.db.settings.kosSound then safe(PlaySoundFile,'Interface\\AddOns\\Gondor_PvP\\Media\\KoSAlert.ogg','Master') end
        end
    end
end

function P.Receipt(receipt)
    local row=P.rows and P.rows[receipt.victim]
    if row and K.ValidReceipt(receipt) and not row.history[receipt.id] then
        row.history[receipt.id]=receipt; P.revision=P.revision+1
    end
end

function P.EachKill(key,visit)
    local row=P.rows[key]
    for _,receipt in pairs(row and row.history or {}) do
        if K.ValidReceipt(receipt) then visit(receipt) end
    end
    if row and GP.KoSDeaths then GP.KoSDeaths.Each(key,visit) end
end

function P.Stats(key)
    local cached=P.statsCache
    if cached and cached.key==key and cached.revision==P.revision and cached.guildRevision==K.statsRevision then return cached.total,cached.players end
    local total,counts=0,{}
    P.EachKill(key,function(receipt)
        total=total+1
        K.EachCredited(receipt,function(name) counts[name]=(counts[name] or 0)+1 end)
    end)
    local players={}
    for name,count in pairs(counts) do players[#players+1]={name=name,count=count} end
    table.sort(players,function(a,b) if a.count~=b.count then return a.count>b.count end; return a.name<b.name end)
    P.statsCache={key=key,revision=P.revision,guildRevision=K.statsRevision,total=total,players=players}
    return total,players
end

function P.RecordDeath(key, owner, stamp)
    P.store.sequence=P.store.sequence+1
    P.Receipt({id='personal:'..owner..':'..stamp..':'..P.store.sequence,owner=owner,victim=key,time=stamp})
end

function P.Push(key)
    local row=P.rows[key]
    P.VerifyGuild(key)
    if not GP.IsEligibleGuild() then GP.Print('Join Gondor to push to Guild KoS.'); return false end
    if K.Active(K.rows[key]) then GP.Print('This player is already on the Guild KoS list.'); return false end
    if not row or not row.verified or not row.identity then GP.Print('Encounter this enemy in the open world to verify them first.'); return false end
    if not K.Add(row.identity,row.reason) then return false end
    K.store.historyTargets=K.store.historyTargets or {}; K.store.historyTargets[key]=true
    GP.KoSSync.HistoryTarget(key)
    for _,r in pairs(row.history) do GP.KoSSync.Statistic(r) end
    P.revision=P.revision+1
    return true
end

function P.AddBoth(identity,reason)
    P.Add(identity.name,reason,identity)
    local proof=P.encounters[K.Name(identity.name)]
    if P.count>=1000 and not P.rows[K.Name(identity.name)] and proof then
        if K.Active(K.rows[K.Name(identity.name)]) then GP.Print('This player is already on the Guild KoS list.'); return false end
        local added=K.Add(proof,reason)
        if added then
            GP.KoSSync.HistoryTarget(K.Name(identity.name))
            GP.Print('Added to Guild KoS. Personal KoS is full.')
        end
        return added
    end
    -- Proof is captured from the actual unit when its portrait menu opens.
    local personal=P.rows[K.Name(identity.name)]
    if personal and personal.verified then P.Push(personal.key)
    else GP.Print('Saved privately. Encounter this living enemy in the open world before pushing to Guild KoS.') end
    return personal~=nil
end

local frame=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGOUT','PLAYER_TARGET_CHANGED','PLAYER_FOCUS_CHANGED','UPDATE_MOUSEOVER_UNIT','NAME_PLATE_UNIT_ADDED'}) do frame:RegisterEvent(event) end
frame:SetScript('OnEvent',function(_,event,a,b)
    if event=='PLAYER_LOGOUT' then K.SaveSnapshot(P.scope,P.store,personalFields); return end
    if not P.rows then return end
    if event=='NAME_PLATE_UNIT_ADDED' then P.Observe(a)
    else P.Observe('target'); P.Observe('focus'); P.Observe('mouseover') end
end)
