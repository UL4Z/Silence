--[[
    Module_Engine.lua (v2)
    Event-driven parry engine with confidence checks and cooldown queue.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Module_Engine = {}
local DataBus = nil
local LearningSystem = nil
local FailDetection = nil

local EntityConnections = {} -- [entity] = connection
local ScheduledJobs = {} -- [entityKey] = job

function Module_Engine.Init(bus, learning, failure)
    DataBus = bus
    LearningSystem = learning
    FailDetection = failure
end

function Module_Engine.Start()
    RunService.Heartbeat:Connect(Module_Engine.Update)
end

function Module_Engine.Update()
    local char = Players.LocalPlayer.Character
    if not char then return end
    
    local now = tick()
    
    -- Process Scheduled Jobs
    for key, job in pairs(ScheduledJobs) do
        if job.cancelled then
            ScheduledJobs[key] = nil
            continue
        end
        
        if now >= job.fireAt then
            if Module_Engine.ValidateJob(job) then
                Module_Engine.ExecuteJob(job)
            end
            ScheduledJobs[key] = nil
        end
    end
end

function Module_Engine.ValidateJob(job)
    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
    
    if not job.entity.Parent then return false end
    
    local dist = (job.entity.HumanoidRootPart.Position - char.HumanoidRootPart.Position).Magnitude
    if dist > DataBus.Config.ParryRange then return false end
    
    if DataBus.ParryState.CooldownActive then
        DataBus.ParryState.PendingParry = job -- Queue newest
        return false
    end
    
    return true
end

function Module_Engine.ExecuteJob(job)
    -- Fake Lag Implementation (Spec: Adds task.wait() delay before firing)
    if DataBus.Config.FakeLagEnabled then
        task.wait(DataBus.Config.FakeLagMs / 1000)
    end
    
    local config = DataBus.Config
    local keyCode = config.ParryKey
    
    if job.action == "Parry" then
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    elseif job.action == "Dodge" and config.DodgeRemote then
        -- fireDodge()
    end
    
    DataBus.ParryState.CooldownActive = true
    DataBus.ParryState.LastFireTime = tick()
    
    -- Resolution tracking
    FailDetection.Resolve(job, function(success)
        local lr = DataBus.LearningData[job.animId]
        if lr then
            LearningSystem.UpdateConfidence(lr, success, config)
            if success then
                LearningSystem.AddSample(lr, (tick() - job.startTime) * 1000, config)
            end
        end
    end)
    
    task.delay(config.ParryCooldownSec, function()
        DataBus.ParryState.CooldownActive = false
        if DataBus.ParryState.PendingParry then
            local pending = DataBus.ParryState.PendingParry
            DataBus.ParryState.PendingParry = nil
            Module_Engine.ExecuteJob(pending)
        end
    end)
end

function Module_Engine.CreateTelegraph(job)
    -- Visualise Parry (Telegraph) Logic
    local entry = DataBus.ActiveBuild.Entries[job.animId]
    if not entry or not entry.TelegraphEnabled then return end

    local ball = Instance.new("Part")
    ball.Shape = Enum.PartType.Ball
    ball.Size = Vector3.new(entry.TelegraphSize or 15, entry.TelegraphSize or 15, entry.TelegraphSize or 15)
    ball.Position = job.entity.HumanoidRootPart.Position
    ball.Anchored = true
    ball.CanCollide = false
    ball.Transparency = 0.5
    ball.Color = Color3.fromRGB(0, 255, 255) -- Cyan for parry
    ball.Parent = workspace
    
    task.delay(0.2, function() ball:Destroy() end)
end

function Module_Engine.OnAnimationPlayed(entity, track)
    local animId = track.Animation.AnimationId:match("%d+")
    local entry = DataBus.ActiveBuild.Entries[animId]
    if not entry or entry.Disabled then return end
    
    local lr = DataBus.LearningData[animId]
    if not lr or lr.Confidence < DataBus.Config.FireThreshold then return end
    
    local startTime = tick()
    local delayMs = lr.ManualOverride and lr.ManualWindowMs or lr.WindowMs
    local ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    
    local adjustedDelay = (delayMs / 1000) - (ping / 2000) - DataBus.Config.PingOffsetSec
    
    local job = {
        entity = entity,
        animId = animId,
        fireAt = startTime + math.max(0, adjustedDelay),
        action = entry.DefaultAction,
        startTime = startTime,
        cancelled = false
    }
    
    ScheduledJobs[entity] = job
end

return Module_Engine
