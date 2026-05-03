

local entity = {}

local _p        = nil   
local _world    = nil
local _weapon   = nil
local _nav      = nil
local _settings = nil
local _ccz      = nil
local _getTime  = nil

function entity.init(deps)
    _p        = deps.player
    _world    = deps.world
    _weapon   = deps.weapon
    _nav      = deps.nav
    _settings = deps.settings
    _ccz      = deps.ccz
    _getTime  = deps.getCurrentTime
end

entity.ALL_PERKS = {
    "perk_juggernog",
    "perk_speedcola",
    "perk_revive",
    "perk_staminup",
    "perk_whoswho",
    "perk_phd",
    "perk_mulekick",
    "perk_cherry",
    "perk_doubletap",
}

local CLASSIC_COSTS = {
    perk_juggernog = 2500,
    perk_speedcola = 3000,
    perk_staminup  = 2000,
    perk_whoswho   = 2000,
    perk_phd       = 2000,
    perk_mulekick  = 4000,
    perk_cherry    = 2000,
    perk_doubletap = 2000,
    
}
local QR_CLASSIC_COSTS = {500, 1000, 1500}   

function entity.getPerkCost(perkType, playerState)
    playerState = playerState or _p
    if (_settings and _settings.pointsSystem == "modern") then
        
        return 2000 + (#(playerState.perks or {}) * 500)
    end
    if perkType == "perk_revive" then
        local uses = playerState.quickReviveUses or 0
        return QR_CLASSIC_COSTS[math.min(uses + 1, 3)]
    end
    return CLASSIC_COSTS[perkType]
end

entity.PERK_JINGLES = {
    perk_revive    = "-XDoiXkkP4k",
    perk_juggernog = "m6V2aw0shfo",
    perk_speedcola = "mR16k1y07P0",
    perk_mulekick  = "CBpM7qasA4U",
    perk_whoswho   = "21fl-DQ1U5A",
    pack_a_punch   = "MtnEYpbhW1o",
    perk_cherry    = "U_JMGGZLZPk",
}

entity.purchaseHold = {
    active  = false,
    elapsed = 0,
    label   = "",
    action  = nil,      
    duration = 2.0,
}
entity.reviveHold = {
    active    = false,
    elapsed   = 0,
    target    = nil,
    targetID  = nil,
    isWhosWho = false,
    duration  = 1.5,
}

function entity.updatePurchaseHold(dt)
    local h = entity.purchaseHold
    if not h.active then return false end
    h.elapsed = h.elapsed + dt
    if h.elapsed >= h.duration then
        local action = h.action
        h.active  = false
        h.elapsed = 0
        h.action  = nil
        h.label   = ""
        if action then action() end
        return true
    end
    return false
end

function entity.updateReviveHold(dt)
    local h = entity.reviveHold
    if not h.active then return false end
    h.elapsed = h.elapsed + dt
    if h.elapsed >= h.duration then
        local target   = h.target
        local targetID = h.targetID
        local isWW     = h.isWhosWho
        h.active  = false
        h.elapsed = 0
        h.target  = nil
        h.targetID = nil
        if target then
            if isWW then
                entity.completeWhosWhoRevive()
            else
                entity.revivePlayer(target)
            end
        end
        return true
    end
    return false
end

function entity.startPurchaseHold(label, action)
    local h = entity.purchaseHold
    h.active  = true
    h.elapsed = 0
    h.label   = label
    h.action  = action
end

function entity.cancelPurchaseHold()
    local h = entity.purchaseHold
    h.active  = false
    h.elapsed = 0
    h.action  = nil
    h.label   = ""
end

local function withinAABB(b)
    
    local m = 0.6
    local px, py, pz = _p.x, _p.y, _p.z
    if px+m < b.minX or px-m > b.maxX then return false end
    if pz+m < b.minZ or pz-m > b.maxZ then return false end
    if py+(_p.height or 2) < b.minY   or py > b.maxY+m then return false end
    return true
end

local INTERACT_Y_RANGE = 3   

local function distSq2D(ax,az, bx,bz)
    local dx,dz = ax-bx, az-bz
    return dx*dx + dz*dz
end

local function inYRange(entityY)
    return math.abs(_p.y - entityY) <= INTERACT_Y_RANGE
end

local DOOR_INTERACT_DIST_SQ = 3*3

function entity.getNearestDoor()
    local best, bestDSq = nil, DOOR_INTERACT_DIST_SQ
    for _, door in ipairs(_world.getDoors()) do
        if not door.opened then
            local b  = door.bounds
            local cy = (b.min[2] + b.max[2]) * 0.5
            if inYRange(cy) then
                local cx  = (b.min[1] + b.max[1]) * 0.5
                local cz  = (b.min[3] + b.max[3]) * 0.5
                local dSq = distSq2D(_p.x, _p.z, cx, cz)
                if dSq < bestDSq then best = door; bestDSq = dSq end
            end
        end
    end
    return best
end

function entity.openDoor(door)
    if not door then return false end
    if _p.points < door.cost then
        _ccz.game.announce("Need " .. door.cost .. " points to open!", 2)
        return false
    end
    _p.points  = _p.points - door.cost
    door.opened = true
    
    if _nav then
        _nav.invalidateArea({
            minX = door.bounds.min[1], minZ = door.bounds.min[3],
            maxX = door.bounds.max[1], maxZ = door.bounds.max[3],
        })
    end
    _ccz.game.announce("Door opened! -" .. door.cost .. " points", 2)
    return true
end

local PERK_INTERACT_DIST_SQ = 3*3

function entity.getNearestPerkMachine()
    for _, m in ipairs(_world.getPerkMachines()) do
        if not m.purchased and inYRange(m.pos.y) and withinAABB(m.bounds) then return m end
    end
    local best, bestDSq = nil, PERK_INTERACT_DIST_SQ
    for _, m in ipairs(_world.getPerkMachines()) do
        if not m.purchased and inYRange(m.pos.y) then
            local b   = m.bounds
            local cx  = (b.minX + b.maxX) * 0.5
            local cz  = (b.minZ + b.maxZ) * 0.5
            local dSq = distSq2D(_p.x, _p.z, cx, cz)
            if dSq < bestDSq then best = m; bestDSq = dSq end
        end
    end
    return best
end

local function applyPerkEffect(perkType)
    if perkType == "perk_juggernog" then
        _p.maxHealth = 250
        _p.health    = math.min(_p.maxHealth, _p.health + 150)
    elseif perkType == "perk_speedcola" then
        _p.reloadMultiplier = (_p.reloadMultiplier or 1) * 0.5
    elseif perkType == "perk_revive" then
        _p.quickRevive = true
    elseif perkType == "perk_mulekick" then
        _p.maxWeaponSlots = 3
    elseif perkType == "perk_whoswho" then
        _p.whosWho = true
    elseif perkType == "perk_phd" then
        _p.phdFlopper = true
    elseif perkType == "perk_cherry" then
        _p.electricCherry = true
    elseif perkType == "perk_doubletap" then
        _p.doubleTap = true
    end
    
end

function entity.purchasePerkMachine(machine)
    if not machine then return false, "Invalid machine" end
    local cost = entity.getPerkCost(machine.type)
    if cost == nil then return false, "Perk not for sale" end
    if _p.points < cost then
        _ccz.game.announce("Need " .. cost .. " points!", 2)
        return false, "Not enough points"
    end

    _p.points = _p.points - cost
    machine.purchased = true
    _p.perks[#_p.perks + 1] = machine.type
    applyPerkEffect(machine.type)
    
    return true
end

local BOX_COST = 950
local BOX_DIST_SQ = 3*3

function entity.getNearestMysteryBox()
    local best, bestDSq = nil, BOX_DIST_SQ
    for _, box in ipairs(_world.getMysteryBoxes()) do
        if inYRange(box.pos.y) then
            local dSq = distSq2D(_p.x, _p.z, box.pos.x, box.pos.z)
            if dSq < bestDSq then best = box; bestDSq = dSq end
        end
    end
    return best
end

function entity.purchaseMysteryBox()
    if _p.points < BOX_COST then
        _ccz.game.announce("Need " .. BOX_COST .. " points!", 2)
        return false
    end
    _p.points = _p.points - BOX_COST
    return true   
end

local PAP_COST = 5000

function entity.getNearestPaP()
    for _, pap in ipairs(_world.getPapMachines()) do
        if inYRange(pap.pos.y) and withinAABB(pap.bounds) then return pap end
    end
    return nil
end

function entity.packAPunchWeapon()
    if _world.hasPowerSwitch and not _world.powerOn then
        return false, "Power must be on"
    end
    if _p.points < PAP_COST then
        return false, "Need 5000 points"
    end
    local ok, reason = _weapon.packAPunch()
    if ok then
        _p.points = _p.points - PAP_COST
        _ccz.game.announce("Pack-a-Punch! -5000 pts", 2)
    end
    return ok, reason
end

local WALL_DIST_SQ = 2.5*2.5

function entity.getNearestWallWeapon()
    local best, bestDSq = nil, WALL_DIST_SQ
    for _, ww in ipairs(_world.getWallWeapons()) do
        if inYRange(ww.pos.y) then
            local dSq = distSq2D(_p.x, _p.z, ww.pos.x, ww.pos.z)
            if dSq < bestDSq then best = ww; bestDSq = dSq end
        end
    end
    return best
end

function entity.purchaseWallWeapon(ww)
    if not ww then return false, "Invalid wall weapon" end
    if _p.points < ww.cost then
        _ccz.game.announce("Need " .. ww.cost .. " points!", 2)
        return false, "Not enough points"
    end
    _p.points = _p.points - ww.cost
    
    for _, pw in ipairs(_p.weapons) do
        if pw and pw.id == ww.weaponId then
            local refill = pw.mag * 2
            pw.reserve = (pw.reserve or 0) + refill
            local def = _ccz.weapons.getDef(ww.weaponId)
            _ccz.game.announce("Ammo: " .. (def and def.name or ww.weaponId) .. " +" .. refill, 2)
            return true
        end
    end
    
    _weapon.giveToPlayer(ww.weaponId)
    local def = _ccz.weapons.getDef(ww.weaponId)
    _ccz.game.announce("Bought: " .. (def and def.name or ww.weaponId) .. " -" .. ww.cost .. " pts", 2)
    return true
end

local POWER_DIST_SQ = 2*2

function entity.getNearestPowerSwitch()
    for _, sw in ipairs(_world.getPowerSwitches()) do
        if not sw.activated then
            if inYRange(sw.pos.y) then
                local dSq = distSq2D(_p.x, _p.z, sw.pos.x, sw.pos.z)
                if dSq <= POWER_DIST_SQ then return sw end
            end
        end
    end
    return nil
end

function entity.activatePowerSwitch(sw)
    if not sw then return false end
    sw.activated   = true
    _world.powerOn = true
    
    local md = _world.loader and _world.loader.currentMap
    if md and md.onPowerActivated then pcall(md.onPowerActivated) end
    _ccz.game.announce("Power ON!", 2)
    return true
end

function entity.getNearestDownedPlayer(_players)
    return nil, nil
end

function entity.revivePlayer(downedPlayer)
    if not downedPlayer then return false end
    downedPlayer.isDowned      = false
    downedPlayer.health        = math.floor((downedPlayer.maxHealth or 100) / 2)
    downedPlayer.reviveProgress = 0
    _p.stats.revives = (_p.stats.revives or 0) + 1
    _p.points = _p.points + 500
    _ccz.game.announce("+500  Revive!", 2)
    return true
end

function entity.isNearWhosWhoBody()
    if not _p.inAfterlife or not _p.afterlifeBodyPos then return false end
    local bp = _p.afterlifeBodyPos
    return distSq2D(_p.x, _p.z, bp.x, bp.z) < 2.5*2.5
end

function entity.completeWhosWhoRevive()
    _p.inAfterlife   = false
    _p.health        = _p.maxHealth
    _p.perks         = {}
    for _, perk in ipairs(_p.afterlifePerks or {}) do
        if perk ~= "perk_whoswho" then
            _p.perks[#_p.perks+1] = perk
        end
    end
    _p.whosWho          = false
    _p.afterlifePerks   = {}
    _p.afterlifeBodyPos = nil
end

function entity.applySoloQuickRevive(perkMachineList)
    if not _p.quickRevive then return false end
    _p.health        = _p.maxHealth
    _p.quickRevive   = false
    _p.quickReviveUses = (_p.quickReviveUses or 0) + 1
    
    for i, pid in ipairs(_p.perks) do
        if pid == "perk_revive" then
            table.remove(_p.perks, i)
            break
        end
    end
    
    if _p.quickReviveUses >= 3 then
        for _, m in ipairs(perkMachineList or {}) do
            if m.type == "perk_revive" then
                m.purchased = true
                break
            end
        end
    end
    return true
end

local function perkDisplayName(perkType)
    local s = perkType:gsub("perk_",""):gsub("_"," ")
    return s:gsub("^%l", string.upper)
end

function entity.getInteractLabel(context)
    
    
    local h   = entity.purchaseHold
    local pct = h.active and math.floor(h.elapsed / h.duration * 100) or nil

    if context.nearPower then
        return "[E] Activate Power", colors.yellow, nil
    end

    if context.nearDoor then
        local door = context.nearDoor
        if pct then
            return string.format("[HOLD E] %s... %d%%", h.label, pct), colors.yellow, pct
        end
        local col = (_p.points >= door.cost) and colors.lime or colors.red
        return string.format("[HOLD E] Open Door - %d Points", door.cost), col, nil
    end

    if context.nearPaP then
        if pct then
            return string.format("[HOLD E] %s... %d%%", h.label, pct), colors.purple, pct
        end
        local w = _weapon.getActive()
        if _world.hasPowerSwitch and not _world.powerOn then
            return "Power must be ON", colors.red, nil
        end
        if w and not w.isPaP then
            local col = (_p.points >= PAP_COST) and colors.purple or colors.red
            return string.format("[HOLD E] Pack-a-Punch - %d Points", PAP_COST), col, nil
        end
        return (w and w.isPaP) and "Already Upgraded" or "Cannot Upgrade", colors.gray, nil
    end

    if context.nearPerk then
        local m = context.nearPerk
        if pct then
            return string.format("[HOLD E] %s... %d%%", h.label, pct), colors.lime, pct
        end
        local cost = entity.getPerkCost(m.type)
        local name = perkDisplayName(m.type)
        if cost then
            local col = (_p.points >= cost and not m.purchased) and colors.lime or colors.red
            return string.format("[HOLD E] Buy %s - %d Points", name, cost), col, nil
        end
        return string.format("[HOLD E] Buy %s", name), colors.white, nil
    end

    if context.nearBox then
        if pct then
            return string.format("[HOLD E] %s... %d%%", h.label, pct), colors.yellow, pct
        end
        local col = (_p.points >= BOX_COST) and colors.lime or colors.red
        return string.format("[HOLD E] Mystery Box - %d Points", BOX_COST), col, nil
    end

    if context.nearWallWeapon then
        local ww = context.nearWallWeapon
        if pct then
            return string.format("[HOLD E] %s... %d%%", h.label, pct), colors.yellow, pct
        end
        local def  = _ccz.weapons.getDef(ww.weaponId)
        local name = (def and def.name) or ww.weaponId
        local owned = false
        for _, pw in ipairs(_p.weapons) do
            if pw and pw.id == ww.weaponId then owned=true; break end
        end
        local label = owned
            and string.format("[HOLD E] Refill %s - %d pts", name, ww.cost)
            or  string.format("[HOLD E] Buy %s - %d pts",    name, ww.cost)
        local col = (_p.points >= ww.cost) and colors.yellow or colors.red
        return label, col, nil
    end

    if context.nearScriptBlock then
        if pct then
            return string.format("[HOLD E] %s... %d%%", h.label, pct), colors.orange, pct
        end
        local sl = context.nearScriptBlock:gsub("_"," "):gsub("(%a)([%w]*)",
            function(a,b) return a:upper()..b end)
        return "[HOLD E] " .. sl, colors.orange, nil
    end

    return nil, nil, nil
end

return entity
