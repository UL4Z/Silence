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

return Module_Config
