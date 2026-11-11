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

-- Drag only the title area, so request buttons retain their normal clicks.
local function movablePopup(f,width)
    f:SetMovable(true); f:SetClampedToScreen(true)
    local handle=CreateFrame('Frame',nil,f); f.dragHandle=handle
    handle:SetSize(width-40,36); handle:SetPoint('TOPLEFT',0,0)
    handle:EnableMouse(true); handle:RegisterForDrag('LeftButton')
    handle:SetScript('OnDragStart',function() f.userMoved=true; f:StartMoving() end)
    handle:SetScript('OnDragStop',function() f:StopMovingOrSizing() end)
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
    local bg=b:CreateTexture(nil,"BACKGROUND"); bg:SetSize(22,22); bg:SetPoint("CENTER"); bg:SetTexture("Interface\\Buttons\\WHITE8X8"); if bg.SetVertexColor then bg:SetVertexColor(140/255,17/255,24/255,1) end
    icon:SetTexture("Interface\\AddOns\\Gondor_PvP\\Media\\KoSOrc"); icon:SetTexCoord(0,941/1024,0,941/2048)
    if b.CreateMaskTexture and icon.AddMaskTexture and bg.AddMaskTexture then
        local mask=b:CreateMaskTexture(nil,'OVERLAY'); mask:SetSize(22,22); mask:SetPoint('CENTER')
        mask:SetTexture('Interface\\CharacterFrame\\TempPortraitAlphaMask','CLAMPTOBLACKADDITIVE','CLAMPTOBLACKADDITIVE')
        icon:AddMaskTexture(mask); bg:AddMaskTexture(mask)
    end
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
        if mouse=="RightButton" then UI.Toggle() else UI.ShowRequestMenu() end
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
        if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:AddLine("Gondor PvP"); GameTooltip:AddLine("Left click: request help  |  Right click: binder"); GameTooltip:Show() end
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
        button(f,"Request help",150,45,80,function() UI.ShowRequestMenu() end)
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
    if not offer or GP.Network.IsOwnRequest(offer.sender) then return end
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
        if offer and offer.expires>now() and not offer.deferred and not GP.Network.IsOwnRequest(offer.sender) and GP.Network.OfferInZone(offer) then
            UI.ShowOffer(entry.token,offer,entry.zone); return
        end
    end
end

function UI.ShowOffer(token, offer, zone)
    if GP.Network.IsOwnRequest(offer.sender) or not GP.Network.OfferInZone(offer) then return end
    if offer.expires<=now() then return end
    if UI.InCombat() then UI.QueueOffer(token,offer,zone); return end
    if not UI.offer then
        local f=CreateFrame("Frame","GondorPvPOffer",UIParent,"BackdropTemplate")
        UI.offer=f; f:SetSize(370,305); f:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",-40,180); f:SetClampedToScreen(true); f:SetFrameStrata("DIALOG")
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
        f:SetBackdropColor(0.10,0.04,0.03,1); f:SetBackdropBorderColor(0.7,0.45,0.2,1)
        movablePopup(f,370)
        f.title=label(f,17,10,12,350,26)
        local picture=art(f,160,80); picture:SetPoint("TOP",0,-42); picture:SetTexture("Interface\\AddOns\\Gondor_PvP\\Media\\Chopper")
        f.detail=label(f,12,20,133,330,100)
        button(f,"Accept",115,55,20,function()
            local selected=f.token; if selected and GP.Network.Accept(selected) then f:Hide() end
        end)
        button(f,"Dismiss",115,200,20,function() GP.Network.offers[f.token]=nil; f:Hide() end)
        f:SetScript("OnUpdate",function(self,elapsed)
            self.distanceElapsed=(self.distanceElapsed or 0)+(elapsed or 0)
            if self.distanceElapsed>=1 then self.distanceElapsed=0; UI.RefreshOfferDistance() end
            if GP.Network.IsOwnRequest(self.currentOffer.sender) or not GP.Network.OfferInZone(self.currentOffer) then GP.Network.offers[self.token]=nil; self:Hide(); return end
            if UI.InCombat() then
                UI.QueueOffer(self.token,self.currentOffer,self.zone,true); self:Hide()
            elseif self.expires and now()>=self.expires then self:Hide() end
        end)
        f:Hide()
        f:SetScript("OnHide",function() f:StopMovingOrSizing(); UI.ShowNextOffer() end)
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
    UI.RefreshOfferDistance(); window(f); f:Show()
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

