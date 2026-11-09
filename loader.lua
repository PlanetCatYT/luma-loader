xpcall(function()
    local LUARMOR_URL = "https://api.luarmor.net/files/v4/loaders/e63bd83e96ab9992d6b1bbd08cc93209.lua"
    local LOBBY_PLACE_ID = 4111023553
    local CHIME_LOBBY_PLACE_ID = 12559711136
    local DEEPWOKEN_GAME_ID = 1359573625

    local DEBUG = (getgenv and getgenv().LumaDebug) and true or false
    local function dbg(stage)
        if DEBUG then warn("[luma] " .. stage) end
    end
    dbg("start")
    local isLoadedOk, isLoaded = pcall(function() return game:IsLoaded() end)
    if not isLoadedOk then
        dbg("IsLoaded blocked (" .. tostring(isLoaded) .. "); skipping explicit gate")
    elseif not isLoaded then
        dbg("waiting game.Loaded")
        pcall(function() game.Loaded:Wait() end)
    end
    dbg("game loaded")

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local isDeepwoken = game.GameId == DEEPWOKEN_GAME_ID
    local inGameplay = isDeepwoken and game.PlaceId ~= LOBBY_PLACE_ID and game.PlaceId ~= CHIME_LOBBY_PLACE_ID

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

    local fetchNonce = 0
    local function fetchLoader()
        local ATTEMPTS = 5
        local lastErr
        for i = 1, ATTEMPTS do
            fetchNonce = fetchNonce + 1
            local url = LUARMOR_URL
                .. "?_=" .. ("%d-%d-%d"):format(os.time(), fetchNonce, math.random(1, 1000000000))
            local ok, body = pcall(game.HttpGet, game, url)
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

    local function attemptLoad()
        local body, err = fetchLoader()
        if not body then
            return false, "failed to fetch loader (" .. tostring(err) .. ")"
        end
        dbg("luarmor loader fetched (" .. tostring(#body) .. " bytes)")
        task.wait(1)

        local fn = loadstring(body)
        if not fn then
            return false, "failed to compile loader"
        end

        if inGameplay then
            dbg("final gate: re-confirming ClientManager disabled")
            if not lockClientManagerDisabled(10) then
                return false, "ClientManager not disabled at load time"
            end
            dbg("final gate: ClientManager confirmed disabled")
        end

        dbg("running luarmor loader")
        local ok, runErr = pcall(fn)
        if not ok then
            return false, "loader error -- " .. tostring(runErr)
        end

        dbg("luarmor loader returned")
        return true
    end

    local attempt = 0
    while true do
        attempt = attempt + 1
        dbg("load attempt " .. attempt)

        local ok, reason = attemptLoad()
        if ok then
            break
        end

        warn("[luma-loader] " .. tostring(reason) .. " on attempt " .. attempt .. " -- retrying")
        task.wait(math.min(attempt * 0.5, 3))
    end
end, function(err)
    warn("[luma-loader] fatal: " .. tostring(err))
end)
