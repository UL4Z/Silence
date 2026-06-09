--[[
    Module_Builder.lua (v2)
    Syncs the parry markers and build entries between the UI tab and the visual viewer.
]]

local Module_Builder = {}
local DataBus = nil

function Module_Builder.Init(bus)
    DataBus = bus
end

function Module_Builder.AddMarker(animId, markerType, offsetMs, durationMs)
    local build = DataBus.ActiveBuild
    local entry = build.Entries[animId]
    
    if not entry then
        entry = {
            AnimId = animId,
            AnimName = DataBus.Animations[animId] and DataBus.Animations[animId].AnimName or "Unknown",
            DefaultAction = "Parry",
            DelayMs = offsetMs,
            DurationMs = durationMs or 150,
            Markers = {},
            Disabled = false
        }
        build.Entries[animId] = entry
    end
    
    table.insert(entry.Markers, {
        Type = markerType,
        OffsetMs = offsetMs,
        DurationMs = durationMs or 150
    })
    
    if DataBus.UI.UpdateBuilder then
        DataBus.UI.UpdateBuilder()
    end
end

function Module_Builder.SaveToBuild(animId, data)
    DataBus.ActiveBuild.Entries[animId] = data
    
    -- Ensure LearningRecord exists
    if not DataBus.LearningData[animId] then
        DataBus.LearningData[animId] = {
            AnimId = animId,
            AnimName = data.AnimName,
            Successes = 0,
            Failures = 0,
            ConsecutiveStreak = 0,
            Confidence = 0.75,
            Locked = false,
            WindowMs = data.DelayMs,
            WindowSamples = {},
            ManualOverride = true,
            ManualWindowMs = data.DelayMs,
            TotalEncounters = 0
        }
    end
end

return Module_Builder
