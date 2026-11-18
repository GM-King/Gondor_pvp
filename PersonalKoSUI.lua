local _, GP = ...
local UI, P, K = GP.UI, GP.PersonalKoS, GP.KoS
local tableUI=UI.KoSTable
local function text(parent,caption,x,y,width)
    local t=parent:CreateFontString(nil,'OVERLAY','GameFontNormal')
    t:SetPoint('TOPLEFT',x,-y); t:SetSize(width,24); t:SetText(caption); t:SetJustifyH('LEFT')
    return t
end
local function button(parent,caption,x,y,width,action)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate')
    b:SetSize(width,24); b:SetPoint('TOPLEFT',x,-y); b:SetText(caption); b:SetScript('OnClick',action)
    return b
end
local function frame(name,width,height,title)
    local f=CreateFrame('Frame',name,UIParent,'BackdropTemplate')
    f:SetSize(width,height); f:SetPoint('CENTER'); f:SetFrameStrata('DIALOG'); f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    f:SetBackdropColor(.08,.035,.03,1); f:SetBackdropBorderColor(.65,.42,.18,1)
    text(f,title,12,10,width-48)
    local close=CreateFrame('Button',nil,f,'UIPanelCloseButton'); f.close=close; close:SetPoint('TOPRIGHT'); close:SetScript('OnClick',function() f:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames,name) end
    tableUI.Window(f)
    f:Hide()
    return f
end
local function edit(parent,x,y,width)
    local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate')
    e:SetSize(width,24); e:SetPoint('TOPLEFT',x,-y); e:SetAutoFocus(false); e:SetMaxLetters(100)
    return e
end

function UI.ShowMinimapOptions()
    local f=UI.minimapOptions
    if not f then
        f=frame('GondorPvPMinimapOptions',180,130,'Gondor PvP'); UI.minimapOptions=f
        button(f,'Menu',10,38,160,function() f:Hide(); UI.Build(); UI.Refresh(); UI.frame:Show() end)
        button(f,'Personal KoS',10,66,160,function() f:Hide(); UI.ShowPersonalKoS() end)
        button(f,'Guild KoS',10,94,160,function() f:Hide(); UI.ShowKoS() end)
        f:Hide()
    end
    if f:IsShown() then f:Hide(); return end
    f:ClearAllPoints(); f:SetPoint('TOPRIGHT',UI.minimap,'BOTTOMRIGHT',0,-2); f:Show()
end

