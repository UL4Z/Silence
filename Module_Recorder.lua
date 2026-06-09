--[[
    Module_Recorder.lua
    Captures raw timing deltas from manual parries and generates guesses.
]]

local UserInputService = game:GetService("UserInputService")

local Module_Recorder = {}
local DataBus = nil

local lastAnimTimes = {} -- [animId] = tick()

function Module_Recorder.Init(bus)
    DataBus = bus

    -- Hook AnimationPlayed on all entities...
    -- (Actually handled by the scanning logic in the engine or logger)
end

function Module_Recorder.RegisterAnimStart(animId)
    lastAnimTimes[animId] = tick()
end

function Module_Recorder.OnInputBegan(input, processed)
    if processed then return end
    if not DataBus.DelayRecorder.Active then return end
    if input.KeyCode ~= DataBus.Config.ParryKey then return end

    -- Find most recent animation
    local bestAnim = nil
    local bestTime = 0
    
    for animId, t in pairs(lastAnimTimes) do
        if t > bestTime then
            bestTime = t
            bestAnim = animId
        end
    end

    if bestAnim then
        local delta = (tick() - bestTime) * 1000
        Module_Recorder.Record(bestAnim, delta)
    end
end

function Module_Recorder.Record(animId, rawDeltaMs)
    local anim = DataBus.Animations[animId]
    local ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    
    local subtract = 0 -- Config.DelayRecorder.Subtract or 0
    local guessDelta = (rawDeltaMs * 0.70) - (ping / 2) - subtract

    local alreadyAdded = false
    local existingDelay = nil
    if DataBus.ActiveBuild.Entries[animId] then
        alreadyAdded = true
        existingDelay = DataBus.ActiveBuild.Entries[animId].DelayMs / 1000
    end

    DataBus.DelayRecorder.Recorded[animId] = {
        AnimId = animId,
        AnimName = anim and anim.AnimName or "Unknown",
        RawDeltaMs = rawDeltaMs,
        GuessSubtract = subtract,
        GuessDeltaMs = guessDelta,
        AlreadyAdded = alreadyAdded,
        ExistingDelay = existingDelay,
    }

    if DataBus.UI.UpdateRecorder then
        DataBus.UI.UpdateRecorder(animId)
    end
end

return Module_Recorder
