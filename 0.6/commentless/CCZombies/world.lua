

local world = {}

local paths = require "CCZombies.paths"

local _player = nil
local _nav    = nil
local _frame  = nil
local _ccz    = nil

function world.init(deps)
    _player = deps.player
    _nav    = deps.nav
    _frame  = deps.frame
    _ccz    = deps.ccz
end

local CHUNK_SIZE      = 8
local RENDER_CHUNKS   = 4   
local ENTITY_DIST_SQ  = 40 * 40

local collisionMask   = {}   
local worldChunks     = {}   
local meshObjects     = {}   
local cachedModels    = {}   
local doors           = {}   
local doorBlocks      = {}   
local perkMachines    = {}
local papMachines     = {}
local mysteryBoxes    = {}
local wallWeapons     = {}
local powerSwitches   = {}
local zombieSpawns    = {}

world.powerOn         = false
world.hasPowerSwitch  = false

local AFTERLIFE_REMAP = {
    [colors.white]     = colors.lightBlue,
    [colors.orange]    = colors.cyan,
    [colors.magenta]   = colors.purple,
    [colors.lightBlue] = colors.lightBlue,
    [colors.yellow]    = colors.cyan,
    [colors.lime]      = colors.blue,
    [colors.pink]      = colors.purple,
    [colors.gray]      = colors.gray,
    [colors.lightGray] = colors.lightBlue,
    [colors.cyan]      = colors.cyan,
    [colors.purple]    = colors.purple,
    [colors.blue]      = colors.blue,
    [colors.brown]     = colors.gray,
    [colors.green]     = colors.blue,
    [colors.red]       = colors.purple,
    [colors.black]     = colors.black,
}

function world.toAfterlifeColor(c)
    return AFTERLIFE_REMAP[c] or colors.blue
end

function world.createBox(width, height, depth, color)
    local hw, hh, hd = width/2, height/2, depth/2
    local function p(x1,y1,z1, x2,y2,z2, x3,y3,z3, c)
        return {x1=x1,y1=y1,z1=z1, x2=x2,y2=y2,z2=z2, x3=x3,y3=y3,z3=z3, c=c}
    end
    return {
        p(-hw,-hh,-hd, -hw,-hh, hd,  hw,-hh, hd, color),
        p(-hw,-hh,-hd,  hw,-hh, hd,  hw,-hh,-hd, color),
        p(-hw, hh,-hd,  hw, hh, hd, -hw, hh, hd, color),
        p(-hw, hh,-hd,  hw, hh,-hd,  hw, hh, hd, color),
        p(-hw,-hh,-hd, -hw, hh,-hd, -hw, hh, hd, color),
        p(-hw,-hh,-hd, -hw, hh, hd, -hw,-hh, hd, color),
        p( hw,-hh,-hd,  hw,-hh, hd,  hw, hh, hd, color),
        p( hw,-hh,-hd,  hw, hh, hd,  hw, hh,-hd, color),
        p(-hw,-hh,-hd,  hw,-hh,-hd,  hw, hh,-hd, color),
        p(-hw,-hh,-hd,  hw, hh,-hd, -hw, hh,-hd, color),
        p(-hw,-hh, hd,  hw, hh, hd,  hw,-hh, hd, color),
        p(-hw,-hh, hd, -hw, hh, hd,  hw, hh, hd, color),
    }
end

function world.getCachedBoxModel(width, height, depth, color)
    local key = width .. "," .. height .. "," .. depth .. "," .. (color or colors.white)
    if not cachedModels[key] then
        cachedModels[key] = world.createBox(width, height, depth, color or colors.white)
    end
    return cachedModels[key]
end

local CCZLoader = {}
CCZLoader.currentMap = nil

