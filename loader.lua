local LUARMOR_URL = "https://api.luarmor.net/files/v4/loaders/e63bd83e96ab9992d6b1bbd08cc93209.lua"
local LOBBY_PLACE_ID = 4111023553
local CHIME_LOBBY_PLACE_ID = 12559711136
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
local inGameplay = isDeepwoken and game.PlaceId ~= LOBBY_PLACE_ID and game.PlaceId ~= CHIME_LOBBY_PLACE_ID

local function resolveClientManager(timeout)
    local cm
    pcall(function()
        local ps = LocalPlayer:WaitForChild("PlayerScripts", timeout)
        local actor = ps and ps:WaitForChild("ClientActor", timeout)
        cm = actor and actor:WaitForChild("ClientManager", timeout)
    end)
    return cm
end

local function confirmDisabled(cm)
    if not cm then
        return false
    end
    pcall(function()
        cm.Enabled = false
    end)
    local ok, enabled = pcall(function()
        return cm.Enabled
    end)
    return ok and enabled == false
end

local clientManagerWatch
local function lockClientManagerDisabled(timeout)
    local deadline = os.clock() + (timeout or 10)
    repeat
        local cm = resolveClientManager(5)
        if confirmDisabled(cm) then
            if clientManagerWatch then
                pcall(function() clientManagerWatch:Disconnect() end)
                clientManagerWatch = nil
            end
            pcall(function()
                clientManagerWatch = cm:GetPropertyChangedSignal("Enabled"):Connect(function()
                    if cm.Enabled then
                        cm.Enabled = false
                    end
                end)
            end)
            return true
        end
        task.wait(0.1)
    until os.clock() >= deadline
    return false
end

if inGameplay then
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
    if not lockClientManagerDisabled(15) then
        return LocalPlayer:Kick("luma: failed disabling ClientManager")
    end
    dbg("deepwoken: ClientManager disabled + watched")
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

if inGameplay then
    dbg("final gate: re-confirming ClientManager disabled")
    if not lockClientManagerDisabled(10) then
        return LocalPlayer:Kick("luma: ClientManager not disabled at load time -- aborting")
    end
    dbg("final gate: ClientManager confirmed disabled")
end

dbg("running luarmor loader")
fn()
dbg("luarmor loader returned")
