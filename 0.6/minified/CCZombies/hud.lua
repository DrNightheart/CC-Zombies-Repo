local hud={}
local paths=require "CCZombies.paths"
local _p=nil
local _pm=nil
local _weapon=nil
local _entity=nil
local _roundState=nil
local _roundTrans=nil
local _boxRoll=nil
local _zombies=nil
local _world=nil
local _settings=nil
local _getTime=nil
local _keyName=nil
function hud.init(deps)
 _p=deps.player
 _pm=deps.playerModule
 _weapon=deps.weapon
 _entity=deps.entity
 _roundState=deps.roundState
 _roundTrans=deps.roundTrans
 _boxRoll=deps.boxRoll
 _zombies=deps.zombies
 _world=deps.world
 _settings=deps.settings
 _getTime=deps.getCurrentTime
 _keyName=deps.keyName
end
local hitMarkers={}
local announceQueue={}
local screenFlash=nil
local muzzleTimer=0
local _gunModelCache={}
local _lastDownedProgress=-1
local MAX_HIT_MARKERS=5
hud._lastDt=0.05
function hud.addHitMarker(text)
 hitMarkers[#hitMarkers+1]={text=text,expiry=_getTime()+0.7}
 if#hitMarkers>MAX_HIT_MARKERS then table.remove(hitMarkers,1)end
end
function hud.setMuzzleTimer(t)muzzleTimer=t or 0.12 end
function hud.setScreenFlash(r,g,b,duration)
 screenFlash={r=r,g=g,b=b,start=_getTime(),duration=duration or 0.3}
end
function hud.queueAnnounce(text,duration)
 announceQueue[#announceQueue+1]={text=text,expiry=_getTime()+(duration or 2)}
end
function hud.clearGunCache()
 _gunModelCache={}
end
function hud.getHitMarkers()return hitMarkers end
local function loadGunModel(weaponId)
 local char=(_p and _p.character)or(_pm and _pm.character)
 local charId=char and char.id
 local cacheKey=weaponId ..(charId or "")
 if _gunModelCache[cacheKey]~=nil then return _gunModelCache[cacheKey]end
 local gunPath=paths.gun(weaponId,charId)
 if not fs.exists(gunPath)then
 _gunModelCache[cacheKey]=false;return nil
 end
 local img=paintutils.loadImage(gunPath)
 if not img or#img==0 then
 _gunModelCache[cacheKey]=false;return nil
 end
 _gunModelCache[cacheKey]=img
 return img
end
local function drawGunModel()
 local active=_weapon.getActive()
 if not active then return end
 local img=loadGunModel(active.id)
 if not img then return end
 local w,h=term.getSize()
 local imgH=#img
 local maxCol=0
 for y=1,imgH do
 if img[y]and#img[y]>maxCol then
 maxCol=#img[y]
 end
 end
 if maxCol==0 then return end
 local firstRow=1
 while firstRow<=imgH do
 local row=img[firstRow]
 local hasPixel=false
 if row then
 for ix=1,#row do
 if row[ix]and row[ix]~=0 then hasPixel=true;break end
 end
 end
 if hasPixel then break end
 firstRow=firstRow+1
 end
 local contentH=imgH-firstRow+1
 local startX=w-maxCol+1
 local startY=h-contentH+1
 for iy=firstRow,imgH do
 local row=img[iy]
 local screenY=math.floor(startY+(iy-firstRow))
 if screenY>=1 and screenY<=h and row then
 for ix=1,#row do
 local color=row[ix]
 local screenX=math.floor(startX+ix-1)
 if color and color~=0 and screenX>=1 and screenX<=w then
 term.setCursorPos(screenX,screenY)
 term.setBackgroundColor(color)
 term.write(" ")
 end
 end
 end
 end
 term.setBackgroundColor(colors.black)
 term.setTextColor(colors.white)
end
local _baseMapPalette={}
hud._basePalette=_baseMapPalette
local CC_DEFAULT_PALETTE={
[colors.white]={0xF0,0xF0,0xF0},
[colors.orange]={0xF2,0x8B,0x41},
[colors.magenta]={0xE5,0x7F,0xD8},
[colors.lightBlue]={0x99,0xB2,0xF2},
[colors.yellow]={0xDE,0xDE,0x6C},
[colors.lime]={0x7F,0xCC,0x19},
[colors.pink]={0xF2,0xB2,0xCC},
[colors.gray]={0x4C,0x4C,0x4C},
[colors.lightGray]={0x99,0x99,0x99},
[colors.cyan]={0x4C,0x99,0xB2},
[colors.purple]={0xB2,0x66,0xE5},
[colors.blue]={0x3C,0x44,0xAA},
[colors.brown]={0x57,0x33,0x1C},
[colors.green]={0x19,0x99,0x32},
[colors.red]={0xCC,0x4C,0x4C},
[colors.black]={0x11,0x11,0x11},
}
function hud.resetPaletteToDefaults()
 for c,rgb in pairs(CC_DEFAULT_PALETTE)do
 term.setPaletteColor(c,rgb[1]/255,rgb[2]/255,rgb[3]/255)
 end
 _lastDownedProgress=-1
 for k in pairs(_baseMapPalette)do _baseMapPalette[k]=nil end
end
function hud.saveMapPalette()
 for i=0,15 do
 local c=2^i
 _baseMapPalette[c]={term.getPaletteColor(c)}
 end
end
function hud.reapplyMapPalette()
 for c,rgb in pairs(_baseMapPalette)do
 term.setPaletteColor(c,rgb[1],rgb[2],rgb[3])
 end
 _lastDownedProgress=-1
end
function hud.applyDownedPalette(progress)
 progress=math.max(0,math.min(1,progress))
 if math.abs(progress-_lastDownedProgress)<0.01 then return end
 _lastDownedProgress=progress
 for c,base in pairs(_baseMapPalette)do
 local r,g,b=base[1],base[2],base[3]
 local grey=r*0.299+g*0.587+b*0.114
 term.setPaletteColor(c,
 r+(grey-r)*progress,
 g+(grey-g)*progress,
 b+(grey-b)*progress)
 end
end
function hud.updateScreenFlash()
 if not screenFlash then return end
 local elapsed=_getTime()-screenFlash.start
 local alpha=1-(elapsed/screenFlash.duration)
 if alpha<=0 then
 screenFlash=nil
 hud.reapplyMapPalette()
 return
 end
 for c,base in pairs(_baseMapPalette)do
 local r,g,b=base[1],base[2],base[3]
 term.setPaletteColor(c,
 r+(screenFlash.r-r)*alpha,
 g+(screenFlash.g-g)*alpha,
 b+(screenFlash.b-b)*alpha)
 end
end
function hud.showInteractPopup(text,color)
 local w,h=term.getSize()
 local x=math.max(1,math.floor((w-#text)/2))
 local y=math.floor(h/2+3)
 term.setCursorPos(x,y)
 term.setBackgroundColor(colors.black)
 term.clearLine()
 term.setTextColor(color or colors.white)
 term.write(text)
end
local PERK_COLORS=nil
function hud.drawPerkIcons()
 PERK_COLORS=PERK_COLORS or(_world and _world.PERK_COLORS)
 local w,h=term.getSize()
 local baseX,baseY=1,h-1
 for idx,perkId in ipairs(_p.perks)do
 if idx>8 then break end
 local c=(PERK_COLORS and PERK_COLORS[perkId])or colors.gray
 term.setBackgroundColor(c)
 term.setCursorPos(baseX+(idx-1)*2,baseY)
 term.write("  ")
 end
 term.setBackgroundColor(colors.black)
end
function hud.drawRoundTransition(w,h)
 local rt=_roundTrans
 if not rt or not rt.phase then return end
 local elapsed=_getTime()-rt.startTime
 local cy=math.floor(h/2)-2
 term.setBackgroundColor(colors.black)
 if rt.phase=="clear" then
 local halfway=rt.clearDur and elapsed>=rt.clearDur*0.5
 local l1="- ROUND " .. rt.round .. " COMPLETE -"
 local l2="Round Bonus: +" ..(rt.round*200).. " pts"
 term.setCursorPos(math.floor((w-#l1)/2),cy)
 term.setTextColor(halfway and colors.white or colors.lightGray)
 term.write(l1)
 term.setCursorPos(math.floor((w-#l2)/2),cy+1)
 term.setTextColor(colors.yellow);term.write(l2)
 elseif rt.phase=="incoming" then
 local halfway=rt.incomeDur and elapsed>=rt.incomeDur*0.4
 local l1="ROUND " .. rt.round
 local l2="- INCOMING -"
 term.setCursorPos(math.floor((w-#l1)/2),cy)
 term.setTextColor(colors.red);term.write(l1)
 term.setCursorPos(math.floor((w-#l2)/2),cy+1)
 term.setTextColor(halfway and colors.white or colors.lightGray)
 term.write(l2)
 end
end
function hud.drawBoxRoll(w,h)
 local br=_boxRoll
 if not br or(not br.active and not br.done)then return end
 local cy=math.floor(h/2)
 local line=br.done and(">>> " ..(br.display or "?").. " <<<")
 or("[ " ..(br.display or "?").. " ]")
 local col=br.done and colors.yellow or colors.white
 if br.done and math.floor((br.doneTimer or 0)*4)%2==0 then col=colors.lime end
 term.setCursorPos(math.floor((w-#line)/2),cy)
 term.setBackgroundColor(colors.black)
 term.setTextColor(col);term.write(line)
 if not br.done and br.duration and br.duration>0 then
 local barW=20
 local filled=math.floor(((br.elapsed or 0)/br.duration)*barW)
 local barX=math.floor(w/2-barW/2)
 term.setCursorPos(barX,cy+1)
 term.setBackgroundColor(colors.gray);term.write(string.rep(" ",barW))
 if filled>0 then
 term.setCursorPos(barX,cy+1)
 term.setBackgroundColor(colors.yellow)
 term.write(string.rep(" ",math.min(filled,barW)))
 end
 term.setBackgroundColor(colors.black)
 end
end
local function drawHealthBar(y,health,maxHealth,name,isDowned,textColor)
 local pct=math.max(0,math.min(1,health/math.max(1,maxHealth)))
 local green=math.floor(pct*20)
 local red=20-green
 term.setCursorPos(1,y)
 term.setBackgroundColor(colors.black)
 term.setTextColor(isDowned and colors.red or(textColor or colors.yellow))
 term.write(isDowned and(name .. ": DOWNED!")or(name .. ":"))
 term.setCursorPos(1,y+1)
 term.setBackgroundColor(colors.lime);term.write(string.rep(" ",green))
 term.setBackgroundColor(colors.red);term.write(string.rep(" ",red))
 term.setBackgroundColor(colors.black)
end
function hud.drawPlayerStatus()
 local w,h=term.getSize()
 local startY=h-4
 local name=(_p.username or "You"):sub(1,15)
 drawHealthBar(startY,_p.health,_p.maxHealth,name,_p.isDowned,colors.yellow)
 term.setCursorPos(1,startY+2)
 term.setTextColor(colors.yellow)
 term.write(string.format("Points: %d | Kills: %d",_p.points or 0,_p.kills or 0))
 term.setBackgroundColor(colors.black);term.setTextColor(colors.white)
end
function hud.drawGameOver(mapName)
 term.setBackgroundColor(colors.black);term.clear()
 local w,h=term.getSize()
 local function cw(y,text,color)
 term.setCursorPos(math.floor((w-#text)/2),y)
 term.setTextColor(color or colors.white);term.write(text)
 end
 cw(2,"GAME OVER",colors.red)
 cw(4,"YOUR STATS:",colors.yellow)
 cw(6,"Player: " ..(_p.username or "Unknown"))
 cw(7,"Map: " ..(mapName or "Unknown"))
 cw(8,"Round: " ..(_roundState and _roundState.currentRound or 1))
 cw(9,"Kills: " ..(_p.kills or 0))
 cw(10,"Points: " ..(_p.points or 0))
 local acc=0
 if _p.stats and _p.stats.shotsFired and _p.stats.shotsFired>0 then
 acc=math.floor((_p.stats.shotsHit/_p.stats.shotsFired)*100)
 end
 local accStr=string.format("Accuracy: %d%% (%d/%d)",
 acc,
(_p.stats and _p.stats.shotsHit)or 0,
(_p.stats and _p.stats.shotsFired)or 0)
 cw(11,accStr,colors.gray)
 cw(h-1,"ENTER - Return to Menu",colors.lightGray)
end
function hud.drawLobbyHost(lobby,availableMaps)
 term.setBackgroundColor(colors.black);term.clear()
 local w,h=term.getSize()
 local function cw(y,text,color)
 term.setCursorPos(math.floor((w-#text)/2),y)
 term.setTextColor(color or colors.white);term.write(text)
 end
 cw(3,"HOSTING LOBBY",colors.yellow)
 local mapName=(availableMaps and lobby.mapIndex and availableMaps[lobby.mapIndex]
 and availableMaps[lobby.mapIndex].name)or(lobby.mapName or "Unknown")
 cw(5,"Lobby: " ..(lobby.name or ""))
 cw(6,"Map: " .. mapName)
 cw(8,"Players (" ..#(lobby.players or{}).. "/" ..(lobby.maxPlayers or 4).. "):",colors.lime)
 for i,lp in ipairs(lobby.players or{})do
 term.setCursorPos(math.floor(w/2-10),9+i)
 term.setTextColor((_pColors and _pColors[i])or colors.white)
 term.write("| ")
 term.setTextColor(colors.white);term.write(lp.name or("Player "..i))
 end
 cw(h-2,"Waiting for players...",colors.lightGray)
 cw(h-1,"ENTER - Start Game | ` - Cancel",colors.lightGray)
end
function hud.drawHUD(context)
 context=context or{}
 local w,h=term.getSize()
 local now=_getTime()
 term.setCursorPos(1,1)
 term.setBackgroundColor(colors.gray)
 term.setTextColor(colors.yellow);term.clearLine()
 local rs=_roundState or{}
 local totalZ=rs.zombiesTotal or 0
 local killedZ=rs.zombiesKilled or 0
 term.write(string.format("Round: %d | Zombies: %d/%d",
 rs.currentRound or 1,killedZ,totalZ))
 if _world and _world.hasPowerSwitch then
 term.write(" | Power: ")
 term.setTextColor(_world.powerOn and colors.lime or colors.red)
 term.write(_world.powerOn and "ON" or "OFF")
 term.setTextColor(colors.white)
 end
 if _settings and _settings.showFPS then
 local fps=(hud._lastDt and hud._lastDt>0)and math.floor(1/hud._lastDt)or 0
 local fs2="FPS:" .. fps
 term.setCursorPos(w-#fs2,1)
 term.setTextColor(fps>=15 and colors.lime or fps>=8 and colors.yellow or colors.red)
 term.write(fs2)
 end
 local active=_weapon.getActive()
 term.setCursorPos(1,2)
 term.setBackgroundColor(colors.gray)
 term.setTextColor(colors.white);term.clearLine()
 if active then
 local name=active.name or active.id or "?"
 local ammo=string.format("%d/%d",active.ammo or 0,active.reserve or 0)
 local slot=_p.activeWeaponSlot or 1
 local slots=_p.maxWeaponSlots or 2
 if active.isReloading then
 local rem=math.max(0,(active.reloadEndTime or 0)-now)
 term.write(string.format("Slot %d/%d: %s | %s (Reloading %.1fs)",
 slot,slots,name,ammo,rem))
 else
 term.write(string.format("Slot %d/%d: %s | %s",slot,slots,name,ammo))
 end
 else
 term.write("Unarmed")
 end
 local label,color=_entity.getInteractLabel({
 nearDoor=context.nearDoor,
 nearPerk=context.nearPerk,
 nearBox=context.nearBox,
 nearWallWeapon=context.nearWallWeapon,
 nearPaP=context.nearPaP,
 nearPower=context.nearPower,
 nearScriptBlock=context.nearScriptBlock,
})
 if label then
 hud.showInteractPopup(label,color)
 else
 if _settings and _settings.crosshairStyle~="off" then
 local cx2,cy2=math.floor(w/2),math.floor(h/2)
 local cCol=(muzzleTimer>0)and colors.yellow or
(_settings.crosshairColor or colors.white)
 term.setBackgroundColor(colors.black)
 term.setTextColor(cCol)
 term.setCursorPos(cx2,cy2)
 term.write(_settings.crosshairStyle=="dot" and "." or "+")
 end
 end
 if _settings and _settings.showDamageNumbers and
 _settings.hitMarkerStyle~="off" then
 local markerY=math.floor(h/2)-1
 for i=#hitMarkers,1,-1 do
 local m=hitMarkers[i]
 if not m or now>=m.expiry then
 table.remove(hitMarkers,i)
 else
 local txt=m.text
 if _settings.hitMarkerStyle=="slash" and
(txt=="X" or txt=="+10")then txt="/" end
 term.setCursorPos(math.floor(w/2-#txt/2),markerY)
 term.setBackgroundColor(colors.black)
 term.setTextColor(colors.lime);term.write(txt)
 markerY=markerY-1
 end
 end
 end
 for i=#announceQueue,1,-1 do
 if now>=announceQueue[i].expiry then
 table.remove(announceQueue,i)
 end
 end
 local announceY=math.floor(h/2)-math.min(#announceQueue,6)
 for i=1,#announceQueue do
 local txt=announceQueue[i].text
 if#txt>w-2 then txt=txt:sub(1,w-2)end
 term.setCursorPos(math.max(1,math.floor((w-#txt)/2)),announceY)
 term.setBackgroundColor(colors.black)
 term.setTextColor(colors.yellow);term.write(txt)
 announceY=announceY+1
 if announceY>=h-4 then break end
 end
 local stamina=context.stamina or 1
 local isSprinting=context.isSprinting
 if stamina<1.0 or isSprinting then
 local barW=math.floor(w*0.3)
 local barX=math.floor(w/2-barW/2)
 local barY=h-6
 local filled=math.floor(stamina*barW)
 term.setCursorPos(barX,barY-1)
 term.setBackgroundColor(colors.black)
 term.setTextColor(colors.lightGray);term.write("STAMINA")
 term.setCursorPos(barX,barY)
 term.setBackgroundColor(colors.gray);term.write(string.rep(" ",barW))
 if filled>0 then
 term.setCursorPos(barX,barY)
 term.setBackgroundColor(isSprinting and colors.lime or colors.yellow)
 term.write(string.rep(" ",math.min(filled,barW)))
 end
 term.setBackgroundColor(colors.black)
 end
 hud.drawPerkIcons()
 hud.drawRoundTransition(w,h)
 hud.drawBoxRoll(w,h)
 drawGunModel()
 hud.drawPlayerStatus()
 if _p.inAfterlife then
 local msg=string.format(" AFTERLIFE - REVIVE TIME: %.1fs ",
 _p.afterlifeTimeLeft or 0)
 term.setCursorPos(math.floor((w-#msg)/2),5)
 term.setBackgroundColor(colors.red)
 term.setTextColor(colors.white);term.write(msg)
 if _entity.isNearWhosWhoBody()then
 term.setBackgroundColor(colors.black)
 term.setCursorPos(math.floor(w/2-10),6)
 local rh=context.reviveHold
 if rh and rh.active then
 local pct=math.floor(rh.elapsed/rh.duration*100)
 term.setTextColor(colors.lime)
 term.write(string.format(" [HOLD E] Reviving... %d%% ",pct))
 else
 term.setTextColor(colors.lime)
 term.write(" [E] Return to body ")
 end
 end
 end
 if muzzleTimer>0 then
 muzzleTimer=math.max(0,muzzleTimer-hud._lastDt)
 end
 if _settings and _settings.hudOpacity and _keyName then
 local kn=_keyName
 local s=_settings
 term.setCursorPos(1,h)
 term.setBackgroundColor(colors.gray)
 term.setTextColor(colors.lightGray);term.clearLine()
 term.write(string.format(
 "%s/%s/%s/%s Move | %s/%s Look | %s Knife | %s/%s/%s Slot | %s Reload | %s Pause",
 kn(s.key_forward),kn(s.key_backward),
 kn(s.key_strafeLeft),kn(s.key_strafeRight),
 kn(s.key_lookLeft),kn(s.key_lookRight),
 kn(s.key_melee),
 kn(s.key_slot1),kn(s.key_slot2),kn(s.key_slot3),
 kn(s.key_reload),
 kn(s.key_pause)))
 end
 term.setBackgroundColor(colors.black);term.setTextColor(colors.white)
end
function hud.topBarExtra()end
function hud.drawExtraPlayerStatus()end
function hud.drawLobbyHost(_lobby,_maps)end
return hud
