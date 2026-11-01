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

-- Keep ClientActor.ClientManager disabled through the WHOLE load, not once. A single Enabled=false that
-- reads back false isn't a guarantee: Deepwoken flips it back on, and a respawn / Actor rebuild around
-- spawn -- exactly when we inject -- hands us a FRESH ClientManager that's running again. The old watch
-- only tracked the one instance it first saw, so a rebuilt ClientManager ran enabled and the script
-- loaded with the anticheat live. So pin the current one, re-disable it the instant its Enabled flips,
-- re-pin any replacement ClientManager, re-bind a rebuilt ClientActor, and keep a slow poll backstop.
-- Mirrors the core's Hooking.watchClientManager so the loader and core hold the exact same guarantee.
local function pinClientManager(cm)
    if not cm then
        return
    end
    pcall(function()
        if cm.Enabled then
            cm.Enabled = false
        end
    end)
    pcall(function()
        cm:GetPropertyChangedSignal("Enabled"):Connect(function()
            if cm.Enabled then
                pcall(function() cm.Enabled = false end)
            end
        end)
    end)
end

local clientManagerWatchStarted = false
local function startClientManagerWatch(playerScripts)
    if clientManagerWatchStarted then
        return
    end
    clientManagerWatchStarted = true

    local function bindActor(clientActor)
        if not clientActor then
            return
        end
        pinClientManager(clientActor:FindFirstChild("ClientManager"))
        pcall(function()
            clientActor.ChildAdded:Connect(function(child)
                if child.Name == "ClientManager" then
                    pinClientManager(child)
                end
            end)
        end)
    end

    bindActor(playerScripts:FindFirstChild("ClientActor"))
    pcall(function()
        playerScripts.ChildAdded:Connect(function(child)
            if child.Name == "ClientActor" then
                bindActor(child)
            end
        end)
    end)

    -- Slow poll backstop in case a property signal is ever missed or a rebuild raced the connections.
    task.spawn(function()
        while true do
            task.wait(2)
            pcall(function()
                local clientActor = playerScripts:FindFirstChild("ClientActor")
                local cm = clientActor and clientActor:FindFirstChild("ClientManager")
                if cm and cm.Enabled then
                    cm.Enabled = false
                end
            end)
        end
    end)
end

-- Wait (bounded) for the first ClientManager, disable it, and start the persistent watch that survives
-- rebuilds. Returns whether we actually disabled one -- the loader kicks if we never do, so it never
-- proceeds to load with the anticheat still live.
local function lockClientManagerDisabled(timeout)
    local deadline = os.clock() + (timeout or 10)
    local playerScripts
    repeat
        playerScripts = playerScripts or LocalPlayer:FindFirstChild("PlayerScripts")
        local clientActor = playerScripts and playerScripts:FindFirstChild("ClientActor")
        local cm = clientActor and clientActor:FindFirstChild("ClientManager")
        if cm then
            pinClientManager(cm)
            startClientManagerWatch(playerScripts)
            return true
        end
        task.wait(0.1)
    until os.clock() >= deadline
    return false
end

local function pressA()
    pcall(function()
        local vim = Instance.new("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.A, false, game)
        vim:SendKeyEvent(false, Enum.KeyCode.A, false, game)
    end)
end

local function spamLoadingScreen(timeout)
    local lp = LocalPlayer or Players.LocalPlayer
    if not lp then
        return
    end
    -- Wait (up to 10s) for the loading screen to appear OR the character to already be in. Poll, not
    -- WaitForChild, so a character that loads in mid-wait bails immediately instead of stalling.
    local loadingGui
    local findDeadline = os.clock() + 10
    repeat
        if lp.Character then
            return
        end
        local pg = lp:FindFirstChildOfClass("PlayerGui")
        loadingGui = pg and pg:FindFirstChild("LoadingGui")
        if loadingGui then
            break
        end
        task.wait()
    until os.clock() >= findDeadline
    if not loadingGui then
        return
    end
    local deadline = os.clock() + (timeout or 30)
    repeat
        pressA()
        task.wait(0.2)
    until not loadingGui.Parent or lp.Character or os.clock() >= deadline
end

if inGameplay then
    -- Kick the A-spam off in the background so it clicks through the loading screen in parallel with the
    -- ClientManager bypass / disable below and keeps going while the gate waits and the luarmor body fetches.
    dbg("deepwoken: starting loading-screen A-spam")
    task.spawn(function()
        spamLoadingScreen(30)
    end)

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
    if not lockClientManagerDisabled(30) then
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

-- The luarmor VM intermittently throws "attempt to perform arithmetic on nil and number" partway
-- through loading -- a transient VM glitch, not a real fault and not a compile error. When that
-- specific error shows up, re-fetch and run the whole thing again until it loads clean. Any OTHER
-- failure (fetch, compile, gate, or a different runtime error) is genuine, so it still kicks as
-- before instead of looping forever. Backoff grows then caps at 3s.
local function isArithmeticGlitch(e)
    return type(e) == "string" and e:lower():find("arithmetic") ~= nil
end

local attempt = 0
while true do
    attempt = attempt + 1
    dbg("load attempt " .. attempt)

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
    local ok, runErr = pcall(fn)
    if ok then
        dbg("luarmor loader returned")
        break
    end

    if not isArithmeticGlitch(runErr) then
        return LocalPlayer:Kick("luma: loader error -- " .. tostring(runErr))
    end

    warn("[luma-loader] luarmor VM arithmetic glitch on attempt " .. attempt .. " -- reloading")
    task.wait(math.min(attempt * 0.5, 3))
end
