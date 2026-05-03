

local paths = require "CCZombies.paths"

local weapon = {}

local _p          = nil   
local _pm         = nil   
local _zombies    = nil
local _settings   = nil
local _ccz        = nil
local _markers    = nil   
local _muzzle     = nil   
local _getTime    = nil

local MAX_MARKERS = 4

function weapon.init(deps)
    _p        = deps.player
    _pm       = deps.playerModule
    _zombies  = deps.zombies
    _settings = deps.settings
    _ccz      = deps.ccz
    _markers  = deps.hitMarkers
    _muzzle   = deps.muzzleFlash
    _getTime  = deps.getCurrentTime
end

local _registry = {}

function weapon.registerBuiltins()
    local defs = {
        {
            id = "m1911",           name = "M1911",
            type = "pistol",        damage = 35,    rpm = 300,
            mag = 8,                reserve = 24,
            reloadTime = 1.6,       spawn = "starting",
            fireMode = "semi",      penetration = 0,    recoil = 1.5,
            papName = "Mustang & Sally",
            papDamage = 105,        papMag = 12,    papReserve = 36,
        },
        {
            id = "standard_lmg",    name = "Standard L.M.G.",
            type = "lmg",           damage = 28,    rpm = 650,
            mag = 100,              reserve = 200,
            reloadTime = 4.0,       spawn = "box",
            fireMode = "auto",      penetration = 1,    recoil = 0.6,
            papName = "115 Infused LMG",
            papDamage = 84,         papMag = 150,   papReserve = 300,
        },
        {
            id = "ballista_sniper", name = "Ballista",
            type = "sniper",        damage = 950,   rpm = 50,
            mag = 5,                reserve = 15,
            reloadTime = 2.8,       spawn = "box",
            fireMode = "semi",      penetration = -1,   recoil = 3.5,
            papName = "Skull Crusher",
            papDamage = 2850,       papMag = 8,     papReserve = 24,
        },
        {
            id = "ak47",            name = "AK-47",
            type = "assault",       damage = 38,    rpm = 600,
            mag = 30,               reserve = 120,
            reloadTime = 2.6,       spawn = "box",
            fireMode = "auto",      penetration = 1,    recoil = 1.0,
            papName = "Reznov's Revenge",
            papDamage = 114,        papMag = 45,    papReserve = 180,
        },
        {
            id = "uzi_md",          name = "Uzi-M.D.",
            type = "smg",           damage = 18,    rpm = 900,
            mag = 40,               reserve = 160,
            reloadTime = 2.0,       spawn = "box",
            fireMode = "auto",      penetration = 2,    recoil = 0.5,
            papName = "Uzi & N",
            papDamage = 54,         papMag = 60,    papReserve = 240,
        },
        {
            id = "raygun",          name = "Ray Gun",
            type = "energy",        damage = 250,   rpm = 280,
            mag = 20,               reserve = 80,
            reloadTime = 3.0,       spawn = "box",
            aoe = 50,
            fireMode = "semi",      penetration = 0,    recoil = 2.0,
            papName = "Dr N's Ray Gun",
            papDamage = 750,        papMag = 30,    papReserve = 120,
        },
    }
    for _, def in ipairs(defs) do
        _registry[def.id] = def
    end
end

function weapon.registerDef(def)
    if def and def.id then _registry[def.id] = def end
end

function weapon.createInstance(weaponId)
    local def = _registry[weaponId]
    if not def then return nil end
    return {
        id         = weaponId,
        name       = def.name       or weaponId,
        ammo       = def.mag        or 8,
        reserve    = def.reserve    or (def.mag or 8) * 3,
        mag        = def.mag        or 8,
        rpm        = def.rpm        or 300,
        damage     = def.damage     or 50,
        reloadTime = def.reloadTime or 2.0,
        fireMode   = def.fireMode   or "semi",
        penetration = def.penetration or 0,
        recoil     = def.recoil     or 0.5,
        aoe        = def.aoe,
        type       = def.type       or "pistol",
        spawn      = def.spawn      or "box",
        isPaP      = false,
        isReloading = false,
        reloadEndTime = 0,
        lastFireTime  = 0,
    }