local function flattenIfNested(t)
    if not t or #t == 0 then return {} end
    local out = {}
    local function isLeafMesh(v)
        if type(v) ~= "table" then return false end
        if v.type or v.min or v.pos or v.x then return true end
        if type(v[1]) == "table" and type(v[1][1]) == "number" then return true end
        if type(v[1]) == "number" then return true end
        return false
    end
    local function flatten(tbl)
        for _, v in ipairs(tbl) do
            if isLeafMesh(v) then
                out[#out+1] = v
            elseif type(v) == "table" then
                flatten(v)
            end
        end
    end
    flatten(t)
    return out
end

local function normalizeMeshes(raw)
    local out = {}
    for _, m in ipairs(raw) do
        local entry = nil

        if m.min and m.max then
            
            entry = {
                min      = { m.min[1] or 0, m.min[2] or 0, m.min[3] or 0 },
                max      = { m.max[1] or 0, m.max[2] or 0, m.max[3] or 0 },
                color    = m.color    or colors.white,
                group    = m.group,
                door     = m.door,
                doorCost = m.doorCost,
                doorId   = m.doorId,
                invisible= m.invisible,
            }
        elseif type(m[1]) == "table" then
            
            local mn = m[1]
            local second = m[2]
            local col
            if type(second) == "table" then
                
                col = m[3]
                entry = {
                    min   = { mn[1] or 0,     mn[2] or 0,     mn[3] or 0     },
                    max   = { second[1] or 0,  second[2] or 0,  second[3] or 0  },
                    color = (type(col) == "number") and col or colors.white,
                }
            else
                
                col = second
                entry = {
                    min   = { mn[1] or 0, mn[2] or 0, mn[3] or 0 },
                    max   = { mn[1] or 0, mn[2] or 0, mn[3] or 0 },
                    color = (type(col) == "number") and col or colors.white,
                }
            end
        elseif m.x ~= nil and m.sx ~= nil then
            local x,y,z   = m.x or 0, m.y or 0, m.z or 0
            local sx,sy,sz = m.sx or 1, m.sy or 1, m.sz or 1
            entry = {
                min   = {x,    y,    z   },
                max   = {x+sx, y+sy, z+sz},
                color = m.color or colors.white,
            }
        elseif type(m[1]) == "number" then
            local x,y,z = m[1] or 0, m[2] or 0, m[3] or 0
            local sx,sy,sz
            local col
            if type(m[4]) == "table" then
                sx,sy,sz = m[4][1] or 1, m[4][2] or 1, m[4][3] or 1
                col      = m[5]
            else
                sx,sy,sz = m[4] or 1, m[5] or 1, m[6] or 1
                col      = m[7]
            end
            if type(sx) ~= "number" then sx = 1 end
            if type(sy) ~= "number" then sy = 1 end
            if type(sz) ~= "number" then sz = 1 end
            entry = {
                min   = {x,    y,    z   },
                max   = {x+sx, y+sy, z+sz},
                color = (type(col) == "number") and col or colors.white,
            }
        end

        if entry then out[#out+1] = entry end
    end
    return out
end

function CCZLoader.loadMap(mapName)
    local mapPath = paths.map(mapName)
    if not fs.exists(mapPath) then return nil, "Map not found: " .. mapPath end

    local f = fs.open(mapPath, "r")
    if not f then return nil, "Could not open: " .. mapPath end
    local content = f.readAll(); f.close()

    local fn, loadErr = load(content, mapPath)
    if not fn then return nil, "Syntax error: " .. tostring(loadErr) end

    
    if CCZLoader._ccz then
        local env = setmetatable({ ccz = CCZLoader._ccz, ccz_map = CCZLoader._ccz.map }, {__index = _G})
        setfenv(fn, env)
    end

    local ok, mapData = pcall(fn)
    if not ok or type(mapData) ~= "table" then
        return nil, "Exec error: " .. tostring(mapData)
    end

    mapData.version      = mapData.version      or 1
    mapData.name         = mapData.name         or mapName
    mapData.mapType      = mapData.mapType       or "normal"
    mapData.description  = mapData.description  or ""
    mapData.meshes       = normalizeMeshes(flattenIfNested(mapData.meshes   or {}))
    mapData.entities     = flattenIfNested(mapData.entities or {})
    mapData.spawns       = mapData.spawns        or {player={{x=0,y=1,z=0}}, zombie={}}
    mapData.interactables = mapData.interactables or {}

    CCZLoader.currentMap = mapData
    return mapData
end

function CCZLoader.scanMaps()
    return paths.scanMaps()
end

function CCZLoader.getDLCMaps()
    local builtin = { MenuRoom=true, Tranzit=true, NHLabs=true, Origins=true }
    local out = {}
    for _, name in ipairs(CCZLoader.scanMaps()) do
        if not builtin[name] then out[#out+1] = name end
    end
    return out
end

function CCZLoader.setCCZ(cczObj)
    CCZLoader._ccz = cczObj
end

world.loader = CCZLoader

function world.showLoadingScreen(mapName)
    term.setBackgroundColor(colors.black)
    term.clear()
    local md = CCZLoader.currentMap
    term.setCursorPos(2, 2)
    term.setTextColor(colors.orange)
    term.write(((md and md.name) or mapName):upper())
    if md and md.description ~= "" then
        term.setCursorPos(2, 3); term.setTextColor(colors.white)
        term.write(md.description); sleep(0.8)
    end
    if md and md.location and md.location ~= "" then
        term.setCursorPos(2, 4); term.setTextColor(colors.gray)
        term.write(md.location); sleep(0.8)
    end
    sleep(0.5)
    term.setCursorPos(2, 6); term.setTextColor(colors.gray); term.write("---")
end

function world.preBakeCollisions(meshes)
    collisionMask = {}
    if not meshes then return end
    term.setCursorPos(2, 7); term.setTextColor(colors.gray); term.write("INITIALIZING PHYSICS...")
    for i, m in ipairs(meshes) do
        for x = math.floor(m.min[1]), math.ceil(m.max[1]) do
            if not collisionMask[x] then collisionMask[x] = {} end
            for z = math.floor(m.min[3]), math.ceil(m.max[3]) do
                if not collisionMask[x][z] then collisionMask[x][z] = {} end
                for y = math.floor(m.min[2]), math.ceil(m.max[2]) do
                    collisionMask[x][z][y] = true
                end
            end
        end
        if i % 50 == 0 then
            term.setCursorPos(27, 7); term.write(math.floor(i/#meshes*100).."%")
        end
    end
    term.setCursorPos(27, 7); term.setTextColor(colors.lime); term.write("DONE")
end

local hiddenMeshGroups  = {}   
local alwaysRenderObjects = {}  

function world.bakeWorldChunks(meshes)
    worldChunks  = {}
    meshObjects  = {}
    if not meshes or not _frame then return end
    term.setCursorPos(2, 8); term.setTextColor(colors.gray); term.write("CHUNKING WORLD...")

    local seen = {}
    for i, m in ipairs(meshes) do
        
        if not m.invisible then
            
            local minCX = math.floor(m.min[1] / CHUNK_SIZE)
            local maxCX = math.floor(m.max[1] / CHUNK_SIZE)
            local minCZ = math.floor(m.min[3] / CHUNK_SIZE)
            local maxCZ = math.floor(m.max[3] / CHUNK_SIZE)
            for cx = minCX, maxCX do
                for cz = minCZ, maxCZ do
                    local key = cx .. "," .. cz
                    if not worldChunks[key] then worldChunks[key] = {} end
                    worldChunks[key][#worldChunks[key]+1] = m
                end
            end

            
            local mk = m.min[1]..","..m.min[2]..","..m.min[3]..","..m.max[1]..","..m.max[2]..","..m.max[3]
            if not seen[mk] then
                seen[mk] = true
                local w = m.max[1] - m.min[1] + 1
                local h = m.max[2] - m.min[2] + 1
                local d = m.max[3] - m.min[3] + 1
                local model = world.getCachedBoxModel(w, h, d, m.color)
                local cx2 = m.min[1] + w/2 - 0.5
                local cy2 = m.min[2] + h/2 - 0.5
                local cz2 = m.min[3] + d/2 - 0.5
                meshObjects[mk] = _frame:newObject(model, cx2, cy2, cz2)
            end
        end

        if i % 50 == 0 then
            term.setCursorPos(20, 8); term.write(math.floor(i/#meshes*100).."%")
        end
    end
    term.setCursorPos(20, 8); term.setTextColor(colors.lime); term.write("DONE")
end

function world.isBlocked(x, y, z)
    local ix = math.floor(x)
    local iy = math.floor(y)
    local iz = math.floor(z)
    local xT = collisionMask[ix]; if not xT then return false end
    local zT = xT[iz];            if not zT then return false end
    return zT[iy] == true
end

function world.isBlockSolid(x, y, z)
    if not world.isBlocked(x, y, z) then return false end
    local key = math.floor(x)..","..math.floor(y)..","..math.floor(z)
    local door = doorBlocks[key]
    if door and door.opened then return false end
    return true
end

function world.checkCollision(x, y, z, radius)
    radius = radius or 0.4
    
    local probes = {
        {-radius, -radius}, {radius, -radius}, {-radius, radius}, {radius, radius},
        {-radius, 0},       {radius, 0},       {0, -radius},      {0, radius},
    }
    for _, o in ipairs(probes) do
        local px, pz = x + o[1], z + o[2]
        if world.isBlocked(px, y, pz) then
            local key = math.floor(px)..","..math.floor(y)..","..math.floor(pz)
            local door = doorBlocks[key]
            if not door or not door.opened then
                return true
            end
        end
    end
    return false
end

function world.checkPlayerCollision(x, y, z, radius)
    radius = radius or 0.4
    local height = (_player and _player.height) or 2
    for h = 0, height - 1 do
        if world.checkCollision(x, y + h, z, radius) then return true end
    end
    return false
end

function world.findGroundBelow(x, y, z, maxDist)
    maxDist = maxDist or 10
    for i = 0, maxDist do
        if world.isBlocked(x, y - i - 0.1, z) then
            return y - i
        end
    end
    return nil
end

function world.isPlayerLookingAt(bounds, plr)
    plr = plr or _player
    local ry = math.rad(plr.rotY or 0)
    local rz = math.rad(plr.rotZ or 0)
    local dir = {
        math.sin(ry) * math.cos(rz),
       -math.sin(rz),
        math.cos(ry) * math.cos(rz),
    }
    local orig = {plr.x, plr.y + 1.5, plr.z}
    local RAY_LEN = 5
    
    local tmin, tmax = -math.huge, math.huge
    for i = 1, 3 do
        local d = dir[i]
        if d == 0 then d = 1e-9 end
        local t1 = (bounds.min[i] - orig[i]) / d
        local t2 = (bounds.max[i] - orig[i]) / d
        if t1 > t2 then t1, t2 = t2, t1 end
        if t1 > tmin then tmin = t1 end
        if t2 < tmax then tmax = t2 end
    end
    return tmin <= tmax and tmin >= 0 and tmin <= RAY_LEN
end

function world.buildDoorsFromMeshes(mapData)
    if not mapData or not mapData.meshes then return end
    doors     = {}
    doorBlocks = {}

    local doorMeshes = {}
    for _, m in ipairs(mapData.meshes) do
        if m.door then doorMeshes[#doorMeshes+1] = m end
    end
    if #doorMeshes == 0 then return end

    local function touching(a, b)
        local function ov1D(amin,amax,bmin,bmax)
            return amin <= bmax+1 and amax >= bmin-1
        end
        if not ov1D(a.min[1],a.max[1],b.min[1],b.max[1]) then return false end
        if not ov1D(a.min[2],a.max[2],b.min[2],b.max[2]) then return false end
        if not ov1D(a.min[3],a.max[3],b.min[3],b.max[3]) then return false end
        
        local adjX = a.min[1]==b.max[1]+1 or a.max[1]==b.min[1]-1
        local adjY = a.min[2]==b.max[2]+1 or a.max[2]==b.min[2]-1
        local adjZ = a.min[3]==b.max[3]+1 or a.max[3]==b.min[3]-1
        return adjX or adjY or adjZ
    end

    local visited = {}
    for i = 1, #doorMeshes do
        if not visited[i] then
            local group = {}
            local queue = {i}; local qi = 1
            while qi <= #queue do
                local idx = queue[qi]; qi = qi + 1
                if not visited[idx] then
                    visited[idx] = true
                    group[#group+1] = doorMeshes[idx]
                    for j = 1, #doorMeshes do
                        if not visited[j] and touching(doorMeshes[idx], doorMeshes[j]) then
                            queue[#queue+1] = j
                        end
                    end
                end
            end

            
            local maxCost = 750
            local minX, minY, minZ =  math.huge,  math.huge,  math.huge
            local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
            for _, m in ipairs(group) do
                local c = m.doorCost or 750
                if c > maxCost then maxCost = c end
                if m.min[1] < minX then minX = m.min[1] end
                if m.min[2] < minY then minY = m.min[2] end
                if m.min[3] < minZ then minZ = m.min[3] end
                if m.max[1] > maxX then maxX = m.max[1] end
                if m.max[2] > maxY then maxY = m.max[2] end
                if m.max[3] > maxZ then maxZ = m.max[3] end
            end

            local door = {
                bounds   = { min={minX,minY,minZ}, max={maxX,maxY,maxZ} },
                cost     = maxCost,
                id       = group[1].doorId or "",   
                opened   = false,
                blocks   = {},
                meshKeys = {},   
            }

            for _, m in ipairs(group) do
                local mk = m.min[1]..","..m.min[2]..","..m.min[3]..","..m.max[1]..","..m.max[2]..","..m.max[3]
                door.meshKeys[mk] = true

                for bx = m.min[1], m.max[1] do
                    for by = m.min[2], m.max[2] do
                        for bz = m.min[3], m.max[3] do
                            local key = bx..","..by..","..bz
                            door.blocks[#door.blocks+1] = key
                            doorBlocks[key] = door
                        end
                    end
                end
            end

            doors[#doors+1] = door
        end
    end
end

local PERK_COLORS = {
    perk_juggernog = colors.red,
    perk_whoswho   = colors.cyan,
    perk_revive    = colors.blue,
    perk_speedcola = colors.green,
    perk_phd       = colors.purple,
    perk_staminup  = colors.orange,
    perk_mulekick  = colors.gray,
    perk_cherry    = colors.magenta,
    perk_doubletap = colors.yellow,
}
world.PERK_COLORS = PERK_COLORS

function world.loadEntities(mapData)
    zombieSpawns  = {}
    powerSwitches = {}
    perkMachines  = {}
    papMachines   = {}
    mysteryBoxes  = {}
    wallWeapons   = {}
    world.powerOn        = false
    world.hasPowerSwitch = false

    if not mapData then return end
    world.buildDoorsFromMeshes(mapData)

    local entities = mapData.entities or {}   

    for _, ent in ipairs(entities) do
        if ent.pos then
            local x, y, z = ent.pos[1], ent.pos[2], ent.pos[3]
            local t = ent.type

            if t == "zombie_spawn" then
                zombieSpawns[#zombieSpawns+1] = {x=x, y=y, z=z, requiredDoor=ent.requiredDoor or ""}

            elseif t == "power_switch" then
                world.hasPowerSwitch = true
                powerSwitches[#powerSwitches+1] = {
                    pos={x=x,y=y,z=z}, activated=false
                }

            elseif PERK_COLORS[t] then
                perkMachines[#perkMachines+1] = {
                    type     = t,
                    pos      = {x=x, y=y, z=z},
                    rotation = ent.rotation or 0,
                    purchased = false,
                    bounds   = {minX=x-0.5,maxX=x+1.5,minY=y,maxY=y+3,minZ=z-0.5,maxZ=z+1.5},
                }

            elseif t == "mystery_box" then
                mysteryBoxes[#mysteryBoxes+1] = {
                    pos      = {x=x, y=y, z=z},
                    rotation = ent.rotation or 0,
                    bounds   = {minX=x-1,maxX=x+2,minY=y,maxY=y+1,minZ=z-0.5,maxZ=z+1.5},
                }

            elseif t == "pack_a_punch" then
                papMachines[#papMachines+1] = {
                    pos      = {x=x, y=y, z=z},
                    rotation = ent.rotation or 0,
                    bounds   = {minX=x-1,maxX=x+2,minY=y,maxY=y+2,minZ=z-1,maxZ=z+2},
                }

            elseif t == "wall_weapon" then
                wallWeapons[#wallWeapons+1] = {
                    pos      = {x=x, y=y, z=z},
                    weaponId = ent.weaponId or "m1911",
                    cost     = ent.cost     or 500,
                    bounds   = {minX=x-1,maxX=x+1,minY=y,maxY=y+2,minZ=z-1,maxZ=z+1},
                }
            end
        end
    end

    
    if #zombieSpawns == 0 and mapData.spawns then
        for _, sp in ipairs(mapData.spawns.zombie or {}) do
            zombieSpawns[#zombieSpawns+1] = {x=sp.x, y=sp.y, z=sp.z, requiredDoor=sp.requiredDoor or ""}
        end
    end
    
    if #zombieSpawns == 0 then
        local sp = (mapData.spawns and mapData.spawns.player and mapData.spawns.player[1]) or {x=0,y=1,z=0}
        for _, o in ipairs({{10,0,0},{-10,0,0},{0,0,10},{0,0,-10},{8,0,8},{-8,0,8},{8,0,-8},{-8,0,-8}}) do
            zombieSpawns[#zombieSpawns+1] = {x=sp.x+o[1], y=sp.y+o[2], z=sp.z+o[3]}
        end
    end

    if not world.hasPowerSwitch then world.powerOn = true end
end

function world.getZombieSpawns()  return zombieSpawns  end
function world.getDoors()         return doors          end
function world.getDoorBlocks()    return doorBlocks     end
function world.getPerkMachines()  return perkMachines   end
function world.getPapMachines()   return papMachines    end
function world.getMysteryBoxes()  return mysteryBoxes   end
function world.getWallWeapons()   return wallWeapons    end
function world.getPowerSwitches() return powerSwitches  end

function world.findPlayerSpawn(mapData)
    mapData = mapData or CCZLoader.currentMap
    if not mapData then return 0, 1, 0 end
    if mapData.entities then
        for _, ent in ipairs(mapData.entities) do
            if ent.type == "player_spawn" and ent.pos then
                return ent.pos[1], ent.pos[2], ent.pos[3]
            end
        end
    end
    if mapData.spawns and mapData.spawns.player and #mapData.spawns.player > 0 then
        local sp = mapData.spawns.player[1]
        return sp.x, sp.y, sp.z
    end
    return 0, 1, 0
end

local function isInRenderDist(pos)
    local dx = _player.x - (pos.x or pos[1] or 0)
    local dz = _player.z - (pos.z or pos[3] or 0)
    return dx*dx + dz*dz <= ENTITY_DIST_SQ
end

local cachedEntityModels = {}
local function entityModel(key, w, h, d, color)
    if not cachedEntityModels[key] then
        cachedEntityModels[key] = world.createBox(w, h, d, color)
    end
    return cachedEntityModels[key]
end

function world.renderMap(renderedObjects)
    if not worldChunks then return end
    local cx = math.floor(_player.x / CHUNK_SIZE)
    local cz = math.floor(_player.z / CHUNK_SIZE)
    local seen = {}

    
    local inAfterlife = _player.inAfterlife

    for dx = -RENDER_CHUNKS, RENDER_CHUNKS do
        for dz = -RENDER_CHUNKS, RENDER_CHUNKS do
            local key = (cx+dx) .. "," .. (cz+dz)
            local chunk = worldChunks[key]
            if chunk then
                for _, mesh in ipairs(chunk) do
                    local mk = mesh.min[1]..","..mesh.min[2]..","..mesh.min[3]..","..mesh.max[1]..","..mesh.max[2]..","..mesh.max[3]
                    if not seen[mk] then
                        seen[mk] = true
                        
                        local skip = (mesh.group and hiddenMeshGroups[mesh.group])
                        if not skip then
                            local door = nil
                            if mesh.door then
                                
                                for _, d in ipairs(doors) do
                                    if d.meshKeys[mk] then door = d; break end
                                end
                            end
                            if door and door.opened then skip = true end
                        end
                        if not skip then
                            local obj = meshObjects[mk]
                            if obj then
                                
                                if inAfterlife and mesh.color then
                                    local remapped = world.toAfterlifeColor(mesh.color)
                                    local w = mesh.max[1]-mesh.min[1]+1
                                    local h = mesh.max[2]-mesh.min[2]+1
                                    local d = mesh.max[3]-mesh.min[3]+1
                                    local model = world.getCachedBoxModel(w, h, d, remapped)
                                    local cx2 = mesh.min[1] + w/2 - 0.5
                                    local cy2 = mesh.min[2] + h/2 - 0.5
                                    local cz2 = mesh.min[3] + d/2 - 0.5
                                    renderedObjects[#renderedObjects+1] = _frame:newObject(model, cx2, cy2, cz2)
                                else
                                    renderedObjects[#renderedObjects+1] = obj
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    for _, entry in ipairs(alwaysRenderObjects) do
        renderedObjects[#renderedObjects+1] = entry.obj
    end
end

function world.renderPerkMachines(renderedObjects)
    for _, m in ipairs(perkMachines) do
        if not m.purchased and isInRenderDist(m.pos) then
            local x, y, z = m.pos.x, m.pos.y, m.pos.z
            local color = PERK_COLORS[m.type] or colors.white
            local model = entityModel("perk_"..m.type, 1, 3, 1, color)
            local rot = m.rotation or 0
            local dx1,dz1,dx2,dz2 = 0,0,0,1
            if     rot==90  then dx1,dz1,dx2,dz2 = 0,0,1,0
            elseif rot==180 then dx1,dz1,dx2,dz2 = 0,0,0,-1
            elseif rot==270 then dx1,dz1,dx2,dz2 = 0,0,-1,0 end
            renderedObjects[#renderedObjects+1] = _frame:newObject(model, x+dx1, y+1.5, z+dz1)
            renderedObjects[#renderedObjects+1] = _frame:newObject(model, x+dx2, y+1.5, z+dz2)
        end
    end
end

function world.renderMysteryBoxes(renderedObjects)
    local model = entityModel("mystery_box", 1, 1, 1, colors.yellow)
    for _, box in ipairs(mysteryBoxes) do
        if isInRenderDist(box.pos) then
            local x, y, z = box.pos.x, box.pos.y, box.pos.z
            local rot = box.rotation or 0
            local positions = (rot==0 or rot==180)
                and {{x-1,y,z},{x,y,z},{x+1,y,z}}
                or  {{x,y,z-1},{x,y,z},{x,y,z+1}}
            for _, p in ipairs(positions) do
                renderedObjects[#renderedObjects+1] = _frame:newObject(model, p[1], p[2], p[3])
            end
        end
    end
end

function world.renderPapMachines(renderedObjects)
    local model = entityModel("pap", 1, 1, 1, colors.purple)
    for _, pap in ipairs(papMachines) do
        if isInRenderDist(pap.pos) then
            local x, y, z = pap.pos.x, pap.pos.y, pap.pos.z
            local rot = pap.rotation or 0
            local positions = (rot==0 or rot==180)
                and {{x-1,y,z},{x,y,z},{x+1,y,z},{x-1,y+1,z},{x,y+1,z},{x+1,y+1,z}}
                or  {{x,y,z-1},{x,y,z},{x,y,z+1},{x,y+1,z-1},{x,y+1,z},{x,y+1,z+1}}
            for _, p in ipairs(positions) do
                renderedObjects[#renderedObjects+1] = _frame:newObject(model, p[1], p[2], p[3])
            end
        end
    end
end

function world.renderPowerSwitches(renderedObjects)
    for _, sw in ipairs(powerSwitches) do
        local x, y, z = sw.pos.x, sw.pos.y, sw.pos.z
        local color = sw.activated and colors.lime or colors.red
        local model = entityModel("switch_"..tostring(sw.activated), 0.5, 1, 0.5, color)
        renderedObjects[#renderedObjects+1] = _frame:newObject(model, x, y,   z)
        renderedObjects[#renderedObjects+1] = _frame:newObject(model, x, y+1, z)
    end
end

world.groupAPI = {
    showGroup  = function(n) hiddenMeshGroups[n] = nil  end,
    hideGroup  = function(n) hiddenMeshGroups[n] = true end,
    swapGroups = function(hide, show)
        hiddenMeshGroups[hide] = true
        hiddenMeshGroups[show] = nil
    end,
    
    
    
    addPersistentObject = function(mesh)
        if not _frame then return nil end
        local w = mesh.max[1] - mesh.min[1] + 1
        local h = mesh.max[2] - mesh.min[2] + 1
        local d = mesh.max[3] - mesh.min[3] + 1
        local cx = mesh.min[1] + w/2 - 0.5
        local cy = mesh.min[2] + h/2 - 0.5
        local cz = mesh.min[3] + d/2 - 0.5
        local model = world.getCachedBoxModel(w, h, d, mesh.color)
        local obj   = _frame:newObject(model, cx, cy, cz)
        local mk    = "persist:"..cx..","..cy..","..cz..","..mesh.color
        alwaysRenderObjects[#alwaysRenderObjects+1] = {obj=obj, mk=mk}
        return mk
    end,
    
    removePersistentObject = function(mk)
        for i = #alwaysRenderObjects, 1, -1 do
            if alwaysRenderObjects[i].mk == mk then
                table.remove(alwaysRenderObjects, i)
                return true
            end
        end
        return false
    end,
}

function world.reset()
    collisionMask      = {}
    worldChunks        = {}
    meshObjects        = {}
    cachedModels       = {}
    cachedEntityModels = {}
    doors              = {}
    doorBlocks         = {}
    perkMachines       = {}
    papMachines        = {}
    mysteryBoxes       = {}
    wallWeapons        = {}
    powerSwitches      = {}
    zombieSpawns       = {}
    hiddenMeshGroups   = {}
    alwaysRenderObjects = {}
    world.powerOn        = false
    world.hasPowerSwitch = false
    if _nav then _nav.clearCache() end
end

return world
