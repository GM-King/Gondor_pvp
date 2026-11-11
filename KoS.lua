local _,GP=...
local K={TTL=864000, units={}, guids={}, deaths={}, sounds={}, pending={}, claims={}, clock=0}
GP.KoS=K
K.pendingDetails={}
function K.Safe(fn,...)
    if type(fn)~='function' then return end
    local ok,a,b=pcall(fn,...)
    if ok and not (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return a,b end
end
local safe=K.Safe
function K.Now() return safe(GetServerTime) or safe(time) or 0 end
function K.Name(name)
    if issecretvalue and issecretvalue(name) then return end
    if type(name)~='string' or name=='' or #name>100 or name:find('[~|%c]') then return end
    if not name:find('-',1,true) then name=name..'-'..(safe(GetNormalizedRealmName) or safe(GetRealmName) or '') end
    local key=name:lower():gsub('%s+',''); return key
end
function K.Own() local n,r=safe(UnitName,'player'); return K.Name(n and (r and r~='' and n..'-'..r or n)) end
function K.Reason(s)
    if type(s)~='string' then return '' end
    s=s:gsub('[%c]',' '):gsub('|','')
    local n=0; local stop=#s
    for i=1,#s do if s:byte(i)<128 or s:byte(i)>=192 then n=n+1; if n==101 then stop=i-1; break end end end
    return s:sub(1,stop),math.min(n,100)
end
function K.Init()
    if not GP.db then return end
    if type(GondorPvPKoS)~='table' then GondorPvPKoS={} end
    local scope=GP.guildName:lower()..'@'..(safe(GetNormalizedRealmName) or safe(GetRealmName) or 'unknown')
    if type(GondorPvPKoS[scope])~='table' then GondorPvPKoS[scope]={rows={},backups={}} end
    K.store=GondorPvPKoS[scope]; if type(K.store.rows)~='table' then K.store.rows={} end; if type(K.store.backups)~='table' then K.store.backups={} end
    K.store.listings=K.store.listings or {}; K.store.attribution=K.store.attribution or {}
    local saved=K.store.rows; K.store.rows={}; K.rows=K.store.rows
    for _,r in pairs(saved) do pcall(K.Merge,r) end
    if type(GP.db.kosReceipts)~='table' then GP.db.kosReceipts={} end; if type(GP.db.kosSoundAt)~='table' then GP.db.kosSoundAt={} end
    if GP.db.settings.kosSound==nil then GP.db.settings.kosSound=true end
    if type(GP.db.kosDeaths)~='table' then GP.db.kosDeaths={} end; K.deaths=GP.db.kosDeaths
    if type(GP.db.kosUndo)~='table' then GP.db.kosUndo={} end
    K.scope=scope
    K.Prune()
end
function K.Active(r) return type(r)=='table' and not r.deleted and K.Now()-(r.seen or r.added)<K.TTL end
function K.Stats(r)
    local total,players,seen=0,{},{}
    local listing=(K.store.listings or {})[r.gen] or r.gen
    for _,records in pairs(K.store.backups or {}) do for id,receipt in pairs(records) do
        local attribution=(K.store.attribution or {})[id]
        if not seen[id] and K.ValidReceipt(receipt) and receipt.victim==r.key and
            ((attribution and attribution==listing) or (not attribution and receipt.time>=r.added)) then
            seen[id]=true; total=total+1; players[receipt.owner]=(players[receipt.owner] or 0)+1
        end
    end end
    local rows={}; for name,count in pairs(players) do rows[#rows+1]={name=name,count=count} end
    table.sort(rows,function(a,b) if a.count~=b.count then return a.count>b.count end return a.name<b.name end)
    return total,rows
end
function K.List()
    local out={}; for _,r in pairs(K.rows or {}) do if K.Active(r) then out[#out+1]=r end end
    local sort=GP.db.settings.kosSort or 'seen'; local asc=GP.db.settings.kosSortAscending
    local counts={}; if sort=='kills' then for _,r in ipairs(out) do counts[r.key]=K.Stats(r) end end
    table.sort(out,function(a,b)
        local av,bv=a.seen,b.seen
        if sort=='name' then
            if asc then return a.key<b.key end
            return a.key>b.key
        elseif sort=='level' then
            av,bv=a.level or 0,b.level or 0
            if (av==0)~=(bv==0) then return av~=0 end
        elseif sort=='kills' then av,bv=counts[a.key],counts[b.key] end
        if av==bv then return a.key<b.key end
        if asc then return av<bv end return av>bv
    end); return out
end
function K.Publish(r) if GP.KoSSync then GP.KoSSync.Record(r) end end
function K.DetailText(value)
    if issecretvalue and issecretvalue(value) then return '' end
    return type(value)=='string' and #value<=80 and not value:find('[|%c]') and value or ''
end
function K.DetailLevel(value)
    if issecretvalue and issecretvalue(value) then return 0 end
    return type(value)=='number' and value==value and value>=1 and value<=255 and value==math.floor(value) and value or 0
end
function K.MergeDetails(d)
    if type(d)~='table' or not K.Name(d.key) or type(d.gen)~='string' or #d.gen>160 or type(d.seen)~='number' or d.seen~=d.seen or d.seen<0 or d.seen>K.Now()+60 then return end
    if K.DetailText(d.race)~=d.race or K.DetailText(d.class)~=d.class or (d.level~=0 and K.DetailLevel(d.level)~=d.level) then return end
    local r=K.rows[d.key]
    if not r or r.gen~=d.gen then
        if r and r.gen>d.gen then return end
        local pending=K.pendingDetails[d.key]
        if pending and (pending.gen>d.gen or (pending.gen==d.gen and pending.seen>d.seen)) then return end
        local n=0; for _ in pairs(K.pendingDetails) do n=n+1 end
        if n<100 or K.pendingDetails[d.key] then K.pendingDetails[d.key]=d end
        return
    end
    if d.seen<(r.detailsAt or 0) or r.deleted then return end
    if d.seen==(r.detailsAt or 0) then
        if d.race=='' then d.race=r.race or '' end
        if d.class=='' then d.class=r.class or '' end
        d.level=math.max(d.level,r.level or 0)
    end
    r.race=d.race; r.class=d.class; r.level=d.level; r.detailsAt=d.seen
    K.pendingDetails[d.key]=nil
end
function K.Prune()
    local active={}
    for _,r in pairs(K.rows or {}) do
        if not r.deleted then
            local expired=not K.Active(r)
            if expired and r.expired~=r.seen then r.expired=r.seen; K.Publish(r) end
            if not expired then r.expired=nil; active[#active+1]=r end
        end
    end
    table.sort(active,function(a,b) if a.added~=b.added then return a.added<b.added end if a.author~=b.author then return a.author<b.author end return a.key<b.key end)
    for i=101,#active do local r=active[i]; r.deleted=true; r.rev=r.rev+1; K.Publish(r); if r.author==K.Own() then GP.Print('KoS list full: '..GP.DisplayName(r.key)..' could not be retained.') end end
end
function K.Merge(r)
    if type(r)~='table' or not K.Name(r.key) or r.key~=K.Name(r.key) or not K.Name(r.author) or type(r.gen)~='string' or #r.gen>160 then return false end
    for _,f in ipairs({'added','seen','rev','alert'}) do if type(r[f])~='number' or r[f]~=r[f] or r[f]<0 or r[f]>4102444800 then return false end end
    for _,f in ipairs({'editor','guid','observer','zone'}) do if type(r[f])~='string' or #r[f]>160 or r[f]:find('[|%c]') then return false end end
    if r.alert>K.Now()+60 then return false end
    if r.seen>K.Now()+60 or r.added>K.Now()+60 or r.seen<r.added or type(r.reason)~='string' or #r.reason>400 or K.Reason(r.reason)~=r.reason then return false end
    local old=K.rows[r.key]
    r.race=K.DetailText(r.race); r.class=K.DetailText(r.class); r.level=K.DetailLevel(r.level)
    if type(r.detailsAt)~='number' or r.detailsAt~=r.detailsAt or r.detailsAt<0 or r.detailsAt>K.Now()+60 then r.detailsAt=0 end
    if old and old.gen==r.gen then
        if not r.deleted then r.reason=old.reason end
        if (old.detailsAt or 0)>=r.detailsAt then r.race=old.race; r.class=old.class; r.level=old.level; r.detailsAt=old.detailsAt end
        r.sentSeen=old.sentSeen; local seen=math.max(old.seen,r.seen); local observer,zone,guid=old.observer,old.zone,old.guid
        if r.seen>old.seen then observer,zone,guid=r.observer,r.zone,r.guid end
        if old.deleted or (old.rev>r.rev) or (old.rev==r.rev and (old.editor or '')>(r.editor or '')) then
            if old.deleted and r.deleted and (r.rev>old.rev or (r.rev==old.rev and r.editor>old.editor)) then old.rev=r.rev; old.editor=r.editor end
            old.seen=seen; old.alert=math.max(old.alert,r.alert); old.observer=observer; old.zone=zone; old.guid=guid; K.Prune(); if GP.UI and GP.UI.RefreshKoSPortraits then GP.UI.RefreshKoSPortraits() end; return true
        end
        r.seen=seen; r.observer=observer; r.zone=zone; r.guid=guid; r.deleted=old.deleted or r.deleted; r.alert=math.max(old.alert,r.alert)
    elseif old and old.gen>r.gen then return false end
    K.rows[r.key]=r
    if K.pendingDetails[r.key] then K.MergeDetails(K.pendingDetails[r.key]) end
    K.Prune(); if GP.UI and GP.UI.RefreshKoSPortraits then GP.UI.RefreshKoSPortraits() end; return true
end
function K.Add(identity,reason)
    if not GP.IsEligibleGuild() or not identity or identity.faction~='Alliance' then return false end
    K.Prune(); local key=K.Name(identity.name); if not key then return false end
    local old=K.rows[key]; local stamp=K.Now(); local own=K.Own()
    if not own then return false end
    if not K.Active(old) and #K.List()>=100 then GP.Print('KoS list is full. Remove a player first.'); return false end
    local r
    if K.Active(old) then GP.Print('This player is already on KoS. The original reason cannot be edited.'); return false
    else
        GP.db.kosSequence=(GP.db.kosSequence or 0)+1
        local gen=string.format('%010d:%010d:%s',stamp,GP.db.kosSequence,own)
        if old and gen<=old.gen then gen=old.gen..'+' end
        r={key=key,author=own,editor=own,added=stamp,seen=stamp,rev=1,alert=0,gen=gen,reason=K.Reason(reason),guid=identity.guid or '',observer=own,zone=safe(GetRealZoneText) or ''}
        r.race=K.DetailText(identity.race); r.class=K.DetailText(identity.class); r.level=K.DetailLevel(identity.level); r.detailsAt=stamp
        K.rows[key]=r
    end
    K.Publish(r); return true
end
local function managementNotice(action,key)
    local display=GP.UI and GP.UI.KoSPlayerName or GP.DisplayName
    if GP.KoSSync then GP.KoSSync.Chat(display(K.Own())..' '..action..' '..display(key)..(action=='removed' and ' from Gondor KoS.' or ' to Gondor KoS.'),true) end
end
function K.Delete(key,gen)
    local r=K.rows[key]; local own=K.Own()
    if not GP.IsEligibleGuild() or not own or not K.Active(r) or r.gen~=gen then return false end
    local snapshot={}; for field,value in pairs(r) do snapshot[field]=value end
    r.deleted=true; r.rev=r.rev+1; r.reason=''; r.editor=own
    GP.db.kosUndo=GP.db.kosUndo or {}
    GP.db.kosUndo[key]={snapshot=snapshot,gen=gen,revision=r.rev,owner=own,scope=K.scope,expires=K.Now()+60}
    K.Publish(r); managementNotice('removed',key)
    GP.Print('KoS target removed. You can undo this removal for 60 seconds.')
    if GP.UI and GP.UI.ShowKoSUndo then GP.UI.ShowKoSUndo() end
    return true
end
function K.UndoList()
    local list={}; local own=K.Own()
    if not own then return list end
    for key,u in pairs(GP.db.kosUndo or {}) do
        local r=K.rows and K.rows[key]
        if type(u)~='table' or u.owner~=own or u.scope~=K.scope or type(u.expires)~='number' or u.expires~=u.expires or K.Now()>=u.expires or u.expires>K.Now()+60
            or type(u.snapshot)~='table' or u.snapshot.key~=key or type(u.snapshot.seen)~='number' or u.snapshot.seen~=u.snapshot.seen
            or type(u.snapshot.added)~='number' or type(u.snapshot.reason)~='string' or not K.Active(u.snapshot)
            or not r or not r.deleted or r.gen~=u.gen or r.rev~=u.revision or r.editor~=u.owner then
            GP.db.kosUndo[key]=nil
        elseif GP.IsEligibleGuild() then list[#list+1]=u end
    end
    table.sort(list,function(a,b) if a.expires~=b.expires then return a.expires>b.expires end return a.snapshot.key<b.snapshot.key end)
    return list
end
function K.UndoDelete(key)
    if not GP.IsEligibleGuild() then return false end
    K.UndoList(); local u=GP.db.kosUndo and GP.db.kosUndo[key]
    if not u then GP.Print('That KoS removal can no longer be undone.'); return false end
    K.Prune()
    if #K.List()>=100 then GP.Print('KoS list is full. Free a slot before the undo timer expires.'); return false end
    local old=K.rows[key]; local restored={}; for field,value in pairs(u.snapshot) do restored[field]=value end
    local stamp,counter=old.gen:match('^(%d+):(%d+):')
    GP.db.kosSequence=math.max(GP.db.kosSequence or 0,tonumber(counter) or 0)+1
    restored.gen=string.format('%010d:%010d:%s',math.max(K.Now(),tonumber(stamp) or 0),GP.db.kosSequence,K.Own())
    if restored.gen<=old.gen then restored.gen=old.gen..'+' end
    if #restored.gen>160 then GP.Print('That KoS removal cannot be restored.'); return false end
    restored.rev=1; restored.deleted=nil; restored.editor=K.Own()
    K.store.listings[restored.gen]=K.store.listings[u.gen] or u.gen
    K.rows[key]=restored; GP.db.kosUndo[key]=nil
    K.Publish(restored); managementNotice('restored',key)
    if GP.UI and GP.UI.RefreshKoS then GP.UI.RefreshKoS() end
    if GP.UI and GP.UI.RefreshKoSPortraits then GP.UI.RefreshKoSPortraits() end
    return true
end
function K.Identity(unit)
    if safe(UnitIsPlayer,unit)~=true or safe(UnitFactionGroup,unit)~='Alliance' then return end
    local n,r=safe(UnitName,unit); if not n then return end
    return {name=r and r~='' and n..'-'..r or n,faction='Alliance',guid=safe(UnitGUID,unit),race=K.DetailText(safe(UnitRace,unit)),class=K.DetailText(safe(UnitClass,unit)),level=K.DetailLevel(safe(UnitLevel,unit))}
end
function K.Observe(unit)
    if not GP.IsEligibleGuild() or GP.Network.InInstance() then return end
    local id=K.Identity(unit); local key=id and K.Name(id.name); local r=key and K.rows[key]
    if not K.Active(r) or safe(UnitIsVisible,unit)~=true or safe(UnitIsDeadOrGhost,unit)~=false then return end
    local stamp=K.Now(); K.units[unit]=true
    if id.guid then K.guids[id.guid]=key; K.deaths[id.guid]=nil; r.guid=id.guid end
    r.seen=stamp; r.expired=nil; r.observer=K.Own(); r.zone=safe(GetRealZoneText) or ''
    r.race=id.race; r.class=id.class; r.level=id.level; r.detailsAt=stamp
    if stamp-(GP.db.kosSoundAt[key] or 0)>=600 then
        GP.db.kosSoundAt[key]=stamp
        if GP.db.settings.kosSound then safe(PlaySoundFile,'Interface\\AddOns\\Gondor_PvP\\Media\\KoSAlert.ogg','Master') end
    end
    if stamp-r.alert>=600 and not K.pending[key] then
        local claim=K.claims[key]; local reporter=K.Own()
        if claim and claim.gen==r.gen and K.clock<claim.expires and claim.reporter<reporter then reporter=claim.reporter end
        K.pending[key]={at=K.clock+2,reporter=reporter,gen=r.gen}
        if GP.KoSSync then GP.KoSSync.Claim(key,r.gen) end
    end
    if stamp-(r.sentSeen or 0)>=30 then r.sentSeen=stamp; K.Publish(r) end
end
function K.ValidReceipt(r)
    return type(r)=='table' and type(r.id)=='string' and #r.id<=220 and K.Name(r.owner)==r.owner and K.Name(r.victim)==r.victim and type(r.time)=='number' and r.time==r.time and r.time>=0 and r.time<=K.Now()+60
end
function K.Receipt(r)
    if not K.ValidReceipt(r) then return end
    local rows=K.store.backups[r.owner] or {}; K.store.backups[r.owner]=rows; rows[r.id]=r
    if r.owner==K.Own() and not GP.db.kosReceipts[r.id] then GP.db.kosReceipts[r.id]=r; if GP.UI then GP.UI.Refresh() end end
end
function K.Points() local n=0; for _,r in pairs(GP.db.kosReceipts or {}) do if K.ValidReceipt(r) then n=n+5 end end; return n end
function K.Kill(attacker,victim)
    if not GP.IsEligibleGuild() or GP.Network.InInstance() then return end
    if issecretvalue and (issecretvalue(attacker) or issecretvalue(victim)) then K.status='Kill verification unavailable: restricted identifiers.'; return end
    if type(attacker)~='string' or type(victim)~='string' then K.status='Kill verification unavailable: missing identifiers.'; return end
    local ownGUID=safe(UnitGUID,'player'); local petGUID=safe(UnitGUID,'pet')
    if not ownGUID then K.status='Kill verification unavailable: local identity restricted.'; return end
    if attacker~=ownGUID and attacker~=petGUID then return end
    local key=K.guids[victim]; if not key then K.status='Kill verification unavailable: victim was not identified locally.'; return end; local r=K.rows[key]
    if not K.Active(r) or K.deaths[victim] then return end
    K.deaths[victim]=true; GP.db.kosSequence=(GP.db.kosSequence or 0)+1
    local receipt={owner=K.Own(),victim=key,time=K.Now()}
    receipt.id=receipt.owner..':'..K.Now()..':'..GP.db.kosSequence
    K.store.attribution[receipt.id]=K.store.listings[r.gen] or r.gen
    K.Receipt(receipt); if GP.KoSSync then GP.KoSSync.Reward(receipt); GP.KoSSync.Chat('Gondor KoS target '..GP.DisplayName(key)..' killed by '..GP.DisplayName(receipt.owner)..'! +5 PvP Points.') end
    GP.Print('KoS kill: +5 PvP Points.'); K.status='Last KoS killing blow verified.'
end
function K.Update(elapsed)
    K.clock=K.clock+elapsed; if not K.rows or not GP.IsEligibleGuild() then return end
    if K.clock>=(K.nextPrune or 0) then K.nextPrune=K.clock+60; K.Prune(); K.UndoList() end
    if K.clock>=(K.nextUnits or 0) then K.nextUnits=K.clock+5; for unit in pairs(K.units) do if safe(UnitExists,unit) then K.Observe(unit) else K.units[unit]=nil end end end
    for key,p in pairs(K.pending) do if K.clock>=p.at then
        K.pending[key]=nil; local r=K.rows[key]
        if K.Active(r) and r.gen==p.gen and K.Now()-r.alert>=600 and p.reporter==K.Own() and not GP.Network.InInstance() then
            r.alert=K.Now(); K.Publish(r)
            GP.KoSSync.Chat('Gondor KoS: '..GP.DisplayName(key)..' seen by '..GP.DisplayName(K.Own())..' in '..(r.zone or 'Unknown')..'. '..r.reason)
        end
    end end
end
local frame=CreateFrame('Frame'); K.frame=frame
for _,e in ipairs({'PLAYER_LOGIN','PLAYER_TARGET_CHANGED','PLAYER_FOCUS_CHANGED','UPDATE_MOUSEOVER_UNIT','NAME_PLATE_UNIT_ADDED','NAME_PLATE_UNIT_REMOVED','PARTY_KILL','PLAYER_REGEN_ENABLED','PLAYER_ENTERING_WORLD','PLAYER_GUILD_UPDATE'}) do pcall(frame.RegisterEvent,frame,e) end
frame:SetScript('OnEvent',function(_,event,a,b)
    if not GP.db then return end
    if event=='PLAYER_LOGIN' then K.Init(); if GP.KoSSync then GP.KoSSync.Init() end; K.Observe('target'); K.Observe('focus')
    elseif not K.rows then return
    elseif event=='PARTY_KILL' then K.Kill(a,b)
    elseif event=='NAME_PLATE_UNIT_REMOVED' then K.units[a]=nil
    elseif event=='NAME_PLATE_UNIT_ADDED' then K.Observe(a)
    else K.Observe('target'); K.Observe('focus'); K.Observe('mouseover') end
    if GP.UI and GP.UI.RefreshKoSPortraits then GP.UI.RefreshKoSPortraits() end
end)
frame:SetScript('OnUpdate',function(_,elapsed) if GP.db then K.Update(elapsed); if GP.KoSSync then GP.KoSSync.Update(elapsed) end end end)
