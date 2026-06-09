--[[
    main.lua (v2)
    Silence v2 — UI & Startup Entry Point
    Corrected for Obsidian (Linoria Fork)
]]

local DataBus = getgenv().Silence.DataBus
local LearningSystem = getgenv().Silence.Learning
local FailDetection = getgenv().Silence.FailDetection

-- 1. Load Obsidian UI Library
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua"))()

-- 2. Create Main Window
local Window = Library:CreateWindow({
    Title = "Silence",
    Footer = "by 6",
    Icon = "rbxassetid://10723343321",
    NotifySide = "Right",
})

-- 3. Create Tabs (Obsidian uses icon names from Lucide)
local Tabs = {
    Parry = Window:AddTab("Parry", "house"),
    Logger = Window:AddTab("Logger", "list"),
    Recorder = Window:AddTab("Recorder", "film"),
    Builder = Window:AddTab("Builder", "hammer"),
    Builds = Window:AddTab("Builds", "save"),
    Config = Window:AddTab("Config", "settings"),
}

-- 4. Parry Tab (Engine Status)
local MainGroup = Tabs.Parry:AddLeftGroupbox("Engine Status")
MainGroup:AddToggle("MasterToggle", {
    Text = "Auto Parry Master",
    Default = DataBus.ParryState.Active,
    Callback = function(v) DataBus.ParryState.Active = v end
})

local BuildGroup = Tabs.Parry:AddLeftGroupbox("Active Build")
BuildGroup:AddLabel("Current: " .. (DataBus.ActiveBuild.Name or "None"))

-- 5. Logger Tab
local LoggerGroup = Tabs.Logger:AddLeftGroupbox("Animation Logger")
LoggerGroup:AddSlider("LoggerDistance", {
    Text = "Logger Distance",
    Min = 0, Max = 200, Default = DataBus.Config.LoggerDistance,
    Rounding = 0,
    Callback = function(v) DataBus.Config.LoggerDistance = v end
})

DataBus.UI.OnNewAnimation = function(animId)
    local anim = DataBus.Animations[animId]
    LoggerGroup:AddLabel(string.format("[%s] %s", anim.EntityType, anim.AnimName))
end

-- 5a. Recorder Tab
local RecorderGroup = Tabs.Recorder:AddLeftGroupbox("Delay Recorder")
RecorderGroup:AddToggle("RecorderActive", {
    Text = "Record Enemy Animations",
    Default = DataBus.DelayRecorder.Active,
    Callback = function(v) DataBus.DelayRecorder.Active = v end
})

DataBus.UI.UpdateRecorder = function(animId)
    local rec = DataBus.DelayRecorder.Recorded[animId]
    RecorderGroup:AddLabel(string.format("%s: Raw %.2fs | Guess %.2fs", rec.AnimName, rec.RawDeltaMs/1000, rec.GuessDeltaMs/1000))
end

-- 6. Config Tab
local ConfigGroup = Tabs.Config:AddLeftGroupbox("Global Settings")
ConfigGroup:AddSlider("ParryRange", {
    Text = "Parry Range",
    Min = 5, Max = 100, Default = DataBus.Config.ParryRange,
    Rounding = 0,
    Callback = function(v) DataBus.Config.ParryRange = v end
})

ConfigGroup:AddSlider("ParryCooldown", {
    Text = "Parry Cooldown",
    Min = 0.3, Max = 2.0, Default = DataBus.Config.ParryCooldownSec,
    Rounding = 2,
    Callback = function(v) DataBus.Config.ParryCooldownSec = v end
})

local LearningGroup = Tabs.Config:AddLeftGroupbox("Learning Parameters")
LearningGroup:AddSlider("Alpha", {
    Text = "Alpha (Prior Successes)",
    Min = 1, Max = 10, Default = DataBus.Config.Learning.Alpha,
    Rounding = 0,
    Callback = function(v) DataBus.Config.Learning.Alpha = v end
})

LearningGroup:AddSlider("MomentumClamp", {
    Text = "Momentum Clamp Max",
    Min = 0.01, Max = 0.10, Default = DataBus.Config.Learning.MomentumClampMax,
    Rounding = 3,
    Callback = function(v) DataBus.Config.Learning.MomentumClampMax = v end
})

-- 7. Start Background Services
DataBus.ParryState.Active = true
getgenv().Silence.Modules.Logger.Start()
getgenv().Silence.Modules.Engine.Start()

print("[Silence] UI and Modules initialized successfully with Obsidian.")
