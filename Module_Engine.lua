--[[
    Module_Engine.lua (v2 — FULL IMPLEMENTATION)
    Event-driven auto-parry engine.
    Spec: SILENCE SPEC (1).md — Module: Auto Parry Engine
]]

local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Module_Engine = {}
local DataBus = nil
local LearningSystem = nil
local FailDetection  = nil

-- ── Ping Rolling Average ───────────────────────────────────────────────────
local pingBuffer = {}
local function getSmoothedPing()
    local ok, v = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if not ok or not v then
        ok, v = pcall(function() return game:GetNetworkPing() * 1000 end)
    end
    if ok and v then
        local n = DataBus.Config.Learning.PingRollingSamples or 5
        table.insert(pingBuffer, v)
        if #pingBuffer > n then table.remove(pingBuffer, 1) end
        local s = 0
        for _, p in ipairs(pingBuffer) do s = s + p end
        return s / #pingBuffer
    end
    return 0
end

-- Poll ping every 5 seconds
task.spawn(function()
    while true do
        task.wait(5)
        getSmoothedPing()
    end
end)

-- ── Entity Connection Management ───────────────────────────────────────────
local EntityConnections = {}   -- [entityKey] = { conn1, conn2, ... }
local ScheduledJobs = {}       -- [entityKey] = job
local scanAccum = 0
local SCAN_INTERVAL = 0.4

local function entityKey(entity)
    return tostring(entity:GetDebugId())
end

local function normaliseId(animId)
    return animId:match("%d+") or animId
end

local function disconnectEntity(key)
    if EntityConnections[key] then
        for _, conn in ipairs(EntityConnections[key]) do
            pcall(function() conn:Disconnect() end)
        end
        EntityConnections[key] = nil
    end
    if ScheduledJobs[key] then
        ScheduledJobs[key].cancelled = true
        ScheduledJobs[key] = nil
    end
end

-- ── Block M1 ───────────────────────────────────────────────────────────────
local m1Connection
local function blockM1Input()
    if m1Connection and m1Connection.Connected then
        m1Connection:Disconnect()
    end
    DataBus.M1Blocked = true
    m1Connection = UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            DataBus.M1Blocked = true
            m1Connection:Disconnect()
        end
    end)
    task.delay(DataBus.Config.ParryCooldownSec + 0.1, function()
        DataBus.M1Blocked = false
        if m1Connection and m1Connection.Connected then
            m1Connection:Disconnect()
        end
    end)
end

-- ── Validate Job ───────────────────────────────────────────────────────────
local function validateJob(job)
    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
    if not job.entity or not job.entity.Parent then return false end
    if not job.entity:FindFirstChild("HumanoidRootPart") then return false end

    local dist = (job.entity.HumanoidRootPart.Position - char.HumanoidRootPart.Position).Magnitude
    if dist > DataBus.Config.ParryRange then return false end

    if DataBus.ParryState.CooldownActive then
        -- Queue as pending (newest wins)
        DataBus.ParryState.PendingParry = job
        return false
    end

    if DataBus.Config.IgnoreList[job.animId] then return false end

    return true
end

