

local player = {}

local _settings = nil
local _ccz      = nil

function player.init(deps)
    _settings = deps.settings
    _ccz      = deps.ccz
end

player.CHARACTERS = {
    { id = "DrNightheart",    name = "Dr. Nightheart"   },
    { id = "ArissNightheart", name = "Ariss Nightheart" },
    { id = "Bayard",          name = "Bayard"           },
    { id = "AliceE",          name = "Alice E."         },
}

local DEFAULTS = {
    
    x = 0, y = 1, z = 0,

    
    rotY = 0, rotZ = 0,

    
    velocityY    = 0,
    onGround     = false,

    
    height    = 2,
    eyeHeight = 1.6,

    
    health    = 100,
    maxHealth = 100,

    
    points = 500,

    
    color = colors.blue,

    
    username = "",

    
    stats = {
        shotsFired   = 0,
        shotsHit     = 0,
        headshots    = 0,
        downs        = 0,
        revives      = 0,
        damageDealt  = 0,
        damageTaken  = 0,
    },

    
    weapons          = {},   
    maxWeaponSlots   = 2,
    activeWeaponSlot = 1,

    
    firing            = false,
    firedOnThisClick  = false,
    recoil            = 0,

    
    reloadMultiplier    = 1,
    moveSpeedMultiplier = 1,
    sprintSpeedMultiplier = 1,

    
    isDowned      = false,
    downedTime    = 0,
    bleedoutTime  = 45,
    reviveProgress = 0,

    
    inAfterlife       = false,
    afterlifeBodyPos  = nil,
    afterlifePerks    = {},
    afterlifeTimeLeft = 30,

    
    perks = {},

    
    quickRevive   = false,
    quickReviveUses = 0,
    doubleTap     = false,
    phdFlopper    = false,
    electricCherry = false,
    whosWho       = false,

    
    lastHitTime   = 0,
    lastMeleeTime = 0,
}

player.state = {}

player.camera = { x = 0, y = 0, z = 0, rotY = 0, rotZ = 0 }

player.keysDown        = {}
player.keysJustPressed = {}

function player.clearJustPressed()
    for k in pairs(player.keysJustPressed) do
        player.keysJustPressed[k] = nil
    end
end

function player.onKeyDown(keycode)
    player.keysDown[keycode]        = true
    player.keysJustPressed[keycode] = true
end

function player.onKeyUp(keycode)
    player.keysDown[keycode] = nil
end

function player.clearAllInput()
    for k in pairs(player.keysDown)        do player.keysDown[k]        = nil end
    for k in pairs(player.keysJustPressed) do player.keysJustPressed[k] = nil end
end

local takenCharacters = {}

player.character = nil

function player.clearTakenCharacters()
    takenCharacters = {}
end

function player.assignCharacter(myPlayerID)
    local preferred = _settings and _settings.preferredCharacter
    if preferred and preferred ~= "random" then
        for _, ch in ipairs(player.CHARACTERS) do
            if ch.id == preferred then
                if not takenCharacters[ch.id] or takenCharacters[ch.id] == myPlayerID then
                    player.character         = ch
                    takenCharacters[ch.id]   = myPlayerID
                    return ch
                end
            end
        end
    end

    
    local available = {}
    for _, ch in ipairs(player.CHARACTERS) do
        if not takenCharacters[ch.id] or takenCharacters[ch.id] == myPlayerID then
            available[#available + 1] = ch
        end
    end
    if #available == 0 then available = player.CHARACTERS end

    
    if player.character then
        for _, ch in ipairs(available) do
            if ch.id == player.character.id then return player.character end
        end
    end

    local chosen               = available[math.random(1, #available)]
    player.character           = chosen
    takenCharacters[chosen.id] = myPlayerID
    return chosen
end

function player.markCharacterTaken(charId, remotePlayerID)
    takenCharacters[charId] = remotePlayerID
end

local USERNAME_FILE = "username.txt"

function player.saveUsername(username)
    local f = fs.open(USERNAME_FILE, "w")
    if f then
        f.write(username)
        f.close()
        return true
    end
    return false
end

function player.loadUsername()
    if fs.exists(USERNAME_FILE) then
        local f = fs.open(USERNAME_FILE, "r")
        if f then
            local name = f.readAll()
            f.close()
            
            name = name:match("^%s*(.-)%s*$")
            return (name ~= "") and name or nil
        end
    end
    return nil
end

function player.promptUsername()
    term.setBackgroundColor(colors.black)
    term.clear()
    local w, h = term.getSize()

    term.setCursorPos(math.max(1, math.floor(w / 2 - 10)), math.floor(h / 2 - 3))
    term.setTextColor(colors.red)
    term.write("CC: ZOMBIES  -  NOT READY TO DIE")

    term.setCursorPos(math.max(1, math.floor(w / 2 - 8)), math.floor(h / 2 - 1))
    term.setTextColor(colors.white)
    term.write("Enter your username:")

    term.setCursorPos(math.max(1, math.floor(w / 2 - 8)), math.floor(h / 2 + 1))
    term.setTextColor(colors.yellow)
    term.setBackgroundColor(colors.gray)
    term.write("                ")   
    term.setCursorPos(math.max(1, math.floor(w / 2 - 8)), math.floor(h / 2 + 1))

    local name = read()
    if name == "" then
        name = "Player"
    elseif #name > 16 then
        name = name:sub(1, 16)
    end

    player.saveUsername(name)
    player.state.username = name
    term.setBackgroundColor(colors.black)
    return name
end

function player.new()
    
    for k, v in pairs(DEFAULTS) do
        if type(v) == "table" then
            local copy = {}
            for kk, vv in pairs(v) do copy[kk] = vv end
            player.state[k] = copy
        else
            player.state[k] = v
        end
    end

    
    local saved = player.loadUsername()
    if saved then player.state.username = saved end

    
    player.camera.x = player.state.x
    player.camera.y = player.state.y + player.state.eyeHeight
    player.camera.z = player.state.z

    return player.state
end

function player.reset(myPlayerID)
    local savedUsername = player.state.username

    
    for k, v in pairs(DEFAULTS) do
        if type(v) == "table" then
            local copy = {}
            for kk, vv in pairs(v) do copy[kk] = vv end
            player.state[k] = copy
        else
            player.state[k] = v
        end
    end

    
    player.state.username = savedUsername

    
    
    if _ccz and _ccz.weapons then
        player.state.weapons[1] = _ccz.weapons.createInstance("m1911")
    end
    player.state.weapons[2] = nil

    
    player.camera.x = player.state.x
    player.camera.y = player.state.y + player.state.eyeHeight
    player.camera.z = player.state.z

    
    player.clearAllInput()

    
    if myPlayerID ~= false then   
        player.assignCharacter(myPlayerID or 1)
    end

    return player.state
end

function player.syncCamera()
    player.camera.x = player.state.x
    player.camera.y = player.state.y + player.state.eyeHeight
    player.camera.z = player.state.z
end

function player.isKeyDown(keycode)
    return player.keysDown[keycode] == true
end

function player.wasKeyJustPressed(keycode)
    return player.keysJustPressed[keycode] == true
end

return player
