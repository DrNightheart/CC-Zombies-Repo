

local ui = {}

local player, roundState, settings, Pine3D, getCurrentTime
local zombies, camera

function ui.init(deps)
    player = deps.player
    roundState = deps.roundState
    settings = deps.settings
    Pine3D = deps.Pine3D
    getCurrentTime = deps.getCurrentTime
    zombies = deps.zombies
    camera = deps.camera
end

function ui.drawHUD()
    local w, h = term.getSize()
    
    
    term.setCursorPos(2, h - 2)
    term.setTextColor(colors.red)
    term.setBackgroundColor(colors.black)
    term.write("HP: " .. math.floor(player.health) .. "/" .. player.maxHealth)
    
    
    term.setCursorPos(2, h - 1)
    term.setTextColor(colors.yellow)
    term.write("Points: " .. player.points)
    
    
    if player.weapons and player.weapons[player.activeWeaponSlot] then
        local weapon = player.weapons[player.activeWeaponSlot]
        term.setCursorPos(w - 15, h - 1)
        term.setTextColor(colors.white)
        term.write(weapon.ammo .. " / " .. weapon.reserve)
    end
    
    
    term.setCursorPos(math.floor(w/2 - 5), 2)
    term.setTextColor(colors.lime)
    term.write("Round " .. roundState.currentRound)
    
    
    term.setCursorPos(math.floor(w/2 - 5), 3)
    term.setTextColor(colors.red)
    term.write("Zombies: " .. #zombies)
    
    
    if settings.crosshairStyle ~= "off" then
        ui.drawCrosshair()
    end
end

function ui.drawCrosshair()
    local w, h = term.getSize()
    local cx, cy = math.floor(w/2), math.floor(h/2)
    
    term.setCursorPos(cx, cy)
    term.setTextColor(settings.crosshairColor or colors.lime)
    term.setBackgroundColor(colors.black)
    
    if settings.crosshairStyle == "plus" then
        term.write("+")
    elseif settings.crosshairStyle == "dot" then
        term.write(".")
    end
end

function ui.showMainMenu()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    local w, h = term.getSize()
    
    
    term.setCursorPos(math.floor(w/2 - 12), math.floor(h/2 - 5))
    term.setTextColor(colors.red)
    term.write("CC: ZOMBIES - NOT READY TO DIE")
    
    
    term.setCursorPos(math.floor(w/2 - 5), math.floor(h/2))
    term.setTextColor(colors.white)
    term.write("1. Play Solo")
    
    term.setCursorPos(math.floor(w/2 - 5), math.floor(h/2 + 1))
    term.write("2. Multiplayer")
    
    term.setCursorPos(math.floor(w/2 - 5), math.floor(h/2 + 2))
    term.write("3. Settings")
    
    term.setCursorPos(math.floor(w/2 - 5), math.floor(h/2 + 3))
    term.write("4. Exit")
    
    
    while true do
        local event, key = os.pullEvent("key")
        if key == keys.one then
            return "solo"
        elseif key == keys.two then
            return "multiplayer"
        elseif key == keys.three then
            return "settings"
        elseif key == keys.four then
            return "exit"
        end
    end
end

function ui.showPauseMenu()
    
    return "resume"
end

function ui.showGameOver()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    local w, h = term.getSize()
    
    term.setCursorPos(math.floor(w/2 - 5), math.floor(h/2 - 2))
    term.setTextColor(colors.red)
    term.write("GAME OVER")
    
    term.setCursorPos(math.floor(w/2 - 10), math.floor(h/2))
    term.setTextColor(colors.white)
    term.write("Round Reached: " .. roundState.currentRound)
    
    term.setCursorPos(math.floor(w/2 - 8), math.floor(h/2 + 1))
    term.write("Final Score: " .. player.points)
    
    term.setCursorPos(math.floor(w/2 - 10), math.floor(h/2 + 3))
    term.setTextColor(colors.yellow)
    term.write("Press any key to continue")
    
    os.pullEvent("key")
    return "main_menu"
end

function ui.render3DFrame(frame, worldObjects, zombieObjects)
    
    term.setBackgroundColor(colors.black)
    term.clear()
    
    frame:setCamera(camera.x, camera.y, camera.z, player.rotY, player.rotZ)
    
    
    for _, obj in ipairs(worldObjects or {}) do
        frame:drawObject(obj)
    end
    
    
    for _, obj in ipairs(zombieObjects or {}) do
        frame:drawObject(obj)
    end
    
    frame:drawBuffer()
end

local audioQueue = {}

function ui.playSound(soundId, volume)
    
    
    table.insert(audioQueue, {id = soundId, volume = volume or 1.0})
end

function ui.playMusic(musicId)
    
end

function ui.stopMusic()
    
end

function ui.updateAudio(dt)
    
end

return ui
