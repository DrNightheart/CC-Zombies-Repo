local TOGGLE_KEY = keys.backslash

local function getPlayer() return ccz.game.getPlayer() end

local PREVIEW_W, PREVIEW_H = 26, 8

local function downscaleToNFP(rows, w, h)

    local out = {}
    for dy = 0, PREVIEW_H - 1 do
        local sy = math.min(h, math.floor(dy * h / PREVIEW_H) + 1)
        local srcRow = rows[sy] or ""
        local line = {}
        for dx = 0, PREVIEW_W - 1 do
            local sx = math.min(w, math.floor(dx * w / PREVIEW_W) + 1)
            line[#line + 1] = srcRow:sub(sx, sx)
        end
        out[#out + 1] = table.concat(line)
    end
    return table.concat(out, "\n")
end

local function requestScreenshot()
    local w, h = term.getSize()

    print("[devtools] Waiting for next frame to capture...")

    local handler
    handler = function()
        ccz.off("frame.rendered", handler)

        local renderWin = ccz.getRenderWindow and ccz.getRenderWindow()
        if not renderWin then
            print("[devtools] Couldn't find Pine3D's render window.")
            if ccz.debugFrameKeys then
                print("[devtools] frame's top-level keys: " .. table.concat(ccz.debugFrameKeys(), ", "))
                print("[devtools] Tell Nightheart these keys so ccz.getRenderWindow() in")
                print("[devtools] game.lua can be pointed at the right field.")
            end
            return
        end

        local rows = {}
        for y = 1, h do
            local _, _, bg = renderWin.getLine(y)
            rows[y] = bg
        end

        local nfp = downscaleToNFP(rows, w, h)
        local f = fs.open("/screenshot.nfp", "w")
        if f then
            f.write(nfp)
            f.close()
            print(("[devtools] Saved screenshot.nfp (%dx%d)"):format(PREVIEW_W, PREVIEW_H))
        else
            print("[devtools] Failed to open /screenshot.nfp for writing")
        end
    end

    ccz.on("frame.rendered", handler)
end

local commands = {}

commands.help = {
    usage = "help",
    desc  = "List all commands",
    run   = function()
        local names = {}
        for name in pairs(commands) do names[#names+1] = name end
        table.sort(names)
        print("Dev Tools commands:")
        for _, name in ipairs(names) do
            print(("  %-10s %s - %s"):format(name, commands[name].usage, commands[name].desc))
        end
    end,
}

commands.give = {
    usage = "give <points>",
    desc  = "Add points to the player",
    run   = function(arg)
        local n = tonumber(arg)
        if not n then print("Usage: give <points>"); return end
        local p = getPlayer()
        p.points = p.points + n
        print(("Gave %d points (now %d)"):format(n, p.points))
    end,
}

commands.heal = {
    usage = "heal",
    desc  = "Fully heal the player",
    run   = function()
        local p = getPlayer()
        p.health = p.maxHealth
        p.isDowned = false
        print("Healed to " .. p.maxHealth)
    end,
}

commands.god = {
    usage = "god",
    desc  = "Toggle god mode (blocks melee + splash self-damage)",
    run   = function()
        local p = getPlayer()
        p._godMode = not p._godMode
        print("God mode: " .. (p._godMode and "ON" or "OFF"))
    end,
}

commands.tp = {
    usage = "tp <x> <y> <z>",
    desc  = "Teleport the player",
    run   = function(arg)
        local x, y, z = arg:match("^(%S+)%s+(%S+)%s+(%S+)$")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        if not (x and y and z) then print("Usage: tp <x> <y> <z>"); return end
        local p = getPlayer()
        p.x, p.y, p.z = x, y, z
        print(("Teleported to %.1f, %.1f, %.1f"):format(x, y, z))
    end,
}

commands.round = {
    usage = "round <n>",
    desc  = "Jump to a specific round",
    run   = function(arg)
        local n = tonumber(arg)
        if not n then print("Usage: round <n>"); return end
        local set = ccz.modules.zombie.setRound(n)
        print("Now on round " .. set)
    end,
}

commands.nuke = {
    usage = "nuke",
    desc  = "Kill every zombie on the map",
    run   = function()
        ccz.modules.zombie.nukeAll()
        print("Nuked.")
    end,
}

commands.spawn = {
    usage = "spawn [type]",
    desc  = "Spawn a zombie at a map spawn point (default: normal)",
    run   = function(arg)
        local zType = (arg ~= "" and arg) or nil
        local z = ccz.modules.zombie.spawnZombie(zType)
        if z then
            print(("Spawned %s (id %s)"):format(z.type or "normal", tostring(z.id)))
        else
            print("Spawn failed (no spawn points on this map?)")
        end
    end,
}

commands.perks = {
    usage = "perks",
    desc  = "List all perk ids",
    run   = function()
        for _, p in ipairs(ccz.modules.entity.ALL_PERKS) do print("  " .. p) end
    end,
}

commands.perk = {
    usage = "perk <perk_id>",
    desc  = "Grant a specific perk for free (see 'perks' for ids)",
    run   = function(arg)
        if arg == "" then print("Usage: perk <perk_id> (see 'perks')"); return end
        local ok, err = ccz.modules.entity.grantPerk(arg)
        print(ok and ("Granted " .. arg) or ("Failed: " .. tostring(err)))
    end,
}

commands.powerup = {
    usage = "powerup <id> [distance]",
    desc  = "Spawn a power-up at your feet, or [distance] blocks in front of you",
    run   = function(arg)
        if arg == "" then
            print("Usage: powerup <id> [distance], one of:")
            print("  powerup_nuke, powerup_double_points, powerup_insta_kill,")
            print("  powerup_max_ammo, powerup_fire_sale, powerup_free_perk")
            print("[distance] is optional, in blocks, straight ahead of your")
            print("current facing direction (default: 0, spawns at your feet).")
            return
        end

        local id, distArg = arg:match("^(%S+)%s*(%S*)$")
        local dist = 0
        if distArg ~= "" then
            dist = tonumber(distArg)
            if not dist then
                print("Usage: powerup <id> [distance] - distance must be a number")
                return
            end
        end

        local p = getPlayer()
        local x, y, z = p.x, p.y, p.z
        if dist ~= 0 then
            local yaw = math.rad(p.rotY or 0)
            x = x + math.cos(yaw) * dist
            z = z + math.sin(yaw) * dist
        end

        local ok = ccz.modules.powerups.spawnAt(id, x, y, z)
        if ok then
            if dist ~= 0 then
                print(("Spawned %s (%.1f blocks ahead)"):format(id, dist))
            else
                print("Spawned " .. id)
            end
        else
            print("Unknown power-up: " .. id)
        end
    end,
}

commands.flash = {
    usage = "flash <r> <g> <b> [dur]",
    desc  = "Trigger a screen flash (0-1 each channel)",
    run   = function(arg)
        local r, g, b, d = arg:match("^(%S+)%s+(%S+)%s+(%S+)%s*(%S*)$")
        r, g, b = tonumber(r), tonumber(g), tonumber(b)
        d = tonumber(d) or 0.5
        if not (r and g and b) then print("Usage: flash <r> <g> <b> [dur]"); return end
        ccz.fx.flash(r, g, b, d)
        print("Flashed.")
    end,
}

commands.shake = {
    usage = "shake [dur] [mag]",
    desc  = "Trigger a screen shake",
    run   = function(arg)
        local d, m = arg:match("^(%S*)%s*(%S*)$")
        ccz.fx.shake(tonumber(d) or 0.4, tonumber(m) or 1)
        print("Shook.")
    end,
}

commands.state = {
    usage = "state",
    desc  = "Print current player/round state",
    run   = function()
        local p = getPlayer()
        local rs = ccz.game.getRoundState()
        print(("HP %d/%d  Points %d  Pos %.1f,%.1f,%.1f"):format(
            p.health, p.maxHealth, p.points, p.x, p.y, p.z))
        print(("Round %s  Killed %s/%s"):format(
            tostring(rs.currentRound), tostring(rs.zombiesKilled), tostring(rs.zombiesTotal)))
    end,
}

commands.characters = {
    usage = "characters",
    desc  = "List all characters",
    run   = function()
        for _, id in ipairs(ccz.modules.characters.getAll()) do
            local c = ccz.modules.characters.get(id)
            print(("  %-12s %s"):format(id, c.name))
        end
    end,
}

commands.character = {
    usage = "character <id>",
    desc  = "Switch active character (see 'characters' for ids)",
    run   = function(arg)
        if arg == "" then print("Usage: character <id> (see 'characters')"); return end
        local ok, err = ccz.modules.characters.setActive(arg)
        print(ok and ("Switched to " .. arg) or ("Failed: " .. tostring(err)))
    end,
}

commands.screenshot = {
    usage = "screenshot",
    desc  = "Capture a UI-less map preview to /screenshot.nfp",
    run   = function()
        requestScreenshot()
        return true
    end,
}

commands.exit = {
    usage = "exit",
    desc  = "Close the console",
    run   = function() end,
}

local function runCommand(line)
    line = line:match("^%s*(.-)%s*$")
    if line == "" then return end
    local verb, rest = line:match("^(%S+)%s*(.-)$")
    verb = verb:lower()
    local cmd = commands[verb]
    if not cmd then
        print("Unknown command: " .. verb .. " (try 'help')")
        return
    end
    local ok, result = pcall(cmd.run, rest or "")
    if not ok then
        print("[DevTools] error: " .. tostring(result))
        return
    end

    return result == true
end

local consoleOpen = false

local function openConsole()
    if consoleOpen then return end
    consoleOpen = true

    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.clearLine()
    term.setTextColor(colors.yellow)

    while true do
        term.setCursorPos(1, h)
        term.clearLine()
        term.write("[devtools] ")
        local ok, line = pcall(read)
        if not ok or not line then break end
        if line:lower() == "exit" or line == "" then break end
        if runCommand(line) then break end
    end

    term.setTextColor(colors.white)
    consoleOpen = false
end

ccz.on("input.key", function(data)
    if data.code == TOGGLE_KEY and not consoleOpen then
        openConsole()
    end
end)

ccz.on("round.start", function(data)
    if data.round == 1 and ccz.game and ccz.game.announce then
        ccz.game.announce("DEV TOOLS ENABLED", 2)
    end
end)

print("[CCMod] Dev Tools loaded. Press \\ (backslash) in-game to open the console.")
