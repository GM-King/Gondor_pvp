local _, GP = ...
local UI = { page = 1, buttons = {}, offerQueue = {} }
GP.UI = UI
local media = "Interface\\AddOns\\Gondor_PvP\\Media\\Cards\\"
local pages = 9
local function now() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end

-- Each window owns a separate range, including all of its descendants.
local windows={}
local function levels(frame,level,root)
    if frame.SetFrameLevel then frame:SetFrameLevel(level) end
    -- Automatic top-level raising can promote the launcher after its click
    -- opens a different window. Keep stacking entirely under this manager.
    if frame.SetToplevel then frame:SetToplevel(false) end
    frame:SetFrameStrata("DIALOG")
    if frame~=root and not frame.gondorRaiseHook then
        frame.gondorRaiseHook=true
        frame:HookScript("OnMouseDown",function() root.gondorRaise() end)
    end
    if frame.GetChildren then
        for _,child in ipairs({frame:GetChildren()}) do levels(child,level+1,root) end
    end
end
local restackPending=false
local function restack()
    for i,w in ipairs(windows) do levels(w,i*30,w) end
end
local function raiseWindow(f)
    for i,w in ipairs(windows) do if w==f then table.remove(windows,i); break end end
    windows[#windows+1]=f
    restack()
    -- Reapply the latest order after the client's click/show dispatch finishes.
    -- A later opened window wins even when several opens share the same frame.
    if not restackPending and C_Timer and C_Timer.After then
        restackPending=true
        C_Timer.After(0,function() restackPending=false; restack() end)
    end
end
local function window(f)
    if f.gondorWindow then raiseWindow(f); return end
    f.gondorWindow=true
    f.gondorRaise=function() raiseWindow(f) end
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG"); f:EnableMouse(true)
    if f.SetToplevel then f:SetToplevel(false) end
    f:HookScript("OnShow",function() raiseWindow(f) end)
    f:HookScript("OnMouseDown",function() raiseWindow(f) end)
    raiseWindow(f)
end
local function label(parent, size, x, y, width, height)
    local result = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    result:SetPoint("TOPLEFT", x, -y); result:SetSize(width, height)
    result:SetFont("Fonts\\FRIZQT__.TTF", size, ""); result:SetJustifyH("CENTER")
    return result
end

local function button(parent, caption, width, x, y, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:HookScript("OnMouseDown",function() local root=parent; while root and not root.gondorWindow and root.GetParent do root=root:GetParent() end; if root then raiseWindow(root) end end)
    b:SetSize(width, 26); b:SetPoint("BOTTOMLEFT", x, y); b:SetText(caption); b:SetScript("OnClick", action)
    return b
end

local function art(parent, width, height)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(width, height)
    return t
end

local function setCardTexture(texture, index)
    local cell=(index-1)%4
    local x=(cell%2)*512
    local y=math.floor(cell/2)*1024
    texture:SetTexture(media .. string.format("atlas_%02d",math.floor((index-1)/4)+1))
    texture:SetTexCoord((x+4)/1024,(x+508)/1024,(y+64)/2048,(y+960)/2048)
end

local function attachSheen(owner, picture, width, height)
    local shine=owner:CreateTexture(nil,"OVERLAY")
    shine:SetTexture("Interface\\Buttons\\WHITE8X8"); shine:SetAlpha(0.10); shine:SetSize(7,height-8); shine:Hide()
    owner.shine=shine; owner.shinePicture=picture; owner.shineWidth=width
    owner:SetScript("OnUpdate",function(self,elapsed)
        if not self.shining or GP.db.settings.reducedMotion then self.shining=false; shine:Hide(); return end
        self.shineTime=(self.shineTime or 0)+elapsed
        local progress=self.shineTime/1.1
        if progress>=1 then self.shining=false; shine:Hide(); return end
        shine:ClearAllPoints(); shine:SetPoint("TOPLEFT",picture,"TOPLEFT",4+(width-15)*progress,-4)
        shine:Show()
    end)
end
local function startSheen(owner)
    if not GP.db.settings.reducedMotion then owner.shineTime=0; owner.shining=true end
end

function UI.InCombat()
    return UI.combat or (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

function UI.PlaceAward(f)
    local w,h=UIParent:GetWidth(),UIParent:GetHeight()
    local scale=math.min(1,(w-32)/320,(h-32)/630)
    scale=math.max(0.1,scale)
    local p=GP.db.settings.awardPosition
    local x=math.max(160*scale+16,math.min(w-160*scale-16,p.x*w))
    local y=math.max(315*scale+16,math.min(h-315*scale-16,p.y*h))
    f:SetScale(scale); f:ClearAllPoints()
    f:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x/scale,y/scale)
end

function UI.RefreshPlacement()
    if not GP.db then return end
    local visible=not UI.InCombat() and ((UI.frame and UI.frame:IsShown()) or (UI.settings and UI.settings:IsShown()))
    if visible and not UI.placement then
        local f=CreateFrame("Frame","GondorPvPAwardPosition",UIParent,"BackdropTemplate")
        UI.placement=f; f:SetSize(320,630); f:SetFrameStrata("TOOLTIP")
        f:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
        f:SetBackdropBorderColor(1,0.75,0.3,0.8)
        local handle=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
        handle:SetSize(320,26); handle:SetPoint("TOP",0,0); handle:SetText("Card unlock position — drag to move")
        f:SetMovable(true); f:SetClampedToScreen(true); handle:RegisterForDrag("LeftButton")
        handle:SetScript("OnDragStart",function()
            if UI.InCombat() then return end
            UI.dragging=true; f:StartMoving()
        end)
        local function stop()
            if not UI.dragging then return end
            f:StopMovingOrSizing(); UI.dragging=false
            local x,y=f:GetCenter(); local ratio=f:GetEffectiveScale()/UIParent:GetEffectiveScale()
            GP.db.settings.awardPosition={x=math.max(0,math.min(1,x*ratio/UIParent:GetWidth())),y=math.max(0,math.min(1,y*ratio/UIParent:GetHeight()))}
            if UI.viewer then UI.viewer.awardElapsed=0 end
            UI.RefreshPlacement()
        end
        f.stopDrag=stop; handle:SetScript("OnDragStop",stop)
        f:SetScript("OnUpdate",function()
            if UI.dragging and UI.viewer and UI.viewer.award then
                UI.viewer:ClearAllPoints(); UI.viewer:SetPoint("CENTER",f,"CENTER",0,0)
            end
        end)
    end
    if UI.placement then
        if not visible and UI.dragging then UI.placement.stopDrag() end
        UI.PlaceAward(UI.placement); UI.placement:SetShown(visible)
    end
    if UI.viewer and UI.viewer.award and not UI.dragging then UI.PlaceAward(UI.viewer) end
end

function UI.OnEvent(event)
    if event=="PLAYER_REGEN_DISABLED" then
        UI.combat=true
        if UI.viewer and UI.viewer.award and UI.viewer:IsShown() then
            UI.suspending=true; UI.viewer:Hide(); UI.suspending=nil
        end
        if UI.offer and UI.offer:IsShown() then
            UI.QueueOffer(UI.offer.token,UI.offer.currentOffer,UI.offer.zone,true)
            UI.offer:Hide()
        end
    elseif event=="PLAYER_REGEN_ENABLED" then UI.combat=nil end
    UI.RefreshPlacement()
    if event=="PLAYER_REGEN_ENABLED" then GP.Cards.Refresh(); UI.ShowNextAward(); UI.ShowNextOffer() end
end

function UI.ShowCard(index, award)
    if not GP.Cards.IsUnlocked(index) or (award and UI.InCombat()) then return end
    if UI.viewer and UI.viewer:IsShown() then
        UI.suspending=true; UI.viewer:Hide(); UI.suspending=nil
    end
    if not UI.viewer then
        local v = CreateFrame("Frame", "GondorPvPCardViewer", UIParent, "BackdropTemplate")
        UI.viewer = v; v:SetSize(320, 630); v:SetPoint("CENTER"); v:SetFrameStrata("DIALOG")
        v:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=2})
        v:SetBackdropColor(0.08,0.035,0.03,1); v:SetBackdropBorderColor(0.65,0.42,0.18,1)
        v.heading = label(v, 18, 10, 12, 300, 30)
        v.picture = art(v, 270, 480); v.picture:SetPoint("TOP", 0, -55)
        attachSheen(v,v.picture,270,480)
        v.caption = label(v, 14, 10, 547, 300, 34)
        button(v, "Close", 110, 105, 15, function() v:Hide() end)
        v:HookScript("OnUpdate",function(self,elapsed)
            if self.award and not UI.dragging then
                if UI.InCombat() then UI.OnEvent("PLAYER_REGEN_DISABLED"); return end
                self.awardElapsed=(self.awardElapsed or 0)+elapsed
                if self.awardElapsed>=5 then self:Hide() end
            end
        end)
        v:SetScript("OnHide",function()
            if not UI.suspending and v.award and v.index then
                GP.db.pendingCards[v.index]=nil; GP.db.presented[v.index]=true
            end
            v.award=nil
            if not UI.suspending then UI.ShowNextAward() end
        end)
        if UISpecialFrames then table.insert(UISpecialFrames,"GondorPvPCardViewer") end
    end
    UI.viewer.index=index; UI.viewer.award=award; UI.viewer.awardElapsed=0
    UI.viewer:ClearAllPoints(); UI.viewer:SetScale(1)
    if award then UI.PlaceAward(UI.viewer) else UI.viewer:SetPoint("CENTER",UIParent,"CENTER",0,0) end
    local card = GP.CardCatalog[index]
    UI.viewer.heading:SetText(award and "NEW CARD UNLOCKED!" or "YOUR COLLECTION")
    setCardTexture(UI.viewer.picture,index)
    UI.viewer.caption:SetText(card.name .. "  |  " .. GP.Cards.thresholds[index] .. " honorable kills")
    window(UI.viewer); UI.viewer:Show()
    startSheen(UI.viewer)