-- ── Fire Parry ─────────────────────────────────────────────────────────────
local function fireParry(job)
    local config = DataBus.Config
    local vim = VirtualInputManager

    if config.FakeLagEnabled then
        task.wait(config.FakeLagMs / 1000)
    end

    if config.BlockM1 then
        blockM1Input()
    end

    if job.action == "Parry" then
        vim:SendKeyEvent(true,  config.ParryKey or Enum.KeyCode.F, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, config.ParryKey or Enum.KeyCode.F, false, game)
    elseif job.action == "Dodge" then
        if config.DodgeKey then
            vim:SendKeyEvent(true,  config.DodgeKey, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(false, config.DodgeKey, false, game)
        end
        -- else: dodge not configured, skip silently
    end

    DataBus.ParryState.CooldownActive  = true
    DataBus.ParryState.LastFireTime    = tick()

    -- Telegraph visual
    task.spawn(function()
        local entry = DataBus.ActiveBuild.Entries[job.animId]
        if entry and entry.TelegraphEnabled and job.entity and job.entity.Parent then
            local ball = Instance.new("Part")
            ball.Shape = Enum.PartType.Ball
            local s = ((entry.TelegraphSize or 15) * 0.1)
            ball.Size = Vector3.new(s, s, s)
            ball.Position = job.entity.HumanoidRootPart.Position + Vector3.new(0, 3, 0)
            ball.Anchored = true
            ball.CanCollide = false
            ball.Transparency = 0.4
            ball.Color = Color3.fromRGB(0, 200, 255)
            ball.Parent = workspace
            task.delay(0.25, function() pcall(function() ball:Destroy() end) end)
        end
    end)

    -- Resolution
    FailDetection.Resolve(job, function(success)
        local lr = DataBus.LearningData[job.animId]
        if lr then
            LearningSystem.UpdateConfidence(lr, success, DataBus.Config)
            if success then
                local delta = (tick() - job.startTime) * 1000
                LearningSystem.AddSample(lr, delta, DataBus.Config)
            end
        end
    end)

    task.delay(config.ParryCooldownSec, function()
        DataBus.ParryState.CooldownActive = false
        if DataBus.ParryState.PendingParry then
            local pending = DataBus.ParryState.PendingParry
            DataBus.ParryState.PendingParry = nil
            if validateJob(pending) then
                fireParry(pending)
            end
        end
    end)
end

-- ── Schedule Job ───────────────────────────────────────────────────────────
local function scheduleJob(entity, animId, track, startTime)
    local config    = DataBus.Config
    local entry     = DataBus.ActiveBuild.Entries[animId]
    local lr        = DataBus.LearningData[animId]

    if not entry or entry.Disabled then return end

    -- Ensure LearningRecord exists
    if not lr then
        lr = LearningSystem.NewRecord(animId, entry.AnimName)
        DataBus.LearningData[animId] = lr
    end

    lr.TotalEncounters = (lr.TotalEncounters or 0) + 1

    if lr.Confidence < config.FireThreshold then
        print(string.format("[Silence] Confidence too low (%.2f) for %s — not firing", lr.Confidence, animId))
        return
    end

    -- Min duration filter
    if entry.MinDuration and entry.MinDuration > 0 then
        if track.Length < entry.MinDuration then return end
    end

    local ping    = getSmoothedPing()
    local delayMs = (lr.ManualOverride and lr.ManualWindowMs or lr.WindowMs) or (entry.DelayMs or 300)
    local adjustedDelay = math.max(0, (delayMs / 1000) - (ping / 2000) - (config.PingOffsetSec or 0))

    local key = entityKey(entity)

    local job = {
        entity    = entity,
        animId    = animId,
        fireAt    = startTime + adjustedDelay,
        action    = (config.GlobalAction == "PerEntry") and entry.DefaultAction or config.GlobalAction,
        startTime = startTime,
        cancelled = false,
    }

    -- Overwrite any existing scheduled job for this entity
    if ScheduledJobs[key] then
        ScheduledJobs[key].cancelled = true
    end
    ScheduledJobs[key] = job
end

-- ── Connect Entity ─────────────────────────────────────────────────────────
local function connectEntity(entity)
    local key = entityKey(entity)
    if EntityConnections[key] then return end -- already connected

    EntityConnections[key] = {}

    -- Method 1: Humanoid Animator via AnimationPlayed
    local function tryConnectAnimator(animator)
        if not animator then return end
        local conn = animator.AnimationPlayed:Connect(function(track)
            if not DataBus.ParryState.Active then return end
            local animId = normaliseId(track.Animation.AnimationId)
            
            -- Track start time for Hit History
            EntityConnections[key].LastAnimStartTime = tick()
            EntityConnections[key].LastAnimId = animId

            if not DataBus.ActiveBuild.Entries[animId] then return end
            if DataBus.Config.IgnoreList[animId] then return end

            -- Notify recorder about this anim start
            if DataBus.DelayRecorder.Active then
                if DataBus.UI and DataBus.UI.RecorderAnimStart then
                    DataBus.UI.RecorderAnimStart(animId)
                end
            end

            -- Update last played for builder
            if DataBus.UI then
                DataBus.UI.LastPlayedAnimId = animId
            end

            scheduleJob(entity, animId, track, tick())
        end)
        table.insert(EntityConnections[key], conn)
    end

    -- Search method 1: Humanoid
    local hum = entity:FindFirstChildOfClass("Humanoid")
    if hum then
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then
            tryConnectAnimator(animator)
        end
        -- If animator not yet present, wait for it
        local animWait = hum.ChildAdded:Connect(function(child)
            if child:IsA("Animator") then tryConnectAnimator(child) end
        end)
        table.insert(EntityConnections[key], animWait)
    end

    EntityConnections[key].Object = entity -- Store reference for hit history

    -- Method 2: AnimationController (bosses / non-humanoid NPCs)
    local function tryAnimController(ac)
        local animator = ac:FindFirstChildOfClass("Animator")
            or ac:FindFirstChild("Animator", true)
        tryConnectAnimator(animator)
        local ac2 = ac.ChildAdded:Connect(function(child)
            if child:IsA("Animator") then tryConnectAnimator(child) end
        end)
        table.insert(EntityConnections[key], ac2)
    end

    for _, ac in ipairs(entity:GetDescendants()) do
        if ac:IsA("AnimationController") then
            tryAnimController(ac)
        end
    end

    local addConn = entity.DescendantAdded:Connect(function(desc)
        if desc:IsA("AnimationController") then
            tryAnimController(desc)
        end
    end)
    table.insert(EntityConnections[key], addConn)
end

-- ── Scanner Loop ───────────────────────────────────────────────────────────
function Module_Engine.Update(dt)
    if not DataBus.ParryState.Active then return end

    scanAccum = scanAccum + dt
    if scanAccum >= SCAN_INTERVAL then
        scanAccum = 0

        local char = Players.LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local localPos = char.HumanoidRootPart.Position
        local range = DataBus.Config.ParryRange

        local currentKeys = {}

        for _, entity in ipairs(workspace:GetDescendants()) do
            if entity:IsA("Model") and entity ~= char then
                local hrp = entity:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dist = (hrp.Position - localPos).Magnitude
                    if dist <= range then
                        local key = entityKey(entity)
                        currentKeys[key] = true
                        connectEntity(entity)
                    end
                end
            end
        end

        -- Disconnect entities that left range
        for key, _ in pairs(EntityConnections) do
            if not currentKeys[key] then
                disconnectEntity(key)
            end
        end
    end

    -- Process scheduled jobs
    local now = tick()
    for key, job in pairs(ScheduledJobs) do
        if job.cancelled then
            ScheduledJobs[key] = nil
        elseif now >= job.fireAt then
            ScheduledJobs[key] = nil
            if validateJob(job) then
                fireParry(job)
            end
        end
    end
end

-- ── Hit History ─────────────────────────────────────────────────────────────
local function recordHit(entity, animId, startTime)
    local now = tick()
    local timeIntoAnim = now - startTime
    local entityName = entity.Name or "Unknown"

    if not DataBus.HitHistory[entityName] then
        DataBus.HitHistory[entityName] = {}
    end

    table.insert(DataBus.HitHistory[entityName], 1, {
        AnimId = animId,
        TimeIntoAnim = timeIntoAnim,
        Timestamp = now
    })

    -- Keep only most recent 10 hits per NPC
    if #DataBus.HitHistory[entityName] > 10 then
        table.remove(DataBus.HitHistory[entityName], 11)
    end

    if DataBus.UI and DataBus.UI.UpdateViewerHistory then
        DataBus.UI.UpdateViewerHistory()
    end
end

local lastKnownHealth = 100
local function setupHitMonitor()
    local char = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid")
    lastKnownHealth = hum.Health

    hum.HealthChanged:Connect(function(newHealth)
        if newHealth < lastKnownHealth then
            -- Damage detected. Find the most recently started animation from any NPC in range.
            local bestEntity = nil
            local bestAnimId = nil
            local bestStartTime = 0

            -- We use the entity connections to find playing animations
            for key, conns in pairs(EntityConnections) do
                -- This requires us to have stored the last started anim per entity
                -- I will add 'LastAnim' to the connection table
                local data = EntityConnections[key]
                if data.LastAnimStartTime and data.LastAnimStartTime > bestStartTime then
                    bestStartTime = data.LastAnimStartTime
                    bestAnimId = data.LastAnimId
                    -- Find entity ref by key (simplified: we'll store the object too)
                    bestEntity = data.Object 
                end
            end

            if bestEntity and bestAnimId and (tick() - bestStartTime < 2.0) then
                recordHit(bestEntity, bestAnimId, bestStartTime)
            end
        end
        lastKnownHealth = newHealth
    end)
end

function Module_Engine.Init(bus, learning, failDetect)
    DataBus      = bus
    LearningSystem = learning
    FailDetection  = failDetect
    
    setupHitMonitor()
    Players.LocalPlayer.CharacterAdded:Connect(setupHitMonitor)
end

function Module_Engine.Start()
    RunService.Heartbeat:Connect(Module_Engine.Update)
end

return Module_Engine
