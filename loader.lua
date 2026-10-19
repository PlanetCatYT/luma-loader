local LUARMOR_URL = "https://api.luarmor.net/files/v4/loaders/e63bd83e96ab9992d6b1bbd08cc93209.lua"
local LOBBY_PLACE_ID = 4111023553
local DEEPWOKEN_GAME_ID = 1359573625

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if game.GameId == DEEPWOKEN_GAME_ID and game.PlaceId ~= LOBBY_PLACE_ID then
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
    -- blocking yield) -- that was the freeze on inject, before the webhook ever fires. WaitForChild
    -- with a timeout returns the instant the child appears, so a slow/early load still succeeds; it
    -- only gives up if ClientManager never shows (game moved/renamed it), and then we KICK -- never
    -- proceed undetected, never freeze -- so the user just re-executes once they are fully in-game.
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

-- Client-readiness gate (all games). Deepwoken warms up implicitly: its AC-bypass block above spends
-- time and waits on ClientManager/PlayerScripts before any fetch. Universal/aba skip that entirely, so
-- on a too-early inject the fetch chain + script ran against a cold client/HTTP stack and hung before
-- anything logged -- which is why the webhook never fired and it only froze on universal/aba. Wait,
-- bounded, for the player + PlayerGui: instant once in-game, a safety net on an early inject (and it
-- gives the HTTP stack time to come up before the first request).
do
    local lp = LocalPlayer
    local deadline = os.clock() + 30
    while not lp and os.clock() < deadline do
        task.wait()
        lp = Players.LocalPlayer
    end
    if lp then
        pcall(function() lp:WaitForChild("PlayerGui", 30) end)
    end
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

local body, err = fetchLoader()
if not body then
    return LocalPlayer:Kick("luma: failed to fetch loader after retries (" .. tostring(err) .. ")")
end

local fn = loadstring(body)
if not fn then
    return LocalPlayer:Kick("luma: failed to compile loader")
end

fn()
