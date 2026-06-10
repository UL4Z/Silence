--[[
    Module_Logger.lua (v2)
    Updated entity scanner with ignore lists and path filtering.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Module_Logger = {}
local DataBus = nil

local accumulator = 0
local SCAN_THROTTLE = 0.4

function Module_Logger.Init(bus)
    DataBus = bus
end

function Module_Logger.NormaliseId(animId)
    return animId:match("%d+") or animId
end

function Module_Logger.GetEntityThumbnail(entity, entityType)
    if entityType == "LocalPlayer" or entityType == "Player" then
        local player = Players:GetPlayerFromCharacter(entity)
        if player then
            local success, content, isReady = pcall(function()
                return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)
            end)
            if success then return content end
        end
    end
    return "rbxassetid://6843503645" -- R6 Noob
end

function Module_Logger.Scan(dt)
    accumulator = accumulator + dt
    if accumulator < SCAN_THROTTLE then return end
    accumulator = 0

    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end

    local localPos = char.HumanoidRootPart.Position
    local config = DataBus.Config

    for _, entity in ipairs(workspace:GetDescendants()) do
        if entity:IsA("Model") and entity:FindFirstChild("HumanoidRootPart") then
            -- Check for Animator
            local animator = entity:FindFirstChildOfClass("Animator", true)
            if animator then
                local dist = (entity.HumanoidRootPart.Position - localPos).Magnitude
                if config.LoggerDistance > 0 and dist > config.LoggerDistance then continue end

                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    local animId = Module_Logger.NormaliseId(track.Animation.AnimationId)
                    
                    if DataBus.Config.IgnoreList[animId] then continue end
                    
                    -- Path filter
                    if config.AnimFolderPath ~= "" then
                        local parent = track.Animation.Parent
                        if not parent or not parent.Name:find(config.AnimFolderPath) then
                            continue
                        end
                    end

                    if DataBus.Animations[animId] then
                        DataBus.Animations[animId].PlayCount = DataBus.Animations[animId].PlayCount + 1
                    else
                        -- New animation found
                        local entityType = "NPC"
                        if entity == char then
                            entityType = "LocalPlayer"
                        elseif Players:GetPlayerFromCharacter(entity) then
                            entityType = "Player"
                        end

                        -- Name Resolution
                        local name = track.Animation.Name
                        if name == "Animation" or name == "" then
                            name = track.Name
                        end
                        if name == "Animation" or name == "" then
                            name = "Anim_" .. animId
                        end

                        -- CACHE RIG IMMEDIATELY (For accurate Viewer usage)
                        if Modules.Viewer and Modules.Viewer.CacheEntity then
                            Modules.Viewer.CacheEntity(animId, entity)
                        end

                        DataBus.Animations[animId] = {
                            AnimId = animId,
                            AnimName = name,
                            EntityName = entity.Name == "" and "Unknown Entity" or entity.Name,
                            EntityType = entityType,
                            UserId = Players:GetPlayerFromCharacter(entity) and Players:GetPlayerFromCharacter(entity).UserId or nil,
                            PlayCount = 1,
                            FirstSeenAt = os.clock(),
                            Ignored = false,
                            Thumbnail = Module_Logger.GetEntityThumbnail(entity, entityType)
                        }

                        if DataBus.UI.OnNewAnimation then
                            DataBus.UI.OnNewAnimation(animId)
                        end
                    end
                end
            end
        end
    end
end

function Module_Logger.Start()
    RunService.Heartbeat:Connect(Module_Logger.Scan)
end

return Module_Logger
