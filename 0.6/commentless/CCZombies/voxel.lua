

local voxel = {}

local _player = nil
local _world  = nil
local _ccz    = nil
local _audio  = nil
local _frame  = nil
local _getRO  = nil   

function voxel.init(deps)
    _player = deps.player
    _world  = deps.world
    _ccz    = deps.ccz
    _audio  = deps.audio
    _frame  = deps.frame
    _getRO  = deps.getRenderedObjects
end

local _sharedBoxCache    = {}
local _deathFlashCache   = {}   

local function getBox(sX, sY, sZ, color)
    local key = sX .. "_" .. sY .. "_" .. sZ .. "_" .. tostring(color)
    if not _sharedBoxCache[key] then
        _sharedBoxCache[key] = _world.createBox(sX, sY, sZ, color)
    end
    return _sharedBoxCache[key]
end

local function getDeathFlashBox(sX, sY, sZ)
    local key = sX .. "_" .. sY .. "_" .. sZ
    if not _deathFlashCache[key] then
        _deathFlashCache[key] = _world.createBox(
            math.max(sX, 0.25),
            math.max(sY, 0.25),
            math.max(sZ, 0.25),
            colors.white)
    end
    return _deathFlashCache[key]
end

local paths = require "CCZombies.paths"

local _loadedModels = {}   

local function findModelPath(pathOrFile)
    return paths.model(pathOrFile)
end

function voxel.loadModel(filename)
    local path = findModelPath(filename)
    if not path then
        print("[voxel] model not found: " .. tostring(filename))
        return nil
    end

    local f = fs.open(path, "r")
    if not f then return nil end
    local content = f.readAll(); f.close()

    
    local raw
    local fn, err = load("return " .. content, path)
    if fn then
        local ok, result = pcall(fn)
        raw = ok and result or nil
    end
    if not raw then
        raw = textutils.unserializeJSON(content)
    end
    if not raw or not raw.frames then
        print("[voxel] bad model format: " .. path)
        return nil
    end

    local res = raw.res or 0.25
    local def = {
        res        = res,
        frameCount = #raw.frames,
        frames     = {},
    }

    for fi, rawFrame in ipairs(raw.frames) do
        local builtFrame = {}
        for _, entry in ipairs(rawFrame) do
            local ox    = entry[1] * res
            local oy    = entry[2] * res
            local oz    = entry[3] * res
            local sX    = entry[4] * res
            local sY    = entry[5] * res
            local sZ    = entry[6] * res
            local color = entry[7]
            builtFrame[#builtFrame+1] = {
                box        = getBox(sX, sY, sZ, color),
                deathBox   = getDeathFlashBox(sX, sY, sZ),
                ox = ox, oy = oy, oz = oz,
            }
        end
        def.frames[fi] = builtFrame
    end
    return def
end

function voxel.getOrLoadModel(bossType)
    if _loadedModels[bossType] ~= nil then
        return _loadedModels[bossType]   
    end
    local def = _ccz and _ccz.boss and _ccz.boss.getDef(bossType)
    if not def then _loadedModels[bossType] = false; return false end
    if not def.model then _loadedModels[bossType] = false; return false end
    local m = voxel.loadModel(def.model)
    _loadedModels[bossType] = m or false
    return m or false
end

local RENDER_DIST_SQ = 50 * 50

