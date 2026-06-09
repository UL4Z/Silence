--[[
    Module_Config.lua (v2)
    Expanded file management for Silence v2: Configs, Builds, and Exports.
]]

local HttpService = game:GetService("HttpService")

local Module_Config = {}
local DataBus = nil

local BASE_PATH = "silence/"
local CONFIG_PATH = BASE_PATH .. "configs/"
local BUILD_PATH = BASE_PATH .. "builds/"
local EXPORT_PATH = BASE_PATH .. "exports/"

function Module_Config.Init(bus)
    DataBus = bus
    if makefolder then
        pcall(makefolder, BASE_PATH)
        pcall(makefolder, CONFIG_PATH)
        pcall(makefolder, BUILD_PATH)
        pcall(makefolder, EXPORT_PATH)
    end
end

function Module_Config.SaveConfig(name)
    if not writefile then return end
    writefile(CONFIG_PATH .. name .. ".json", HttpService:JSONEncode(DataBus.Config))
end

function Module_Config.LoadConfig(name)
    if not readfile then return end
    local path = CONFIG_PATH .. name .. ".json"
    if isfile(path) then
        local data = HttpService:JSONDecode(readfile(path))
        DataBus.Config = data
        return true
    end
    return false
end

function Module_Config.SaveBuild(name)
    if not writefile then return end
    local buildData = {
        Name = name,
        Version = 1,
        CreatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        LastSaved = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        Entries = DataBus.ActiveBuild.Entries,
        LearningData = DataBus.LearningData
    }
    writefile(BUILD_PATH .. name .. ".json", HttpService:JSONEncode(buildData))
end

function Module_Config.LoadBuild(name)
    if not readfile then return end
    local path = BUILD_PATH .. name .. ".json"
    if isfile(path) then
        local data = HttpService:JSONDecode(readfile(path))
        DataBus.ActiveBuild.Entries = data.Entries
        DataBus.LearningData = data.LearningData
        return true
    end
    return false
end

function Module_Config.ExportBuild(name)
    local entries = {}
    for id, entry in pairs(DataBus.ActiveBuild.Entries) do
        entries[id] = {
            AnimId = entry.AnimId,
            AnimName = entry.AnimName,
            DelayMs = entry.DelayMs,
            DurationMs = entry.DurationMs,
            DefaultAction = entry.DefaultAction,
            Markers = entry.Markers,
            MinDuration = entry.MinDuration
        }
    end
    
    local export = {
        Name = name,
        ExportedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        ExportedBy = game:GetService("Players").LocalPlayer.Name,
        Game = game.Name,
        Entries = entries
    }
    
    local json = HttpService:JSONEncode(export)
    if writefile then writefile(EXPORT_PATH .. name .. "_export.json", json) end
    if setclipboard then setclipboard(json) end
    return json
end

function Module_Config.ImportBuild(jsonOrPath)
    local success, data = pcall(function()
        if jsonOrPath:sub(1, 1) == "{" then
            return HttpService:JSONDecode(jsonOrPath)
        else
            return HttpService:JSONDecode(readfile(jsonOrPath))
        end
    end)
    
    if success and data.Entries then
        -- Imported timing treated as manual override
        for id, entry in pairs(data.Entries) do
            DataBus.ActiveBuild.Entries[id] = entry
            
            -- Initialize LearningRecord as ManualOverride
            DataBus.LearningData[id] = {
                AnimId = id,
                AnimName = entry.AnimName,
                Successes = 0,
                Failures = 0,
                ConsecutiveStreak = 0,
                Confidence = 0.75,
                Locked = false,
                WindowMs = entry.DelayMs,
                WindowSamples = {},
                ManualOverride = true,
                ManualWindowMs = entry.DelayMs,
                TotalEncounters = 0
            }
        end
        return true
    end
    return false, "Invalid build data"
end

function Module_Config.GetSavedConfigs()
    if not listfiles then return {} end
    local files = listfiles(CONFIG_PATH)
    local names = {}
    for _, file in ipairs(files) do
        table.insert(names, file:match("([^/\\]+)%.json$"))
    end
    return names
end

function Module_Config.GetSavedBuilds()
    if not listfiles then return {} end
    local files = listfiles(BUILD_PATH)
    local names = {}
    for _, file in ipairs(files) do
        table.insert(names, file:match("([^/\\]+)%.json$"))
    end
    return names
end

return Module_Config