function UI.HideDeathPrompt()
    if UI.requestMenu and UI.requestMenu.serial then UI.requestMenu:Hide() end
end
function UI.ShowRequestMenu(serial)
    if not UI.requestMenu then
        local f=CreateFrame('Frame','GondorPvPRequestMenu',UIParent,'BackdropTemplate')
        UI.requestMenu=f; f.choices={}; f:SetSize(300,160)
        f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=2})
        f:SetBackdropColor(.12,.03,.03,1); f:SetBackdropBorderColor(.7,.45,.2,1)
        movablePopup(f,300)
        f.title=label(f,14,10,8,245,25)
        f.close=button(f,'X',24,267,128,function() f:Hide() end)
        for i,choice in ipairs({{'Muster Rohirrim (Zone)','ZONE'},{'Light Beacons (World)','WORLD'}}) do
            local scope=choice[2]
            local choiceButton=button(f,choice[1],270,15,75-(i-1)*33,function()
                local death=f.serial; f.serial=nil; f:Hide()
                if death then GP.Network.RespondToDeathPrompt(death,true,scope) else GP.Network.Request(true,false,scope) end
            end)
            choiceButton.gondorScopeIndex=i; f.choices[i]=choiceButton
        end
        f.decline=button(f,'Decline',120,90,9,function() f:Hide() end)
        f:SetScript('OnHide',function()
            f:StopMovingOrSizing()
            local death=f.serial; f.serial=nil
            if death then GP.Network.RespondToDeathPrompt(death,false) end
        end)
        f:SetScript('OnUpdate',function()
            if f.serial and (now()>=f.deadline or f.serial~=GP.Network.pendingDeathSerial or not GP.db.settings.alerts or not GP.IsEligibleGuild() or GP.Network.InInstance()) then f:Hide() end
        end)
        if UISpecialFrames then table.insert(UISpecialFrames,'GondorPvPRequestMenu') end
        f:Hide()
    end
    local f=UI.requestMenu
    if f:IsShown() then f:Hide(); if not serial then return end end
    f.serial=serial; f.deadline=now()+15; f.decline:SetShown(serial~=nil)
    f:SetHeight(serial and 160 or 124)
    f.close:ClearAllPoints(); f.close:SetPoint('TOPRIGHT',f,'TOPRIGHT',-8,-7)
    for _,child in ipairs(f.choices) do
        if child.gondorScopeIndex then child:ClearAllPoints(); child:SetPoint('TOPLEFT',f,'TOPLEFT',15,-(43+(child.gondorScopeIndex-1)*33)) end
    end
    f.title:SetText(serial and 'Killed in PvP? Call for aid' or 'Gondor calls for aid')
    if not f.userMoved then f:ClearAllPoints(); f:SetPoint('CENTER',UIParent,'TOP',0,-UIParent:GetHeight()*.28) end
    window(f); f:Show()
end
function UI.ConfirmDeath(serial) UI.ShowRequestMenu(serial) end

function UI.Toggle()
    UI.Build()
    if UI.frame:IsShown() then UI.frame:Hide() else GP.Cards.Refresh(); UI.Refresh(); UI.frame:Show() end
end

local kosMedia='Interface\\AddOns\\Gondor_PvP\\Media\\'
local function kosWindow(name,w,h,title)
    local f=CreateFrame('Frame',name,UIParent,'BackdropTemplate'); f:SetSize(w,h); f:SetPoint('CENTER')
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=2})
    f:SetBackdropColor(.08,.035,.03,1); f:SetBackdropBorderColor(.65,.42,.18,1)
    f:SetMovable(true)
    local drag=CreateFrame('Frame',nil,f); drag:SetPoint('TOPLEFT',0,0); drag:SetSize(w-36,42)
    drag:EnableMouse(true); drag:RegisterForDrag('LeftButton')
    drag:SetScript('OnDragStart',function() f:StartMoving() end)
    drag:SetScript('OnDragStop',function() f:StopMovingOrSizing() end)
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

-- Shared KoS table primitives. Offsets are row indices, never pixel positions.
local function kosText(parent,size,x,y,w,h,text,align)
    local t=label(parent,size,x,y,w,h); t:SetJustifyH(align or 'LEFT')
    t:SetTextColor(.94,.95,.97); if text then t:SetText(text) end
    return t