function voxel.renderModel(modelDef, entity, dt)
    if not modelDef or not modelDef.frames or #modelDef.frames == 0 then return end

    
    local dx    = _player.x - entity.x
    local dz    = _player.z - entity.z
    local angle = math.atan2(dz, dx) + math.pi
    local sinA  = math.sin(angle)
    local cosA  = math.cos(angle)

    
    local frameIdx = 1
    if entity.animState then
        frameIdx = _ccz.animation.update(entity.animState, dt)
        entity.currentFrame = frameIdx
    else
        entity.animTimer = (entity.animTimer or 0) + dt
        if entity.animTimer >= 0.25 then
            entity.animTimer = 0
            local fc = math.max(1, modelDef.frameCount)
            entity.currentFrame = ((entity.currentFrame or 1) % fc) + 1
        end
        frameIdx = entity.currentFrame or 1
    end
    frameIdx = math.max(1, math.min(frameIdx, #modelDef.frames))

    local builtFrame = modelDef.frames[frameIdx]
    if not builtFrame then return end

    
    local deathFlash = entity._dying and
        (os.epoch("utc") / 1000 - (entity._deathTime or 0)) < 0.4

    local ro = _getRO()
    for _, vox in ipairs(builtFrame) do
        local rx = vox.ox * cosA - vox.oz * sinA
        local rz = vox.ox * sinA + vox.oz * cosA
        local box = deathFlash and vox.deathBox or vox.box
        ro[#ro+1] = _frame:newObject(box, entity.x + rx, entity.y + vox.oy, entity.z + rz)
    end
end

voxel.shakeOffset = {x = 0, y = 0}
local _shake = nil

function voxel.triggerShake(duration, magnitude)
    _shake = {
        startTime = os.epoch("utc") / 1000,
        duration  = duration  or 0.2,
        magnitude = magnitude or 1.5,
    }
end

function voxel.updateShake(dt)
    voxel.shakeOffset.x = 0
    voxel.shakeOffset.y = 0
    if not _shake then return end
    local elapsed = os.epoch("utc") / 1000 - _shake.startTime
    if elapsed >= _shake.duration then
        _shake = nil
        return
    end
    local t   = elapsed / _shake.duration
    local mag = math.sin(t * math.pi * 6) * _shake.magnitude * (1 - t)
    voxel.shakeOffset.x = mag
    voxel.shakeOffset.y = mag * 0.5
end

function voxel.drawBoss(z, dt)
    local model = voxel.getOrLoadModel(z.type)
    if not model then return end
    if not z.animState then
        z.animState = _ccz.animation.newState(z.type, "walk")
    end
    local prevHealth = z._prevHealth or z.health
    _ccz.boss.update(z, dt, prevHealth)
    z._prevHealth = z.health
    voxel.renderModel(model, z, dt)
end

function voxel.renderZombies(zombies, dt)
    dt = dt or 0.05
    for _, z in ipairs(zombies) do
        if z.health > 0 then
            local dx = _player.x - z.x
            local dz = _player.z - z.z
            if dx*dx + dz*dz <= RENDER_DIST_SQ then
                if _ccz.boss.isBoss(z) then
                    voxel.drawBoss(z, dt)
                end
                
            end
        end
    end
end

function voxel.registerPanzer()
    _ccz.animation.define("panzer", {
        walk     = {frames = {1, 1}, loop = true,  fps = 4},
        flameOut = {frames = {1, 1}, loop = true,  fps = 6},
        death    = {frames = {1, 1}, loop = false, fps = 4, onEnd = "dead"},
        dead     = {frames = {1, 1}, loop = false, fps = 1},
    })
    _ccz.boss.register("panzer", {
        model      = paths.model("panzermodel.json"),
        health     = nil,   
        speed      = 0.14,
        damage     = 50,
        attackRate = 1.0,
        killPoints = 500,
        animation  = "panzer",
        phases = {
            {healthPct = 1.0,  state = "walk",     speed = 0.14},
            {healthPct = 0.66, state = "flameOut",  speed = 0.20,
                onEnter = function(_boss)
                    _ccz.game.announce("Panzer Soldát ENRAGED!", 2)
                end},
            {healthPct = 0.33, state = "walk",     speed = 0.28},
        },
        onSpawn = function(_boss)
            _audio.playPanzerSiren()
        end,
        onAttack = function(_boss, _target)
            voxel.triggerShake(0.2, 1.5)
        end,
        onDeath = function(boss)
            boss._dying     = true
            boss._deathTime = os.epoch("utc") / 1000
            if boss.animState then
                _ccz.animation.setState(boss.animState, "death")
            end
            _ccz.game.announce("Panzer Soldát destroyed!", 3)
        end,
    })
end

function voxel.initialize()
    voxel.registerPanzer()
    
    
end

function voxel.reset()
    _loadedModels = {}
    _sharedBoxCache  = {}
    _deathFlashCache = {}
    _shake = nil
    voxel.shakeOffset.x = 0
    voxel.shakeOffset.y = 0
end

return voxel
