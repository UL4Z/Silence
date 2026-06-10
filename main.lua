--[[
    Silence v2 — main.lua (RESTORED & FIXED)
    Matches spec linear flow with specific fixes applied.
]]

local DataBus = getgenv().Silence.DataBus
local Modules = getgenv().Silence.Modules
local Config = DataBus.Config

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local Options = Library.Options

local Window = Library:CreateWindow({ Title = "Silence", Footer = "by 6", Icon = 0, NotifySide = "Right" })

-- ────────────────────────────────────────────────────────────────────────────
-- 1. PARRY TAB (Front Page)
-- ────────────────────────────────────────────────────────────────────────────
local ParryTab = Window:AddTab("Parry", "sword")
local EngineGroup = ParryTab:AddLeftGroupbox("Engine")

-- Description added
EngineGroup:AddLabel("Auto Parry: Central combat engine. When active, it will use Bayesian learning to defend against attacks.", true)
EngineGroup:AddToggle("ParryMaster", {
    Text = "Enable Engine",
    Default = false,
    Callback = function(v) DataBus.ParryState.Active = v end
})

-- Keybinds added
EngineGroup:AddLabel("Parry Key"):AddKeyPicker("PKey", { Default = "F", Text = "Parry", Callback = function(v) Config.ParryKey = v end })
EngineGroup:AddLabel("Dodge Key"):AddKeyPicker("DKey", { Default = "Q", Text = "Dodge", Callback = function(v) Config.DodgeKey = v end })
EngineGroup:AddLabel("Counter Key"):AddKeyPicker("CKey", { Default = "C", Text = "Counter", Callback = function(v) Config.CounterKey = v end })

-- Auto Learn Dashboard (Spec: Front Page)
local DashGroup = ParryTab:AddRightGroupbox("Learning Dashboard")
DashGroup:AddLabel("Live view of Bayesian confidence and ring-buffer timing convergence.", true)

DataBus.UI.UpdateDashboard = function()
    for animId, entry in pairs(DataBus.ActiveBuild.Entries) do
        local lr = DataBus.LearningData[animId]
        local labelId = "Dash_" .. animId
        local status = lr and string.format("%.0f%% conf | %.3fs | %d✓", lr.Confidence*100, (lr.ManualOverride and lr.ManualWindowMs or lr.WindowMs)/1000, lr.Successes) or "No data"
        if Options[labelId] then Options[labelId]:SetText(entry.AnimName .. ": " .. status)
        else DashGroup:AddLabel(entry.AnimName .. ": " .. status, false, labelId) end
    end
end

-- Override description
local OverrideGroup = ParryTab:AddLeftGroupbox("Override System")
OverrideGroup:AddLabel("Overrides allow you to force specific manual timings globally, bypassing the adaptive learning engine.", true)
OverrideGroup:AddToggle("ForceManual", { Text = "Force Manual Timing", Callback = function(v) Config.ForceManual = v end })

-- ────────────────────────────────────────────────────────────────────────────
-- 2. RECORDER TAB (Matched to Spec)
-- ────────────────────────────────────────────────────────────────────────────
local RecTab = Window:AddTab("Recorder", "video")
local RecGroup = RecTab:AddLeftGroupbox("Timing Recorder")
RecGroup:AddToggle("RecState", { Text = "Active Recorder", Callback = function(v) DataBus.DelayRecorder.Active = v end })
local RecHistory = RecTab:AddLeftGroupbox("Recorded Entries")

DataBus.UI.UpdateRecorder = function(animId)
    local rec = DataBus.DelayRecorder.Recorded[animId]
    RecHistory:AddLabel(rec.AnimName .. " | " .. string.format("%.3fs", rec.RawDeltaMs/1000))
    RecHistory:AddButton({ Text = "Add Guess", Func = function() Modules.Builder.SaveToBuild(animId, { AnimId = animId, AnimName = rec.AnimName, DelayMs = rec.GuessDeltaMs }) end })
end

-- ────────────────────────────────────────────────────────────────────────────
-- 3. BUILDS / CONFIG TABS (Restored)
-- ────────────────────────────────────────────────────────────────────────────
local BuildTab = Window:AddTab("Builds", "save")
BuildTab:AddLeftGroupbox("Active Build"):AddLabel("Management of your current animation sets.", true)

local ConfigTab = Window:AddTab("Config", "settings")
ConfigTab:AddLeftGroupbox("Settings")

-- ────────────────────────────────────────────────────────────────────────────
-- 4. SETTINGS (Visuals & Debug)
-- ────────────────────────────────────────────────────────────────────────────
local SettTab = Window:AddTab("Settings", "shield")
local Visuals = SettTab:AddLeftGroupbox("Visuals")
Visuals:AddToggle("Countdown", { Text = "Visualize Parry Countdown", Callback = function(v) Config.VisualiseParry = v end })
Visuals:AddButton({ Text = "Open Advanced Viewer", Func = function() Modules.Viewer.Open() end })

local DebugGroup = SettTab:AddRightGroupbox("Debug Mode")
DebugGroup:AddToggle("Dbg", { Text = "Enable Mark History", Callback = function(v) Config.DebugMode = v end })
DebugGroup:AddLabel("Mark Key"):AddKeyPicker("MKey", { Default = "P", Text = "Mark Anim", Callback = function(v) Config.MarkKey = v end })

local LearningParams = SettTab:AddLeftGroupbox("Learning Parameters")
LearningParams:AddSlider("Alpha", { Text = "Learning Velocity", Min = 1, Max = 10, Default = 3, Tooltip = "Lower = Bot reacts faster to new hits. Higher = Bot is more 'cautious' and waits for more proof." })
LearningParams:AddSlider("Momentum", { Text = "Stability", Min = 1, Max = 10, Default = 4, Tooltip = "How much confidence drops on a single fail. Higher = Bot is harder to 'tilt' by lag." })
LearningParams:AddSlider("LockConf", { Text = "Lock Confidence", Min = 90, Max = 100, Default = 96, Suffix = "%", Tooltip = "Required confidence to 'Lock' an animation (stop learning and go perfect)." })
LearningParams:AddSlider("RingSize", { Text = "Sample Memory", Min = 5, Max = 50, Default = 20, Tooltip = "How many previous hits the bot remembers for timing. Higher = better average, but slower to adapt to ping changes." })
LearningParams:AddSlider("Trim", { Text = "Noise Filtering", Min = 0, Max = 30, Default = 15, Suffix = "%", Tooltip = "Precentage of 'weird' timing samples to ignore (the outliers caused by lag spikes)." })

-- ────────────────────────────────────────────────────────────────────────────
-- 5. LOOPS
-- ────────────────────────────────────────────────────────────────────────────
task.spawn(function()
    while task.wait(0.5) do
        if Library.Unloaded then break end
        DataBus.UI.UpdateDashboard()
    end
end)

Modules.Logger.Start()
Modules.Engine.Start()
