--[[
Banana Cat Hub - Delta compatibility and diagnostics loader
Version: 1.0 (2026-10-10)

This loader downloads the original script supplied by the user, applies a
limited set of compatibility fixes, saves the complete patched source when
Delta supports file writing, and then launches it.

It preserves the ORIGINAL Banana Cat Hub menu, logic, and features.
It is NOT a replacement menu or a verified bypass for game-side restrictions.
This code has NOT been tested in a live Blox Fruits/Delta session.

Never run untrusted scripts without inspecting the original source.
]]

local SOURCE_URL = "https://raw.githubusercontent.com/ptlhub2026/ptlhub/refs/heads/main/3nn_main.lua.txt"
local SAVE_FOLDER = "Banana Cat Hub"
local SAVE_FILE = SAVE_FOLDER .. "/BananaCatHub_Delta_Fixed_Full.lua"
local LOG_FILE = SAVE_FOLDER .. "/Delta_Fix_Errors.txt"
local PREFIX = "[BananaCat Delta Fix] "

local function info(message)
    print(PREFIX .. tostring(message))
end

local function problem(message)
    warn(PREFIX .. tostring(message))
end

if type(getgenv) ~= "function" then
    problem("Delta/getgenv() is unavailable; cannot start.")
    return
end

local env = getgenv()
if env.__BC_DELTA_PATCH_RUNNING then
    problem("The Delta patch loader is already running. Do not execute it twice.")
    return
end

-- The original UI and workers cannot be safely recreated in the same session.
if env.__BF_LOADED or env.LoadScript then
    problem("A Banana Cat Hub session is already loaded. Leave and rejoin Blox Fruits, then use ONLY this file once.")
    return
end

env.__BC_DELTA_PATCH_RUNNING = true
local function stop(message)
    env.__BC_DELTA_PATCH_RUNNING = false
    problem(message)
end

if type(loadstring) ~= "function" then
    stop("Delta does not expose loadstring().")
    return
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local players = game:GetService("Players")
local deadline = os.clock() + 25
while not players.LocalPlayer and os.clock() < deadline do
    task.wait(0.1)
end
if not players.LocalPlayer then
    stop("LocalPlayer is not ready.")
    return
end

-- Download as TEXT ONLY. We patch it before compilation/execution.
local downloaded, original = pcall(function()
    return game:HttpGet(SOURCE_URL, true)
end)
if not downloaded or type(original) ~= "string" then
    stop("Failed to download original source: " .. tostring(original))
    return
end
if #original < 100000
    or not original:find("function toTarget(", 1, true)
    or not original:find("function AttackAOE(", 1, true)
    or not original:find("Settings = ReadSetting()", 1, true)
then
    stop("The GitHub source no longer matches the inspected Banana Cat Hub file. Stopping rather than patching unrelated code.")
    return
end

local source = original
local counts = {}
local function escapePattern(value)
    return (value:gsub("([^%w])", "%%%1"))
end
local function replaceLiteral(name, oldText, newText)
    local amount
    source, amount = source:gsub(escapePattern(oldText), function()
        return newText
    end)
    counts[name] = amount
    info(name .. " -> " .. tostring(amount) .. " replacement(s)")
    return amount
end

-- 1. A plain-text source should not call an undefined code-protector macro.
replaceLiteral("Protection directive", "LPH_ATTRIBUTES(VM(NONE))", "do end -- BC_DELTA: ignored source protection directive")

-- 2. Fix 'S' (Players service) when calculating hit targets. This was an
--    undeclared alias in the inspected source section.
replaceLiteral("Player hit target lookup", "S:GetPlayerFromCharacter(", 'game:GetService("Players"):GetPlayerFromCharacter(')

-- 3. Roblox service/member names are case-sensitive in Lua.
replaceLiteral("LocalPlayer capitalization", "game.Players.localPlayer", "game.Players.LocalPlayer")

-- 4. Some executors don't define a global 'http'; avoid indexing nil.
replaceLiteral("HTTP request nil guard", "or http.request", "or (http and http.request)")

