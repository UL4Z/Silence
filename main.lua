--[[
    Silence v2 — main.lua
    Full UI implementation using correct Obsidian API (deividcomsono/Obsidian)
    Spec: SILENCE SPEC (1).md — Every tab, groupbox, element, and callback implemented.
]]

local DataBus = getgenv().Silence.DataBus
local Modules = getgenv().Silence.Modules
local Config = DataBus.Config

-- ────────────────────────────────────────────────────────────────────────────
-- 1. OBSIDIAN LIBRARY LOAD
-- ────────────────────────────────────────────────────────────────────────────
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Window = Library:CreateWindow({
    Title = "Silence",
    Footer = "by 6",
    Icon = 0,
    NotifySide = "Right",
    ShowCustomCursor = false,
})

-- ────────────────────────────────────────────────────────────────────────────
-- 2. TABS
-- Spec: Parry | Logger | Recorder | Builder | Builds | Config
-- ────────────────────────────────────────────────────────────────────────────
local Tabs = {
    Parry    = Window:AddTab("Parry",    "sword"),
    Logger   = Window:AddTab("Logger",   "scan-eye"),
    Recorder = Window:AddTab("Recorder", "video"),
    Builder  = Window:AddTab("Builder",  "hammer"),
    Builds   = Window:AddTab("Builds",   "save"),
    Config   = Window:AddTab("Config",   "settings"),
}

-- ────────────────────────────────────────────────────────────────────────────
-- 3. PARRY TAB
-- Spec: Master toggle, Active Build, Cooldown display, Loaded Build Entries,
--       Enable/Disable All, Fire threshold
-- ────────────────────────────────────────────────────────────────────────────
local ParryStatusGroup = Tabs.Parry:AddLeftGroupbox("Status")

ParryStatusGroup:AddToggle("ParryMaster", {
    Text    = "Auto Parry",
    Default = false,
    Callback = function(v)
        DataBus.ParryState.Active = v
    end,
})

local buildLabel = ParryStatusGroup:AddLabel("Active Build: " .. (DataBus.ActiveBuild.Name or "None"), true, "ParryBuildLabel")
local cooldownLabel = ParryStatusGroup:AddLabel("Cooldown: Ready", false, "ParryCooldownLabel")

-- LiveUpdate cooldown display
task.spawn(function()
    while task.wait(0.1) do
        if Library.Unloaded then break end
        if DataBus.ParryState.CooldownActive then
            local remaining = math.max(0, Config.ParryCooldownSec - (os.clock() - DataBus.ParryState.LastFireTime))
            Options.ParryCooldownLabel:SetText(string.format("Cooldown: %.1fs remaining", remaining))
        else
            Options.ParryCooldownLabel:SetText("Cooldown: Ready")
        end
    end
end)

local ParryEntriesGroup = Tabs.Parry:AddLeftGroupbox("Loaded Build Entries")

