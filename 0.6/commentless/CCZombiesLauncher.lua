local LOG_PATH = "CCZombies/crash.log"

local function crashHandler(err)
    local tb = debug and debug.traceback and debug.traceback(tostring(err), 2)
               or tostring(err)
    return tb
end

local function writeLog(report)
    pcall(function()
        local f = fs.open(LOG_PATH, "w")
        if not f then return end
        f.writeLine("=== CCZombies Crash Report ===")
        f.writeLine("Version: " .. (_G._CCZ_VERSION or "unknown"))
        f.writeLine(os.date and os.date("Date: %Y-%m-%d %H:%M:%S") or "Date: unknown")
        f.writeLine("")
        f.writeLine(report)
        f.close()
    end)
end

local function showCrashScreen(report)
    pcall(function()
        if term.native then term.redirect(term.native()) end
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1, 1)
    end)

    local w = term.getSize()

    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    term.clearLine()
    local title = "  !! CCZombies Crashed !!"
    term.write(title)
    term.setCursorPos(1, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.orange)
    term.clearLine()
    term.write("  Crash log saved to: " .. LOG_PATH)

    term.setTextColor(colors.white)
    term.setCursorPos(1, 4)

    local lines = {}
    for line in (report .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("^\t", "  ")
        while #line > w do
            lines[#lines + 1] = line:sub(1, w)
            line = "  " .. line:sub(w + 1)
        end
        lines[#lines + 1] = line
    end

    local _, cy = term.getCursorPos()
    local _, h  = term.getSize()
    local maxLines = h - cy - 2

    local inStack = false
    for i = 1, math.min(#lines, maxLines) do
        local ln = lines[i]
        if ln:find("stack traceback") then
            inStack = true
            term.setTextColor(colors.orange)
        elseif inStack then
            if ln:find("CCZombies/") or ln:find("CCZombies\\") then
                term.setTextColor(colors.yellow)
            else
                term.setTextColor(colors.lightGray)
            end
        else
            term.setTextColor(colors.white)
        end
        term.clearLine()
        term.write(ln)
        term.setCursorPos(1, select(2, term.getCursorPos()) + 1)
    end

    if #lines > maxLines then
        term.setTextColor(colors.lightGray)
        term.clearLine()
        term.write("  ... (" .. (#lines - maxLines) .. " more lines in " .. LOG_PATH .. ")")
    end

    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("  Press any key to exit")
    term.setBackgroundColor(colors.black)

    os.pullEvent("key")
end

local ok, report = xpcall(function()
    local g = require("CCZombies.game")
    _G._CCZ_VERSION = g.version or "unknown"
    g.run()
end, crashHandler)

if not ok then
    writeLog(report)
    showCrashScreen(report)
end
