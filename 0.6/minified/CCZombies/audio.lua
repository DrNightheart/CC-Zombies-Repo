local audio={}
local dfpwm=require("cc.audio.dfpwm")
local _world=nil
local _player=nil
local _settings=nil
local _ccz=nil
function audio.init(deps)
 _world=deps.world
 _player=deps.player
 _settings=deps.settings
 _ccz=deps.ccz
end
local paths=require "CCZombies.paths"
local _speakerQueue={}
local function pushSpeaker(file,priority)
 if not fs.exists(file)then return end
 local speaker=peripheral.find("speaker")
 if not speaker then return end
 _speakerQueue[#_speakerQueue+1]={file=file,priority=priority,speaker=speaker}
 table.sort(_speakerQueue,function(a,b)return a.priority>b.priority end)
 os.queueEvent("ccz_audio_queued")
end
function audio.speakerLoop()
 while true do
 while#_speakerQueue==0 do
 os.pullEvent("ccz_audio_queued")
 end
 local req=table.remove(_speakerQueue,1)
 if req and fs.exists(req.file)then
 local speaker=req.speaker
 local speakerName=peripheral.getName(speaker)
 local decoder=dfpwm.make_decoder()
 local vol=(_settings and _settings.sfxVolume)or 1.0
 local f=fs.open(req.file,"rb")
 if f then
 while true do
 local chunk=f.read(16*1024)
 if not chunk then break end
 local buf=decoder(chunk)
 while not speaker.playAudio(buf,vol)do
 local _,name=os.pullEvent("speaker_audio_empty")
 if name~=speakerName then
 os.queueEvent("speaker_audio_empty",name)
 end
 end
 end
 f.close()
 end
 end
 end
end
function audio.playRoundSound(filename)
 pushSpeaker(filename,2)
end
local _sirenPending=false
function audio.playPanzerSiren()
 local sirenPath=paths.audio("panzer.dfpwm")
 if not _sirenPending and fs.exists(sirenPath)then
 _sirenPending=true
 pushSpeaker(sirenPath,3)
 _sirenPending=false
 end
end
local CHUNK_SIZE=16*1024
local API_BASE="https://" .. "ipod-2to6magyna-uc" .. ".a.run.app/"
local function newStream()
 return{
 playing=false,
 handle=nil,
 decoder=nil,
 buffer=nil,
 url=nil,
 start=nil,
 chunkSize=CHUNK_SIZE,
}
end
local function updateStream(s,speaker,volume)
 if not s.playing then return false end
 if not speaker then
 s.playing=false;return true
 end
 if s.handle and s.buffer then
 if speaker.playAudio(s.buffer,volume)then
 s.buffer=nil
 end
 return false
 end
 if s.handle and not s.buffer then
 local chunk=s.handle.read(s.chunkSize)
 if not chunk then
 s.handle.close();s.handle=nil
 s.playing=false;return true
 end
 if s.start then
 chunk=s.start .. chunk
 s.start=nil
 s.chunkSize=s.chunkSize+4
 end
 s.buffer=s.decoder(chunk)
 end
 return false
end
local function stopStream(s)
 s.playing=false
 if s.handle then s.handle.close();s.handle=nil end
 s.decoder=nil;s.buffer=nil;s.url=nil;s.start=nil
 local speaker=peripheral.find("speaker")
 if speaker then speaker.stop()end
end
local function startStream(s,youtubeId)
 stopStream(s)
 local speaker=peripheral.find("speaker")
 if not speaker then return false end
 s.url=API_BASE .. "?v=2.1&id=" .. youtubeId
 s.playing=true
 s.decoder=dfpwm.make_decoder()
 http.request({url=s.url,binary=true})
 return true
end
local function claimHttpSuccess(s,url,handle)
 if s.url and s.url==url then
 s.handle=handle
 return true
 end
 return false
end
local MENU_SONGS={
{id="uIpTKRWEJzI",name="Beauty of Annihilation (Remix)"},
{id="suyHYn91wmc",name="The Gift (Remix)"},
{id="_4MvHGw62CI",name="Damned 100ae"},
}
local menuStream=newStream()
local eeStream=newStream()
local jingleStream=newStream()
jingleStream.currentPerk=nil
jingleStream.cooldown=0
local menuState={
 songIndex=1,
 songName="",
 shuffleOrder={},
 shufflePos=0,
}
local function buildShuffle()
 local order={}
 for i=1,#MENU_SONGS do order[i]=i end
 for i=#order,2,-1 do
 local j=math.random(1,i)
 order[i],order[j]=order[j],order[i]
 end
 return order
end
function audio.startMenuMusic(index)
 if _settings and _settings.disableMenuMusic then return end
 local actualIndex
 if index then
 actualIndex=((index-1)%#MENU_SONGS)+1
 else
 menuState.shufflePos=menuState.shufflePos+1
 if menuState.shufflePos>#menuState.shuffleOrder then
 menuState.shuffleOrder=buildShuffle()
 menuState.shufflePos=1
 if#MENU_SONGS>1 and menuState.shuffleOrder[1]==menuState.songIndex then
 menuState.shuffleOrder[1],menuState.shuffleOrder[2]=
 menuState.shuffleOrder[2],menuState.shuffleOrder[1]
 end
 end
 actualIndex=menuState.shuffleOrder[menuState.shufflePos]
 end
 local song=MENU_SONGS[actualIndex]
 menuState.songIndex=actualIndex
 menuState.songName=song.name
 startStream(menuStream,song.id)
end
function audio.stopMenuMusic()
 stopStream(menuStream)
end
function audio.onHttpSuccess(url,handle)
 if claimHttpSuccess(menuStream,url,handle)then return true end
 if claimHttpSuccess(eeStream,url,handle)then return true end
 if claimHttpSuccess(jingleStream,url,handle)then return true end
 return false
end
function audio.updateMenuMusic(dt)
 if not menuStream.playing then return end
 local speaker=peripheral.find("speaker")
 local vol=(_settings and _settings.musicVolume)or 1.0
 local ended=updateStream(menuStream,speaker,vol)
 if ended then
 audio.startMenuMusic()
 end
end
function audio.isEESongPlaying()return eeStream.playing end
function audio.isMenuMusicPlaying()return menuStream.playing end
function audio.getMenuSongName()return menuState.songName end
function audio.startEESong()
 local mapData=_world and _world.loader and _world.loader.currentMap
 if not mapData or not mapData.eeSongId then return false end
 return startStream(eeStream,mapData.eeSongId)
end
function audio.stopEESong()
 stopStream(eeStream)
end
function audio.updateEESong(dt)
 if not eeStream.playing then return end
 local speaker=peripheral.find("speaker")
 local vol=(_settings and _settings.sfxVolume)or 1.0
 updateStream(eeStream,speaker,vol)
end
local JINGLE_RANGE=10
local JINGLE_RANGE_SQ=JINGLE_RANGE*JINGLE_RANGE
local JINGLE_COOLDOWN=5
local proximityTimer=0
function audio.startJingle(perkType)
 if eeStream.playing or jingleStream.playing then return end
 if jingleStream.cooldown>0 then return end
 local jingleId=audio.PERK_JINGLES and audio.PERK_JINGLES[perkType]
 if not jingleId then return end
 if not startStream(jingleStream,jingleId)then return end
 jingleStream.currentPerk=perkType
 jingleStream.cooldown=JINGLE_COOLDOWN
end
function audio.stopJingle()
 stopStream(jingleStream)
 jingleStream.currentPerk=nil
end
function audio.updateJingle(dt)
 if jingleStream.cooldown>0 then
 jingleStream.cooldown=math.max(0,jingleStream.cooldown-dt)
 end
 if not jingleStream.playing then return end
 local speaker=peripheral.find("speaker")
 local distToSource=math.huge
 local perk=jingleStream.currentPerk
 if perk=="pack_a_punch" then
 for _,pap in ipairs(_world.getPapMachines())do
 local dx=_player.x-pap.pos.x
 local dz=_player.z-pap.pos.z
 local d=math.sqrt(dx*dx+dz*dz)
 if d<distToSource then distToSource=d end
 end
 else
 for _,m in ipairs(_world.getPerkMachines())do
 if m.type==perk then
 local dx=_player.x-m.pos.x
 local dz=_player.z-m.pos.z
 distToSource=math.sqrt(dx*dx+dz*dz)
 break
 end
 end
 end
 local sfxVol=(_settings and _settings.sfxVolume)or 1.0
 local vol=math.max(0,1-distToSource*0.1)*sfxVol
 if vol<=0 then
 audio.stopJingle()
 return
 end
 updateStream(jingleStream,speaker,vol)
end
function audio.checkPerkProximity(dt)
 proximityTimer=proximityTimer+dt
 if proximityTimer<0.2 then return end
 proximityTimer=0
 if jingleStream.playing or jingleStream.cooldown>0 then return end
 local nearestPerk=nil
 local nearestDSq=JINGLE_RANGE_SQ
 for _,m in ipairs(_world.getPerkMachines())do
 if not m.purchased and audio.PERK_JINGLES and audio.PERK_JINGLES[m.type]then
 local dx=_player.x-m.pos.x
 local dz=_player.z-m.pos.z
 local dSq=dx*dx+dz*dz
 if dSq<nearestDSq then nearestDSq=dSq;nearestPerk=m.type end
 end
 end
 for _,pap in ipairs(_world.getPapMachines())do
 local dx=_player.x-pap.pos.x
 local dz=_player.z-pap.pos.z
 local dSq=dx*dx+dz*dz
 if dSq<nearestDSq then nearestDSq=dSq;nearestPerk="pack_a_punch" end
 end
 if nearestPerk then
 audio.startJingle(nearestPerk)
 end
end
function audio.update(dt)
 audio.updateMenuMusic(dt)
 audio.updateEESong(dt)
 audio.updateJingle(dt)
 audio.checkPerkProximity(dt)
end
function audio.drawNowPlaying()
 if not menuStream.playing or menuState.songName=="" then return end
 local w,_=term.getSize()
 local label="♪ " .. menuState.songName
 term.setCursorPos(w-#label,1)
 term.setTextColor(colors.gray)
 term.write(label)
end
function audio.linkPerkJingles(t)
 audio.PERK_JINGLES=t
end
return audio
