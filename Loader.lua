--[[
    Silence v2 Loader
    Author: 6
    Username: UL4Z
]]

local GITHUB_USER = "UL4Z"
local GITHUB_REPO = "Silence"
local GITHUB_BRANCH = "main"

local function load(path)
    local url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, path)
    local success, content = pcall(game.HttpGet, game, url)
    if success then
        local fn, err = loadstring(content)
        if fn then return fn() else error("[Silence] Syntax error in " .. path .. ": " .. err) end
    else
        error("[Silence] Failed to load " .. path .. " from GitHub. Check URL: " .. url)
    end
end

-- Load the framework modules into the global environment
getgenv().Silence = {
    DataBus = load("DataBus.lua"),
    Learning = load("LearningSystem.lua"),
    FailDetection = load("FailDetection.lua"),
}

-- Load and Initialize Modules
local Logger = load("Module_Logger.lua")
local Engine = load("Module_Engine.lua")
local Config = load("Module_Config.lua")
local Viewer = load("Module_Viewer.lua")
local Builder = load("Module_Builder.lua")
local Recorder = load("Module_Recorder.lua")

-- Store for main.lua access
getgenv().Silence.Modules = {
    Logger = Logger,
    Engine = Engine,
    Config = Config,
    Viewer = Viewer,
    Builder = Builder,
    Recorder = Recorder
}

-- Connect shared DataBus
Logger.Init(getgenv().Silence.DataBus)
Engine.Init(getgenv().Silence.DataBus, getgenv().Silence.Learning, getgenv().Silence.FailDetection)
Config.Init(getgenv().Silence.DataBus)
Viewer.Init(getgenv().Silence.DataBus)
Builder.Init(getgenv().Silence.DataBus)
Recorder.Init(getgenv().Silence.DataBus)

-- Launch the main UI and start loops
load("main.lua")
