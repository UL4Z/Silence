--[[
    Module_Recorder.lua (v2 — FULL IMPLEMENTATION)
    Manual Timing Capture System.
    Spec: SILENCE SPEC (1).md — Module: Delay Recorder
]]

local UserInputService = game:GetService("UserInputService")

local Module_Recorder = {}
local DataBus = nil

local lastAnimStarts = {} -- [animId] = tick()

function Module_Recorder.Init(bus)
    DataBus = bus

    -- Sync with UI callback
    DataBus.UI.RecorderAnimStart = function(animId)
        lastAnimStarts[animId] = tick()
    end

    -- Input Hook
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if not DataBus.DelayRecorder.Active then return end
        
        if input.KeyCode == (DataBus.Config.ParryKey or Enum.KeyCode.F) or 
           (DataBus.Config.DodgeKey and input.KeyCode == DataBus.Config.DodgeKey) then
            
            Module_Recorder.Capture()
        end
    end)
end

function Module_Recorder.Capture()
    local now = tick()
    local bestAnimId = nil
    local shortestDelta = math.huge

    -- Find most recent animation pair
    for id, startTime in pairs(lastAnimStarts) do
        local delta = now - startTime
        -- Limit to reasonable window (e.g. 2 seconds)
        if delta < 2.0 and delta < shortestDelta then
            shortestDelta = delta
            bestAnimId = id
        end
    end

    if bestAnimId then
        local rawDeltaMs = shortestDelta * 1000
        Module_Recorder.ProcessRecord(bestAnimId, rawDeltaMs)
    end
end

function Module_Recorder.ProcessRecord(animId, rawDeltaMs)
    local anim = DataBus.Animations[animId]
    local config = DataBus.Config
    
    -- Guess Logic: (Raw - Ping) * 0.70
    local ping = 0
    local ok, v = pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
    if ok then ping = v end
    
    local guessSubtract = 0 -- Modified by UI slider in recorder tab
    local guessDeltaMs = (rawDeltaMs * 0.70) - (ping / 2) - guessSubtract

    local existing = DataBus.ActiveBuild.Entries[animId]
    
    DataBus.DelayRecorder.Recorded[animId] = {
        AnimId = animId,
        AnimName = anim and anim.AnimName or "Unknown",
        RawDeltaMs = rawDeltaMs,
        GuessDeltaMs = guessDeltaMs,
        GuessSubtract = guessSubtract,
        AlreadyAdded = existing ~= nil,
        ExistingDelay = existing and (existing.DelayMs / 1000) or nil
    }

    if DataBus.UI.UpdateRecorder then
        DataBus.UI.UpdateRecorder(animId)
    end
end

return Module_Recorder