end
local function kosPanel(parent,w,h,x,y)
    local f=CreateFrame('Frame',nil,parent,'BackdropTemplate')
    f:SetSize(w,h); f:SetPoint('TOPLEFT',x,-y)
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    f:SetBackdropColor(.035,.04,.05,1); f:SetBackdropBorderColor(.38,.30,.20,1)
    return f
end
local function kosAge(seen)
    local age=math.max(0,GP.KoS.Now()-(seen or 0))
    return age<60 and 'just now' or age<3600 and math.floor(age/60)..'m ago' or age<86400 and math.floor(age/3600)..'h ago' or math.floor(age/86400)..'d ago'
end
local function kosClass(value)
    if type(value)~='string' or (issecretvalue and issecretvalue(value)) then return end
    local token=value:upper():gsub('%s+','')
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then return token end
    for _,names in ipairs({LOCALIZED_CLASS_NAMES_MALE or {},LOCALIZED_CLASS_NAMES_FEMALE or {}}) do
        for key,name in pairs(names) do if name==value then return key end end
    end
end
local rosterClasses
local function kosRoster()
    if rosterClasses then return rosterClasses end
    rosterClasses={}
    if not GetNumGuildMembers or not GetGuildRosterInfo then return rosterClasses end
    local count=GP.KoS.Safe(GetNumGuildMembers,true)
    if type(count)~='number' or count<0 or count>2000 then return rosterClasses end
    for i=1,count do
        local data={pcall(GetGuildRosterInfo,i)}
        if data[1] then
            local name,class=data[2],data[12]
            if not (issecretvalue and issecretvalue(class)) and class==nil then class=data[6] end
            if not issecretvalue or (not issecretvalue(name) and not issecretvalue(class)) then
                local key=GP.KoS.Name(name)
                if key then rosterClasses[key]=kosClass(class) end
            end
        end
    end
    return rosterClasses
end
local rosterEvents=CreateFrame('Frame')
rosterEvents:RegisterEvent('GUILD_ROSTER_UPDATE')
rosterEvents:SetScript('OnEvent',function() rosterClasses=nil end)
local function kosColour(text,class)
    local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[kosClass(class) or '']
    text:SetTextColor(c and c.r or .94,c and c.g or .95,c and c.b or .97)
end
local function kosMemberColour(text,key)
    kosColour(text,kosRoster()[key])
end
local function kosTooltip(owner,name,class)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner,'ANCHOR_RIGHT')
    GameTooltip:SetText(name)
    GameTooltip:AddLine(class and class~='' and class or 'Unknown class',.8,.84,.9)
    GameTooltip:Show()
end
local function kosScroll(panel,name,refresh)
    panel.offset=0
    local bar=CreateFrame('Slider',name,panel,'UIPanelScrollBarTemplate')
    panel.scrollbar=bar; bar:SetSize(16,100); bar:SetPoint('TOPRIGHT',-5,-48)
    bar:SetMinMaxValues(0,0); bar:SetValueStep(1)
    bar:SetScript('OnValueChanged',function(_,value)
        if panel.syncing then return end
        local offset=math.max(0,math.min(panel.maxOffset or 0,math.floor(value+.5)))
        if panel.offset~=offset then panel.offset=offset; refresh() end
    end)
    panel:EnableMouseWheel(true)
    panel:SetScript('OnMouseWheel',function(_,delta)
        panel.offset=math.max(0,math.min(panel.maxOffset or 0,panel.offset-delta))
        refresh()
    end)
end
local function kosScrollRange(panel,count,visible)
    panel.maxOffset=math.max(0,count-visible)
    panel.offset=math.max(0,math.min(panel.offset or 0,panel.maxOffset))
    panel.syncing=true
    panel.scrollbar:SetMinMaxValues(0,panel.maxOffset); panel.scrollbar:SetValue(panel.offset)
    panel.scrollbar:SetEnabled(panel.maxOffset>0)
    panel.scrollbar:SetAlpha(panel.maxOffset>0 and 1 or .4)
    panel.syncing=nil
    if panel.scrollbar.ScrollUpButton then panel.scrollbar.ScrollUpButton:SetEnabled(panel.offset>0) end
    if panel.scrollbar.ScrollDownButton then panel.scrollbar.ScrollDownButton:SetEnabled(panel.offset<panel.maxOffset) end
end
local function kosFit(f)
    local scale=math.min(1,(UIParent:GetWidth()-32)/f:GetWidth(),(UIParent:GetHeight()-32)/f:GetHeight())
    f:SetScale(math.max(.1,scale))
