--[[
    Module_Viewer.lua (v3 — SILENCE HUB CONSOLIDATION)
    Centralized Standalone Hub for Logger, Hit History, and Preview.
]]

local RunService     = game:GetService("RunService")
local Players        = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService    = game:GetService("HttpService")
local TweenService   = game:GetService("TweenService")

local Module_Viewer = {}
local DataBus = nil

-- ── State ──────────────────────────────────────────────────────────────────
local gui, mainFrame, viewportFrame, worldModel, rigModel, animCamera
local currentTrack = nil
local currentAnimId = nil
local activeViewerTab = "Preview" -- "Preview" | "Logger" | "Hits"
local tabButtons = {}
local tabPanes = {}

local orbitY, orbitX, zoomDist = 30, -15, 10
local isSpinning, isDragging, lastMousePos, isHovering = false, false, nil, false
local isLooping, fpsLockMode = false, "60"

local markers, markerLines = {}, {}

-- ── Helpers ────────────────────────────────────────────────────────────────
local function make(cls, props, parent)
    local i = Instance.new(cls); for k, v in pairs(props) do i[k] = v end
    if parent then i.Parent = parent end; return i
end

local function makeTxt(txt, sz, bold, color, wrap, parent)
    return make("TextLabel", {
        Text = txt, TextSize = sz or 12, Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextColor3 = color or Color3.fromRGB(220, 220, 255), BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = wrap or false, Size = UDim2.new(1, 0, 0, sz and sz + 4 or 16),
    }, parent)
end

local function makeBtn(txt, parent, callback)
    local btn = make("TextButton", {
        Text = txt, TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(210, 210, 255),
        BackgroundColor3 = Color3.fromRGB(45, 45, 80), AutoButtonColor = true, Size = UDim2.new(0, 0, 0, 22), AutomaticSize = Enum.AutomaticSize.X,
    }, parent)
    make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, btn)
    make("UICorner", { CornerRadius = UDim.new(0, 4) }, btn)
    btn.MouseButton1Click:Connect(callback); return btn
end

-- ── Entity Cache ───────────────────────────────────────────────────────────
local function getOrMakeCacheFolder()
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    local folder = pg:FindFirstChild("SilenceEntityCache") or make("Folder", { Name = "SilenceEntityCache" }, pg)
    return folder
end

