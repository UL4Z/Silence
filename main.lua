--[[
    Silence (v2) — Universal Auto Parry & Animation Logger
    Credit: 6
    Target Executors: Potassium, Volt
]]

local Capabilities = {
    WriteFile = type(writefile) == "function",
    ReadFile = type(readfile) == "function",
    Clipboard = type(setclipboard) == "function",
    VIM = game:GetService("VirtualInputManager") ~= nil,
    GetNetworkPing = type(game.GetNetworkPing) == "function"
}

-- Hard requirements — abort if missing
if not Capabilities.VIM then
    error("[Silence] VirtualInputManager unavailable. This executor is not supported.")
end

local DataBus = require(script.DataBus) -- In practice: loadstring(game:HttpGet(...))
local LearningSystem = require(script.LearningSystem)
local FailDetection = require(script.FailDetection)
local Logger = require(script.Module_Logger)
local Recorder = require(script.Module_Recorder)
local Viewer = require(script.Module_Viewer)
local Builder = require(script.Module_Builder)
local Engine = require(script.Module_Engine)
local Config = require(script.Module_Config)

-- 1. Capability Notification
if not Capabilities.WriteFile then
    warn("[Silence] writefile unavailable. Operating in memory-only mode.")
end

-- 2. Module Initialization
Config.Init(DataBus)
FailDetection.Init(DataBus)
Logger.Init(DataBus)
Recorder.Init(DataBus)
Viewer.Init(DataBus)
Builder.Init(DataBus)
Engine.Init(DataBus, LearningSystem, FailDetection)

-- 3. Load Config/Build
Config.LoadConfig("Default")
if DataBus.Config.AutoLoadBuild then
    Config.LoadBuild(DataBus.Config.AutoLoadBuild)
end

-- 4. UI Setup (Obsidian)
-- Load Obsidian UI Library...
-- Build tabs (Parry, Logger, Recorder, Builder, Builds, Config)
-- ...

-- 5. Start Loops
Logger.Start()
-- Engine and Recorder start based on UI toggles/ActiveBuild presence

print("[Silence] Script loaded successfully.")
