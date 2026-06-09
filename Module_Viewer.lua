--[[
    Module_Viewer.lua (v2)
    Standalone ScreenGui for 3D animation preview, orbit/zoom, and marker scrubbing.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Module_Viewer = {}
local DataBus = nil

local gui = nil
local viewport = nil
local previewRig = nil
local camera = nil

local orbitY = 0
local orbitX = 0
local zoomDist = 10
local isSpinning = false

function Module_Viewer.Init(bus)
    DataBus = bus
end

function Module_Viewer.Open()
    if gui then gui:Destroy() end

    gui = Instance.new("ScreenGui")
    gui.Name = "SilenceViewer"
    gui.ResetOnSpawn = false
    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

    local window = Instance.new("Frame")
    window.Size = UDim2.fromOffset(400, 480)
    window.Position = UDim2.fromScale(0.5, 0.5)
    window.AnchorPoint = Vector2.new(0.5, 0.5)
    window.BackgroundColor3 = Color3.fromHex("1A1A2E")
    window.Parent = gui
    
    -- (Add UI components: Viewport, Play/Stop, Scrubber, Markers list...)
    Module_Viewer.SetupViewport(window)
end

function Module_Viewer.SetupViewport(container)
    viewport = Instance.new("ViewportFrame")
    viewport.Size = UDim2.new(1, -20, 0, 220)
    viewport.Position = UDim2.fromOffset(10, 40)
    viewport.BackgroundTransparency = 1
    viewport.Parent = container

    local worldModel = Instance.new("WorldModel")
    worldModel.Parent = viewport

    camera = Instance.new("Camera")
    viewport.CurrentCamera = camera
    camera.Parent = viewport

    Module_Viewer.CreateDefaultRig(worldModel)
    
    -- Connect Camera Update
    RunService.RenderStepped:Connect(function()
        if isSpinning then orbitY = orbitY + 0.5 end
        
        local char = Players.LocalPlayer.Character
        local target = (previewRig and previewRig.PrimaryPart) and previewRig.PrimaryPart.Position or Vector3.new(0, 5, 0)
        
        local cf = CFrame.new(target) 
            * CFrame.Angles(0, math.rad(orbitY), 0) 
            * CFrame.Angles(math.rad(orbitX), 0, 0) 
            * CFrame.new(0, 0, zoomDist)
            
        camera.CFrame = cf
    end)
end

function Module_Viewer.ToggleSpin(v)
    isSpinning = v
end

function Module_Viewer.ResetCamera()
    orbitY = 0
    orbitX = 0
    zoomDist = 10
end

function Module_Viewer.ToggleGrid(v)
    if not viewport:FindFirstChild("WorldModel") then return end
    local wm = viewport.WorldModel
    
    local existing = wm:FindFirstChild("FloorGrid")
    if existing then existing:Destroy() end
    
    if v then
        local grid = Instance.new("Model")
        grid.Name = "FloorGrid"
        for x = -5, 5 do
            for z = -5, 5 do
                local p = Instance.new("Part")
                p.Size = Vector3.new(2, 0.1, 2)
                p.Position = Vector3.new(x * 2, 0, z * 2)
                p.Anchored = true
                p.Color = Color3.fromRGB(50, 50, 70)
                p.Parent = grid
            end
        end
        grid.Parent = wm
    end
end

function Module_Viewer.CreateDefaultRig(worldModel)
    local rig = Instance.new("Model")
    rig.Name = "PreviewRig"
    
    local hrp = Instance.new("Part")
    hrp.Name = "HumanoidRootPart"
    hrp.Size = Vector3.new(2, 2, 1)
    hrp.Anchored = true
    hrp.Parent = rig
    rig.PrimaryPart = hrp
    
    local hum = Instance.new("Humanoid")
    hum.Parent = rig
    
    rig.Parent = worldModel
    previewRig = rig
end

function Module_Viewer.PlayAnimation(animId)
    if not previewRig then return end
    
    local animator = previewRig.Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", previewRig.Humanoid)
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. animId
    
    local success, track = pcall(function() return animator:LoadAnimation(anim) end)
    if success then
        track:Play()
        return track
    end
end

return Module_Viewer
