

local utilities = {}

local player, zombies, camera, settings
local getCurrentTime
local ccz

function utilities.init(deps)
    player = deps.player
    zombies = deps.zombies
    camera = deps.camera
    getCurrentTime = deps.getCurrentTime
    settings = deps.settings
    ccz = deps.ccz
end

local HITSCAN = {
    MAX_RANGE = 50,
    HIT_RADIUS = 0.6,
    HEADSHOT_THRESHOLD = 0.7  
}

local function zombieWithinRange(z, ox, oz, maxRange)
    local dx = z.x - ox
    local dz = z.z - oz
    return (dx*dx + dz*dz) <= (maxRange * maxRange)
end

function utilities.performHitscan(origin, yaw, pitch, weaponDef)
    local results = {}
    local ox, oy, oz = origin.x, origin.y, origin.z
    
    
    yaw = math.rad(yaw or 0)
    pitch = math.rad(pitch or 0)
    local dx = math.cos(yaw) * math.cos(pitch)
    local dy = math.sin(pitch)
    local dz = math.sin(yaw) * math.cos(pitch)
    
    
    local candidates = {}
    for i = 1, #zombies do
        local z = zombies[i]
        if z and z.health > 0 then
            if zombieWithinRange(z, ox, oz, HITSCAN.MAX_RANGE + 1) then
                local centerY = z.y + (z.height or 1.8) * 0.5 + 0.4
                
                
                local vx = z.x - ox
                local vy = centerY - oy
                local vz = z.z - oz
                local t = vx*dx + vy*dy + vz*dz
                
                if t > 0 and t <= HITSCAN.MAX_RANGE then
                    local px = ox + dx * t
                    local py = oy + dy * t
                    local pz = oz + dz * t
                    local ddx = px - z.x
                    local ddy = py - centerY
                    local ddz = pz - z.z
                    
                    if ddx*ddx + ddy*ddy + ddz*ddz <= HITSCAN.HIT_RADIUS*HITSCAN.HIT_RADIUS then
                        table.insert(candidates, {index = i, dist = t, hitY = py})
                    end
                end
            end
        end
    end
    
    
    if #candidates > 1 then
        table.sort(candidates, function(a,b) return a.dist < b.dist end)
    end
    
    
    local penetration = weaponDef.penetration or 0
    local maxHits = (penetration == -1) and 999 or (penetration + 1)
    local hits = 0
    
    for _, cand in ipairs(candidates) do
        if hits >= maxHits then break end
        
        local z = zombies[cand.index]
        if z and z.health > 0 then
            
            local isHeadshot = (cand.hitY >= (z.y + (z.height or 1.8) * HITSCAN.HEADSHOT_THRESHOLD))
            
            
            local dmg = weaponDef.damage
            if isHeadshot then
                dmg = dmg * (weaponDef.headshotMultiplier or 2.0)
            end
            
            
            z.health = z.health - dmg
            if z.health <= 0 then
                z._killedByPlayer = true
                z._headshotKill = isHeadshot
            end
            
            table.insert(results, {
                zombieIndex = cand.index,
                damage = dmg,
                remaining = z.health,
                headshot = isHeadshot
            })
            
            
            if weaponDef.aoe and weaponDef.aoe > 0 and z.health <= 0 then
                utilities.performSplashDamage(
                    {x = z.x, y = z.y + 0.9, z = z.z},
                    weaponDef.aoe,
                    weaponDef.damage * 0.5
                )
            end
            
            hits = hits + 1
        end
    end
    
    return results
end

function utilities.performSplashDamage(origin, radius, damage)
    local results = {}
    for i = 1, #zombies do
        local z = zombies[i]
        if z and z.health > 0 then
            local dx = z.x - origin.x
            local dy = z.y - origin.y
            local dz = z.z - origin.z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            
            if dist <= radius then
                local falloff = 1 - (dist / radius)
                local dmg = math.floor(damage * falloff)
                z.health = z.health - dmg
                if z.health <= 0 then
                    z._killedByPlayer = true
                end
                table.insert(results, {zombieIndex = i, damage = dmg, remaining = z.health})
            end
        end
    end
    return results
end

function utilities.tryFireWeapon(weaponInstance, hitCallback)
    if not weaponInstance then return false end
    if weaponInstance.isReloading then return false end
    if weaponInstance.ammo <= 0 then return false end
    
    local now = getCurrentTime()
    local timeBetweenShots = 60 / weaponInstance.rpm
    if now - (weaponInstance.lastFireTime or 0) < timeBetweenShots then
        return false
    end
    
    
    weaponInstance.ammo = math.max(0, weaponInstance.ammo - 1)
    weaponInstance.lastFireTime = now
    
    
    local weaponDef = ccz.weapons.getDef(weaponInstance.id)
    local origin = {x = camera.x, y = camera.y, z = camera.z}
    local results = utilities.performHitscan(origin, player.rotY, player.rotZ, weaponDef)
    
    
    if hitCallback then
        hitCallback(results, weaponInstance)
    end
    
    return true
end

