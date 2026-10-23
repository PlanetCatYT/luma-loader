local LUARMOR_URL = "https://api.luarmor.net/files/v4/loaders/e63bd83e96ab9992d6b1bbd08cc93209.lua"
local LOBBY_PLACE_ID = 4111023553
local DEEPWOKEN_GAME_ID = 1359573625

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
local isDeepwoken = game.GameId == DEEPWOKEN_GAME_ID

if isDeepwoken and game.PlaceId ~= LOBBY_PLACE_ID then
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

    dbg("deepwoken: disabling ClientManager")
    if not pcall(function()
        LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ClientActor"):WaitForChild("ClientManager").Enabled = false
    end) then
        return LocalPlayer:Kick("luma: failed disabling ClientManager")
    end
end

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
        if not isDeepwoken then
            dbg("gate: waiting Character")
            local d2 = os.clock() + 45
            while os.clock() < d2 do
                local char = lp.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then break end
                task.wait(0.1)
            end
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
task.wait(1)
local fn = loadstring(body)
if not fn then
    return LocalPlayer:Kick("luma: failed to compile loader")
end

dbg("running luarmor loader")
fn()
dbg("luarmor loader returned")
