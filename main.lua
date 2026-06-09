--[[
    main.lua (v2)
    Silence v2 — UI & Startup Entry Point
    Loaded via Loader.lua
]]

local DataBus = getgenv().Silence.DataBus
local LearningSystem = getgenv().Silence.Learning
local FailDetection = getgenv().Silence.FailDetection

-- 1. Load Obsidian UI Library (Using the signature variant mstudio45 uses)
local Obsidian = loadstring(game:HttpGet("https://raw.githubusercontent.com/mstudio45/Obsidian/main/Library.lua"))()

-- 2. Create Main Window
local Window = Obsidian:CreateWindow({
    Title = "Silence",
    SubTitle = "by 6",
    Size = UDim2.fromOffset(600, 480),
    Draggable = true,
    Icon = "rbxassetid://10723343321", -- Bolt icon
})

-- 3. Create Tabs
local Tabs = {
    Parry = Window:CreateTab({ Name = "Parry", Icon = "rbxassetid://10723346610" }), -- Swords
    Logger = Window:CreateTab({ Name = "Logger", Icon = "rbxassetid://10723346955" }), -- List
    Recorder = Window:CreateTab({ Name = "Recorder", Icon = "rbxassetid://10723345840" }), -- Film
    Builder = Window:CreateTab({ Name = "Builder", Icon = "rbxassetid://10723345532" }), -- Hammer
    Builds = Window:CreateTab({ Name = "Builds", Icon = "rbxassetid://10723346371" }), -- Save
    Config = Window:CreateTab({ Name = "Config", Icon = "rbxassetid://10723344435" }), -- Settings
}

-- 4. Hook up Logger UI
local LoggerSub = Tabs.Logger:CreateSection("Animation Scanner")
DataBus.UI.OnNewAnimation = function(animId)
    local anim = DataBus.Animations[animId]
    LoggerSub:CreateLabel({
        Text = string.format("[%s] %s (%s)", anim.EntityType, anim.AnimName, anim.AnimId),
        TextColor = Color3.fromRGB(200, 200, 255)
    })
    -- Add buttons (Copy ID, Preview, Add to Build, Ignore) as per spec
end

-- 5. Hook up Engine UI (Parry Tab)
local EngineSection = Tabs.Parry:CreateSection("Status")
EngineSection:CreateToggle({
    Name = "Auto Parry Master",
    Value = DataBus.ParryState.Active,
    Callback = function(v)
        DataBus.ParryState.Active = v
    end
})

-- 6. Config Section
local ConfigSection = Tabs.Config:CreateSection("Engine Settings")
ConfigSection:CreateSlider({
    Name = "Parry Range",
    Min = 5, Max = 100,
    Default = DataBus.Config.ParryRange,
    Callback = function(v) DataBus.Config.ParryRange = v end
})

-- 7. Start Background Service
DataBus.ParryState.Active = true
getgenv().Silence.Modules.Logger.Start()
getgenv().Silence.Modules.Engine.Start()

print("[Silence] UI and Modules initialized successfully.")
