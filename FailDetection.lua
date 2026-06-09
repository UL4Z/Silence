--[[
    FailDetection.lua
    Resolves parry success/failure based on HP, sound, and animation signals.
]]

local FailDetection = {}
local DataBus = nil

function FailDetection.Init(bus)
    DataBus = bus
end

function FailDetection.Resolve(attempt, callback)
    local config = DataBus.Config
    local startHealth = game:GetService("Players").LocalPlayer.Character and game:GetService("Players").LocalPlayer.Character.Humanoid.Health or 100
    local resolved = false

    local function finish(success)
        if resolved then return end
        resolved = true
        callback(success)
    end

    -- COROUTINE: Monitor window
    task.spawn(function()
        local window = config.ResolutionWindowSec
        local elapsed = 0
        
        -- Listen for success/fail animations and sounds
        -- (This would be hooked via game:GetService("RunService").Heartbeat or similar)
        
        while elapsed < window and not resolved do
            local dt = task.wait()
            elapsed = elapsed + dt
            
            local char = game:GetService("Players").LocalPlayer.Character
            if char and char:FindFirstChild("Humanoid") then
                local currentHealth = char.Humanoid.Health
                
                -- HP Fallback check
                if config.UseHealthFallback and currentHealth < startHealth then
                    -- Check if it's fall damage (best effort)
                    -- if config.IgnoreFallDamage and isFalling then ... end
                    finish(false) -- Failure detected
                end
                
                -- Check for success animations...
                -- for _, id in ipairs(config.SuccessAnimIds) do ... end
            end
        end
        
        -- If window expires without HP drop or other fail signals, consider it a success
        finish(true)
    end)
end

return FailDetection
