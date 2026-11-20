local _,GP=...
local K=GP.KoS
local T={seen={},plates={},dead={},serial=0,clock=0}
GP.KoSTargets=T
local safe=K.Safe
local function combat() return safe(InCombatLockdown)==true end
local function tracked(key)
    return (GP.IsEligibleGuild() and K.Active(K.rows[key])) or (GP.PersonalKoS and GP.PersonalKoS.rows and GP.PersonalKoS.rows[key])
end
local function allowed() return GP.db and K.rows and not GP.Network.InInstance() end

function T.TargetName(name)
    -- Forever exposes first/last names with a dash in unit identities, but
    -- /targetexact expects their displayed space-separated character name.
    -- Keep realm-qualified names intact on clients using realm-based names.
    if safe(RegionalUniqueNamesEnabled)==true then return (name:gsub('-', ' ')) end
    return name
end

function T.Observe(unit,live)
    local id=K.Identity(unit); local key=id and K.Name(id.name)
    if not key or not tracked(key) then return end
    local death=id.guid and T.dead[id.guid]
    if death then
        if safe(UnitIsDeadOrGhost,unit)==true then death.corpse=true
        elseif death.corpse or T.clock-death.at>=30 then T.dead[id.guid]=nil; death=nil end
        if death then T.seen[key]=nil; return end
    end
    if safe(UnitIsDeadOrGhost,unit)==true then T.seen[key]=nil; live[key]=nil; return end
    if safe(UnitExists,unit)~=true or safe(UnitIsVisible,unit)~=true or safe(UnitIsDeadOrGhost,unit)~=false then return end
    local r=T.seen[key]
    if not r then T.serial=T.serial+1; r={key=key,order=T.serial}; T.seen[key]=r end
    r.name=id.name; r.at=T.clock; r.unit=unit; r.guid=id.guid; r.class=id.class; r.level=id.level
    local _,class=safe(UnitClass,unit); r.classToken=class
    live[key]=true
end

local function tooltip(b)
    local r=b.entry; local record=r and (K.rows[r.key] or (GP.PersonalKoS and GP.PersonalKoS.rows and GP.PersonalKoS.rows[r.key]))
    if not record or not GameTooltip then return end
    GameTooltip:SetOwner(b,'ANCHOR_BOTTOM')
    GameTooltip:AddLine(T.TargetName(r.name),1,.82,.45)
    GameTooltip:AddLine((r.class~='' and r.class or 'Unknown')..' — Level '..((r.level or 0)>0 and r.level or '?'))
    GameTooltip:AddLine(record.reason or '',1,1,1,true)
    GameTooltip:AddLine(r.detected and 'Currently detected' or 'Recently seen (30-second grace)',.8,.8,.8)
    if b.combatPreview then GameTooltip:AddLine('Click to target after combat.',.8,.8,.8) end
    GameTooltip:Show()
end

local function positionBox(f)
    local p=GP.db.settings.kosTargetsPosition
    f:ClearAllPoints()
    if type(p)=='table' and type(p.x)=='number' and type(p.y)=='number' and p.x==p.x and p.y==p.y and p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1 then
        local w,h=UIParent:GetWidth(),UIParent:GetHeight()
        f:SetPoint('CENTER',UIParent,'BOTTOMLEFT',math.max(f:GetWidth()/2,math.min(w-f:GetWidth()/2,p.x*w)),math.max(f:GetHeight()/2,math.min(h-f:GetHeight()/2,p.y*h)))
    else f:SetPoint('TOP',UIParent,'TOP',0,-100) end
    -- Keep the combat display independent of the protected target buttons.
    if f==T.combatBox and T.box and T.box:IsShown() then
        local x,y=T.box:GetCenter()
        if x and y then
            f:ClearAllPoints()
            f:SetPoint('TOP',UIParent,'BOTTOMLEFT',x,y-T.box:GetHeight()/2-6)
        end
    end
end

