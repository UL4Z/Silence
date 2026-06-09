--[[
    DataBus.lua (v2)
    Centralized data store for Silence v2.
]]

local DataBus = {
    Animations = {},        -- [animId] = AnimationRecord
    ActiveBuild = {
        Name = "Default",
        Entries = {}
    },       -- BuildData
    LearningData = {},      -- [animId] = LearningRecord
    Config = {
        -- Defaults from Spec v2
        Name = "Default",
        AutoLoadBuild = nil,
        ParryRange = 25,
        ParryCooldownSec = 0.8,
        PingOffsetSec = 0,
        FireThreshold = 0.60,
        BlockM1 = false,
        GlobalAction = "PerEntry",
        ParryKey = Enum.KeyCode.F,
        LoggerDistance = 50, -- Recommended default
        AnimFolderPath = "",
        SuccessAnimIds = {},
        FailAnimIds = {},
        SuccessSoundIds = {},
        FailSoundIds = {},
        UseHealthFallback = true,
        IgnoreFallDamage = true,
        ResolutionWindowSec = 0.8,
        M1AnimIds = {},
        IgnoreList = {},
        DodgeRemote = nil,
        DodgeKey = nil,
        FakeLagEnabled = false,
        FakeLagMs = 0,
        Learning = {
            Alpha = 3,
            Beta = 1,
            MomentumClampMax = 0.04,
            StreakBonusPerHit = 0.008,
            StreakBonusMax = 0.08,
            LockConfidence = 0.96,
            LockSuccesses = 12,
            LockStreak = 6,
            RingBufferSize = 20,
            MinSamplesForTrim = 5,
            TrimFraction = 0.15,
            PingRollingSamples = 5,
        }
    },            -- Current loaded Config
    EntityCache = {},       -- [cacheKey] = frozen model in PlayerGui
    ParryState = {
        Active = false,
        CooldownActive = false,
        LastFireTime = 0,
        PendingParry = nil,
        ScheduledJobs = {}, -- [entityKey] = ParryJob
    },
    IgnoreList = {},        -- [animId] = true
    DelayRecorder = {
        Active = false,
        Recorded = {},      -- [animId] = DelayRecord
    },
    M1Blocked = false,
    UI = {},                -- UI component references
    ExternalViewer = {
        Window = nil,
        CurrentAnimId = nil,
        Markers = {},       -- Markers for current anim in viewer
    }
}

return DataBus
