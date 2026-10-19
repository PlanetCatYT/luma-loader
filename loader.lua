local LUARMOR_URL = "https://api.luarmor.net/files/v4/loaders/e63bd83e96ab9992d6b1bbd08cc93209.lua"
local LOBBY_PLACE_ID = 4111023553
local DEEPWOKEN_GAME_ID = 1359573625

-- Opt-in diagnostics: run `getgenv().LumaDebug = true` before the loadstring to get a [luma] marker
-- printed at every stage. On a freeze, the LAST marker printed is the stage that hung. Silent otherwise.
local DEBUG = (getgenv and getgenv().LumaDebug) and true or false
local function dbg(stage)
    if DEBUG then warn("[luma] " .. stage) end
end
dbg("start")

if not game:IsLoaded() then
    dbg("waiting game.Loaded")
    game.Loaded:Wait()
end
dbg("game loaded")

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if game.GameId == DEEPWOKEN_GAME_ID and game.PlaceId ~= LOBBY_PLACE_ID then
    dbg("deepwoken: scriptcontext bypass")
    local e = game:GetService("ScriptContext").Error
    if not (getconnections and getconstants and setconstant and pcall(function()
        local t, d = false, os.clock() + 6.7
        repeat
            for _, c in ipairs(getconnections(e)) do
                local f = c.Function
                if f then
                    pcall(function()
                        for i, k in pairs(getconstants(f)) do
                            if k == "IsStudio" then
                                setconstant(f, i, "IsClient")
                                t = true
                            end
                        end
                    end)
                end
            end
            if t then break end
            task.wait(0.67)
        until os.clock() > d
    end)) then
        return LocalPlayer:Kick("luma: failed bypass in ClientManager")
    end

    -- Bounded waits, NOT a timeoutless WaitForChild: on an early inject ClientActor/ClientManager
    -- do not exist yet, and the no-timeout form there hangs this thread forever (pcall cannot catch a
    -- blocking yield). WaitForChild with a timeout returns the instant the child appears, so a slow/early
    -- load still succeeds; it only gives up if ClientManager never shows, and then we KICK (never freeze).
    dbg("deepwoken: disabling ClientManager")
    local function waitChild(parent, name, timeout)
        local ok, child = pcall(function() return parent:WaitForChild(name, timeout) end)
        return ok and child or nil
    end
    local ps = waitChild(LocalPlayer, "PlayerScripts", 30)
    local actor = ps and waitChild(ps, "ClientActor", 30)
    local clientManager = actor and waitChild(actor, "ClientManager", 30)
    if not clientManager then
        return LocalPlayer:Kick("luma: client not ready (injected too early or the game updated) -- rejoin and re-execute once you are fully in-game")
    end
    pcall(function() clientManager.Enabled = false end)
end

-- Client-readiness gate (all games). The real fix for "freezes instantly on an early inject, nothing
-- shows, webhook never fires": a main-thread game:HttpGet / executor request made before the client's
-- HTTP stack is up BLOCKS with no yield, which hard-freezes Roblox (Task Manager territory). Deepwoken
-- never hit it because its AC-bypass block above already burns several seconds before any fetch;
-- universal/aba skipped straight to the fetch. Gate until the player is genuinely in-game -- LocalPlayer,
-- PlayerGui, then a spawned Character with a HumanoidRootPart. A live Character means the client/server
-- connection (and therefore HTTP) is up. All bounded, proceeding on timeout, so the gate never hangs.
do
    dbg("gate: waiting LocalPlayer")
    local lp = LocalPlayer
    local d1 = os.clock() + 30
    while not lp and os.clock() < d1 do
        task.wait()
        lp = Players.LocalPlayer
    end
    if lp then
        dbg("gate: waiting PlayerGui")
        pcall(function() lp:WaitForChild("PlayerGui", 30) end)
        dbg("gate: waiting Character")
        local d2 = os.clock() + 45
        while os.clock() < d2 do
            local char = lp.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then break end
            task.wait(0.1)
        end
    end
    dbg("gate: done")
end

local function fetchLoader()
    local ATTEMPTS = 5
    local lastErr
    for i = 1, ATTEMPTS do
        local ok, body = pcall(game.HttpGet, game, LUARMOR_URL)
        if ok and type(body) == "string" and #body > 0 then
            return body
        end
        lastErr = body
        if i < ATTEMPTS then
            task.wait(i * 0.5)
        end
    end
    return nil, lastErr
end

dbg("fetching luarmor loader")
local body, err = fetchLoader()
if not body then
    return LocalPlayer:Kick("luma: failed to fetch loader after retries (" .. tostring(err) .. ")")
end
dbg("luarmor loader fetched (" .. tostring(#body) .. " bytes)")

local fn = loadstring(body)
if not fn then
    return LocalPlayer:Kick("luma: failed to compile loader")
end

dbg("running luarmor loader")
fn()
dbg("luarmor loader returned")
