--[[
    FailDetection.lua (v2 — FULL IMPLEMENTATION)
    Multi-Method Parry Resolution System.
    Spec: SILENCE SPEC (1).md — Module: Fail Detection (Multi-Method)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FailDetection = {}
local DataBus = nil

function FailDetection.Init(bus)
    DataBus = bus
end

-- Detection Signals
local function checkAnimations(char, config)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return nil end

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local id = track.Animation.AnimationId:match("%d+")
        if table.find(config.SuccessAnimIds, id) then return true end
        if table.find(config.FailAnimIds, id) then return false end
    end
    return nil
end

local function checkSounds(char, config)
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("Sound") and desc.IsPlaying then
            local id = desc.SoundId:match("%d+")
            if table.find(config.SuccessSoundIds, id) then return true end
            if table.find(config.FailSoundIds, id) then return false end
        end
    end
    return nil
end

function FailDetection.Resolve(job, callback)
    local config = DataBus.Config
    local char = Players.LocalPlayer.Character
    if not char then return callback(true) end -- Best effort fallback

    local startHealth = char:FindFirstChildOfClass("Humanoid") and char:FindFirstChildOfClass("Humanoid").Health or 0
    local resolved = false
    local startTime = tick()

    -- Signal Priority Logic
    local function finish(success)
        if resolved then return end
        resolved = true
        callback(success)
    end

    local connection
    connection = RunService.Heartbeat:Connect(function()
        local now = tick()
        local elapsed = now - startTime

        if elapsed > config.ResolutionWindowSec or resolved then
            connection:Disconnect()
            if not resolved then finish(true) end -- Assume success if window expires with no fail signals
            return
        end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end

        -- 1. Animation Signals (Top Priority)
        local animSignal = checkAnimations(char, config)
        if animSignal ~= nil then return finish(animSignal) end

        -- 2. Sound Signals
        local soundSignal = checkSounds(char, config)
        if soundSignal ~= nil then return finish(soundSignal) end

        -- 3. Health Fallback
        if config.UseHealthFallback then
            local currentHealth = hum.Health
            if currentHealth < startHealth then
                -- Fall Damage Check
                local isFalling = hum:GetState() == Enum.HumanoidStateType.Freefall
                if config.IgnoreFallDamage and isFalling then
                    -- Ignore this health drop
                else
                    return finish(false)
                end
            end
        end
    end)
end

return FailDetection