local function build(preview)
    local name=preview and 'GondorPvPKoSCombatTargets' or 'GondorPvPKoSTargets'
    local f=CreateFrame('Frame',name,UIParent,'BackdropTemplate')
    f.buttons={}
    f:Hide(); f:SetFrameStrata('MEDIUM'); f:SetMovable(true); f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    f:SetBackdropColor(.10,.03,.03,.92); f:SetBackdropBorderColor(.65,.48,.20,1)
    local header=CreateFrame('Frame',nil,f); f.header=header
    header:SetPoint('TOPLEFT',0,0); header:SetSize(130,24); header:EnableMouse(true); header:RegisterForDrag('LeftButton')
    local title=header:CreateFontString(nil,'OVERLAY','GameFontNormal'); title:SetPoint('LEFT',8,0); title:SetText('KoS Targets'); title:SetTextColor(1,.82,.45)
    header:SetScript('OnDragStart',function() if not combat() then T.dragging=true; f:StartMoving() end end)
    header:SetScript('OnDragStop',function()
        if not T.dragging then return end
        f:StopMovingOrSizing(); T.dragging=false
        local x,y=f:GetCenter(); local ratio=f:GetEffectiveScale()/UIParent:GetEffectiveScale()
        GP.db.settings.kosTargetsPosition={x=math.max(0,math.min(1,x*ratio/UIParent:GetWidth())),y=math.max(0,math.min(1,y*ratio/UIParent:GetHeight()))}
    end)
    local close=CreateFrame('Button',nil,f,not preview and 'SecureHandlerClickTemplate' or nil); f.close=close
    close:SetSize(22,22); close:SetPoint('TOPRIGHT',-2,-1)
    local x=close:CreateFontString(nil,'OVERLAY','GameFontNormal'); x:SetAllPoints(); x:SetText('X')
    close:RegisterForClicks('LeftButtonUp')
    if preview then
        close:SetScript('OnClick',function()
            if T.box and T.box:IsShown() then T.previewDismissed=true else T.dismissed=true end
            f:Hide()
        end)
    else
        close:SetFrameRef('box',f)
        close:SetAttribute('_onclick',"self:GetFrameRef('box'):Hide()")
        close:SetScript('PostClick',function()
            T.dismissed=true
            if T.combatBox then T.combatBox:Hide() end
        end)
    end
    return f
end