function UI.RefreshPersonalKoS()
    local f=UI.personalKoS
    if not f or not f:IsShown() then return end
    local query=(f.search:GetText() or ''):lower()
    local sort=GP.db.settings.personalKoSSort or 'name'
    local ascending=GP.db.settings.personalKoSAscending~=false
    local changed=f.revision~=P.revision or f.query~=query
    if changed then
        f.revision=P.revision; f.query=query; f.list={}
        for _,r in pairs(P.rows) do if r.name:lower():find(query,1,true) then f.list[#f.list+1]=r end end
        f.killCounts={}
        for _,r in ipairs(f.list) do local count=0; for _ in pairs(r.history) do count=count+1 end; f.killCounts[r.key]=count end
    end
    if changed or f.sort~=sort or f.ascending~=ascending or sort=='seen' then
        f.sort=sort; f.ascending=ascending
        table.sort(f.list,function(a,b)
            local av,bv=a.name:lower(),b.name:lower()
            if sort=='level' then
                av,bv=(a.identity and a.identity.level or 0),(b.identity and b.identity.level or 0)
                if (av==0)~=(bv==0) then return av~=0 end
            elseif sort=='seen' then av,bv=a.seen or 0,b.seen or 0
            elseif sort=='kills' then av,bv=f.killCounts[a.key],f.killCounts[b.key] end
            if av==bv then return a.key<b.key end
            if ascending then return av<bv end
            return av>bv
        end)
    end
    local panel=f.listPanel
    tableUI.ScrollRange(panel,#f.list,10)
    for i,row in ipairs(f.rows) do
        local r=f.list[panel.offset+i]; row.record=r; row:SetShown(r~=nil)
        if r then
            local guild=K.Active(K.rows[r.key])
            P.VerifyGuild(r.key)
            local identity=r.identity or {}
            row.name:SetText(r.name); tableUI.Colour(row.name,identity.class)
            row.name:SetWidth(guild and 112 or 188)
            row.guildIndicator:SetShown(guild)
            row.level:SetText((identity.level or 0)>0 and tostring(identity.level) or '?')
            row.seen:SetText(r.seen and tableUI.Age(r.seen) or 'Never')
            row.kills:SetText(tostring(f.killCounts[r.key] or 0))
            row.push:SetEnabled(r.verified and GP.IsEligibleGuild() and not guild)
        end
    end
    panel.empty:SetShown(#f.list==0)
    for _,h in ipairs(f.headings) do
        h.arrow:SetShown(sort==h.field)
        if sort==h.field then h.arrow:SetTexCoord(0,1,ascending and 1 or 0,ascending and 0 or 1) end
    end
    f.count:SetText(P.count..'/1000 enemies | Showing '..math.min(#f.list,panel.offset+1)..'–'..math.min(#f.list,panel.offset+10)..' of '..#f.list)
    tableUI.Fit(f)
end

function UI.ShowPersonalKoS()
    if not P.rows then P.Init() end
    if not UI.personalKoS then
        local f=frame('GondorPvPPersonalKoSFrame',730,660,'PERSONAL KoS — shared across your characters'); UI.personalKoS=f; f.rows={}; f.headings={}
        text(f,'Search',14,44,60); f.search=edit(f,80,44,280)
        text(f,'First name',14,80,78); f.firstName=edit(f,96,80,145)
        text(f,'Last name',255,80,78); f.lastName=edit(f,337,80,170)
        text(f,'Reason',14,112,100); f.reason=edit(f,190,112,360)
        button(f,'Add to personal list',525,80,190,function()
            local first=f.firstName:GetText():match('^%s*(.-)%s*$')
            local last=f.lastName:GetText():match('^%s*(.-)%s*$')
            if not first:match('^[^%s%-]+$') or not last:match('^[^%s%-]+$') then
                GP.Print('Enter a first name and a last name in their separate fields.')
                return
            end
            if P.Add(first..' '..last,f.reason:GetText()) then
                f.firstName:SetText(''); f.lastName:SetText(''); f.reason:SetText(''); UI.RefreshPersonalKoS()
            end
        end)
        text(f,'Verified by an open-world encounter or active Guild KoS membership. [Guild KoS] marks shared targets.',14,145,700)
        local panel=tableUI.Panel(f,580,400,14,176); f.listPanel=panel
        local header=tableUI.Panel(panel,578,32,1,1); header:SetBackdropColor(.22,.18,.12,1)
        for _,spec in ipairs({{'Name','name',8,190},{'Level','level',200,56},{'Last Seen','seen',258,90},{'Total Kills','kills',350,100}}) do
            local h=CreateFrame('Button',nil,header); h:SetSize(spec[4],30); h:SetPoint('TOPLEFT',spec[3],-2)
            h.field=spec[2]; h.title=tableUI.Text(h,11,0,3,spec[4]-12,24,spec[1],h.field=='name' and 'LEFT' or 'CENTER')
            h.arrow=h:CreateTexture(nil,'OVERLAY'); h.arrow:SetSize(8,8); h.arrow:SetPoint('RIGHT',-1,0); h.arrow:SetTexture('Interface\\Buttons\\UI-SortArrow')
            h:SetScript('OnClick',function()
                if (GP.db.settings.personalKoSSort or 'name')==h.field then GP.db.settings.personalKoSAscending=not (GP.db.settings.personalKoSAscending~=false)
                else GP.db.settings.personalKoSSort=h.field; GP.db.settings.personalKoSAscending=h.field=='name' end
                panel.offset=0; UI.RefreshPersonalKoS()
            end)
            f.headings[#f.headings+1]=h
        end
        for i=1,10 do
            local row=tableUI.Panel(panel,550,36,2,34+(i-1)*36)
            row:SetBackdropBorderColor(0,0,0,0)
            local shade=i%2==0 and .10 or .075; row:SetBackdropColor(shade,shade+.008,shade+.018,1)
            local player=CreateFrame('Button',nil,row); row.player=player; player:SetSize(452,36); player:SetPoint('TOPLEFT')
            row.name=tableUI.Text(player,13,8,6,188,24)
            row.guildIndicator=tableUI.Text(player,10,124,6,70,24,'[Guild KoS]','CENTER')
            row.guildIndicator:SetTextColor(1,.2,.2)
            if row.name.SetWordWrap then row.name:SetWordWrap(false) end
            row.level=tableUI.Text(player,12,198,6,56,24,nil,'CENTER')
            row.seen=tableUI.Text(player,12,256,6,90,24)
            row.kills=tableUI.Text(player,12,348,6,90,24,nil,'RIGHT')
            row.push=button(row,'Push to Guild',586,6,110,function() if row.record then P.Push(row.record.key); UI.RefreshPersonalKoS() end end)
            player:SetScript('OnEnter',function()
                local r=row.record; if not r then return end
                row.name:SetAlpha(.8)
                if GameTooltip then
                    GameTooltip:SetOwner(player,'ANCHOR_RIGHT'); GameTooltip:AddLine(r.name)
                    GameTooltip:AddLine((r.verified and 'Verified' or 'Unverified')..' | '..(K.Active(K.rows[r.key]) and 'Guild active' or 'Guild inactive'))
                    GameTooltip:AddLine('Click for reason and kill history.'); GameTooltip:Show()
                end
            end)
            player:SetScript('OnLeave',function() row.name:SetAlpha(1); if GameTooltip then GameTooltip:Hide() end end)
            player:SetScript('OnClick',function()
                local r=row.record; if not r then return end
                UI.ShowKoSDetails(r,true)
            end)
            row.delete=button(row,'Delete',474,5,64,function()
                local r=row.record; if not r then return end
                local confirm=UI.personalConfirm
                if not confirm then
                    confirm=frame('GondorPvPPersonalConfirm',400,140,'Remove from Personal KoS?'); UI.personalConfirm=confirm
                    confirm.caption=text(confirm,'',15,45,370)
                    button(confirm,'Remove',30,90,130,function()
                        if P.rows[confirm.key] then P.rows[confirm.key]=nil; P.count=P.count-1; P.revision=P.revision+1 end
                        confirm:Hide(); UI.RefreshPersonalKoS()
                    end)
                    button(confirm,'Cancel',230,90,130,function() confirm:Hide() end)
                end
                confirm.key=r.key; confirm.caption:SetText(r.name); tableUI.Window(confirm); confirm:Show()
            end)
            f.rows[i]=row
        end
        panel.empty=tableUI.Text(panel,13,15,170,520,50,'No players on your Personal KoS list.','CENTER')
        tableUI.Scroll(panel,'GondorPvPPersonalKoSScroll',UI.RefreshPersonalKoS); panel.scrollbar:SetHeight(320)
        f.count=text(f,'',14,582,700)
        text(f,'Click a name for details. Hover for verification and guild status.',14,620,700)
        f.search:SetScript('OnTextChanged',function() panel.offset=0; UI.RefreshPersonalKoS() end)
        f:SetScript('OnUpdate',function(_,elapsed) f.elapsed=(f.elapsed or 0)+elapsed; if f.elapsed>=1 then f.elapsed=0; UI.RefreshPersonalKoS() end end)
    end
    tableUI.Window(UI.personalKoS); UI.personalKoS:Show(); UI.RefreshPersonalKoS()
end