end

function UI.ShowNextAward()
    if UI.InCombat() or not GP.db or not GP.Cards.kills or (UI.viewer and UI.viewer:IsShown()) then return end
    for i = 1, GP.Cards.count do
        if GP.db.pendingCards[i] and GP.Cards.IsUnlocked(i) then UI.ShowCard(i, true); return end
    end
end

function UI.Build()
    if UI.frame then return end
    local f = CreateFrame("Frame", "GondorPvPFrame", UIParent, "BackdropTemplate")
    if UISpecialFrames then table.insert(UISpecialFrames,"GondorPvPFrame") end
    f:SetScript("OnShow",UI.RefreshPlacement); f:SetScript("OnHide",UI.RefreshPlacement)
    window(f); UI.frame = f; f:SetSize(780, 680); f:SetPoint("CENTER")
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=2})
    f:SetBackdropColor(0.08,0.035,0.03,1); f:SetBackdropBorderColor(0.65,0.42,0.18,1)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    label(f, 24, 20, 14, 740, 34):SetText("GONDOR PvP — CARD BINDER")
    local mascot=f:CreateTexture(nil,"ARTWORK"); mascot:SetSize(55,55); mascot:SetPoint("TOPLEFT",12,-10)
    mascot:SetTexture("Interface\\AddOns\\Gondor_PvP\\Media\\Murloc")
    local horde=f:CreateTexture(nil,"ARTWORK"); horde:SetSize(100,50); horde:SetPoint("TOPRIGHT",-30,-7)
    horde:SetTexture("Interface\\AddOns\\Gondor_PvP\\Media\\Horde")
    UI.status = label(f, 12, 20, 52, 590, 28)
    button(f, "Kill on Sight", 120, 635, 605, function() UI.ShowKoS() end)
    for i = 1, 8 do
        local card = CreateFrame("Button", nil, f, "BackdropTemplate")
        card:SetSize(164, 267); card:SetPoint("TOPLEFT", 36 + ((i-1)%4)*181, -(85 + math.floor((i-1)/4)*282))
        card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
        card:SetBackdropColor(0.12,0.07,0.055,1); card:SetBackdropBorderColor(0.4,0.27,0.13,1)
        card.picture = art(card, 126, 224); card.picture:SetPoint("TOP", 0, -8)
        attachSheen(card,card.picture,126,224)
        card.question = label(card, 48, 10, 68, 144, 75)
        card.caption = label(card, 11, 5, 238, 154, 25)
        card:SetScript("OnClick", function(self) if self.index then UI.ShowCard(self.index, false) end end)
        card:SetScript("OnEnter",function(self) if self.index then startSheen(self) end end)
        card:SetScript("OnLeave",function(self) self.shining=false; self.shine:Hide() end)
        UI.buttons[i] = card
    end
    button(f, "Previous", 110, 35, 15, function() UI.page=math.max(1,UI.page-1); UI.Refresh() end)
    button(f, "Next", 110, 635, 15, function() UI.page=math.min(pages,UI.page+1); UI.Refresh() end)
    button(f, "Kill Share", 110, 180, 15, function() UI.ShowKillShare() end)
    button(f, "Settings", 110, 490, 15, function() UI.ToggleSettings() end)
    UI.points = button(f, "Points", 140, 320, 15, function() UI.ShowPoints() end)
    local close=CreateFrame("Button",nil,f,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-2,-2)
    f:Hide()