end

local function getActive()
    return _p.weapons[_p.activeWeaponSlot]
end

local function ensureMuleKick()
    for _, pid in ipairs(_p.perks) do
        if pid == "perk_mulekick" then
            if _p.maxWeaponSlots < 3 then _p.maxWeaponSlots = 3 end
            return
        end
    end
end

function weapon.switchSlot(slot)
    ensureMuleKick()
    if slot < 1 or slot > _p.maxWeaponSlots then return false end
    if not _p.weapons[slot] then return false end
    _p.activeWeaponSlot = slot
    return true
end

function weapon.giveToPlayer(weaponId, slot)
    ensureMuleKick()
    local inst = weapon.createInstance(weaponId)
    if not inst then return false end

    if slot and slot >= 1 and slot <= _p.maxWeaponSlots then
        _p.weapons[slot] = inst
        return slot
    end
    for i = 1, _p.maxWeaponSlots do
        if not _p.weapons[i] then _p.weapons[i] = inst; return i end
    end
    local active = _p.activeWeaponSlot
    _p.weapons[active] = inst
    return active
end

function weapon.getActive()
    return getActive()
end

local BOX_POOL = {
    { id = "standard_lmg",    name = "Standard L.M.G.", weight = 12 },
    { id = "ak47",            name = "AK-47",           weight = 12 },
    { id = "uzi_md",          name = "Uzi-M.D.",        weight = 12 },
    { id = "ballista_sniper", name = "Ballista",         weight =  8 },
    { id = "raygun",          name = "Ray Gun",          weight =  2 },
}
local BOX_TOTAL = 0
for _, e in ipairs(BOX_POOL) do BOX_TOTAL = BOX_TOTAL + e.weight end