local function render(list,preview)
    local slot=preview and 'combatBox' or 'box'
    local f=T[slot]
    if #list==0 or T.dismissed or (preview and T.previewDismissed) then
        if f then f:Hide() end
        return
    end
    local signature={}
    for _,r in ipairs(list) do signature[#signature+1]=r.key..'|'..r.name..'|'..tostring(r.detected) end
    local position=GP.db.settings.kosTargetsPosition
    if type(position)~='table' then position={} end
    signature=table.concat(signature,';')..tostring(SetPortraitTexture)..tostring(position.x)..tostring(position.y)..UIParent:GetWidth()..'x'..UIParent:GetHeight()
    if f and f:IsShown() and f.signature==signature then return end
    if not f then f=build(preview); T[slot]=f end
    f.signature=signature
    local width=math.max(160,12+math.min(10,#list)*36)
    f:SetSize(width,30+math.ceil(#list/10)*36); f.header:SetWidth(width-26)
    for i,r in ipairs(list) do
        local b=f.buttons[i]
        if not b then
            b=CreateFrame('Button',nil,f,not preview and 'SecureActionButtonTemplate' or nil); f.buttons[i]=b
            b:SetSize(32,32)
            b.combatPreview=preview
            if not preview then
                b:RegisterForClicks('AnyUp','AnyDown')
                b:SetAttribute('type','macro')
            end
            b.icon=b:CreateTexture(nil,'ARTWORK'); b.icon:SetAllPoints()
            b:SetScript('OnEnter',tooltip); b:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
            local highlight=b:CreateTexture(nil,'HIGHLIGHT')
            highlight:SetAllPoints()
            highlight:SetTexture('Interface\\Buttons\\ButtonHilight-Square')
            highlight:SetBlendMode('ADD')
        end
        local changed=not b.entry or b.entry.key~=r.key
        b.entry=r
        if not preview then b:SetAttribute('macrotext','/targetexact '..T.TargetName(r.name)) end
        b:ClearAllPoints(); b:SetPoint('TOPLEFT',6+((i-1)%10)*36,-26-math.floor((i-1)/10)*36)
        if changed or not b.portrait then
            local coords=CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[r.classToken or '']
            b.icon:SetTexture(coords and 'Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes' or 'Interface\\Icons\\INV_Misc_QuestionMark')
            b.icon:SetTexCoord(unpack(coords or {0,1,0,1})); b.portrait=false
        end
        local id=r.detected and r.unit and K.Identity(r.unit)
        if id and K.Name(id.name)==r.key and type(SetPortraitTexture)=='function' then
            b.icon:SetTexCoord(0,1,0,1); safe(SetPortraitTexture,b.icon,r.unit); b.portrait=true
        end
        b:Show()
    end
    for i=#list+1,#f.buttons do f.buttons[i]:Hide(); f.buttons[i].entry=nil end
    positionBox(f); f:Show()
end

function T.Render(list)
    if combat() then
        local bound={}
        if T.box and T.box:IsShown() then
            for _,button in ipairs(T.box.buttons) do
                if button.entry and button:IsShown() then bound[button.entry.key]=true end
            end
        end
        local preview={}
        for _,entry in ipairs(list) do
            if not bound[entry.key] then preview[#preview+1]=entry end
        end
        render(preview,true)
        return
    end
    if T.combatBox then T.combatBox:Hide() end
    T.previewDismissed=false
    if not T.dragging then render(list,false) end
end

function T.Refresh()
    if not GP.db then return end
    local live={}
    if allowed() then
        local units={'target','focus','mouseover'}
        local plates=safe(C_NamePlate and C_NamePlate.GetNamePlates)
        if type(plates)=='table' then
            for _,p in ipairs(plates) do
                local unit=p.namePlateUnitToken
                if not (issecretvalue and issecretvalue(unit)) and type(unit)=='string' then T.plates[unit]=true end
            end
        end
        for unit in pairs(T.plates) do units[#units+1]=unit end
        -- Also works on clients without nameplate enumeration, including login mid-encounter.
        if not plates then for i=1,40 do units[#units+1]='nameplate'..i end end
        for _,unit in ipairs(units) do if GP.PersonalKoS then GP.PersonalKoS.Observe(unit) end; T.Observe(unit,live) end
        for key,r in pairs(T.seen) do
            if not tracked(key) or T.clock-r.at>=30 then T.seen[key]=nil
            else r.detected=live[key] or false end
        end
    else T.seen={}; T.plates={}; T.dead={} end
    for guid,death in pairs(T.dead) do if T.clock-death.at>=30 then T.dead[guid]=nil end end
    local list={}; for _,r in pairs(T.seen) do list[#list+1]=r end
    table.sort(list,function(a,b) return a.order<b.order end)
    if #list==0 then T.dismissed=false end
    T.Render(list)
end

function T.ShowNearby() T.dismissed=false; T.previewDismissed=false; T.Refresh() end
local events=CreateFrame('Frame'); T.frame=events
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_ENTERING_WORLD','PLAYER_GUILD_UPDATE','PLAYER_TARGET_CHANGED','PLAYER_FOCUS_CHANGED','UPDATE_MOUSEOVER_UNIT','NAME_PLATE_UNIT_ADDED','NAME_PLATE_UNIT_REMOVED','PLAYER_REGEN_DISABLED','PLAYER_REGEN_ENABLED','PARTY_KILL'}) do pcall(events.RegisterEvent,events,event) end
events:SetScript('OnEvent',function(_,event,a,b)
    if event=='NAME_PLATE_UNIT_ADDED' or event=='NAME_PLATE_UNIT_REMOVED' then
        if not (issecretvalue and issecretvalue(a)) and type(a)=='string' then
            T.plates[a]=event=='NAME_PLATE_UNIT_ADDED' and true or nil
        end
    elseif event=='PLAYER_ENTERING_WORLD' then T.seen={}; T.plates={}; T.dead={}; T.dismissed=false; T.previewDismissed=false
    elseif event=='PARTY_KILL' and not (issecretvalue and issecretvalue(b)) and type(b)=='string' then
        for key,r in pairs(T.seen) do
            if r.guid==b then T.seen[key]=nil; T.dead[b]={at=T.clock} end
        end
    end
    T.Refresh()
end)
events:SetScript('OnUpdate',function(_,elapsed)
    T.clock=T.clock+elapsed; T.elapsed=(T.elapsed or 0)+elapsed
    if T.elapsed>=.25 then T.elapsed=0; T.Refresh() end
end)