end

function UI.BuildMinimap()
    if UI.minimap or not Minimap then return end
    local b=CreateFrame("Button","GondorPvPMinimapButton",UIParent)
    UI.minimap=b; b:SetSize(32,32); b:SetFrameStrata("MEDIUM")
    local icon=b:CreateTexture(nil,"ARTWORK"); icon:SetSize(22,22); icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\Gondor_PvP\\Media\\Murloc")
    local border=b:CreateTexture(nil,"OVERLAY"); border:SetSize(54,54); border:SetPoint("TOPLEFT",0,0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:RegisterForClicks("LeftButtonUp","RightButtonUp"); b:RegisterForDrag("LeftButton")
    local function place()
        local angle=math.rad(GP.db.settings.minimapAngle or 215)
        local ratio=Minimap:GetEffectiveScale()/UIParent:GetEffectiveScale()
        local rx,ry=Minimap:GetWidth()*ratio/2+24,Minimap:GetHeight()*ratio/2+24
        local x,y=math.cos(angle),math.sin(angle)
        if GetMinimapShape and GetMinimapShape()=="SQUARE" then
            local divisor=math.max(math.abs(x),math.abs(y)); x,y=x/divisor,y/divisor
        end
        b:ClearAllPoints(); b:SetPoint("CENTER",Minimap,"CENTER",x*rx,y*ry)
    end
    b:SetScript("OnClick",function(_,mouse)
        if b.skipClick then b.skipClick=false; return end
        if mouse=="RightButton" then UI.ToggleSettings() else UI.Toggle() end
    end)
    b:SetScript("OnDragStart",function() b.dragging=true end)
    b:SetScript("OnDragStop",function() b.dragging=false; b.skipClick=true; place() end)
    b:SetScript("OnUpdate",function(_,elapsed)
        if b.dragging then
            local x,y=GetCursorPosition(); local mx,my=Minimap:GetCenter(); local scale=Minimap:GetEffectiveScale()
            GP.db.settings.minimapAngle=math.deg(math.atan2(y/scale-my,x/scale-mx)); place()
        else
            b.refresh=(b.refresh or 0)+elapsed
            if b.refresh>=0.5 then b.refresh=0; place() end
        end
    end)
    b:SetScript("OnEnter",function(self)
        if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:AddLine("Gondor PvP"); GameTooltip:AddLine("Left click: binder  |  Right click: settings"); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    place()
end

function UI.Refresh()
    if not UI.frame then return end
    local kills=GP.Cards.kills
    UI.status:SetText("Lifetime honorable kills: " .. (kills and tostring(kills) or "Unavailable") .. "   |   Page " .. UI.page .. " / " .. pages)
    UI.points:SetText("Points: " .. GP.Network.Points())
    for i, card in ipairs(UI.buttons) do
        local index=(UI.page-1)*8+i
        card:SetShown(index<=GP.Cards.count)
        if index<=GP.Cards.count then
            local unlocked=GP.Cards.IsUnlocked(index)
            card.index=unlocked and index or nil
            card.question:SetText(unlocked and "" or "?")
            card.caption:SetText(unlocked and GP.CardCatalog[index].name or "Locked")
            if unlocked then setCardTexture(card.picture,index); card.picture:Show()
            else card.picture:SetTexture(nil); card.picture:Hide() end
        end
    end
end

local function refreshKillShare()
    local f=UI.killShare
    if not f then return end
    local active,request=GP.Network.active,GP.Network.request
    local lines={"YOUR ACTIVE FARE"}
    if active then
        lines[#lines+1]="Helping " .. GP.DisplayName(active.requester) .. "  |  " .. active.amount .. " points"
        lines[#lines+1]="Fare ends in "..math.max(0,math.ceil((GP.Network.Deadline(active.id)-now())/60)).." min."
    else lines[#lines+1]="No active fare." end
    lines[#lines+1]=""
    lines[#lines+1]="YOUR HELP REQUEST"
    if request then
        lines[#lines+1]="Request ends in "..math.max(0,math.ceil((GP.Network.Deadline(request.id)-now())/60)).." min."
        local helpers={}
        for _,helper in pairs(request.helpers or {}) do
            if type(helper.name)=="string" then helpers[#helpers+1]=GP.DisplayName(helper.name) end
        end
        table.sort(helpers)
        if #helpers==0 then lines[#lines+1]="Waiting for guildmates to respond."
        else
            lines[#lines+1]=#helpers .. (#helpers==1 and " guildmate responding:" or " guildmates responding:")
            for i=1,math.min(#helpers,6) do lines[#lines+1]=helpers[i] end
            if #helpers>6 then lines[#lines+1]="... and " .. (#helpers-6) .. " more" end
        end
    else lines[#lines+1]="No open request." end
    local remaining=math.max(0,math.ceil((GP.db.manualReadyAt or 0)-now()))
    lines[#lines+1]=""
    lines[#lines+1]=remaining>0 and ("Manual request available in " .. math.ceil(remaining/60) .. " min.") or "Manual request available."
    if GP.Network.StatusText then lines[#lines+1]=GP.Network.StatusText() end
    f.detail:SetText(table.concat(lines,"\n"))
end

function UI.ShowKillShare()
    if not UI.killShare then
        local f=CreateFrame("Frame","GondorPvPKillShare",UIParent,"BackdropTemplate")
        if UISpecialFrames then table.insert(UISpecialFrames,"GondorPvPKillShare") end
        UI.killShare=f; f:SetSize(430,550); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
        f:SetBackdropColor(0.08,0.035,0.03,1); f:SetBackdropBorderColor(0.65,0.42,0.18,1)
        label(f,20,10,25,300,30):SetText("KILL SHARE")
        local picture=art(f,90,90); picture:SetPoint("TOPRIGHT",-15,-8); picture:SetTexture("Interface\\AddOns\\Gondor_PvP\\Media\\Peon")
        f.detail=label(f,12,25,110,380,330); f.detail:SetJustifyH("LEFT"); f.detail:SetJustifyV("TOP")
        button(f,"Retry announcement",180,125,12,function() GP.Network.RetryAnnouncement(); refreshKillShare() end)
        button(f,"Request help",150,45,80,function() GP.Network.Request(true); refreshKillShare() end)
        button(f,"Cancel my fare",150,235,80,function() GP.Network.CancelFare(); refreshKillShare() end)
        button(f,"Withdraw request",150,45,45,function() GP.Network.CancelRequest(); refreshKillShare() end)
        button(f,"Close",150,235,45,function() f:Hide() end)
        f:SetScript("OnUpdate",function(self,elapsed)
            self.refreshElapsed=(self.refreshElapsed or 0)+elapsed
            if self.refreshElapsed>=1 then self.refreshElapsed=0; refreshKillShare() end
        end)
    end
    refreshKillShare(); window(UI.killShare); UI.killShare:Show()
end

function UI.ShowPoints()
    if not UI.pointFrame then
        local f=CreateFrame("Frame","GondorPvPPoints",UIParent,"BackdropTemplate")
        if UISpecialFrames then table.insert(UISpecialFrames,"GondorPvPPoints") end
        UI.pointFrame=f; f:SetSize(430,400); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
        f:SetBackdropColor(0.08,0.035,0.03,1); f:SetBackdropBorderColor(0.65,0.42,0.18,1)
        f.title=label(f,20,10,12,410,30)
        f.history=label(f,12,25,60,380,250); f.history:SetJustifyH("LEFT"); f.history:SetJustifyV("TOP")
        button(f,"Cancel my fare",150,45,50,function() GP.Network.CancelFare(); f:Hide() end)
        button(f,"Withdraw request",150,235,50,function() GP.Network.CancelRequest(); f:Hide() end)
        button(f,"Close",110,160,15,function() f:Hide() end)
    end
    local rows={}
    for _,record in pairs(GP.db.receipts or {}) do
        if GP.Network.ValidReceipt(record) then
            rows[#rows+1]=record
        end
    end
    for _,r in pairs(GP.db.kosReceipts or {}) do
        if GP.KoS and GP.KoS.ValidReceipt(r) then rows[#rows+1]={requester="KoS: "..GP.DisplayName(r.victim),amount=5,time=r.time} end
    end
    table.sort(rows,function(a,b) return a.time>b.time end)
    local lines={"Recent PvP rewards:"}
    if GP.Recovery then table.insert(lines,1,GP.Recovery.Status()) end
    for i=1,math.min(10,#rows) do
        local r=rows[i]; lines[#lines+1]=string.format("%s   +%d points",GP.DisplayName(r.requester),r.amount)
    end
    if #rows==0 then lines[#lines+1]="No completed fares yet." end
    lines[#lines+1]=""
    lines[#lines+1]=GP.Network.active and ("Active fare: " .. GP.DisplayName(GP.Network.active.requester)) or "No active fare."
    UI.pointFrame.title:SetText("PvP POINTS: " .. GP.Network.Points())
    UI.pointFrame.history:SetText(table.concat(lines,"\n"))
    window(UI.pointFrame); UI.pointFrame:Show()
end

local function checkbox(parent, title, y, key)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(26,26); c:SetPoint("TOPLEFT",25,-y)
    local caption = label(parent, 13, 60, y+5, 300, 25); caption:SetJustifyH("LEFT"); caption:SetText(title)
    c:SetChecked(GP.db.settings[key])
    c:SetScript("OnClick", function(self) GP.db.settings[key] = not not self:GetChecked() end)
    return c
end
function UI.ToggleSettings()
    if UI.settings then
        if UI.settings:IsShown() then UI.settings:Hide() else raiseWindow(UI.settings); UI.settings:Show() end
        return
    end
    local s=CreateFrame("Frame", "GondorPvPSettings", UIParent, "BackdropTemplate")
    if UISpecialFrames then table.insert(UISpecialFrames,"GondorPvPSettings") end
    s:SetScript("OnShow",UI.RefreshPlacement); s:SetScript("OnHide",UI.RefreshPlacement)
    UI.settings=s; s:SetSize(420,390); s:SetPoint("CENTER"); s:SetFrameStrata("DIALOG")
    s:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
    s:SetBackdropColor(0.08,0.035,0.03,1); s:SetBackdropBorderColor(0.65,0.42,0.18,1)
    label(s,20,10,14,400,30):SetText("GONDOR PvP SETTINGS")
    checkbox(s,"PvP death alerts",55,"alerts")
    checkbox(s,"Incoming Kill Share offers",92,"offers")
    checkbox(s,"Reduce card motion",129,"reducedMotion")
    local channelLabel=label(s,12,25,174,370,22); channelLabel:SetJustifyH("LEFT"); channelLabel:SetText("Announcement channel (name, GUILD, PARTY, or RAID)")
    local channel=CreateFrame("EditBox",nil,s,"InputBoxTemplate")
    channel:SetSize(350,25); channel:SetPoint("TOPLEFT",35,-200); channel:SetAutoFocus(false); channel:SetMaxLetters(30); channel:SetText(GP.db.settings.channel or "gcfrpvp")
    local expiryLabel=label(s,12,25,239,370,22); expiryLabel:SetJustifyH("LEFT"); expiryLabel:SetText("Offer expiry in seconds (5–60)")
    local expiry=CreateFrame("EditBox",nil,s,"InputBoxTemplate")
    expiry:SetSize(100,25); expiry:SetPoint("TOPLEFT",35,-265); expiry:SetAutoFocus(false); expiry:SetMaxLetters(2); expiry:SetNumeric(true); expiry:SetText(tostring(GP.db.settings.expiry or GP.defaults.expiry))
    button(s,"Save",110,55,24,function()
        local name=channel:GetText():gsub("^%s+",""):gsub("%s+$",""):gsub("^/","")
        if name=="" or name:find("[^%w ]") then GP.Print("Enter a valid channel name."); return end
        local seconds=tonumber(expiry:GetText())
        if not seconds or seconds<5 or seconds>60 then GP.Print("Offer expiry must be from 5 to 60 seconds."); return end
        GP.db.settings.channel=name; GP.db.settings.expiry=math.floor(seconds)
        GP.Network.JoinChannel()
        channel:ClearFocus(); expiry:ClearFocus(); s:Hide()
    end)
    button(s,"Close",110,250,24,function() s:Hide() end)
    window(s); s:Show(); UI.RefreshPlacement()
end

function UI.QueueOffer(token,offer,zone,first)
    if not offer then return end
    for _,queued in ipairs(UI.offerQueue) do
        if queued.token==token then queued.offer=offer; queued.zone=zone; return end
    end
    local entry={token=token,offer=offer,zone=zone}
    if first then table.insert(UI.offerQueue,1,entry) else UI.offerQueue[#UI.offerQueue+1]=entry end
end

function UI.ShowNextOffer()
    if UI.InCombat() or (UI.offer and UI.offer:IsShown()) then return end
    while #UI.offerQueue>0 do
        local entry=table.remove(UI.offerQueue,1)
        local offer=GP.Network.offers[entry.token]
        if offer and offer.expires>now() and not offer.deferred then
            UI.ShowOffer(entry.token,offer,entry.zone); return
        end
    end
end

function UI.ShowOffer(token, offer, zone)
    if offer.expires<=now() then return end
    if UI.InCombat() then UI.QueueOffer(token,offer,zone); return end
    if not UI.offer then
        local f=CreateFrame("Frame","GondorPvPOffer",UIParent,"BackdropTemplate")
        UI.offer=f; f:SetSize(370,280); f:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",-40,180); f:SetClampedToScreen(true); f:SetFrameStrata("DIALOG")
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
        f:SetBackdropColor(0.10,0.04,0.03,1); f:SetBackdropBorderColor(0.7,0.45,0.2,1)
        f.title=label(f,17,10,12,350,26)
        local picture=art(f,160,80); picture:SetPoint("TOP",0,-42); picture:SetTexture("Interface\\AddOns\\Gondor_PvP\\Media\\Chopper")
        f.detail=label(f,12,20,133,330,70)
        button(f,"Accept",115,55,20,function()
            local selected=f.token; if selected and GP.Network.Accept(selected) then f:Hide() end
        end)
        button(f,"Dismiss",115,200,20,function() GP.Network.offers[f.token]=nil; f:Hide() end)
        f:SetScript("OnUpdate",function(self)
            if UI.InCombat() then
                UI.QueueOffer(self.token,self.currentOffer,self.zone,true); self:Hide()
            elseif self.expires and now()>=self.expires then self:Hide() end
        end)
        f:Hide()
        f:SetScript("OnHide",UI.ShowNextOffer)
    end
    local f=UI.offer
    if f:IsShown() and f.token~=token then
        UI.QueueOffer(token,offer,zone); return
    end
    f.token=token; f.expires=offer.expires; f.currentOffer=offer; f.zone=zone
    f.title:SetText("PvP HELP REQUEST")
    f.detail:SetText(string.format("%s — %s %s\n%s (%.1f, %.1f)\nPotential reward: %s PvP Points",
        GP.DisplayName(offer.sender),offer.race or "Unknown",offer.class or "Unknown",zone,offer.x*100,offer.y*100,
        offer.quote and tostring(offer.quote) or "unavailable"))
    window(f); f:Show()
end

function UI.RemoveOffer(token)
    for i=#UI.offerQueue,1,-1 do
        if UI.offerQueue[i].token==token then table.remove(UI.offerQueue,i) end
    end
    if UI.offer and UI.offer.token==token and UI.offer:IsShown() then UI.offer:Hide() end
end

function UI.ClearOffers()
    UI.offerQueue={}
    if UI.offer and UI.offer:IsShown() then UI.offer:Hide() end
end

function UI.ConfirmDeath(serial)
    if not StaticPopupDialogs or not StaticPopup_Show then
        GP.Print("Death detected. If this was PvP, use /gpvp request.")
        return
    end
    if not StaticPopupDialogs.GONDOR_PVP_DEATH then
        StaticPopupDialogs.GONDOR_PVP_DEATH={
            text="Were you killed in PvP? Send a Gondor PvP help alert?",
            button1="Request help", button2="Decline", timeout=15, whileDead=true, hideOnEscape=true,
            OnAccept=function(_,data)
                GP.Network.RespondToDeathPrompt(data,true)
            end,
            OnCancel=function(_,data)
                GP.Network.RespondToDeathPrompt(data,false)
            end,
        }
    end
    StaticPopup_Show("GONDOR_PVP_DEATH",nil,nil,serial)
end

function UI.Toggle()
    UI.Build()
    if UI.frame:IsShown() then UI.frame:Hide() else GP.Cards.Refresh(); UI.Refresh(); UI.frame:Show() end
end

local kosMedia='Interface\\AddOns\\Gondor_PvP\\Media\\'
local function kosWindow(name,w,h,title)
    local f=CreateFrame('Frame',name,UIParent,'BackdropTemplate'); f:SetSize(w,h); f:SetPoint('CENTER')
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=2})
    f:SetBackdropColor(.08,.035,.03,1); f:SetBackdropBorderColor(.65,.42,.18,1)
    f:SetMovable(true); f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart',f.StartMoving); f:SetScript('OnDragStop',f.StopMovingOrSizing)
    if UISpecialFrames then table.insert(UISpecialFrames,name) end
    label(f,20,10,12,w-20,30):SetText(title)
    local close=CreateFrame('Button',nil,f,'UIPanelCloseButton'); close:SetPoint('TOPRIGHT',-2,-2)
    window(f); return f
end
function UI.EditKoS(identity)
    if not identity or not GP.IsEligibleGuild() then return end
    local K=GP.KoS; local key=K.Name(identity.name); if not key then return end
    if K.Active(K.rows and K.rows[key]) then
        if UI.kosEdit then UI.kosEdit:Hide() end
        UI.ShowKoSDetails(K.rows[key]); return
    end
    if UI.kosEdit then UI.kosEdit:Hide() end
    local f=UI.kosEdit
    if not f then f=kosWindow('GondorPvPKoSEdit',460,190,'Gondor KoS'); UI.kosEdit=f end
    if f.edit then f.identity=identity; f.edit:SetText(K.Active(K.rows[key]) and K.rows[key].reason or ''); f:Show(); window(f); f.edit:SetFocus(); return end
    f.identity=identity
    local edit=CreateFrame('EditBox',nil,f,'InputBoxTemplate'); edit:SetSize(400,30); edit:SetPoint('TOPLEFT',30,-65); edit:SetAutoFocus(false); edit:SetMaxLetters(400)
    f.edit=edit; local counter=label(f,12,20,103,420,25)
    edit:SetScript('OnTextChanged',function(self)
        local raw=self:GetText(); local text,count=K.Reason(raw)
        if raw~=text then self:SetText(text) end; counter:SetText(count..'/100 characters')
    end)
    local r=K.rows and K.rows[key]; edit:SetText(K.Active(r) and r.reason or '')
    button(f,'Save',120,70,20,function() if K.Add(f.identity,edit:GetText()) then f:Hide(); UI.RefreshKoS(); UI.RefreshKoSPortraits() end end)
    button(f,'Cancel',120,270,20,function() f:Hide() end); f:Show(); edit:SetFocus()
end
function UI.DeleteKoS(r)
    if UI.kosConfirm then UI.kosConfirm:Hide() end
    local f=UI.kosConfirm
    if f then f.key=r.key; f.gen=r.gen; f.target:SetText(r.key); f:Show(); window(f); return end
    f=kosWindow('GondorPvPKoSConfirm',420,170,'Remove from Kill on Sight?'); UI.kosConfirm=f
    f.target=label(f,14,15,57,390,40); f.target:SetText(r.key)
    f.key=r.key; f.gen=r.gen
    button(f,'Remove',120,50,20,function() GP.KoS.Delete(f.key,f.gen); f:Hide(); UI.RefreshKoS(); UI.RefreshKoSPortraits() end)
    button(f,'Cancel',120,250,20,function() f:Hide() end)
end
function UI.KoSPlayerName(key)
    -- Keep both parts of Forever's regionally unique character names.
    -- On realm-based clients, retain the realm separator for clarity.
    local name=key or ''
    if GP.KoS.Safe(RegionalUniqueNamesEnabled)==true then name=name:gsub('-', ' ') end
    return (name:gsub('^%l',string.upper):gsub('([ %-])(%l)',function(space,letter) return space..letter:upper() end))
end
function UI.RefreshKoSUndo()
    local f=UI.kosUndo; if not f then return end
    local list=GP.KoS.UndoList()
    f.offset=math.max(0,math.min(f.offset or 0,math.max(0,#list-5)))
    f.empty:SetShown(#list==0)
    for i,row in ipairs(f.rows) do
        local u=list[i+f.offset]; row.removal=u
        if u then
            row.text:SetText(UI.KoSPlayerName(u.snapshot.key)..'\nUndo available for '..math.max(0,u.expires-GP.KoS.Now())..' seconds')
            row:Show()
        else row:Hide() end
    end
end
function UI.ShowKoSUndo()
    if not UI.kosUndo then
        local f=kosWindow('GondorPvPKoSUndo',500,340,'RECENT KoS REMOVALS'); UI.kosUndo=f; f.rows={}
        f.empty=label(f,13,25,80,450,40); f.empty:SetText('No removals available to undo.')
        for i=1,5 do
            local row=CreateFrame('Frame',nil,f); row:SetSize(450,40); row:SetPoint('TOPLEFT',25,-(62+(i-1)*43))
            row.text=label(row,12,0,0,340,40); row.text:SetJustifyH('LEFT')
            row.undo=button(row,'Undo',80,360,7,function()
                if row.removal then GP.KoS.UndoDelete(row.removal.snapshot.key); UI.RefreshKoSUndo() end
            end)
            f.rows[i]=row
        end
        button(f,'Previous',100,25,20,function() f.offset=(f.offset or 0)-5; UI.RefreshKoSUndo() end)
        button(f,'Next',100,135,20,function() f.offset=(f.offset or 0)+5; UI.RefreshKoSUndo() end)
        button(f,'Close',100,375,20,function() f:Hide() end)
        f:SetScript('OnUpdate',function(_,elapsed) f.elapsed=(f.elapsed or 0)+elapsed; if f.elapsed>=1 then f.elapsed=0; UI.RefreshKoSUndo() end end)
    end
    UI.RefreshKoSUndo(); window(UI.kosUndo); UI.kosUndo:Show()
end
function UI.RefreshKoSDetails()
    local f=UI.kosDetails; if not f or not f:IsShown() then return end
    local r=GP.KoS.rows[f.key]
    if not GP.IsEligibleGuild() or not GP.KoS.Active(r) or r.gen~=f.gen then f:Hide(); return end
    f.player:SetText(UI.KoSPlayerName(r.key))
    f.reason:SetText(r.reason~='' and r.reason or 'No reason provided.')
    f.author:SetText('Added by '..UI.KoSPlayerName(r.author))
    f.attributes:SetText('Race: '..(r.race and r.race~='' and r.race or 'Unknown')..'  |  Class: '..(r.class and r.class~='' and r.class or 'Unknown')..'\nLast seen level: '..(r.level and r.level>0 and tostring(r.level) or 'Unknown'))
end
function UI.ShowKoSDetails(r)
    if not GP.IsEligibleGuild() or not GP.KoS.Active(r) then return end
    if not UI.kosDetails then
        local f=kosWindow('GondorPvPKoSDetails',500,320,'KILL ON SIGHT — TARGET DETAILS'); UI.kosDetails=f
        f.player=label(f,18,25,55,450,30); f.player:SetTextColor(1,.82,.38)
        f.attributes=label(f,12,25,90,450,42); f.attributes:SetJustifyH('LEFT'); f.attributes:SetTextColor(.85,.8,.7)
        local caption=label(f,11,25,143,450,20); caption:SetJustifyH('LEFT'); caption:SetText('REASON'); caption:SetTextColor(.75,.65,.55)
        f.reason=label(f,13,25,169,450,65); f.reason:SetJustifyH('LEFT'); f.reason:SetJustifyV('TOP'); f.reason:SetTextColor(.95,.9,.82)
        f.author=label(f,12,25,247,450,25); f.author:SetJustifyH('LEFT'); f.author:SetTextColor(.75,.65,.55)
        button(f,'Close',110,195,15,function() f:Hide() end)
    end
    local f=UI.kosDetails; f.key=r.key; f.gen=r.gen; f:Show(); window(f); UI.RefreshKoSDetails()
end
function UI.RefreshKoS()
    local f=UI.kosFrame; if not f or not GP.KoS.rows then return end
    local K=GP.KoS; local list=GP.IsEligibleGuild() and K.List() or {}; local count=#list
    f.offset=math.max(0,math.min(f.offset or 0,math.max(0,count-7)))
    f.status:SetText('All alliance on this list are kill on sight by order of the Doctor of War.')
    for i,row in ipairs(f.rows) do
        local r=list[i+f.offset]; row.record=r
        if r then
            local age=math.max(0,K.Now()-r.seen); local ago=age<60 and 'just now' or age<3600 and math.floor(age/60)..'m ago' or age<86400 and math.floor(age/3600)..'h ago' or math.floor(age/86400)..'d ago'
            row.name:SetText(UI.KoSPlayerName(r.key)); row.seen:SetText('Last seen '..ago); row:Show()
        else row:Hide() end
    end
    f.mute:SetText(GP.db.settings.kosSound and 'Sound: on' or 'Sound: off')
    f.undo:SetShown(#K.UndoList()>0)
    UI.RefreshKoSDetails()
end
function UI.ShowKoS()
    if not GP.KoS.rows then GP.KoS.Init() end
    if not UI.kosFrame then
        local f=kosWindow('GondorPvPKoSFrame',840,570,'GONDOR — KILL ON SIGHT'); UI.kosFrame=f; f.rows={}
        local picture=art(f,220,391); picture:SetPoint('TOPLEFT',12,-90); picture:SetTexture(kosMedia..'KoSOrc'); picture:SetTexCoord(0,941/1024,0,1672/2048)
        f.status=label(f,12,20,48,800,40)
        for i=1,7 do
            local row=CreateFrame('Frame',nil,f,'BackdropTemplate'); row:SetSize(580,54); row:SetPoint('TOPLEFT',245,-(92+(i-1)*58))
            row:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'})
            local shade=i%2==0 and .12 or .07; row:SetBackdropColor(shade,shade*.55,shade*.4,1)
            local player=CreateFrame('Button',nil,row); player:SetSize(490,54); player:SetPoint('TOPLEFT')
            player:SetScript('OnClick',function() if row.record then UI.ShowKoSDetails(row.record) end end)
            player:SetScript('OnEnter',function() row.name:SetTextColor(1,.95,.75) end)
            player:SetScript('OnLeave',function() row.name:SetTextColor(1,.82,.38) end)
            player:HookScript('OnMouseDown',function() raiseWindow(f) end)
            row.name=label(player,15,12,6,465,23); row.name:SetJustifyH('LEFT'); row.name:SetTextColor(1,.82,.38)
            row.seen=label(player,11,12,31,465,18); row.seen:SetJustifyH('LEFT'); row.seen:SetTextColor(.72,.64,.56)
            row.delete=button(row,'Delete',70,500,14,function() if row.record then UI.DeleteKoS(row.record) end end)
            row.player=player; f.rows[i]=row
        end
        f:EnableMouseWheel(true); f:SetScript('OnMouseWheel',function(_,delta) f.offset=(f.offset or 0)-delta; UI.RefreshKoS() end)
        button(f,'Previous',100,250,20,function() f.offset=(f.offset or 0)-7; UI.RefreshKoS() end)
        button(f,'Next',100,360,20,function() f.offset=(f.offset or 0)+7; UI.RefreshKoS() end)
        f.mute=button(f,'Sound: on',120,480,20,function() GP.db.settings.kosSound=not GP.db.settings.kosSound; UI.RefreshKoS() end)
        f.undo=button(f,'Undo deletes',95,610,20,UI.ShowKoSUndo)
        button(f,'Close',100,710,20,function() f:Hide() end)
        f:SetScript('OnUpdate',function(_,elapsed) f.elapsed=(f.elapsed or 0)+elapsed; if f.elapsed>=1 then f.elapsed=0; UI.RefreshKoS() end end)
    end
    UI.RefreshKoS(); window(UI.kosFrame); UI.kosFrame:Show()
end
function UI.RefreshKoSPortraits()
    if not GP.KoS or not GP.KoS.rows then return end
    UI.kosMarks=UI.kosMarks or {}
    for _,spec in ipairs({{'TargetFrame','target'},{'FocusFrame','focus'},{'XPerl_Target','target'},{'XPerl_Focus','focus'}}) do
        local owner=_G[spec[1]]
        local anchor=owner and (owner.portraitFrame or owner.portrait or (owner.TargetFrameContainer and owner.TargetFrameContainer.Portrait))
        if anchor then
            local mark=UI.kosMarks[spec[1]]
            if not mark and not UI.InCombat() then
                mark=CreateFrame('Frame',nil,UIParent); mark:SetSize(18,18); mark:SetPoint('BOTTOMRIGHT',anchor,'BOTTOMRIGHT',2,-2); mark:SetFrameStrata('HIGH')
                local t=mark:CreateTexture(nil,'OVERLAY'); t:SetAllPoints(); t:SetTexture(kosMedia..'KoSCrosshair'); UI.kosMarks[spec[1]]=mark
                owner:HookScript('OnHide',function() mark:Hide() end)
                owner:HookScript('OnShow',function() UI.RefreshKoSPortraits() end)
            end
            if mark then local id=GP.KoS.Identity(spec[2]); local key=id and GP.KoS.Name(id.name)
                mark:SetShown(GP.IsEligibleGuild() and owner:IsShown() and key and GP.KoS.Active(GP.KoS.rows[key]) or false)
            end
        end
    end
end
function UI.InstallKoSMenu()
    if not UI.kosMenuInstalled and Menu and Menu.ModifyMenu then
        local function addEntry(_,root,context)
            local id=context and context.unit and GP.KoS.Identity(context.unit)
            if id and GP.IsEligibleGuild() then root:CreateDivider(); root:CreateButton('Gondor KoS',function() UI.EditKoS(id) end) end
        end
        -- SecureUnitButton's togglemenu action (used by Z-Perl) chooses
        -- PLAYER for a target and FOCUS for a focus, even for enemies.
        for _,kind in ipairs({'ENEMY_PLAYER','PLAYER','TARGET','FOCUS','PARTY','RAID_PLAYER','RAID'}) do
            Menu.ModifyMenu('MENU_UNIT_'..kind,addEntry)
        end
        UI.kosMenuInstalled=true
    end
end
local kosHooks=CreateFrame('Frame'); kosHooks:RegisterEvent('PLAYER_LOGIN'); kosHooks:RegisterEvent('ADDON_LOADED')
kosHooks:SetScript('OnEvent',UI.InstallKoSMenu)