function utilities.reloadWeapon(weaponInstance)
    if not weaponInstance then return false end
    if weaponInstance.isReloading then return false end
    if weaponInstance.ammo >= weaponInstance.mag then return false end
    if weaponInstance.reserve <= 0 then return false end
    
    local now = getCurrentTime()
    weaponInstance.isReloading = true
    local multiplier = player.reloadMultiplier or 1
    weaponInstance.reloadEndTime = now + weaponInstance.reloadTime / multiplier
    
    
    if player.electricCherry then
        utilities.performSplashDamage(
            {x = player.x, y = player.y + 1, z = player.z},
            5,
            100
        )
    end
    
    return true
end

function utilities.completeReload(weaponInstance)
    if not weaponInstance or not weaponInstance.isReloading then return false end
    
    local needed = weaponInstance.mag - weaponInstance.ammo
    local take = math.min(needed, weaponInstance.reserve)
    weaponInstance.ammo = weaponInstance.ammo + take
    weaponInstance.reserve = weaponInstance.reserve - take
    weaponInstance.isReloading = false
    weaponInstance.reloadEndTime = 0
    
    return true
end

local MELEE = {
    RANGE = 2.2,
    CONE_DOT = 0.4,
    COOLDOWN = 0.5,
    DAMAGE = 99999,  
    POINTS_CLASSIC = 130,
    POINTS_MODERN = 100
}

function utilities.performMelee(meleeCallback)
    local now = getCurrentTime()
    if now - (player.lastMeleeTime or 0) < MELEE.COOLDOWN then return false end
    if player.isDowned or player.inAfterlife then return false end
    
    player.lastMeleeTime = now
    
    
    local yaw = math.rad(player.rotY or 0)
    local fdx = math.cos(yaw)
    local fdz = math.sin(yaw)
    local px, pz = player.x, player.z
    
    local isModern = settings.pointsSystem == "modern"
    local meleePoints = isModern and MELEE.POINTS_MODERN or MELEE.POINTS_CLASSIC
    local hits = 0
    
    for _, z in ipairs(zombies) do
        if z and z.health > 0 then
            local dx = z.x - px
            local dz = z.z - pz
            local distSq = dx*dx + dz*dz
            
            if distSq <= MELEE.RANGE * MELEE.RANGE then
                local dist = math.sqrt(distSq)
                local dot = (dx/dist)*fdx + (dz/dist)*fdz
                
                if dot >= MELEE.CONE_DOT then
                    z.health = z.health - MELEE.DAMAGE
                    if z.health <= 0 then
                        z._killedByMelee = true
                    end
                    hits = hits + 1
                end
            end
        end
    end
    
    if hits > 0 and meleeCallback then
        meleeCallback(hits, meleePoints * hits)
    end
    
    return hits > 0
end

function utilities.canAffordEntity(cost)
    return player.points >= cost
end

function utilities.spendPoints(amount)
    player.points = math.max(0, player.points - amount)
end

function utilities.addPoints(amount)
    player.points = player.points + amount
end

function utilities.purchaseDoor(door)
    if not door or door.isOpen then return false end
    
    local cost = door.cost or 750
    if not utilities.canAffordEntity(cost) then return false end
    
    utilities.spendPoints(cost)
    door.isOpen = true
    
    return true
end

function utilities.purchasePerk(perkId)
    if not perkId then return false end
    
    
    for _, p in ipairs(player.perks) do
        if p == perkId then return false end
    end
    
    local cost = ccz.perk.getCost(perkId)
    if not utilities.canAffordEntity(cost) then return false end
    
    utilities.spendPoints(cost)
    table.insert(player.perks, perkId)
    
    
    ccz.perk.applyEffects(perkId)
    
    return true, cost
end

function utilities.packAPunchWeapon(weaponInstance)
    if not weaponInstance or weaponInstance.isPaP then return false end
    
    local cost = 5000
    if not utilities.canAffordEntity(cost) then return false end
    
    utilities.spendPoints(cost)
    ccz.weapons.upgradeToPackAPunch(weaponInstance)
    
    return true
end

function utilities.hitMysteryBox()
    local cost = 950
    if not utilities.canAffordEntity(cost) then return false end
    
    utilities.spendPoints(cost)
    
    
    local boxWeapons = ccz.weapons.getBySpawn("box")
    if #boxWeapons == 0 then return false end
    
    local randomWeaponId = boxWeapons[math.random(#boxWeapons)]
    return randomWeaponId
end

function utilities.purchaseWallWeapon(weaponId)
    local weaponDef = ccz.weapons.getDef(weaponId)
    if not weaponDef or weaponDef.spawn ~= "wall" then return false end
    
    local cost = weaponDef.wallCost or 1500
    if not utilities.canAffordEntity(cost) then return false end
    
    utilities.spendPoints(cost)
    return weaponId
end

function utilities.checkCollision(x, y, z, mapData)
    if not mapData or not mapData.collision then return false end
    
    local bx = math.floor(x + 0.5)
    local by = math.floor(y + 0.5)
    local bz = math.floor(z + 0.5)
    
    local key = bx .. "," .. by .. "," .. bz
    return mapData.collision[key] == true
end

function utilities.raycastToGround(x, z, mapData, maxDistance)
    maxDistance = maxDistance or 10
    
    for dy = 0, maxDistance do
        local testY = math.floor(player.y - dy)
        if utilities.checkCollision(x, testY, z, mapData) then
            return testY + 1
        end
    end
    
    return player.y  
end

return utilities