function Module_Viewer.CacheEntity(animId, sourceModel)
    if not sourceModel then return end
    local cacheFolder = getOrMakeCacheFolder()
    local existing = cacheFolder:FindFirstChild("e_" .. animId)
    if existing then existing:Destroy() end
    sourceModel.Archivable = true
    local clone = sourceModel:Clone()
    clone.Name = "e_" .. animId
    for _, s in ipairs(clone:GetDescendants()) do if s:IsA("Script") or s:IsA("LocalScript") or s:IsA("ModuleScript") then s:Destroy() end end
    for _, p in ipairs(clone:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
    clone.Parent = cacheFolder
    return clone
end

local function getRigForAnim(animId)
    local cached = getOrMakeCacheFolder():FindFirstChild("e_" .. (animId or ""))
    if cached then return cached:Clone() end
    local char = Players.LocalPlayer.Character
    if char then char.Archivable = true; return char:Clone() end
    return Instance.new("Model")
end

-- ── Animation Load ─────────────────────────────────────────────────────────
local animLabel, idLabel
function Module_Viewer.LoadAnimation(animId)
    currentAnimId = animId
    if currentTrack then pcall(function() currentTrack:Stop() end) end
    local anim = DataBus.Animations[animId]
    if animLabel then animLabel.Text = "Playing: " .. (anim and anim.AnimName or "Unknown") end
    if idLabel then idLabel.Text = "ID: rbxassetid://" .. animId end
    local rig = getRigForAnim(animId)
    if rigModel then rigModel:Destroy() end
    rig.Parent = worldModel; rigModel = rig
    local animator = rig:FindFirstChildOfClass("Humanoid") and rig:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator") 
        or make("Animator", {}, rig:FindFirstChildOfClass("Humanoid") or rig)
    local animObj = Instance.new("Animation"); animObj.AnimationId = "rbxassetid://" .. animId
    local ok, track = pcall(function() return animator:LoadAnimation(animObj) end)
    if ok and track then
        currentTrack = track
        track.Stopped:Connect(function() if isLooping and currentTrack == track then task.wait(); pcall(function() track:Play() end) end end)
        markers = DataBus.ExternalViewer.Markers[animId] or {}
        DataBus.ExternalViewer.Markers[animId] = markers
    end
end

-- ── UI Refresh Functions ───────────────────────────────────────────────────
local loggerScroll, hitsScroll

function Module_Viewer.RefreshLogger()
    if not loggerScroll then return end
    for _, c in ipairs(loggerScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    
    local categories = { LocalPlayer = {}, Others = {} }
    for id, anim in pairs(DataBus.Animations) do
        local cat = anim.EntityType == "LocalPlayer" and "LocalPlayer" or "Others"
        table.insert(categories[cat], anim)
    end

    local function renderCat(name, list)
        local frame = make("Frame", { Size = UDim2.new(1, -5, 0, 24), BackgroundColor3 = Color3.fromRGB(35, 35, 55), AutomaticSize = Enum.AutomaticSize.Y }, loggerScroll)
        make("UICorner", { CornerRadius = UDim.new(0, 4) }, frame)
        make("UIListLayout", { Padding = UDim.new(0, 2) }, frame)
        makeTxt("  " .. name, 11, true, Color3.fromRGB(200, 200, 255), false, frame)
        for _, anim in ipairs(list) do
            local row = make("Frame", { Size = UDim2.new(1, -4, 0, 30), BackgroundTransparency = 1 }, frame)
            make("UIListLayout", { FillDirection = "Horizontal", VerticalAlignment = "Center", Padding = UDim.new(0, 5) }, row)
            makeTxt("  " .. anim.AnimName .. " (" .. anim.EntityName .. ")", 10, false, Color3.fromRGB(180, 180, 220), false, row).Size = UDim2.new(0.65, 0, 1, 0)
            makeBtn("▶", row, function() Module_Viewer.SetTab("Preview"); Module_Viewer.LoadAnimation(anim.AnimId) end)
            makeBtn("+", row, function() DataBus.UI.SelectBuilderAnim(anim.AnimId) end)
        end
    end
    renderCat("Local Player", categories.LocalPlayer); renderCat("Others", categories.Others)
end

function Module_Viewer.RefreshHits()
    if not hitsScroll then return end
    for _, c in ipairs(hitsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    for npcName, hits in pairs(DataBus.HitHistory) do
        local frame = make("Frame", { Size = UDim2.new(1, -5, 0, 24), BackgroundColor3 = Color3.fromRGB(35, 35, 55), AutomaticSize = Enum.AutomaticSize.Y }, hitsScroll)
        make("UICorner", { CornerRadius = UDim.new(0, 4) }, frame)
        make("UIListLayout", { Padding = UDim.new(0, 2) }, frame)
        makeTxt("  " .. npcName, 11, true, Color3.fromRGB(200, 200, 255), false, frame)
        for _, hit in ipairs(hits) do
            local row = make("Frame", { Size = UDim2.new(1, -4, 0, 30), BackgroundTransparency = 1 }, frame)
            make("UIListLayout", { FillDirection = "Horizontal", VerticalAlignment = "Center", Padding = UDim.new(0, 5) }, row)
            local anim = DataBus.Animations[hit.AnimId]; local name = anim and anim.AnimName or hit.AnimId
            makeTxt(string.format("  %s: %.2fs", name, hit.TimeIntoAnim), 10, false, Color3.fromRGB(180, 180, 220), false, row).Size = UDim2.new(0.65, 0, 1, 0)
            makeBtn("+ Place", row, function()
                Module_Viewer.SetTab("Preview"); Module_Viewer.LoadAnimation(hit.AnimId)
                table.insert(markers, { Type = "Parry", OffsetMs = hit.TimeIntoAnim * 1000 })
                DataBus.ExternalViewer.Markers[hit.AnimId] = markers
            end)
        end
    end
end

-- ── Tab System ─────────────────────────────────────────────────────────────
function Module_Viewer.SetTab(tabName)
    activeViewerTab = tabName
    for name, btn in pairs(tabButtons) do
        btn.BackgroundColor3 = name == tabName and Color3.fromRGB(80, 80, 140) or Color3.fromRGB(45, 45, 80)
    end
    for name, pane in pairs(tabPanes) do pane.Visible = (name == tabName) end
    if tabName == "Logger" then Module_Viewer.RefreshLogger()
    elseif tabName == "Hits" then Module_Viewer.RefreshHits() end
end

-- ── Open / Build GUI ───────────────────────────────────────────────────────
function Module_Viewer.Open(animId)
    if gui then gui:Destroy() end
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    gui = make("ScreenGui", { Name = "SilenceHub", DisplayOrder = 100, ResetOnSpawn = false }, pg)
    mainFrame = make("Frame", { Size = UDim2.fromOffset(480, 540), Position = UDim2.new(0.5, -240, 0.5, -270), BackgroundColor3 = Color3.fromHex("1A1A2E") }, gui)
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, mainFrame); make("UIStroke", { Color = Color3.fromRGB(80, 80, 140) }, mainFrame)

    -- Title & Tabs
    local topBar = make("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromHex("12122A") }, mainFrame)
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, topBar)
    makeTxt("Silence Hub", 14, true, nil, false, topBar).Position = UDim2.fromOffset(15, 0)
    
    local tabContainer = make("Frame", { Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0.35, 0, 0, 0), BackgroundTransparency = 1 }, topBar)
    make("UIListLayout", { FillDirection = "Horizontal", VerticalAlignment = "Center", Padding = UDim.new(0, 5) }, tabContainer)
    
    for _, t in ipairs({"Preview", "Logger", "Hits"}) do
        tabButtons[t] = makeBtn(t, tabContainer, function() Module_Viewer.SetTab(t) end)
    end
    makeBtn("✕", topBar, function() gui:Destroy() end).Position = UDim2.new(1, -30, 0.5, -11)

    -- Panes
    tabPanes.Preview = make("Frame", { Size = UDim2.new(1, -20, 1, -55), Position = UDim2.new(0, 10, 0, 45), BackgroundTransparency = 1 }, mainFrame)
    tabPanes.Logger  = make("Frame", { Size = UDim2.new(1, -20, 1, -55), Position = UDim2.new(0, 10, 0, 45), BackgroundTransparency = 1, Visible = false }, mainFrame)
    tabPanes.Hits    = make("Frame", { Size = UDim2.new(1, -20, 1, -55), Position = UDim2.new(0, 10, 0, 45), BackgroundTransparency = 1, Visible = false }, mainFrame)

    -- Build Preview Tab (Existing Viewport + Controls)
    viewportFrame = make("ViewportFrame", { Size = UDim2.new(1, 0, 0, 240), BackgroundColor3 = Color3.fromRGB(18, 18, 35) }, tabPanes.Preview)
    worldModel = make("WorldModel", {}, viewportFrame); animCamera = make("Camera", {}, viewportFrame); viewportFrame.CurrentCamera = animCamera
    
    local ctrlRow = make("Frame", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 245), BackgroundTransparency = 1 }, tabPanes.Preview)
    make("UIListLayout", { FillDirection = "Horizontal", Padding = UDim.new(0, 5) }, ctrlRow)
    makeBtn("▶ Play", ctrlRow, function() if currentTrack then pcall(function() currentTrack:AdjustSpeed(1); currentTrack:Play() end) end end)
    makeBtn("⏹ Stop", ctrlRow, function() if currentTrack then pcall(function() currentTrack:AdjustSpeed(0) end) end end)
    
    animLabel = makeTxt("Playing: —", 11, false, nil, false, tabPanes.Preview); animLabel.Position = UDim2.new(0, 0, 0, 275)
    idLabel = makeTxt("ID: —", 10, false, Color3.fromRGB(140, 140, 200), false, tabPanes.Preview); idLabel.Position = UDim2.new(0, 0, 0, 290)

    -- Build Logger Tab
    loggerScroll = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = "Y", ScrollBarThickness = 2 }, tabPanes.Logger)
    make("UIListLayout", { Padding = UDim.new(0, 10) }, loggerScroll)

    -- Build Hits Tab
    hitsScroll = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = "Y", ScrollBarThickness = 2 }, tabPanes.Hits)
    make("UIListLayout", { Padding = UDim.new(0, 10) }, hitsScroll)

    Module_Viewer.SetTab("Preview")
    if animId then Module_Viewer.LoadAnimation(animId) end

    -- Camera / Refresh Loops
    spawn(function()
        while gui and gui.Parent do
            local dt = RunService.RenderStepped:Wait()
            if viewportFrame and viewportFrame.Parent then
                local originCF = rigModel and rigModel.PrimaryPart and CFrame.new(rigModel.PrimaryPart.Position + Vector3.new(0, 1, 0)) or CFrame.new(0, 3, 0)
                animCamera.CFrame = originCF * CFrame.Angles(0, math.rad(orbitY), 0) * CFrame.Angles(math.rad(orbitX), 0, 0) * CFrame.new(0, 0, zoomDist)
                if isSpinning then orbitY = orbitY + 40 * dt end
            end
        end
    end)

    -- Bind Global Updates
    DataBus.UI.OnNewAnimation = function() if activeViewerTab == "Logger" then Module_Viewer.RefreshLogger() end end
    DataBus.UI.UpdateViewerHistory = function() if activeViewerTab == "Hits" then Module_Viewer.RefreshHits() end end
end

function Module_Viewer.Init(bus) DataBus = bus end
return Module_Viewer