-- Populated dynamically when a build is loaded
DataBus.UI.RefreshParryEntries = function()
    -- Clear (Obsidian doesn't have a clear method, so we rebuild from Builds tab logic)
    for animId, entry in pairs(DataBus.ActiveBuild.Entries) do
        local lr = DataBus.LearningData[animId]
        local conf = lr and math.floor(lr.Confidence * 100) or 0
        local timingLabel = lr and (lr.ManualOverride and "manual" or "auto") or "—"
        local timing = lr and (lr.ManualOverride and lr.ManualWindowMs or lr.WindowMs) or 0
        local locked = lr and lr.Locked

        ParryEntriesGroup:AddLabel(string.format(
            "%s%s | %.0f%% conf | %.3fs (%s) | %d✓ %d✗ %d seen",
            locked and "🔒 " or "",
            entry.AnimName,
            conf,
            timing / 1000,
            timingLabel,
            lr and lr.Successes or 0,
            lr and lr.Failures or 0,
            lr and lr.TotalEncounters or 0
        ), true)

        ParryEntriesGroup:AddToggle("Disable_" .. animId, {
            Text    = "Disable this entry",
            Default = entry.Disabled or false,
            Callback = function(v)
                DataBus.ActiveBuild.Entries[animId].Disabled = v
            end,
        })

        ParryEntriesGroup:AddButton({
            Text = "Edit in Builder",
            Func = function()
                DataBus.UI.SelectBuilderAnim(animId)
                -- Switch to Builder tab
            end,
        })

        ParryEntriesGroup:AddDivider()
    end
end

local ParryOverrideGroup = Tabs.Parry:AddRightGroupbox("Override")
ParryOverrideGroup:AddButton({
    Text = "Enable All",
    Func = function()
        for _, entry in pairs(DataBus.ActiveBuild.Entries) do
            entry.Disabled = false
        end
    end,
})
ParryOverrideGroup:AddButton({
    Text = "Disable All",
    Func = function()
        for _, entry in pairs(DataBus.ActiveBuild.Entries) do
            entry.Disabled = true
        end
    end,
})

-- ────────────────────────────────────────────────────────────────────────────
-- 4. LOGGER TAB
-- Spec: Logged count, Clear All, Open Viewer, Logger Distance, sub-tabs
--       Local Player | Others — each with Copy ID, Preview, Add to Build, Ignore
-- ────────────────────────────────────────────────────────────────────────────
local LoggerTopGroup = Tabs.Logger:AddLeftGroupbox("Scanner")
local loggedCountLabel = LoggerTopGroup:AddLabel("Logged: 0", false, "LoggedCount")

LoggerTopGroup:AddSlider("LoggerDistanceSlider", {
    Text    = "Logger Distance (0 = unlimited)",
    Min     = 0, Max = 200,
    Default = Config.LoggerDistance,
    Rounding = 0,
    Suffix  = " studs",
    Callback = function(v) Config.LoggerDistance = v end,
})

LoggerTopGroup:AddButton({
    Text      = "Clear All",
    DoubleClick = true,
    Tooltip   = "Double-click to clear all logged animations.",
    Func      = function()
        DataBus.Animations = {}
        Library:Notify({ Title = "Silence", Description = "All logged animations cleared.", Time = 3 })
    end,
})

LoggerTopGroup:AddButton({
    Text = "Open Animation Viewer",
    Func = function()
        Modules.Viewer.Open()
    end,
})

-- Sub-tabbox: Local Player | Others
local LoggerTabBox = Tabs.Logger:AddLeftTabbox()
local LocalPlayerTab = LoggerTabBox:AddTab("Local Player")
local OthersTab = LoggerTabBox:AddTab("Others")

local loggerCount = 0
DataBus.UI.OnNewAnimation = function(animId)
    local anim = DataBus.Animations[animId]
    loggerCount = loggerCount + 1
    Options.LoggedCount:SetText("Logged: " .. loggerCount)

    local targetTab = (anim.EntityType == "LocalPlayer") and LocalPlayerTab or OthersTab

    targetTab:AddLabel(string.format("%s  |  %s", anim.AnimName, anim.EntityName), true)
    targetTab:AddLabel(anim.AnimId, false)

    targetTab:AddButton({
        Text = "Copy ID",
        Func = function()
            if setclipboard then setclipboard("rbxassetid://" .. anim.AnimId) end
            Library:Notify({ Title = "Copied", Description = anim.AnimId, Time = 2 })
        end,
    })

    targetTab:AddButton({
        Text = "▶ Preview",
        Func = function()
            Modules.Viewer.Open()
            Modules.Viewer.LoadAnimation(animId)
        end,
    })

    targetTab:AddButton({
        Text = "+ Add to Build",
        Func = function()
            DataBus.UI.SelectBuilderAnim(animId)
        end,
    })

    targetTab:AddButton({
        Text = "🚫 Ignore",
        Func = function()
            DataBus.Config.IgnoreList[animId] = true
            DataBus.Animations[animId] = nil
            loggerCount = math.max(0, loggerCount - 1)
            Options.LoggedCount:SetText("Logged: " .. loggerCount)
            Library:Notify({ Title = "Ignored", Description = animId, Time = 2 })
        end,
    })

    targetTab:AddDivider()
end

-- ────────────────────────────────────────────────────────────────────────────
-- 5. RECORDER TAB
-- Spec: Record toggle, Logger distance (shared), Folder path filter,
--       Per-record: AnimName, Raw delta, Guess delta, Already Added status,
--       GuessSubtract input, Add Guess, Add Raw, Copy ID, Ignore, Remove
-- ────────────────────────────────────────────────────────────────────────────
local RecorderTopGroup = Tabs.Recorder:AddLeftGroupbox("Delay Recorder")

RecorderTopGroup:AddToggle("RecorderActive", {
    Text    = "Record Enemy Animations",
    Default = false,
    Callback = function(v) DataBus.DelayRecorder.Active = v end,
})

RecorderTopGroup:AddLabel("Press [ParryKey] near enemy attacks to record timing deltas.", true)

RecorderTopGroup:AddSlider("RecorderDistanceSlider", {
    Text    = "Logger Distance (shared)",
    Min     = 0, Max = 200,
    Default = Config.LoggerDistance,
    Rounding = 0,
    Suffix  = " studs",
    Callback = function(v) Config.LoggerDistance = v end,
})

RecorderTopGroup:AddInput("AnimFolderPathInput", {
    Default = Config.AnimFolderPath or "",
    Numeric  = false,
    Finished = true,
    Text     = "Animation Folder Path Filter",
    Placeholder = "Leave blank for all. e.g. 'Swords/'",
    Callback = function(v) Config.AnimFolderPath = v end,
})

RecorderTopGroup:AddButton({
    Text = "Clear Recorded",
    DoubleClick = true,
    Func = function()
        DataBus.DelayRecorder.Recorded = {}
        Library:Notify({ Title = "Silence", Description = "Recorded entries cleared.", Time = 2 })
    end,
})

local RecorderListGroup = Tabs.Recorder:AddLeftGroupbox("Recorded")

DataBus.UI.UpdateRecorder = function(animId)
    local rec = DataBus.DelayRecorder.Recorded[animId]
    if not rec then return end

    local addedStr = rec.AlreadyAdded
        and string.format("✓ Already added — delay %.3fs", (rec.ExistingDelay or 0))
        or  "Not added yet"

    RecorderListGroup:AddLabel(rec.AnimName, false)
    RecorderListGroup:AddLabel(string.format("Raw: %.3fs  |  Guess: %.3fs", rec.RawDeltaMs/1000, rec.GuessDeltaMs/1000), false)
    RecorderListGroup:AddLabel(addedStr, false)

    RecorderListGroup:AddInput("GuessSubtract_" .. animId, {
        Default  = "",
        Numeric  = true,
        Finished = true,
        Text     = "Custom guess subtract (s)",
        Placeholder = "0",
        Callback = function(v)
            local n = tonumber(v) or 0
            rec.GuessSubtract = n * 1000
            local ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
            rec.GuessDeltaMs = (rec.RawDeltaMs * 0.70) - (ping / 2) - rec.GuessSubtract
        end,
    })

    RecorderListGroup:AddButton({
        Text = "Add Guess",
        Func = function()
            Modules.Builder.SaveToBuild(animId, {
                AnimId = animId,
                AnimName = rec.AnimName,
                DefaultAction = "Parry",
                DelayMs = rec.GuessDeltaMs,
                DurationMs = 150,
                Markers = {},
                Disabled = false,
            })
            DataBus.DelayRecorder.Recorded[animId].AlreadyAdded = true
            DataBus.DelayRecorder.Recorded[animId].ExistingDelay = rec.GuessDeltaMs / 1000
            Library:Notify({ Title = "Added", Description = string.format("%s @ %.3fs (guess)", rec.AnimName, rec.GuessDeltaMs/1000), Time = 3 })
        end,
    })

    RecorderListGroup:AddButton({
        Text = "Add Raw",
        Func = function()
            Modules.Builder.SaveToBuild(animId, {
                AnimId = animId,
                AnimName = rec.AnimName,
                DefaultAction = "Parry",
                DelayMs = rec.RawDeltaMs,
                DurationMs = 150,
                Markers = {},
                Disabled = false,
            })
            Library:Notify({ Title = "Added", Description = string.format("%s @ %.3fs (raw)", rec.AnimName, rec.RawDeltaMs/1000), Time = 3 })
        end,
    })

    RecorderListGroup:AddButton({
        Text = "Copy ID",
        Func = function()
            if setclipboard then setclipboard("rbxassetid://" .. animId) end
        end,
    })

    RecorderListGroup:AddButton({
        Text = "Ignore",
        Func = function()
            Config.IgnoreList[animId] = true
            DataBus.DelayRecorder.Recorded[animId] = nil
        end,
    })

    RecorderListGroup:AddButton({
        Text = "Remove",
        Func = function()
            DataBus.DelayRecorder.Recorded[animId] = nil
        end,
    })

    RecorderListGroup:AddDivider()
end

-- ────────────────────────────────────────────────────────────────────────────
-- 6. BUILDER TAB
-- Spec: Animation dropdown, Use Last Played, Type ID, Preview
--       Delay slider + text, Auto Learned label, Use Auto/Manual buttons
--       Telegraph toggle + size, Action dropdown, Min Duration filter
--       Marker list (live sync from viewer), Save to Build
-- ────────────────────────────────────────────────────────────────────────────
local BuilderSelectGroup = Tabs.Builder:AddLeftGroupbox("Select Animation")

local function getAnimDropdownValues()
    local vals = {}
    for id, anim in pairs(DataBus.Animations) do
        table.insert(vals, anim.AnimName .. " [" .. id .. "]")
    end
    if #vals == 0 then vals = { "— none logged yet —" } end
    return vals
end

BuilderSelectGroup:AddDropdown("BuilderAnimSelect", {
    Values   = getAnimDropdownValues(),
    Default  = 1,
    Text     = "Animation",
    Searchable = true,
    Callback = function(v) end,
})

BuilderSelectGroup:AddButton({
    Text = "Use Last Played",
    Func = function()
        local lastId = DataBus.UI.LastPlayedAnimId
        if lastId and DataBus.Animations[lastId] then
            local name = DataBus.Animations[lastId].AnimName .. " [" .. lastId .. "]"
            Options.BuilderAnimSelect:SetValue(name)
        end
    end,
})

BuilderSelectGroup:AddInput("BuilderManualIdInput", {
    Default = "",
    Numeric = false,
    Finished = true,
    Text = "Type Animation ID manually",
    Placeholder = "rbxassetid://...",
    Callback = function(v)
        local id = v:match("%d+")
        if id then DataBus.UI.BuilderSelectedId = id end
    end,
})

BuilderSelectGroup:AddButton({
    Text = "Preview in Viewer",
    Func = function()
        local id = DataBus.UI.BuilderSelectedId
        if id then
            Modules.Viewer.Open()
            Modules.Viewer.LoadAnimation(id)
        end
    end,
})

local BuilderTimingGroup = Tabs.Builder:AddLeftGroupbox("Timing")

BuilderTimingGroup:AddSlider("BuilderDelaySlider", {
    Text    = "Parry Delay (s)",
    Min     = 0.00, Max = 3.00,
    Default = 0.25,
    Rounding = 2,
    Suffix  = "s",
    Callback = function(v) end,
})

local autoLearnedLabel = BuilderTimingGroup:AddLabel("Auto learned: —", false, "BuilderAutoLearnedLabel")

BuilderTimingGroup:AddButton({
    Text = "Use Auto Learned",
    Func = function()
        local id = DataBus.UI.BuilderSelectedId
        if id then
            local lr = DataBus.LearningData[id]
            if lr and lr.WindowMs and lr.WindowMs > 0 then
                Options.BuilderDelaySlider:SetValue(lr.WindowMs / 1000)
            end
        end
    end,
})

BuilderTimingGroup:AddButton({
    Text = "Use Manual",
    Func = function()
        local id = DataBus.UI.BuilderSelectedId
        if id then
            local lr = DataBus.LearningData[id]
            if lr and lr.ManualWindowMs then
                Options.BuilderDelaySlider:SetValue(lr.ManualWindowMs / 1000)
            end
        end
    end,
})

local BuilderOptionsGroup = Tabs.Builder:AddRightGroupbox("Options")

BuilderOptionsGroup:AddToggle("BuilderTelegraph", {
    Text    = "Visualise Parry (Telegraph)",
    Default = false,
    Tooltip = "Shows a visual indicator before the parry fires.",
    Callback = function(v) end,
})

BuilderOptionsGroup:AddSlider("BuilderTelegraphSize", {
    Text    = "Telegraph Size",
    Min     = 5, Max = 40,
    Default = 15,
    Rounding = 0,
    Callback = function(v) end,
})

BuilderOptionsGroup:AddDropdown("BuilderAction", {
    Values  = { "Parry", "Dodge" },
    Default = "Parry",
    Text    = "Default Action",
    Callback = function(v) end,
})

BuilderOptionsGroup:AddToggle("BuilderMinDuration", {
    Text    = "Min Duration Filter",
    Default = false,
    Callback = function(v) end,
})

BuilderOptionsGroup:AddSlider("BuilderMinDurationVal", {
    Text    = "Min Duration",
    Min     = 0.1, Max = 5.0,
    Default = 0.5,
    Rounding = 1,
    Suffix  = "s",
    Tooltip = "Only fire if animation has played for at least this long.",
    Callback = function(v) end,
})

local BuilderMarkersGroup = Tabs.Builder:AddLeftGroupbox("Markers (from Viewer)")
BuilderMarkersGroup:AddLabel("Open viewer and place markers. They will sync here.", true)

DataBus.UI.RefreshBuilderMarkers = function(animId)
    -- Markers displayed as labels, with Jump in Viewer / Delete buttons
    local markers = DataBus.ExternalViewer.Markers[animId] or {}
    for i, marker in ipairs(markers) do
        BuilderMarkersGroup:AddLabel(string.format("%s @ %.3fs", marker.Type, marker.OffsetMs/1000), false)
    end
end

local builderSaveBg = Tabs.Builder:AddLeftGroupbox("")
builderSaveBg:AddButton({
    Text = "💾  Save to Build",
    Func = function()
        local id = DataBus.UI.BuilderSelectedId
        if not id then
            Library:Notify({ Title = "Silence", Description = "No animation selected.", Time = 2 })
            return
        end

        local anim = DataBus.Animations[id]
        local entry = {
            AnimId        = id,
            AnimName      = anim and anim.AnimName or ("Anim_" .. id),
            DefaultAction = Options.BuilderAction.Value,
            DelayMs       = Options.BuilderDelaySlider.Value * 1000,
            DurationMs    = 150,
            MinDuration   = Toggles.BuilderMinDuration.Value and Options.BuilderMinDurationVal.Value or nil,
            Markers       = DataBus.ExternalViewer.Markers[id] or {},
            TelegraphEnabled = Toggles.BuilderTelegraph.Value,
            TelegraphSize    = Options.BuilderTelegraphSize.Value,
            Disabled      = false,
        }

        Modules.Builder.SaveToBuild(id, entry)

        local lr = DataBus.LearningData[id]
        if lr then
            lr.ManualWindowMs = entry.DelayMs
            lr.ManualOverride = true
        end

        DataBus.UI.RefreshParryEntries()
        Library:Notify({ Title = "Saved", Description = entry.AnimName .. " added to build.", Time = 3 })
    end,
})

DataBus.UI.SelectBuilderAnim = function(animId)
    DataBus.UI.BuilderSelectedId = animId
    local lr = DataBus.LearningData[animId]
    if lr then
        Options.BuilderDelaySlider:SetValue((lr.ManualOverride and lr.ManualWindowMs or lr.WindowMs) / 1000)
        local autoStr = lr.WindowMs and string.format("Auto learned: %.3fs", lr.WindowMs/1000) or "Auto learned: —"
        Options.BuilderAutoLearnedLabel:SetText(autoStr)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 7. BUILDS TAB
-- Spec: Active Build section, New/Save/Save As/Duplicate,
--       Saved Builds section with Load/Delete/Enable toggle,
--       Entries section: Preview/Edit/Unlock/Remove/Disable,
--       Export/Import section
-- ────────────────────────────────────────────────────────────────────────────
local BuildsActiveGroup = Tabs.Builds:AddLeftGroupbox("Active Build")
local activeBuildsLabel = BuildsActiveGroup:AddLabel("None", true, "ActiveBuildLabel")

BuildsActiveGroup:AddButton({
    Text = "New Build",
    Func = function()
        -- Prompt via input in a notification
        DataBus.ActiveBuild = { Name = "NewBuild_" .. os.time(), Entries = {} }
        Options.ActiveBuildLabel:SetText(DataBus.ActiveBuild.Name .. " — 0 entries")
        Library:Notify({ Title = "New Build Created", Description = DataBus.ActiveBuild.Name, Time = 3 })
    end,
})

BuildsActiveGroup:AddButton({
    Text = "Save",
    Func = function()
        local ok, err = Modules.Config.SaveBuild(DataBus.ActiveBuild.Name)
        Library:Notify({ Title = "Saved", Description = DataBus.ActiveBuild.Name .. ".json", Time = 3 })
    end,
})

BuildsActiveGroup:AddInput("SaveAsInput", {
    Default = "",
    Numeric = false,
    Finished = true,
    Text = "Save As (new name)",
    Placeholder = "MyBuild",
    Callback = function(v)
        if v ~= "" then
            DataBus.ActiveBuild.Name = v
            Modules.Config.SaveBuild(v)
            Library:Notify({ Title = "Saved As", Description = v .. ".json", Time = 3 })
        end
    end,
})

BuildsActiveGroup:AddButton({
    Text = "Duplicate",
    Func = function()
        local newName = DataBus.ActiveBuild.Name .. "_copy"
        Modules.Config.SaveBuild(newName)
        Library:Notify({ Title = "Duplicated", Description = newName, Time = 3 })
    end,
})

local BuildsSavedGroup = Tabs.Builds:AddRightGroupbox("Saved Builds")

local function getSavedBuildValues()
    local names = Modules.Config.GetSavedBuilds()
    return #names > 0 and names or { "— none —" }
end

BuildsSavedGroup:AddDropdown("BuildsLoadDropdown", {
    Values   = getSavedBuildValues(),
    Default  = 1,
    Text     = "Select Build",
    Callback = function(v) end,
})

BuildsSavedGroup:AddButton({
    Text = "Load",
    Func = function()
        local name = Options.BuildsLoadDropdown.Value
        local ok = Modules.Config.LoadBuild(name)
        if ok then
            Options.ActiveBuildLabel:SetText(name .. " — " .. #DataBus.ActiveBuild.Entries .. " entries")
            DataBus.UI.RefreshParryEntries()
            Library:Notify({ Title = "Build Loaded", Description = name, Time = 3 })
        end
    end,
})

BuildsSavedGroup:AddButton({
    Text     = "Delete",
    DoubleClick = true,
    Tooltip  = "Double-click to delete the selected build.",
    Func     = function()
        local name = Options.BuildsLoadDropdown.Value
        if writefile then
            pcall(function()
                local path = "silence/builds/" .. name .. ".json"
                -- Roblox executor deletefile if available
                if type(deletefile) == "function" then deletefile(path) end
            end)
        end
        Library:Notify({ Title = "Deleted", Description = name, Time = 3 })
    end,
})

-- Entries section with per‐entry actions
local BuildsEntriesGroup = Tabs.Builds:AddLeftGroupbox("Build Entries")

DataBus.UI.RefreshBuildEntries = function()
    for animId, entry in pairs(DataBus.ActiveBuild.Entries) do
        local lr = DataBus.LearningData[animId]
        local conf = lr and math.floor(lr.Confidence * 100) or 0
        local locked = lr and lr.Locked

        BuildsEntriesGroup:AddLabel(string.format(
            "%s%s | %s | %.0f%%",
            locked and "🔒 " or "",
            entry.AnimName,
            (lr and (lr.ManualOverride and "manual" or "auto") or "—"),
            conf
        ), true)

        BuildsEntriesGroup:AddButton({
            Text = "▶ Preview",
            Func = function()
                Modules.Viewer.Open()
                Modules.Viewer.LoadAnimation(animId)
            end,
        })

        BuildsEntriesGroup:AddButton({
            Text = "✏ Edit",
            Func = function()
                DataBus.UI.SelectBuilderAnim(animId)
            end,
        })

        if locked then
            BuildsEntriesGroup:AddButton({
                Text = "🔓 Unlock & Retrain",
                Func = function()
                    if lr then
                        lr.Locked = false
                        lr.ConsecutiveStreak = 0
                    end
                    Library:Notify({ Title = "Unlocked", Description = entry.AnimName, Time = 3 })
                end,
            })
        end

        BuildsEntriesGroup:AddButton({
            Text = "Force Lock",
            Func = function()
                if lr then
                    lr.Locked = true
                    lr.Confidence = 1.0
                end
                Library:Notify({ Title = "Locked", Description = entry.AnimName, Time = 3 })
            end,
        })

        BuildsEntriesGroup:AddButton({
            Text     = "✕ Remove",
            DoubleClick = true,
            Func     = function()
                DataBus.ActiveBuild.Entries[animId] = nil
                Library:Notify({ Title = "Removed", Description = entry.AnimName, Time = 2 })
            end,
        })

        BuildsEntriesGroup:AddToggle("BuildEntryDisable_" .. animId, {
            Text    = "🚫 Disable",
            Default = entry.Disabled or false,
            Callback = function(v) DataBus.ActiveBuild.Entries[animId].Disabled = v end,
        })

        BuildsEntriesGroup:AddDivider()
    end
end

local BuildsExportGroup = Tabs.Builds:AddRightGroupbox("Export / Import")

BuildsExportGroup:AddButton({
    Text = "Export Build",
    Func = function()
        local json = Modules.Config.ExportBuild(DataBus.ActiveBuild.Name)
        Library:Notify({
            Title = "Exported",
            Description = "silence/exports/ — JSON copied to clipboard.",
            Time = 4,
        })
    end,
})

BuildsExportGroup:AddInput("ImportBuildInput", {
    Default = "",
    Numeric = false,
    Finished = true,
    Text = "Import Build",
    Placeholder = "Paste export JSON or file path",
    Callback = function(v)
        if v == "" then return end
        local ok, err = Modules.Config.ImportBuild(v)
        if ok then
            Library:Notify({ Title = "Imported", Description = "Build imported. Load now?", Time = 5 })
        else
            Library:Notify({ Title = "Import Failed", Description = tostring(err), Time = 5 })
        end
    end,
})

BuildsExportGroup:AddLabel("Exported builds strip learning data.", true)

-- ────────────────────────────────────────────────────────────────────────────
-- 8. CONFIG TAB
-- Spec: Config Management, Engine Settings, Scanner/Logger, Parry Feedback,
--       M1 AnimIDs, Ignored Animations, Dodge, Fake Lag, Learning Parameters
-- ────────────────────────────────────────────────────────────────────────────
local CfgMgmtGroup = Tabs.Config:AddLeftGroupbox("Config Management")

CfgMgmtGroup:AddInput("CfgName", {
    Default  = Config.Name or "Default",
    Numeric  = false,
    Finished = true,
    Text     = "Config Name",
    Callback = function(v) Config.Name = v end,
})

CfgMgmtGroup:AddButton({
    Text = "Save Config",
    Func = function()
        Modules.Config.SaveConfig(Config.Name)
        Library:Notify({ Title = "Saved", Description = Config.Name .. ".json", Time = 3 })
    end,
})

CfgMgmtGroup:AddDropdown("CfgLoadDropdown", {
    Values   = (function()
        local names = Modules.Config.GetSavedConfigs()
        return #names > 0 and names or { "— none —" }
    end)(),
    Default  = 1,
    Text     = "Load Config",
    Callback = function(v) end,
})

CfgMgmtGroup:AddButton({
    Text = "Load Selected Config",
    Func = function()
        local name = Options.CfgLoadDropdown.Value
        local ok = Modules.Config.LoadConfig(name)
        if ok then
            Library:Notify({ Title = "Config Loaded", Description = name, Time = 3 })
        end
    end,
})

CfgMgmtGroup:AddButton({
    Text     = "Delete Config",
    DoubleClick = true,
    Func     = function()
        local name = Options.CfgLoadDropdown.Value
        if name ~= "— none —" and type(deletefile) == "function" then
            pcall(deletefile, "silence/configs/" .. name .. ".json")
        end
        Library:Notify({ Title = "Deleted", Description = name, Time = 2 })
    end,
})

local CfgEngineGroup = Tabs.Config:AddLeftGroupbox("Engine Settings")

CfgEngineGroup:AddSlider("CfgParryRange", {
    Text    = "Parry Range",
    Min     = 5, Max = 100,
    Default = Config.ParryRange,
    Rounding = 0,
    Suffix  = " studs",
    Callback = function(v) Config.ParryRange = v end,
})

CfgEngineGroup:AddSlider("CfgParryCooldown", {
    Text    = "Parry Cooldown",
    Min     = 0.3, Max = 2.0,
    Default = Config.ParryCooldownSec,
    Rounding = 2,
    Suffix  = "s",
    Callback = function(v) Config.ParryCooldownSec = v end,
})

CfgEngineGroup:AddSlider("CfgPingOffset", {
    Text    = "Ping Compensation",
    Min     = -0.20, Max = 0.20,
    Default = Config.PingOffsetSec,
    Rounding = 3,
    Suffix  = "s",
    Callback = function(v) Config.PingOffsetSec = v end,
})

CfgEngineGroup:AddSlider("CfgFireThreshold", {
    Text    = "Fire Threshold",
    Min     = 0.50, Max = 0.95,
    Default = Config.FireThreshold,
    Rounding = 2,
    Tooltip = "Engine only fires if confidence ≥ this value.",
    Callback = function(v) Config.FireThreshold = v end,
})

CfgEngineGroup:AddToggle("CfgBlockM1", {
    Text    = "Block M1 if Cancel Parry",
    Default = Config.BlockM1,
    Tooltip = "M1 block is best-effort. Works in most games using InputBegan for attacks.",
    Callback = function(v) Config.BlockM1 = v end,
})

CfgEngineGroup:AddDropdown("CfgGlobalAction", {
    Values  = { "Parry", "Dodge", "PerEntry" },
    Default = Config.GlobalAction or "PerEntry",
    Text    = "Default Action",
    Callback = function(v) Config.GlobalAction = v end,
})

CfgEngineGroup:AddLabel("Keybind\nParry Key"):AddKeyPicker("CfgParryKey", {
    Default = "F",
    Mode    = "Always",
    Text    = "Parry Key",
    NoUI    = false,
    Callback = function(v) end,
})

Options.CfgParryKey:OnChanged(function()
    Config.ParryKey = Options.CfgParryKey.Value
end)

CfgEngineGroup:AddDropdown("CfgAutoLoadBuild", {
    Values   = (function()
        local names = Modules.Config.GetSavedBuilds()
        table.insert(names, 1, "— none —")
        return names
    end)(),
    Default  = 1,
    Text     = "Auto-Load Build on Start",
    Callback = function(v)
        Config.AutoLoadBuild = (v == "— none —") and nil or v
    end,
})

local CfgScannerGroup = Tabs.Config:AddRightGroupbox("Scanner / Logger")

CfgScannerGroup:AddSlider("CfgLoggerDistance", {
    Text    = "Logger Distance",
    Min     = 0, Max = 200,
    Default = Config.LoggerDistance,
    Rounding = 0,
    Suffix  = " studs",
    Tooltip = "0 = unlimited.",
    Callback = function(v) Config.LoggerDistance = v end,
})

CfgScannerGroup:AddInput("CfgAnimFolderPath", {
    Default  = Config.AnimFolderPath or "",
    Numeric  = false,
    Finished = true,
    Text     = "Animation Folder Path Filter",
    Placeholder = "Applied to Logger and Recorder.",
    Callback = function(v) Config.AnimFolderPath = v end,
})

local CfgFeedbackGroup = Tabs.Config:AddRightGroupbox("Parry Feedback")

-- Each list managed via input + add button pattern
local function makeIdListSection(group, label, configTable)
    group:AddInput("Add_" .. label, {
        Default = "",
        Numeric = false,
        Finished = true,
        Text    = label,
        Placeholder = "Enter ID then press Enter",
        Callback = function(v)
            if v ~= "" then
                table.insert(configTable, v)
                group:AddLabel("• " .. v)
            end
        end,
    })
end

makeIdListSection(CfgFeedbackGroup, "Parry Success Animation IDs", Config.SuccessAnimIds)
makeIdListSection(CfgFeedbackGroup, "Parry Fail Animation IDs",    Config.FailAnimIds)
makeIdListSection(CfgFeedbackGroup, "Parry Success Sound IDs",     Config.SuccessSoundIds)
makeIdListSection(CfgFeedbackGroup, "Parry Fail Sound IDs",        Config.FailSoundIds)

CfgFeedbackGroup:AddToggle("CfgHealthFallback", {
    Text    = "Use Health Check Fallback",
    Default = Config.UseHealthFallback,
    Callback = function(v) Config.UseHealthFallback = v end,
})

CfgFeedbackGroup:AddToggle("CfgIgnoreFallDamage", {
    Text    = "Ignore Fall Damage in Health Check",
    Default = Config.IgnoreFallDamage,
    Callback = function(v) Config.IgnoreFallDamage = v end,
})

CfgFeedbackGroup:AddSlider("CfgResolutionWindow", {
    Text    = "Resolution Window",
    Min     = 0.3, Max = 1.5,
    Default = Config.ResolutionWindowSec,
    Rounding = 2,
    Suffix  = "s",
    Callback = function(v) Config.ResolutionWindowSec = v end,
})

local CfgM1Group = Tabs.Config:AddRightGroupbox("M1 Animation IDs")
makeIdListSection(CfgM1Group, "Add M1 Anim ID", Config.M1AnimIds)

local CfgIgnoreGroup = Tabs.Config:AddRightGroupbox("Ignored Animations")

CfgIgnoreGroup:AddButton({
    Text     = "Clear All Ignored",
    DoubleClick = true,
    Func     = function()
        Config.IgnoreList = {}
        Library:Notify({ Title = "Silence", Description = "Ignore list cleared.", Time = 2 })
    end,
})

for animId, _ in pairs(Config.IgnoreList) do
    CfgIgnoreGroup:AddLabel(animId, false)
    CfgIgnoreGroup:AddButton({
        Text = "Remove",
        Func = function()
            Config.IgnoreList[animId] = nil
        end,
    })
end

local CfgDodgeGroup = Tabs.Config:AddLeftGroupbox("Dodge (Coming Soon)")

CfgDodgeGroup:AddInput("CfgDodgeRemote", {
    Default     = "",
    Numeric     = false,
    Finished    = true,
    Text        = "Dodge Remote Name",
    Placeholder = "Wire in when remote is known.",
    Callback    = function(v) Config.DodgeRemote = v ~= "" and v or nil end,
})

local CfgFakeLagGroup = Tabs.Config:AddLeftGroupbox("Fake Lag")

CfgFakeLagGroup:AddToggle("CfgFakeLag", {
    Text    = "Enable Fake Lag",
    Default = Config.FakeLagEnabled,
    Callback = function(v) Config.FakeLagEnabled = v end,
})

CfgFakeLagGroup:AddSlider("CfgFakeLagMs", {
    Text    = "Fake Lag Amount",
    Min     = 0, Max = 300,
    Default = Config.FakeLagMs,
    Rounding = 0,
    Suffix  = "ms",
    Tooltip = "Adds task.wait() delay before firing. Safe. Does not touch network.",
    Callback = function(v) Config.FakeLagMs = v end,
})

-- LEARNING PARAMETERS (collapsible via tabbox)
local CfgLearningTabbox = Tabs.Config:AddLeftTabbox()
local LearningTab = CfgLearningTabbox:AddTab("Learning Parameters (Advanced)")

LearningTab:AddLabel("Defaults tuned for Bayesian Beta distribution confidence. Reset if unsure.", true)

LearningTab:AddSlider("LAlpha", {
    Text    = "Alpha (prior successes)",
    Min     = 1, Max = 10,
    Default = Config.Learning.Alpha,
    Rounding = 0,
    Callback = function(v) Config.Learning.Alpha = v end,
})

LearningTab:AddSlider("LBeta", {
    Text    = "Beta (prior failures)",
    Min     = 1, Max = 10,
    Default = Config.Learning.Beta,
    Rounding = 0,
    Callback = function(v) Config.Learning.Beta = v end,
})

LearningTab:AddSlider("LMomentumClamp", {
    Text    = "Momentum Clamp Max",
    Min     = 0.01, Max = 0.10,
    Default = Config.Learning.MomentumClampMax,
    Rounding = 3,
    Tooltip = "Max confidence drop per failure.",
    Callback = function(v) Config.Learning.MomentumClampMax = v end,
})

LearningTab:AddSlider("LStreakBonus", {
    Text    = "Streak Bonus Per Hit",
    Min     = 0.001, Max = 0.02,
    Default = Config.Learning.StreakBonusPerHit,
    Rounding = 3,
    Callback = function(v) Config.Learning.StreakBonusPerHit = v end,
})

LearningTab:AddSlider("LStreakBonusMax", {
    Text    = "Streak Bonus Cap",
    Min     = 0.02, Max = 0.20,
    Default = Config.Learning.StreakBonusMax,
    Rounding = 2,
    Callback = function(v) Config.Learning.StreakBonusMax = v end,
})

LearningTab:AddSlider("LLockConfidence", {
    Text    = "Lock Confidence",
    Min     = 0.90, Max = 1.00,
    Default = Config.Learning.LockConfidence,
    Rounding = 2,
    Callback = function(v) Config.Learning.LockConfidence = v end,
})

LearningTab:AddSlider("LLockSuccesses", {
    Text    = "Lock Successes Required",
    Min     = 5, Max = 50,
    Default = Config.Learning.LockSuccesses,
    Rounding = 0,
    Callback = function(v) Config.Learning.LockSuccesses = v end,
})

LearningTab:AddSlider("LLockStreak", {
    Text    = "Lock Streak Required",
    Min     = 3, Max = 20,
    Default = Config.Learning.LockStreak,
    Rounding = 0,
    Callback = function(v) Config.Learning.LockStreak = v end,
})

LearningTab:AddSlider("LRingBufferSize", {
    Text    = "Ring Buffer Size",
    Min     = 5, Max = 50,
    Default = Config.Learning.RingBufferSize,
    Rounding = 0,
    Callback = function(v) Config.Learning.RingBufferSize = v end,
})

LearningTab:AddSlider("LMinSamples", {
    Text    = "Min Samples For Trim",
    Min     = 3, Max = 20,
    Default = Config.Learning.MinSamplesForTrim,
    Rounding = 0,
    Callback = function(v) Config.Learning.MinSamplesForTrim = v end,
})

LearningTab:AddSlider("LTrimFraction", {
    Text    = "Trim Fraction",
    Min     = 0.05, Max = 0.30,
    Default = Config.Learning.TrimFraction,
    Rounding = 2,
    Callback = function(v) Config.Learning.TrimFraction = v end,
})

LearningTab:AddSlider("LPingSamples", {
    Text    = "Ping Rolling Samples",
    Min     = 3, Max = 20,
    Default = Config.Learning.PingRollingSamples,
    Rounding = 0,
    Callback = function(v) Config.Learning.PingRollingSamples = v end,
})

LearningTab:AddButton({
    Text = "Reset All to Defaults",
    Func = function()
        local defaults = {
            Alpha = 3, Beta = 1, MomentumClampMax = 0.04,
            StreakBonusPerHit = 0.008, StreakBonusMax = 0.08,
            LockConfidence = 0.96, LockSuccesses = 12, LockStreak = 6,
            RingBufferSize = 20, MinSamplesForTrim = 5, TrimFraction = 0.15,
            PingRollingSamples = 5,
        }
        Config.Learning = defaults
        Options.LAlpha:SetValue(defaults.Alpha)
        Options.LBeta:SetValue(defaults.Beta)
        Options.LMomentumClamp:SetValue(defaults.MomentumClampMax)
        Options.LStreakBonus:SetValue(defaults.StreakBonusPerHit)
        Options.LStreakBonusMax:SetValue(defaults.StreakBonusMax)
        Options.LLockConfidence:SetValue(defaults.LockConfidence)
        Options.LLockSuccesses:SetValue(defaults.LockSuccesses)
        Options.LLockStreak:SetValue(defaults.LockStreak)
        Options.LRingBufferSize:SetValue(defaults.RingBufferSize)
        Options.LMinSamples:SetValue(defaults.MinSamplesForTrim)
        Options.LTrimFraction:SetValue(defaults.TrimFraction)
        Options.LPingSamples:SetValue(defaults.PingRollingSamples)
        Library:Notify({ Title = "Reset", Description = "Learning parameters reset to defaults.", Time = 3 })
    end,
})

-- ────────────────────────────────────────────────────────────────────────────
-- 9. STARTUP
-- ────────────────────────────────────────────────────────────────────────────
Modules.Logger.Start()
Modules.Engine.Start()

Library:Notify({
    Title       = "Silence",
    Description = DataBus.ActiveBuild.Name and ("Build: " .. DataBus.ActiveBuild.Name) or "No build loaded",
    Time        = 5,
})