-- 5. Set sensible initial farm controls without turning automation on.
replaceLiteral(
    "Missing farm defaults",
    "Settings = ReadSetting()",
    [[Settings = ReadSetting()
if Settings["Select Method Farm"] == nil then
    SaveSettings("Select Method Farm", "Level Farm")
end
if Settings["Select Weapon"] == nil then
    SaveSettings("Select Weapon", "Melee")
end]]
)

-- 6. Many loops hide errors inside pcall. The scoped wrapper preserves the
--    original return values while reporting the FIRST errors in the console.
--    Limit the rate and the total count so RenderStepped does not spam Delta.
local instrument = [==[
-- BEGIN Banana Cat Hub Delta diagnostics
local Workspace = game:GetService("Workspace")
local __BC_NATIVE_PCALL = pcall
local __BC_SEEN_ERRORS = {}
local __BC_ERROR_COUNT = 0
local function pcall(...)
    local results = table.pack(__BC_NATIVE_PCALL(...))
    if results[1] == false then
        local message = tostring(results[2])
        local now = os.clock()
        local previous = __BC_SEEN_ERRORS[message]
        if __BC_ERROR_COUNT < 30 and (not previous or now - previous > 20) then
            __BC_SEEN_ERRORS[message] = now
            __BC_ERROR_COUNT = __BC_ERROR_COUNT + 1
            warn("[BananaCat Delta Fix][caught error] " .. message)
            local shared = getgenv()
            shared.__BC_DELTA_ERRORS = shared.__BC_DELTA_ERRORS or {}
            table.insert(shared.__BC_DELTA_ERRORS, message)
            if type(appendfile) == "function" then
                __BC_NATIVE_PCALL(function()
                    appendfile("Banana Cat Hub/Delta_Fix_Errors.txt", message .. "\n")
                end)
            end
        end
    end
    return table.unpack(results, 1, results.n)
end
-- END Banana Cat Hub Delta diagnostics
]==]
source = instrument .. "\n" .. source

-- Structural verification: at least these two critical areas must still be present.
if (counts["Protection directive"] or 0) == 0
    or (counts["Player hit target lookup"] or 0) == 0
    or (counts["Missing farm defaults"] or 0) ~= 1
then
    stop("Critical patch markers not found; refusing to execute a mismatched version.")
    return
end

-- Save the COMPLETE modified (~19k lines) code to Delta's local script folder.
local folderAvailable = false
if type(isfolder) == "function" and type(makefolder) == "function" then
    local ok, message = pcall(function()
        if not isfolder(SAVE_FOLDER) then
            makefolder(SAVE_FOLDER)
        end
    end)
    folderAvailable = ok
    if not ok then
        problem("Couldn't create output directory: " .. tostring(message))
    end
end
if folderAvailable and type(writefile) == "function" then
    local saved, why = pcall(function()
        writefile(SAVE_FILE, source)
        writefile(LOG_FILE, "Banana Cat Hub Delta Fix log (2026-10-10)\n")
    end)
    if saved then
        info("The full fixed Lua source was saved to: " .. SAVE_FILE)
    else
        problem("The patched script is in memory; could not write it: " .. tostring(why))
    end
else
    problem("File APIs are not available. Running patched source from memory.")
end

if type(debug) ~= "table"
    or type(debug.getupvalues) ~= "function"
    or type(debug.getupvalue) ~= "function"
then
    problem("Some debug.getupvalue(s) APIs are missing in this Delta build. Some features may still fail.")
end

if not (workspace:FindFirstChild("Enemies") and game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")) then
    problem("Enemies/Remotes was not found at startup; the game may still be loading or may have changed.")
end

local compiler, compileError = loadstring(source)
if not compiler then
    stop("Luau compile failed: " .. tostring(compileError))
    return
end

info("Launching original Banana Cat Hub with verified compatibility patches.")
local success, executionError = pcall(compiler)
env.__BC_DELTA_PATCH_RUNNING = false
if not success then
    problem("Main script stopped: " .. tostring(executionError))
    problem("If the menu already appeared, rejoin before another attempt.")
    return
end

info("Loader returned. Open Delta Console and check for '[caught error]' if a feature fails.")
info("Full patched script: " .. SAVE_FILE)