end
function UI.RefreshKoSDetails()
    local f=UI.kosDetails; if not f or not f:IsShown() then return end
    local r=GP.KoS.rows[f.key]
    if not GP.IsEligibleGuild() or not GP.KoS.Active(r) or r.gen~=f.gen then f:Hide(); return end
    f.player:SetText(UI.KoSPlayerName(r.key)); kosColour(f.player,r.class)
    f.attributes:SetText('Race: '..(r.race and r.race~='' and r.race or 'Unknown')..'  |  Class: '..(r.class and r.class~='' and r.class or 'Unknown')..'\nLast seen level: '..((r.level or 0)>0 and r.level or 'Unknown')..'  |  Last seen: '..kosAge(r.seen))
    f.reason:SetText(r.reason~='' and r.reason or 'No reason provided.')
    f.reason:SetHeight(200)
    local measured=f.reason.GetStringHeight and f.reason:GetStringHeight()
    local reasonHeight=math.max(18,type(measured)=='number' and measured or math.ceil(#r.reason/54)*18)
    f.reason:SetHeight(reasonHeight)
    f.reasonBox:SetHeight(reasonHeight+16)
    local y=138+reasonHeight+26
    f.authorHeading:ClearAllPoints(); f.authorHeading:SetPoint('TOPLEFT',25,-y)
    f.author:ClearAllPoints(); f.author:SetPoint('TOPLEFT',25,-(y+18))
    f.author:SetText(UI.KoSPlayerName(r.author)); kosMemberColour(f.author,r.author)
    local total,players=GP.KoS.Stats(r)
    f.killTotal:ClearAllPoints(); f.killTotal:SetPoint('TOPLEFT',345,-(y+48)); f.killTotal:SetText('Total kills: '..total)
    f.killsHeading:ClearAllPoints(); f.killsHeading:SetPoint('TOPLEFT',25,-(y+48))
    local visible=math.max(1,math.min(6,#players))
    local panel=f.killPanel
    panel:ClearAllPoints(); panel:SetPoint('TOPLEFT',25,-(y+80)); panel:SetHeight(32+visible*28+8)
    panel.scrollbar:SetHeight(math.max(1,visible*28-32))
    kosScrollRange(panel,#players,visible)
    for i,row in ipairs(panel.rows) do
        local entry=players[i+panel.offset]
        row:SetShown(i<=visible and entry~=nil)
        if entry then
            row.name:SetText(UI.KoSPlayerName(entry.name)); kosMemberColour(row.name,entry.name)
            row.count:SetText(tostring(entry.count))
        end
    end
    panel.empty:SetShown(#players==0)
    f.range:ClearAllPoints(); f.range:SetPoint('TOPLEFT',25,-(y+80+panel:GetHeight()+3))
    f.range:SetText(#players==0 and '0 guildmates' or (panel.offset+1)..'–'..math.min(#players,panel.offset+visible)..' of '..#players..' guildmates')
    f:SetHeight(y+80+panel:GetHeight()+64); kosFit(f)
end
function UI.ShowKoSDetails(r)
    if not GP.IsEligibleGuild() or not GP.KoS.Active(r) then return end
    if not UI.kosDetails then
        local f=kosWindow('GondorPvPKoSDetails',500,400,'KoS — TARGET DETAILS'); UI.kosDetails=f
        f.player=kosText(f,18,25,48,450,26)
        f.attributes=kosText(f,12,25,78,450,38); f.attributes:SetTextColor(.80,.84,.89)
        kosText(f,11,25,116,450,18,'REASON'):SetTextColor(1,.82,.45)
        f.reasonBox=kosPanel(f,450,56,25,138)
        f.reasonBox:SetBackdropColor(.12,.13,.15,1)
        f.reason=kosText(f.reasonBox,13,10,8,430,40); f.reason:SetJustifyV('TOP')
        f.authorHeading=kosText(f,11,25,190,450,18,'ADDED BY'); f.authorHeading:SetTextColor(1,.82,.45)
        f.killsHeading=kosText(f,12,25,220,310,24,'GUILD KILL BREAKDOWN'); f.killsHeading:SetTextColor(1,.82,.45)
        f.author=kosText(f,12,25,190,450,22)
        f.killTotal=kosText(f,13,345,220,130,24,nil,'RIGHT')
        local panel=kosPanel(f,450,100,25,250); f.killPanel=panel; panel.rows={}
        -- Header labels belong to the header frame, above its opaque backdrop.
        local header=kosPanel(panel,448,30,1,1); panel.header=header
        header:SetBackdropColor(.22,.18,.12,1)
        panel.guildmateHeading=kosText(header,12,9,4,330,22,'Guildmate')
        panel.killsHeading=kosText(header,12,344,4,68,22,'Kills','RIGHT')
        panel.guildmateHeading:SetTextColor(1,.86,.58); panel.killsHeading:SetTextColor(1,.86,.58)
        panel.empty=kosText(panel,12,10,34,400,28,'No recorded kills.')
        for i=1,6 do
            local row=kosPanel(panel,420,28,2,32+(i-1)*28); panel.rows[i]=row
            row:SetBackdropBorderColor(0,0,0,0)
            local shade=i%2==0 and .10 or .075; row:SetBackdropColor(shade,shade+.008,shade+.018,1)
            row.name=kosText(row,12,8,3,325,22); row.count=kosText(row,12,343,3,65,22,nil,'RIGHT')
        end
        kosScroll(panel,'GondorPvPKoSKillScroll',UI.RefreshKoSDetails)
        f.range=kosText(f,10,25,350,300,16); f.range:SetTextColor(.8,.84,.89)
        button(f,'Close',100,375,12,function() f:Hide() end)
        f:SetScript('OnUpdate',function(_,elapsed) f.elapsed=(f.elapsed or 0)+elapsed; if f.elapsed>=1 then f.elapsed=0; UI.RefreshKoSDetails() end end)
    end
    local f=UI.kosDetails
    if f.key~=r.key or f.gen~=r.gen then f.killPanel.offset=0 end
    rosterClasses=nil; f.key=r.key; f.gen=r.gen; window(f); f:Show(); UI.RefreshKoSDetails()
end
function UI.RefreshKoS()
    local f=UI.kosFrame; if not f or not GP.KoS.rows then return end
    local K=GP.KoS; local list=GP.IsEligibleGuild() and K.List() or {}; local count=#list
    local panel=f.listPanel; kosScrollRange(panel,count,10)
    f.status:SetText('All Alliance on this list are kill on sight by order of the Doctor of War.')
    for i,row in ipairs(f.rows) do
        local r=list[i+panel.offset]; row.record=r
        if r then
            row.name:SetText(UI.KoSPlayerName(r.key)); kosColour(row.name,r.class)
            row.level:SetText((r.level or 0)>0 and tostring(r.level) or '?')
            row.seen:SetText(kosAge(r.seen)); row.kills:SetText(tostring(K.Stats(r))); row:Show()
        else row:Hide() end
    end
    for _,h in ipairs(f.headings) do
        local active=(GP.db.settings.kosSort or 'seen')==h.field
        h.arrow:SetShown(active)
        if active then h.arrow:SetTexCoord(0,1,GP.db.settings.kosSortAscending and 1 or 0,GP.db.settings.kosSortAscending and 0 or 1) end
    end
    panel.empty:SetShown(count==0)
    f.range:SetText(count==0 and '0 targets' or (panel.offset+1)..'–'..math.min(count,panel.offset+10)..' of '..count..' targets')
    f.mute:SetText(GP.db.settings.kosSound and 'Sound: on' or 'Sound: off')
    f.undo:SetShown(#K.UndoList()>0)
    kosFit(f); UI.RefreshKoSDetails()
end
function UI.ShowKoS()
    if not GP.KoS.rows then GP.KoS.Init() end
    if not UI.kosFrame then
        local f=kosWindow('GondorPvPKoSFrame',840,570,'GONDOR — KILL ON SIGHT'); UI.kosFrame=f; f.rows={}; f.headings={}
        local picture=art(f,220,391); picture:SetPoint('TOPLEFT',12,-90); picture:SetTexture(kosMedia..'KoSOrc'); picture:SetTexCoord(0,941/1024,0,1672/2048)
        f.status=label(f,12,20,48,800,28); f.status:SetTextColor(.85,.87,.9)
        local panel=kosPanel(f,580,400,245,94); f.listPanel=panel
        local header=kosPanel(panel,578,32,1,1); header:SetBackdropColor(.22,.18,.12,1)
        for _,spec in ipairs({{'Name','name',8,190},{'Level','level',200,56},{'Last Seen','seen',258,90},{'Total Kills','kills',350,100}}) do
            local field=spec[2]
            local h=CreateFrame('Button',nil,header); h:SetSize(spec[4],30); h:SetPoint('TOPLEFT',spec[3],-2)
            h.title=kosText(h,11,0,3,spec[4]-12,24,spec[1],field=='name' and 'LEFT' or 'CENTER'); h.field=field; h.caption=spec[1]
            local arrow=h:CreateTexture(nil,'OVERLAY'); h.arrow=arrow; arrow:SetSize(8,8); arrow:SetPoint('RIGHT',-1,0)
            arrow:SetTexture('Interface\\Buttons\\UI-SortArrow')
            h:SetScript('OnClick',function()
                if (GP.db.settings.kosSort or 'seen')==field then GP.db.settings.kosSortAscending=not GP.db.settings.kosSortAscending
                else GP.db.settings.kosSort=field; GP.db.settings.kosSortAscending=field=='name' end
                panel.offset=0; UI.RefreshKoS()
            end)
            f.headings[#f.headings+1]=h
        end
        for i=1,10 do
            local row=kosPanel(panel,550,36,2,34+(i-1)*36)
            row:SetBackdropBorderColor(0,0,0,0)
            local shade=i%2==0 and .10 or .075; row:SetBackdropColor(shade,shade+.008,shade+.018,1)
            local player=CreateFrame('Button',nil,row); player:SetSize(452,36); player:SetPoint('TOPLEFT')
            row.name=kosText(player,13,8,6,188,24)
            if row.name.SetWordWrap then row.name:SetWordWrap(false) end
            row.level=kosText(player,12,198,6,56,24,nil,'CENTER')
            row.seen=kosText(player,12,256,6,90,24)
            row.kills=kosText(player,12,348,6,90,24,nil,'RIGHT')
            player:SetScript('OnClick',function() if row.record then UI.ShowKoSDetails(row.record) end end)
            player:SetScript('OnEnter',function()
                if row.record then kosTooltip(player,UI.KoSPlayerName(row.record.key),row.record.class) end
                row.name:SetAlpha(.8)
            end)
            player:SetScript('OnLeave',function() row.name:SetAlpha(1); if GameTooltip then GameTooltip:Hide() end end)
            player:HookScript('OnMouseDown',function() raiseWindow(f) end)
            row.delete=button(row,'Delete',64,474,5,function() if row.record then UI.DeleteKoS(row.record) end end)
            row.player=player; f.rows[i]=row
        end
        panel.empty=kosText(panel,13,15,170,520,50,'No players on the Kill on Sight list.','CENTER')
        kosScroll(panel,'GondorPvPKoSListScroll',UI.RefreshKoS); panel.scrollbar:SetHeight(320)
        f.range=kosText(f,11,250,499,540,20)
        f.mute=button(f,'Sound: on',120,250,20,function() GP.db.settings.kosSound=not GP.db.settings.kosSound; UI.RefreshKoS() end)
        f.undo=button(f,'Undo deletes',120,390,20,UI.ShowKoSUndo)
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
                mark=CreateFrame('Frame',nil,UIParent); mark:SetSize(36,36); mark:SetPoint('BOTTOMRIGHT',anchor,'BOTTOMRIGHT',2,-2); mark:SetFrameStrata('HIGH')
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

function UI.DistanceText(map,x,y,otherMap,otherX,otherY)
    local d=GP.Map and GP.Map.DistanceYards and GP.Map.DistanceYards(map,x,y,otherMap,otherX,otherY)
    return d and ('Distance: ~'..math.floor(d+.5)..' yards') or 'Distance unavailable'
end
function UI.RefreshOfferDistance()
    local f=UI.offer; local offer=f and f.currentOffer
    if not offer then return end
    local map,x,y
    if GP.Map and GP.Map.Position then map,x,y=GP.Map.Position() end
    f.detail:SetText(string.format('%s — %s %s\n%s (%.1f, %.1f)\n%s\nPotential reward: %s PvP Points',GP.DisplayName(offer.sender),offer.race or 'Unknown',offer.class or 'Unknown',f.zone or 'Unknown',offer.x*100,offer.y*100,UI.DistanceText(map,x,y,offer.map,offer.x,offer.y),offer.quote and tostring(offer.quote) or 'unavailable'))
end
function UI.RefreshTracker()
    local n=GP.Network; local entries={}; local map,x,y=GP.Map.Position()
    local a=n.active
    if a then entries[#entries+1]={role='H',id=a.id,revision=a.revision,requester=a.requester,text='Helping '..GP.DisplayName(a.requester)..' (you accepted)\n'..(not a.acceptedAt and 'Awaiting acceptance acknowledgement' or (not a.positionAt or now()-a.positionAt>10) and 'Updating location...' or UI.DistanceText(map,x,y,a.map,a.x,a.y))} end
    local r=n.request
    if r then
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost('player') then map,x,y=r.map,r.x,r.y end
        local helpers={}; for key,h in pairs(r.helpers) do helpers[#helpers+1]={key=key,h=h} end
        table.sort(helpers,function(a,b) return a.key<b.key end)
        for _,v in ipairs(helpers) do
            local h=v.h; local p=h.position
            entries[#entries+1]={role='R',id=r.id,key=v.key,revision=h.revision,completed=h.completedAt,text='Your request: '..GP.DisplayName(h.name)..' accepted\n'..(h.completedAt and 'Confirming completion...' or (not p or now()-p.at>10) and 'Updating location...' or UI.DistanceText(map,x,y,p[1],p[2],p[3]))}
        end
    end
    if #entries==0 then if UI.tracker then UI.tracker:Hide() end; return end
    if not UI.tracker then
        local f=CreateFrame('Frame','GondorPvPFareTracker',UIParent,'BackdropTemplate'); UI.tracker=f; f.rows={}
        f:SetWidth(300); f:SetFrameStrata('MEDIUM'); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
        f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1}); f:SetBackdropColor(.1,.03,.03,.92)
        local header=CreateFrame('Button',nil,f); header:SetSize(300,24); header:SetPoint('TOP'); header:RegisterForDrag('LeftButton')
        label(header,12,6,2,288,20):SetText('GONDOR — ACTIVE FARES (drag)')
        header:SetScript('OnDragStart',function() f.dragging=true; f:StartMoving() end)
        header:SetScript('OnDragStop',function()
            f:StopMovingOrSizing(); f.dragging=false
            local cx,cy=f:GetCenter(); local ratio=f:GetEffectiveScale()/UIParent:GetEffectiveScale()
            GP.db.settings.trackerPosition={x=cx*ratio/UIParent:GetWidth(),y=cy*ratio/UIParent:GetHeight()}
        end)
        for i=1,5 do
            local row=CreateFrame('Frame',nil,f); row:SetSize(290,48); row:SetPoint('TOPLEFT',5,-24-(i-1)*48)
            row.text=label(row,11,3,3,250,43); row.text:SetJustifyH('LEFT')
            row.cancel=button(row,'X',24,263,12,function()
                local e=row.entry; if not e then return end
                if e.role=='R' then n.CancelHelper(e.id,e.key,e.revision)
                elseif n.active and n.active.id==e.id and n.active.requester==e.requester and n.active.revision==e.revision then n.CancelFare() end
                UI.RefreshTracker()
            end)
            row.cancel:SetScript('OnEnter',function(self) if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_LEFT'); GameTooltip:AddLine('Cancel this fare'); GameTooltip:Show() end end)
            row.cancel:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
            f.rows[i]=row
        end
        f:EnableMouseWheel(true); f:SetScript('OnMouseWheel',function(_,delta) f.offset=(f.offset or 0)-delta; UI.RefreshTracker() end)
    end
    local f=UI.tracker; f:SetHeight(24+math.min(5,#entries)*48); f.offset=math.max(0,math.min(f.offset or 0,math.max(0,#entries-5)))
    for i,row in ipairs(f.rows) do local e=entries[i+f.offset]; row.entry=e; row:SetShown(e~=nil); if e then row.text:SetText(e.text); row.cancel:SetShown(not e.completed) end end
    if not f.dragging then
        f:ClearAllPoints(); local p=GP.db.settings.trackerPosition
        if type(p)=='table' and type(p.x)=='number' and type(p.y)=='number' then f:SetPoint('CENTER',UIParent,'BOTTOMLEFT',math.max(150,math.min(UIParent:GetWidth()-150,p.x*UIParent:GetWidth())),math.max(f:GetHeight()/2,math.min(UIParent:GetHeight()-f:GetHeight()/2,p.y*UIParent:GetHeight()))) else f:SetPoint('BOTTOMRIGHT',UIParent,'BOTTOMRIGHT',-40,30) end
    end
    f:Show()
end
