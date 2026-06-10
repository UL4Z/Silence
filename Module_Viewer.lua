--[[
    Module_Viewer.lua (v2 — FULL IMPLEMENTATION)
    External floating Animation Viewer window.
    Spec: SILENCE SPEC (1).md — Module: Animation Viewer (External Window)

    This is NOT an Obsidian tab. It is a standalone ScreenGui styled to match
    Obsidian's dark theme (#1A1A2E) that can be dragged independently.
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
local historyFrame -- NEW: Hit History Panel
local currentTrack = nil
local currentAnimId = nil
local wasPlayingBeforeScrub = false
local isLooping = false
local fpsLockMode = "60"   -- "30" | "60" | "unlimited"
local fpsAccum = 0

local orbitY = 30
local orbitX = -15
local zoomDist = 10
local isSpinning = false
local isDragging = false
local lastMousePos = nil
local isHovering = false

local markers = {}          -- { { Type, OffsetMs, Line (Frame UI ref) }, ... }
local markerLines = {}      -- [i] = Frame element on scrubber

-- Ping rolling average
local pingBuffer = {}
local function getCurrentPing()
    local ok, v = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if not ok then
        ok, v = pcall(function() return game:GetNetworkPing() * 1000 end)
    end
    if ok and v then
        table.insert(pingBuffer, v)
        if #pingBuffer > (DataBus.Config.Learning.PingRollingSamples or 5) then
            table.remove(pingBuffer, 1)
        end
        local s = 0
        for _, p in ipairs(pingBuffer) do s = s + p end
        return s / #pingBuffer
    end
    return 0
end

-- ── Helpers ────────────────────────────────────────────────────────────────
local function make(cls, props, parent)
    local i = Instance.new(cls)
    for k, v in pairs(props) do i[k] = v end
    if parent then i.Parent = parent end
    return i
end

local function makeTxt(txt, sz, bold, color, wrap, parent)
    return make("TextLabel", {
        Text              = txt,
        TextSize          = sz or 12,
        Font              = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextColor3        = color or Color3.fromRGB(220, 220, 255),
        BackgroundTransparency = 1,
        TextXAlignment    = Enum.TextXAlignment.Left,
        TextWrapped       = wrap or false,
        Size              = UDim2.new(1, 0, 0, sz and sz + 4 or 16),
    }, parent)
end

local function makeBtn(txt, parent, callback)
    local btn = make("TextButton", {
        Text       = txt,
        TextSize   = 11,
        Font       = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(210, 210, 255),
        BackgroundColor3 = Color3.fromRGB(45, 45, 80),
        AutoButtonColor  = true,
        Size       = UDim2.new(0, 0, 0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
    }, parent)
    make("UIPadding", {
        PaddingLeft  = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, btn)
    make("UICorner", { CornerRadius = UDim.new(0, 4) }, btn)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- ── Entity Cache ───────────────────────────────────────────────────────────
local CACHE_FOLDER_NAME = "SilenceEntityCache"

local function getOrMakeCacheFolder()
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    local folder = pg:FindFirstChild(CACHE_FOLDER_NAME)
    if not folder then
        folder = make("Folder", { Name = CACHE_FOLDER_NAME }, pg)
    end
    return folder
end

function Module_Viewer.CacheEntity(animId, sourceModel)
    if not sourceModel then return nil end
    local cacheFolder = getOrMakeCacheFolder()

    -- Remove existing cache for this anim
    local existing = cacheFolder:FindFirstChild("e_" .. animId)
    if existing then existing:Destroy() end

    -- Enable archiving so we can clone
    sourceModel.Archivable = true
    local clone = sourceModel:Clone()
    clone.Name = "e_" .. animId

    -- Strip scripts
    for _, s in ipairs(clone:GetDescendants()) do
        if s:IsA("Script") or s:IsA("LocalScript") or s:IsA("ModuleScript") then s:Destroy() end
    end

    -- Anchor rig
    for _, p in ipairs(clone:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = true end
    end

    clone.Parent = cacheFolder
    return clone
end

local function getRigForAnim(animId)
    -- 1. Check local cache first (The real NPC/Player rig)
    local cacheFolder = getOrMakeCacheFolder()
    local cached = cacheFolder:FindFirstChild("e_" .. animId)
    if cached then return cached:Clone() end

    -- 2. Check if it belongs to a player currently in game
    local animRecord = DataBus.Animations[animId]
    if animRecord and animRecord.UserId then
        local player = Players:GetPlayerByUserId(animRecord.UserId)
        if player and player.Character then
            player.Character.Archivable = true
            return player.Character:Clone()
        end
    end

    -- 3. Fallback to LocalPlayer's rig
    local localChar = Players.LocalPlayer.Character
    if localChar then
        localChar.Archivable = true
        return localChar:Clone()
    end

    return Instance.new("Model")
end

-- ── Camera Update ──────────────────────────────────────────────────────────
local cameraConn
local function startCameraLoop()
    if cameraConn then cameraConn:Disconnect() end
    cameraConn = RunService.RenderStepped:Connect(function(dt)
        if not (viewportFrame and viewportFrame.Parent) then
            cameraConn:Disconnect()
            return
        end

        if isSpinning then
            orbitY = orbitY + 40 * dt
        end

        local originCF = rigModel and rigModel.PrimaryPart
            and CFrame.new(rigModel.PrimaryPart.Position + Vector3.new(0, 1, 0))
            or CFrame.new(0, 3, 0)

        animCamera.CFrame = originCF
            * CFrame.Angles(0, math.rad(orbitY), 0)
            * CFrame.Angles(math.rad(orbitX), 0, 0)
            * CFrame.new(0, 0, zoomDist)
    end)
end

-- ── Scrubber & Markers ────────────────────────────────────────────────────
local scrubberBar, scrubberFill, scrubberHandle
local timeLabel

local function updateScrubberVisual(fraction)
    if not scrubberBar then return end
    local w = scrubberBar.AbsoluteSize.X
    scrubberFill.Size = UDim2.new(fraction, 0, 1, 0)
    scrubberHandle.Position = UDim2.new(fraction, -6, 0.5, -6)
end

local function clearMarkerLines()
    for _, ln in ipairs(markerLines) do pcall(function() ln:Destroy() end) end
    markerLines = {}
end

local function redrawMarkers(totalLength)
    clearMarkerLines()
    if not scrubberBar or not totalLength or totalLength <= 0 then return end
    for i, m in ipairs(markers) do
        local frac = math.clamp((m.OffsetMs / 1000) / totalLength, 0, 1)
        local color = m.Type == "Parry" and Color3.fromRGB(100, 160, 255)
            or m.Type == "Dodge" and Color3.fromRGB(255, 165, 60)
            or Color3.fromRGB(255, 80, 80) -- Cancel/Red

        local line = make("Frame", {
            Size = UDim2.new(0, 2, 1, 0),
            Position = UDim2.new(frac, -1, 0, 0),
            BackgroundColor3 = color,
            ZIndex = 5,
        }, scrubberBar)

        -- Click to jump
        line.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                if currentTrack then
                    currentTrack.TimePosition = m.OffsetMs / 1000
                end
            elseif inp.UserInputType == Enum.UserInputType.MouseButton2 then
                table.remove(markers, i)
                redrawMarkers(currentTrack and currentTrack.Length or 1)
                if DataBus.ExternalViewer then
                    DataBus.ExternalViewer.Markers[currentAnimId] = markers
                end
            end
        end)

        table.insert(markerLines, line)
    end
end

local scrubIsDragging = false
local function setupScrubber(container, totalLength)
    -- Container for scrubber
    local barBg = make("Frame", {
        Size = UDim2.new(1, -20, 0, 16),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundColor3 = Color3.fromRGB(30, 30, 55),
    }, container)
    make("UICorner", { CornerRadius = UDim.new(0, 4) }, barBg)

    scrubberBar = barBg

    scrubberFill = make("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(100, 100, 220),
        ZIndex = 2,
    }, barBg)
    make("UICorner", { CornerRadius = UDim.new(0, 4) }, scrubberFill)

    scrubberHandle = make("Frame", {
        Size = UDim2.new(0, 12, 0, 12),
        Position = UDim2.new(0, -6, 0.5, -6),
        BackgroundColor3 = Color3.fromRGB(200, 200, 255),
        ZIndex = 6,
    }, barBg)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, scrubberHandle)

    -- Drag to seek
    barBg.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            scrubIsDragging = true
            wasPlayingBeforeScrub = currentTrack and currentTrack.IsPlaying or false
            if currentTrack and currentTrack.IsPlaying then
                currentTrack:AdjustSpeed(0)
            end
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 and scrubIsDragging then
            scrubIsDragging = false
            if currentTrack and wasPlayingBeforeScrub then
                currentTrack:AdjustSpeed(1)
            end
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if scrubIsDragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            if currentTrack then
                local absPos = barBg.AbsolutePosition.X
                local absSize = barBg.AbsoluteSize.X
                local mouseX = inp.Position.X
                local frac = math.clamp((mouseX - absPos) / absSize, 0, 1)
                currentTrack.TimePosition = frac * currentTrack.Length
            end
        end
    end)
end

-- ── Animation Load ─────────────────────────────────────────────────────────
local animLabel, idLabel

function Module_Viewer.LoadAnimation(animId)
    currentAnimId = animId

    -- Stop existing
    if currentTrack then
        pcall(function() currentTrack:Stop() end)
        currentTrack = nil
    end

    -- Set labels
    local anim = DataBus.Animations[animId]
    if animLabel then
        animLabel.Text = "Playing: " .. (anim and anim.AnimName or "Unknown")
    end
    if idLabel then
        idLabel.Text = "ID: rbxassetid://" .. animId
    end

    -- Get rig
    local rig = getRigForAnim(animId)
    if rigModel then rigModel:Destroy() end
    rig.Parent = worldModel
    rigModel = rig

    -- Load animation
    local animator = rig:FindFirstChildOfClass("Humanoid") and rig:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
    if not animator then
        animator = make("Animator", {}, rig:FindFirstChildOfClass("Humanoid") or rig)
    end

    local animObj = Instance.new("Animation")
    animObj.AnimationId = "rbxassetid://" .. animId

    local ok, track = pcall(function() return animator:LoadAnimation(animObj) end)

    if not ok or not track then
        -- Try default R6 rig fallback
        local fallback = getRigForAnim(nil) -- nil forces default R6
        if rigModel then rigModel:Destroy() end
        fallback.Parent = worldModel
        rigModel = fallback

        local fa = fallback:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
        ok, track = pcall(function() return fa:LoadAnimation(animObj) end)
    end

    if ok and track then
        currentTrack = track

        track.Stopped:Connect(function()
            if isLooping and currentTrack == track then
                task.wait()
                pcall(function() track:Play() end)
            end
        end)

        -- Restore markers for this anim
        if DataBus.ExternalViewer then
            markers = DataBus.ExternalViewer.Markers[animId] or {}
            DataBus.ExternalViewer.Markers[animId] = markers
            DataBus.ExternalViewer.CurrentAnimId = animId
        end

        redrawMarkers(track.Length)
    else
        -- Show overlay
        if viewportFrame then
            local overlay = make("TextLabel", {
                Name = "FailOverlay",
                Text = "Animation could not be loaded for preview",
                TextSize = 13,
                Font = Enum.Font.Gotham,
                TextColor3 = Color3.fromRGB(255, 100, 100),
                BackgroundTransparency = 0.3,
                BackgroundColor3 = Color3.fromRGB(20, 20, 40),
                Size = UDim2.new(1, 0, 0.3, 0),
                Position = UDim2.new(0, 0, 0.35, 0),
                TextWrapped = true,
                ZIndex = 10,
            }, viewportFrame)
            task.delay(3, function() if overlay and overlay.Parent then overlay:Destroy() end end)
        end
    end
end

-- ── Open / Build GUI ───────────────────────────────────────────────────────
function Module_Viewer.Open(animId)
    -- Close existing
    if gui and gui.Parent then gui:Destroy() end

    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    gui = make("ScreenGui", {
        Name = "SilenceViewer",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 100,
    }, pg)

    -- Main window frame
    mainFrame = make("Frame", {
        Size     = UDim2.fromOffset(430, 540),
        Position = UDim2.new(0.5, 10, 0.5, -270),
        BackgroundColor3 = Color3.fromHex("1A1A2E"),
        BorderSizePixel = 0,
    }, gui)
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, mainFrame)
    make("UIStroke", { Color = Color3.fromRGB(80, 80, 140), Thickness = 1 }, mainFrame)

    -- ── Drag logic ──
    local dragging, dragStart, startPos
    mainFrame.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = inp.Position
            startPos  = mainFrame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)

    -- ── Title bar ──
    local titleBar = make("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = Color3.fromHex("12122A"),
        BorderSizePixel = 0,
    }, mainFrame)
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, titleBar)

    makeTxt("Animation Preview", 13, true, Color3.fromRGB(200, 200, 255), false, titleBar)
        .Position = UDim2.fromOffset(10, 0)
    titleBar:FindFirstChildOfClass("TextLabel").Size = UDim2.new(0.5, 0, 1, 0)

    -- Title bar buttons row (right side)
    local titleBtns = make("Frame", {
        Size = UDim2.new(0.5, -10, 1, 0),
        Position = UDim2.new(0.5, 5, 0, 0),
        BackgroundTransparency = 1,
    }, titleBar)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 4),
    }, titleBtns)

    local pinBtn = makeBtn("📌", titleBtns, function() end)
    local closeBtn = makeBtn("✕", titleBtns, function()
        if gui then gui:Destroy() end
    end)

    -- ── Row 2: Playing label + camera buttons ──
    local row2 = make("Frame", {
        Size = UDim2.new(1, -20, 0, 28),
        Position = UDim2.new(0, 10, 0, 38),
        BackgroundTransparency = 1,
    }, mainFrame)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 4),
    }, row2)

    animLabel = make("TextLabel", {
        Text = "Playing: —",
        TextSize = 11, Font = Enum.Font.Gotham,
        TextColor3 = Color3.fromRGB(180, 180, 220),
        BackgroundTransparency = 1,
        Size = UDim2.new(0.45, 0, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row2)

    local function camBtn(lbl, cb) return makeBtn(lbl, row2, cb) end

    local gridOn = false
    camBtn("Grid", function()
        gridOn = not gridOn
        if not worldModel then return end
        local existing = worldModel:FindFirstChild("FloorGrid")
        if existing then existing:Destroy() end
        if gridOn then
            local grid = make("Model", { Name = "FloorGrid" }, worldModel)
            for x = -5, 5 do
                for z = -5, 5 do
                    make("Part", {
                        Size = Vector3.new(2, 0.05, 2),
                        CFrame = CFrame.new(x * 2, 0, z * 2),
                        Anchored = true, CanCollide = false,
                        Color = Color3.fromRGB(50, 50, 75),
                        Material = Enum.Material.SmoothPlastic,
                    }, grid)
                end
            end
        end
    end)

    camBtn("Spin", function()
        isSpinning = not isSpinning
    end)

    camBtn("Reset Camera", function()
        orbitY = 30; orbitX = -15; zoomDist = 10
    end)

    -- ── ViewportFrame ──
    viewportFrame = make("ViewportFrame", {
        Size = UDim2.new(1, -20, 0, 220),
        Position = UDim2.new(0, 10, 0, 68),
        BackgroundColor3 = Color3.fromRGB(18, 18, 35),
        BorderSizePixel = 0,
        LightColor = Color3.fromRGB(180, 180, 220),
        Ambient = Color3.fromRGB(100, 100, 140),
    }, mainFrame)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, viewportFrame)

    worldModel = make("WorldModel", {}, viewportFrame)
    animCamera = make("Camera", {}, viewportFrame)
    viewportFrame.CurrentCamera = animCamera

    -- Camera orbit/zoom mouse controls
    viewportFrame.MouseEnter:Connect(function() isHovering = true end)
    viewportFrame.MouseLeave:Connect(function() isHovering = false; isDragging = false end)
    viewportFrame.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = true
            lastMousePos = inp.Position
        end
    end)
    viewportFrame.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = false; lastMousePos = nil
        end
    end)
    viewportFrame.InputChanged:Connect(function(inp)
        if isHovering then
            if inp.UserInputType == Enum.UserInputType.MouseMovement and isDragging and lastMousePos then
                local delta = inp.Position - lastMousePos
                orbitY = orbitY + delta.X * 0.5
                orbitX = math.clamp(orbitX + delta.Y * 0.3, -60, 80)
                lastMousePos = inp.Position
            elseif inp.UserInputType == Enum.UserInputType.MouseWheel then
                zoomDist = math.clamp(zoomDist - inp.Position.Z * 0.8, 3, 30)
            end
        end
    end)

    startCameraLoop()

    -- ── Info row (ID + Time + FPS) ──
    local infoRow = make("Frame", {
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 10, 0, 292),
        BackgroundTransparency = 1,
    }, mainFrame)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 6),
    }, infoRow)

    idLabel = make("TextLabel", {
        Text = "ID: —",
        TextSize = 10, Font = Enum.Font.Code,
        TextColor3 = Color3.fromRGB(140, 140, 200),
        BackgroundTransparency = 1,
        Size = UDim2.new(0.6, 0, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, infoRow)

    timeLabel = make("TextLabel", {
        Text = "0.00 / 0.00s",
        TextSize = 10, Font = Enum.Font.Gotham,
        TextColor3 = Color3.fromRGB(180, 180, 220),
        BackgroundTransparency = 1,
        Size = UDim2.new(0.22, 0, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Center,
    }, infoRow)

    -- FPS toggle button
    local fpsBtn = makeBtn("60 FPS", infoRow, function() end)
    fpsBtn.MouseButton1Click:Connect(function()
        if fpsLockMode == "60" then fpsLockMode = "30"; fpsBtn.Text = "30 FPS"
        elseif fpsLockMode == "30" then fpsLockMode = "unlimited"; fpsBtn.Text = "∞ FPS"
        else fpsLockMode = "60"; fpsBtn.Text = "60 FPS" end
    end)

    -- ── Scrubber ──
    local scrubContainer = make("Frame", {
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 10, 0, 316),
        BackgroundTransparency = 1,
    }, mainFrame)
    setupScrubber(scrubContainer, 1)

    -- ── Playback controls ──
    local ctrlRow = make("Frame", {
        Size = UDim2.new(1, -20, 0, 28),
        Position = UDim2.new(0, 10, 0, 340),
        BackgroundTransparency = 1,
    }, mainFrame)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 4),
    }, ctrlRow)

    makeBtn("▶ Play", ctrlRow, function()
        if not currentTrack then
            if currentAnimId then Module_Viewer.LoadAnimation(currentAnimId) end
            return
        end
        if currentTrack.IsPlaying then return end
        pcall(function() currentTrack:AdjustSpeed(1) end)
        pcall(function() currentTrack:Play() end)
    end)

    makeBtn("⏹ Stop", ctrlRow, function()
        if currentTrack then
            pcall(function() currentTrack:AdjustSpeed(0) end)
        end
    end)

    -- Speed dropdown (simulated via button cycle)
    local speeds = {0.25, 0.50, 0.75, 1.0, 1.5, 2.0, 3.0}
    local speedIdx = 4
    local speedBtn = makeBtn("Speed: 1.0x", ctrlRow, function() end)
    speedBtn.MouseButton1Click:Connect(function()
        speedIdx = (speedIdx % #speeds) + 1
        speedBtn.Text = "Speed: " .. speeds[speedIdx] .. "x"
        if currentTrack then
            pcall(function() currentTrack:AdjustSpeed(speeds[speedIdx]) end)
        end
    end)

    -- Zoom slider (text input style)
    local zoomLabel = make("TextLabel", {
        Text = "Zoom: 10",
        TextSize = 10, Font = Enum.Font.Gotham,
        TextColor3 = Color3.fromRGB(170, 170, 210),
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 55, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, ctrlRow)

    -- Loop toggle
    local loopBtn = makeBtn("🔁 Loop: OFF", ctrlRow, function() end)
    loopBtn.MouseButton1Click:Connect(function()
        isLooping = not isLooping
        loopBtn.Text = "🔁 Loop: " .. (isLooping and "ON" or "OFF")
    end)

    -- ── Parry Builder Panel ──
    local divider = make("Frame", {
        Size = UDim2.new(1, -20, 0, 1),
        Position = UDim2.new(0, 10, 0, 375),
        BackgroundColor3 = Color3.fromRGB(70, 70, 120),
        BorderSizePixel = 0,
    }, mainFrame)

    local builderLabel = makeTxt("── Parry Builder ─────────────────────────────", 11, true, Color3.fromRGB(160, 160, 220), false, mainFrame)
    builderLabel.Position = UDim2.new(0, 10, 0, 380)
    builderLabel.Size = UDim2.new(1, -20, 0, 16)

    local builderBtnRow1 = make("Frame", {
        Size = UDim2.new(1, -20, 0, 26),
        Position = UDim2.new(0, 10, 0, 398),
        BackgroundTransparency = 1,
    }, mainFrame)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 4),
    }, builderBtnRow1)

    local function addMarker(markerType)
        local offset = currentTrack and (currentTrack.TimePosition * 1000) or 0
        local newMarker = { Type = markerType, OffsetMs = offset }
        table.insert(markers, newMarker)
        if DataBus.ExternalViewer and currentAnimId then
            DataBus.ExternalViewer.Markers[currentAnimId] = markers
        end
        redrawMarkers(currentTrack and currentTrack.Length or 1)
        if DataBus.UI and DataBus.UI.RefreshBuilderMarkers then
            DataBus.UI.RefreshBuilderMarkers(currentAnimId)
        end
    end

    makeBtn("+ Parry", builderBtnRow1, function() addMarker("Parry") end)
    makeBtn("+ Dodge", builderBtnRow1, function() addMarker("Dodge") end)
    makeBtn("+ Red",   builderBtnRow1, function() addMarker("Cancel") end)

    -- [+ Table] — type exact ms value
    makeBtn("+ Table", builderBtnRow1, function()
        -- Mini popover
        local pop = make("Frame", {
            Size = UDim2.fromOffset(200, 80),
            Position = UDim2.new(0.5, -100, 0, 425),
            BackgroundColor3 = Color3.fromHex("12122A"),
            ZIndex = 20,
        }, mainFrame)
        make("UICorner", { CornerRadius = UDim.new(0, 6) }, pop)
        make("UIStroke", { Color = Color3.fromRGB(80, 80, 140), Thickness = 1 }, pop)

        local inp = make("TextBox", {
            PlaceholderText = "ms (e.g. 420)",
            Text = "",
            TextSize = 12, Font = Enum.Font.Gotham,
            TextColor3 = Color3.fromRGB(220, 220, 255),
            BackgroundColor3 = Color3.fromRGB(30, 30, 55),
            Size = UDim2.new(1, -20, 0, 28),
            Position = UDim2.new(0, 10, 0, 10),
            ZIndex = 21,
        }, pop)
        make("UICorner", { CornerRadius = UDim.new(0, 4) }, inp)

        make("TextLabel", {
            Text = "Type delay in ms, press Enter",
            TextSize = 10, Font = Enum.Font.Gotham,
            TextColor3 = Color3.fromRGB(140, 140, 180),
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -20, 0, 16),
            Position = UDim2.new(0, 10, 0, 44),
            ZIndex = 21,
        }, pop)

        inp.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                local ms = tonumber(inp.Text)
                if ms then
                    table.insert(markers, { Type = "Parry", OffsetMs = ms })
                    if DataBus.ExternalViewer and currentAnimId then
                        DataBus.ExternalViewer.Markers[currentAnimId] = markers
                    end
                    redrawMarkers(currentTrack and currentTrack.Length or 1)
                end
            end
            pop:Destroy()
        end)
        inp:CaptureFocus()
    end)

    makeBtn("Clear", builderBtnRow1, function()
        markers = {}
        clearMarkerLines()
        if DataBus.ExternalViewer and currentAnimId then
            DataBus.ExternalViewer.Markers[currentAnimId] = {}
        end
    end)

    local builderBtnRow2 = make("Frame", {
        Size = UDim2.new(1, -20, 0, 26),
        Position = UDim2.new(0, 10, 0, 428),
        BackgroundTransparency = 1,
    }, mainFrame)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 4),
    }, builderBtnRow2)

    makeBtn("Export", builderBtnRow2, function()
        if not currentAnimId then return end
        local data = { AnimId = currentAnimId, Markers = markers }
        local json = HttpService:JSONEncode(data)
        if setclipboard then setclipboard(json) end
    end)

    makeBtn("Export All", builderBtnRow2, function()
        if not DataBus.ExternalViewer then return end
        local json = HttpService:JSONEncode(DataBus.ExternalViewer.Markers)
        if setclipboard then setclipboard(json) end
    end)

    local tipLabel = makeTxt("Tip: Click markers to jump · Right-click to delete · Drag viewport to orbit", 9, false, Color3.fromRGB(120, 120, 160), true, mainFrame)
    tipLabel.Position = UDim2.new(0, 10, 0, 460)
    tipLabel.Size = UDim2.new(1, -20, 0, 28)

    -- ── Live update loop ──
    task.spawn(function()
        while gui and gui.Parent do
            local targetFPS = fpsLockMode == "30" and 30 or fpsLockMode == "60" and 60 or 144
            local dt = task.wait(1 / targetFPS)

            -- Update scrubber + time label
            if currentTrack then
                local pos = currentTrack.TimePosition
                local len = currentTrack.Length
                if len > 0 then
                    updateScrubberVisual(pos / len)
                end
                if timeLabel then
                    timeLabel.Text = string.format("%.2f / %.2fs", pos, len)
                end
                if zoomLabel then
                    zoomLabel.Text = string.format("Zoom: %.1f", zoomDist)
                end
                redrawMarkers(len)
            end
        end
    end)

    -- Load anim if provided
    if animId then
        Module_Viewer.LoadAnimation(animId)
    else
        -- Placeholder state
        make("TextLabel", {
            Text = "No animation selected.\nClick Preview on any animation in Logger.",
            TextSize = 12, Font = Enum.Font.Gotham,
            TextColor3 = Color3.fromRGB(140, 140, 180),
            BackgroundTransparency = 0.3,
            BackgroundColor3 = Color3.fromRGB(20, 20, 40),
            Size = UDim2.new(1, 0, 0.4, 0),
            Position = UDim2.new(0, 0, 0.3, 0),
            TextWrapped = true,
            ZIndex = 5,
        }, viewportFrame)
    end

    -- ── 10. Hit History Side Panel ──────────────────────────────────────────
    historyFrame = make("Frame", {
        Size = UDim2.fromOffset(220, 540),
        Position = UDim2.new(1, 10, 0, 0),
        BackgroundColor3 = Color3.fromHex("1A1A2E"),
        BorderSizePixel = 0,
        Parent = mainFrame,
    }, mainFrame)
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, historyFrame)
    make("UIStroke", { Color = Color3.fromRGB(80, 80, 140), Thickness = 1 }, historyFrame)

    local histTitle = makeTxt("Hit History", 13, true, Color3.fromRGB(200, 200, 255), false, historyFrame)
    histTitle.Position = UDim2.fromOffset(10, 10)
    histTitle.Size = UDim2.new(1, -20, 0, 20)

    local histScroll = make("ScrollingFrame", {
        Size = UDim2.new(1, -10, 1, -50),
        Position = UDim2.fromOffset(5, 40),
        BackgroundTransparency = 1,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2,
    }, historyFrame)
    make("UIListLayout", { Padding = UDim.new(0, 5) }, histScroll)

    DataBus.UI.UpdateViewerHistory = function()
        if not histScroll then return end
        for _, c in ipairs(histScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end

        for npcName, hits in pairs(DataBus.HitHistory) do
            local npcSection = make("Frame", {
                Size = UDim2.new(1, -5, 0, 24),
                BackgroundColor3 = Color3.fromRGB(40, 40, 65),
                AutomaticSize = Enum.AutomaticSize.Y,
            }, histScroll)
            make("UICorner", { CornerRadius = UDim.new(0, 4) }, npcSection)
            make("UIListLayout", { Padding = UDim.new(0, 2) }, npcSection)

            makeTxt("  " .. npcName, 11, true, Color3.fromRGB(230, 230, 255), false, npcSection)

            for i, hit in ipairs(hits) do
                local hitRow = make("Frame", {
                    Size = UDim2.new(1, -4, 0, 32),
                    BackgroundTransparency = 1,
                }, npcSection)
                make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center }, hitRow)

                local anim = DataBus.Animations[hit.AnimId]
                local animName = anim and anim.AnimName or hit.AnimId
                makeTxt(string.format("  • %s: %.2fs", animName, hit.TimeIntoAnim), 10, false, Color3.fromRGB(180, 180, 220), false, hitRow).Size = UDim2.new(0.6, 0, 1, 0)

                local placeBtn = makeBtn("+ Place", hitRow, function()
                    Module_Viewer.LoadAnimation(hit.AnimId)
                    -- Add marker at hit time
                    local offset = hit.TimeIntoAnim * 1000
                    table.insert(markers, { Type = "Parry", OffsetMs = offset })
                    if DataBus.ExternalViewer and currentAnimId then
                        DataBus.ExternalViewer.Markers[currentAnimId] = markers
                    end
                    redrawMarkers(currentTrack and currentTrack.Length or 1)
                    if DataBus.UI and DataBus.UI.RefreshBuilderMarkers then
                        DataBus.UI.RefreshBuilderMarkers(currentAnimId)
                    end
                    Library:Notify({ Title = "Marker Placed", Description = string.format("Parry set at hit time: %.3fs", hit.TimeIntoAnim), Time = 3 })
                end)
            end
        end
    end

    DataBus.UI.UpdateViewerHistory() -- Initial update
end

function Module_Viewer.Init(bus)
    DataBus = bus
end

return Module_Viewer
