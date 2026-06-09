--[[
    LearningSystem.lua (v2)
    Implements Beta Distribution Confidence and Timing Refinement for Silence v2.
]]

local LearningSystem = {}

function LearningSystem.NewRecord(animId, animName)
    return {
        AnimId = animId,
        AnimName = animName or "Unknown",
        Successes = 0,
        Failures = 0,
        ConsecutiveStreak = 0,
        Confidence = 0.75, -- (0 + 3) / (0 + 0 + 3 + 1)
        Locked = false,
        WindowMs = 0,
        WindowSamples = {}, -- Ring buffer
        ManualOverride = false,
        ManualWindowMs = 0,
        TotalEncounters = 0,
    }
end

function LearningSystem.UpdateConfidence(record, wasSuccess, config)
    if record.Locked then return end

    local L = config.Learning
    local previousConfidence = record.Confidence

    if wasSuccess then
        record.Successes = record.Successes + 1
        record.ConsecutiveStreak = record.ConsecutiveStreak + 1
    else
        record.Failures = record.Failures + 1
        record.ConsecutiveStreak = 0
    end

    -- 1. Raw Bayesian Confidence (Beta Mean)
    local rawConfidence = (record.Successes + L.Alpha) / (record.Successes + record.Failures + L.Alpha + L.Beta)

    -- 2. Momentum Clamp
    if not wasSuccess then
        record.Confidence = math.max(rawConfidence, previousConfidence - L.MomentumClampMax)
    else
        record.Confidence = rawConfidence
    end

    -- 3. Streak Bonus
    local streakBonus = math.min(record.ConsecutiveStreak * L.StreakBonusPerHit, L.StreakBonusMax)
    record.Confidence = math.min(record.Confidence + streakBonus, 1.0)

    -- 4. Lock Threshold Check
    if record.Confidence >= L.LockConfidence and
       record.Successes >= L.LockSuccesses and
       record.ConsecutiveStreak >= L.LockStreak then
        record.Locked = true
        record.Confidence = 1.0
    end
end

function LearningSystem.AddSample(record, deltaMs, config)
    if record.Locked then return end
    
    table.insert(record.WindowSamples, deltaMs)
    if #record.WindowSamples > config.Learning.RingBufferSize then
        table.remove(record.WindowSamples, 1)
    end

    -- Update WindowMs using Trimmed Mean
    local samples = record.WindowSamples
    if #samples < config.Learning.MinSamplesForTrim then
        record.WindowMs = deltaMs -- Fallback to latest
    else
        local sorted = {unpack(samples)}
        table.sort(sorted)
        
        local n = #sorted
        local trim = math.floor(n * config.Learning.TrimFraction)
        
        local sum = 0
        local count = 0
        for i = trim + 1, n - trim do
            sum = sum + sorted[i]
            count = count + 1
        end
        
        record.WindowMs = sum / count
    end
end

return LearningSystem