local function boxPick()
    local r = math.random() * BOX_TOTAL
    for _, e in ipairs(BOX_POOL) do
        r = r - e.weight
        if r <= 0 then return e end
    end
    return BOX_POOL[#BOX_POOL]
end

function weapon.boxSpinName() return boxPick().name end

weapon.boxRoll = {
    active = false, elapsed = 0, duration = 3.0,
    chosen = nil,   display = "",
    spinTimer = 0,  spinRate = 0.08,
    done = false,   doneTimer = 0, doneDur = 1.5,
}

function weapon.startBoxRoll()
    local r = weapon.boxRoll
    r.active = true; r.elapsed = 0; r.done = false; r.doneTimer = 0
    r.spinTimer = 0;  r.chosen = boxPick(); r.display = r.chosen.name
end

function weapon.updateBoxRoll(dt)
    local r = weapon.boxRoll
    if not r.active and not r.done then return false end

    if r.active then
        r.elapsed   = r.elapsed   + dt
        r.spinTimer = r.spinTimer + dt
        if r.spinTimer >= r.spinRate then
            r.spinTimer = 0
            r.display   = weapon.boxSpinName()
        end
        if r.elapsed >= r.duration then
            r.active    = false; r.done = true
            r.doneTimer = 0;     r.display = r.chosen.name
            weapon.giveToPlayer(r.chosen.id)
            return true
        end
    elseif r.done then
        r.doneTimer = r.doneTimer + dt
        if r.doneTimer >= r.doneDur then
            r.done = false; r.display = ""
        end
    end
    return false
end

function weapon.resetBoxRoll()
    local r = weapon.boxRoll
    r.active = false; r.elapsed = 0; r.done = false; r.doneTimer = 0
    r.chosen = nil;   r.display = ""; r.spinTimer = 0
end

local RANGE      = 50
local RANGE_SQ   = 50 * 50
local HIT_R      = 0.6
local HIT_R_SQ   = 0.6 * 0.6
local HEAD_FRAC  = 0.7   

local function pushMarker(text, expiry)
    _markers[#_markers + 1] = { text = text, expiry = expiry }
    if #_markers > MAX_MARKERS then table.remove(_markers, 1) end
end

function weapon.performHitscan(origin, yaw, pitch, w, opts)
    opts = opts or {}
    local doPoints  = opts.awardPoints
    local doMarkers = opts.addMarkers
    local isModern  = _settings.pointsSystem == "modern"
    local now       = _getTime()

    local ox, oy, oz = origin.x, origin.y, origin.z
    yaw   = math.rad(yaw   or 0)
    pitch = math.rad(pitch or 0)
    local rdx = math.cos(yaw) * math.cos(pitch)
    local rdy = math.sin(pitch)
    local rdz = math.sin(yaw) * math.cos(pitch)

    
    local candidates = {}
    for i = 1, #_zombies do
        local z = _zombies[i]
        if z and z.health > 0 then
            local ex = z.x - ox; local ez = z.z - oz
            if ex*ex + ez*ez <= (RANGE + 1) * (RANGE + 1) then
                local h     = z.height or 1.8
                local cy    = z.y + h * 0.5 + 0.4
                local vx    = z.x - ox
                local vy    = cy  - oy
                local vz    = z.z - oz
                local t     = vx*rdx + vy*rdy + vz*rdz
                if t > 0 and t <= RANGE then
                    local hx = ox + rdx*t - z.x
                    local hy = oy + rdy*t - cy
                    local hz = oz + rdz*t - z.z
                    if hx*hx + hy*hy + hz*hz <= HIT_R_SQ then
                        candidates[#candidates + 1] = {
                            index = i, dist = t,
                            hitY  = oy + rdy * t,
                        }
                    end
                end
            end
        end
    end

    
    if #candidates > 1 then
        table.sort(candidates, function(a, b) return a.dist < b.dist end)
    end

    
    local pen     = w.penetration or 0
    local maxHits = (pen == -1) and 999 or (pen + 1)
    local hits    = 0
    local results = {}

    for _, cand in ipairs(candidates) do
        if hits >= maxHits then break end
        local z = _zombies[cand.index]
        if z and z.health > 0 then
            local zH     = z.height or 1.8
            local isHead = cand.hitY >= (z.y + zH * HEAD_FRAC)
            local dmg    = w.damage * (isHead and 2 or 1)

            if doPoints then
                _p.stats.shotsHit    = _p.stats.shotsHit    + 1
                _p.stats.damageDealt = _p.stats.damageDealt + dmg
                if isHead then _p.stats.headshots = _p.stats.headshots + 1 end
            end

            local marker
            if doPoints and not isModern then
                _p.points = _p.points + 10
                marker = "+10"
            elseif doPoints then
                marker = "X"
            end

            z.health = z.health - dmg
            local killed = z.health <= 0

            if killed then
                z._killedByPlayer = true
                z._headshotKill   = isHead
                if doPoints then
                    local kpts = isModern
                        and (isHead and 115 or 90)
                        or  (isHead and 110 or 60)
                    _p.points = _p.points + kpts
                    marker = (isHead and "HEADSHOT! +" or "+")
                             .. (isModern and (isHead and 115 or 90)
                                          or  (isHead and 110 or 60))
                end
            end

            if doMarkers and marker then
                pushMarker(tostring(marker), now + 0.7)
            end

            results[#results + 1] = {
                zombieIndex = cand.index,
                damage      = dmg,
                remaining   = z.health,
                headshot    = isHead,
            }

            
            if killed and w.aoe and w.aoe > 0 then
                weapon.performSplash(
                    { x = z.x, y = z.y + 0.9, z = z.z },
                    w.aoe, w.damage * 0.5
                )
            end

            hits = hits + 1
        end
    end

    return results
end

function weapon.performSplash(origin, radius, damage)
    local ox, oy, oz = origin.x, origin.y, origin.z
    local rSq        = radius * radius
    local now        = _getTime()

    for _, z in ipairs(_zombies) do
        if z and z.health > 0 then
            local dx = z.x - ox
            local dy = (z.y + 0.9) - oy
            local dz = z.z - oz
            local dSq = dx*dx + dy*dy + dz*dz
            if dSq <= rSq then
                local factor = 1 - (math.sqrt(dSq) / radius)
                local dmg    = math.floor(damage * factor)
                if dmg > 0 then
                    z.health = z.health - dmg
                    if z.health <= 0 and not z._killedByPlayer
                                    and not z._killedByMelee then
                        z._killedBySplash = true
                    end
                end
            end
        end
    end

    
    if not _p._godMode then
        local pdx = _p.x - ox
        local pdy = (_p.y + (_p.eyeHeight or 1.6)) - oy
        local pdz = _p.z - oz
        local pdSq = pdx*pdx + pdy*pdy + pdz*pdz
        if pdSq <= rSq then
            local factor  = math.max(0, 1 - (math.sqrt(pdSq) / radius))
            local selfDmg = math.floor(damage * factor)
            if selfDmg > 0 then
                _p.health            = _p.health - selfDmg
                _p.lastHitTime       = now
                _p.stats.damageTaken = _p.stats.damageTaken + selfDmg
                pushMarker("SELF -" .. selfDmg, now + 0.8)
            end
        end
    end
end

local M_RANGE_SQ = 2.2 * 2.2
local M_DOT      = 0.4
local M_COOL     = 0.5
local M_DMG      = 99999

function weapon.performMelee()
    local now = _getTime()
    if now - (_p.lastMeleeTime or 0) < M_COOL then return false end
    if _p.isDowned or _p.inAfterlife then return false end

    _p.lastMeleeTime = now
    local yaw = math.rad(_p.rotY or 0)
    local fdx = math.cos(yaw)
    local fdz = math.sin(yaw)
    local isModern = _settings.pointsSystem == "modern"
    local mpts     = isModern and 100 or 130
    local hitCount = 0

    for _, z in ipairs(_zombies) do
        if z and z.health > 0 then
            local dx  = z.x - _p.x
            local dz  = z.z - _p.z
            local dSq = dx*dx + dz*dz
            if dSq <= M_RANGE_SQ then
                local dist = math.sqrt(dSq)
                if dist > 0 and (dx/dist)*fdx + (dz/dist)*fdz >= M_DOT then
                    z.health = z.health - M_DMG
                    if z.health <= 0 then z._killedByMelee = true end
                    _p.points            = _p.points + mpts
                    _p.stats.damageDealt = _p.stats.damageDealt + M_DMG
                    pushMarker("KNIFE! +" .. mpts, now + 0.8)
                    hitCount = hitCount + 1
                end
            end
        end
    end

    return hitCount > 0
end

function weapon.tryFire()
    local w = getActive()
    if not w or w.isReloading or w.ammo <= 0 then return false end

    local now = _getTime()
    if now - (w.lastFireTime or 0) < 60 / w.rpm then return false end

    w.ammo         = math.max(0, w.ammo - 1)
    w.lastFireTime = now
    _p.stats.shotsFired = _p.stats.shotsFired + 1
    if _muzzle then _muzzle.timer = 0.12 end
    _p.recoil = (_p.recoil or 0) + (w.recoil or 0)

    
    
    local origin = _pm.camera
    local shots  = _p.doubleTap and 2 or 1
    for _ = 1, shots do
        weapon.performHitscan(origin, _p.rotY, _p.rotZ, w,
            { awardPoints = true, addMarkers = true })
    end

    return true
end

function weapon.startReload()
    local w = getActive()
    if not w or w.isReloading          then return false end
    if w.ammo >= w.mag                 then return false end
    if not w.reserve or w.reserve <= 0 then return false end

    w.isReloading   = true
    w.reloadEndTime = _getTime() + (w.reloadTime or 1.5) / (_p.reloadMultiplier or 1)

    
    if _p.electricCherry then
        for _, z in ipairs(_zombies) do
            if z and z.health > 0 then
                local dx = z.x - _p.x
                local dz = z.z - _p.z
                if dx*dx + dz*dz <= 25 then
                    z.health = z.health - 100
                end
            end
        end
    end

    return true
end

function weapon.completeReload(w)
    w = w or getActive()
    if not w then return false end
    if not w.reserve or w.reserve <= 0 then
        w.isReloading = false; w.reloadEndTime = 0
        return false
    end
    local take  = math.min(w.mag - w.ammo, w.reserve)
    w.ammo      = w.ammo    + take
    w.reserve   = w.reserve - take
    w.isReloading = false; w.reloadEndTime = 0
    return true
end

function weapon.updateFiring(dt)
    local w = getActive()
    if not w then return end

    if w.isReloading and _getTime() >= (w.reloadEndTime or 0) then
        weapon.completeReload(w)
    end
    if w.isReloading then return end

    if _settings.autoReload and w.ammo <= 0
       and w.reserve and w.reserve > 0 then
        weapon.startReload(); return
    end

    if w.fireMode == "auto" then
        if _p.firing then weapon.tryFire() end
    else
        if _p.firing and not _p.firedOnThisClick then
            weapon.tryFire()
            _p.firedOnThisClick = true
        end
    end
end

function weapon.packAPunch()
    local w = getActive()
    if not w   then return false, "No weapon"        end
    if w.isPaP then return false, "Already upgraded" end

    local def = weapon.getWeaponDef(w.id)
    if not def or not def.papName then
        return false, "Cannot upgrade"
    end

    w.name    = def.papName
    w.damage  = def.papDamage  or (w.damage * 3)
    w.mag     = def.papMag     or w.mag
    w.ammo    = w.mag
    w.reserve = def.papReserve or w.reserve
    w.isPaP   = true
    return true
end

local _gmCache = {}   

function weapon.loadGunModel(weaponId)
    local char = _pm and _pm.character
    if not char then return nil end
    local cid = char.id

    if not _gmCache[weaponId] then _gmCache[weaponId] = {} end
    local cached = _gmCache[weaponId][cid]
    if cached ~= nil then return cached or nil end

    local gunPath = paths.gun(weaponId, cid)
    if fs.exists(gunPath) then
        local img = paintutils.loadImage(gunPath)
        if img then
            _gmCache[weaponId][cid] = img
            return img
        end
    end

    _gmCache[weaponId][cid] = false
    return nil
end

function weapon.clearGunModelCache()
    _gmCache = {}
end

function weapon.drawGunModel()
    if _p.isDowned or _p.inAfterlife then return end
    local w = getActive()
    if not w then return end
    local img = weapon.loadGunModel(w.id)
    if not img then return end

    local sw, sh = term.getSize()
    local imgH   = #img
    local imgW   = 0
    for row = 1, imgH do
        if img[row] and #img[row] > imgW then imgW = #img[row] end
    end

    local startX = sw - imgW + 1
    local startY = sh - imgH + 1

    for row = 1, imgH do
        local line = img[row]
        if line then
            for col = 1, #line do
                local px = line[col]
                if px and px ~= 0 then
                    term.setCursorPos(startX + col - 1, startY + row - 1)
                    term.setBackgroundColor(px)
                    term.write(" ")
                end
            end
        end
    end
    term.setCursorPos(1, 1)
end

function weapon.isBoxWeapon(weaponId)
    local def = weapon.getWeaponDef(weaponId)
    return def and def.spawn == "box"
end

function weapon.getWeaponDef(id)
    return _registry[id]
end

function weapon.getBoxPool()
    local pool = {}
    for _, def in pairs(_registry) do
        if def.spawn == "box" then
            pool[#pool+1] = def
        end
    end
    if #pool == 0 then pool[1] = _registry["m1911"] or {id="m1911",name="M1911"} end
    return pool
end

weapon.tryFireWeapon = weapon.tryFire

function weapon.reloadWeapon()
    return weapon.startReload()
end

return weapon
