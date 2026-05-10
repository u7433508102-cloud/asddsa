local Config = shared.Xanax
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local cheatActive = true
local currentTarget = nil
local isLocking = false
local triggerEnabled = false
local fovBox = nil
local espLabels = {}
local SpeedEnabled = false
local BaseSpeed = 16
local lastVisibleTarget = nil
local lastTriggerClick = 0
local superJumpActive = false
local snaplineDrawing = nil

-- ========== CLEANUP (END key) ==========
local function Cleanup()
    cheatActive = false
    Config['Silent Aim']['Enabled'] = false
    Config['Spread']['Enabled'] = false
    Config['Trigger Bot']['Enabled'] = false
    Config['Speed']['Enabled'] = false
    SpeedEnabled = false
    isLocking = false
    currentTarget = nil
    triggerEnabled = false

    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
    if hum then hum.WalkSpeed = 16 end

    if fovBox then pcall(function() fovBox:Remove() end) end
    if snaplineDrawing then pcall(function() snaplineDrawing:Remove() end) end
    for _, esp in pairs(espLabels) do
        pcall(function() esp.nameTag:Remove() end)
    end
    espLabels = {}

    pcall(function() gui:Destroy() end)

    pcall(function()
        local mt = getrawmetatable(game)
        if mt and oldIndex then
            setreadonly(mt, false)
            mt.__index = oldIndex
        end
    end)

    print("Cheat destroyed. Re‑execute the loader to start again.")
end

-- ========== HELPER FUNCTIONS ==========
local function isPlayerKnockedOrKO(player)
    if not Config['Settings']['Knock Check'] then return false end
    if player.Character then
        local bodyEffects = player.Character:FindFirstChild("BodyEffects")
        if bodyEffects then
            local ko = bodyEffects:FindFirstChild("K.O")
            if ko and ko.Value == true then return true end
            local knocked = bodyEffects:FindFirstChild("Knocked")
            if knocked and knocked.Value == true then return true end
        end
    end
    return false
end

local function isSelfKnocked()
    if LocalPlayer.Character then
        local bodyEffects = LocalPlayer.Character:FindFirstChild("BodyEffects")
        if bodyEffects then
            local ko = bodyEffects:FindFirstChild("K.O")
            if ko and ko.Value == true then return true end
            local knocked = bodyEffects:FindFirstChild("Knocked")
            if knocked and knocked.Value == true then return true end
        end
    end
    return false
end

local function canSeeTarget(part)
    if not Config['Settings']['Visible Check'] then return true end
    if not part or not part.Parent then return false end
    local character = part.Parent
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    local state = humanoid:GetState()
    local isAirborne = (state == Enum.HumanoidStateType.Jumping or
                        state == Enum.HumanoidStateType.Freefall or
                        state == Enum.HumanoidStateType.FallingDown)
    local root = character:FindFirstChild("HumanoidRootPart")
    local velY = root and math.abs((root.AssemblyLinearVelocity or root.Velocity or Vector3.new()).Y) or 0
    if (isAirborne or velY > 8) and isLocking then return true end
    local origin = Camera.CFrame.Position
    local direction = (part.Position - origin).Unit * (part.Position - origin).Magnitude
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, character}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.IgnoreWater = true
    local rayResult = Workspace:Raycast(origin, direction, raycastParams)
    return rayResult == nil or rayResult.Instance:IsDescendantOf(character)
end

local function getClosestBodyPart(character)
    local closestPart, shortestDist = nil, math.huge
    local parts = {
        character:FindFirstChild("Head"), character:FindFirstChild("UpperTorso"),
        character:FindFirstChild("HumanoidRootPart"), character:FindFirstChild("LowerTorso"),
        character:FindFirstChild("LeftUpperArm"), character:FindFirstChild("RightUpperArm"),
        character:FindFirstChild("LeftLowerArm"), character:FindFirstChild("RightLowerArm"),
        character:FindFirstChild("LeftHand"), character:FindFirstChild("RightHand"),
        character:FindFirstChild("LeftUpperLeg"), character:FindFirstChild("RightUpperLeg"),
        character:FindFirstChild("LeftLowerLeg"), character:FindFirstChild("RightLowerLeg"),
        character:FindFirstChild("LeftFoot"), character:FindFirstChild("RightFoot"),
    }
    for _, part in ipairs(parts) do
        if part then
            local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
            local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
            local dist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
            if dist < shortestDist then
                shortestDist = dist; closestPart = part
            end
        end
    end
    return closestPart
end

local function isMouseInFOV(character)
    if not Config['FOV']['Enabled'] then return true end
    if not character then return false end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    if not rootPart or not head then return false end
    local headPos, headOnScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0,0.5,0))
    local legPos, legOnScreen = Camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0,3,0))
    if not headOnScreen or not legOnScreen then return false end
    local height = math.abs(headPos.Y - legPos.Y)
    local width = height / 2
    local rootPos = Camera:WorldToViewportPoint(rootPart.Position)
    local padding = 10
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    return mousePos.X >= rootPos.X - width/2 - padding and mousePos.X <= rootPos.X + width/2 + padding
            and mousePos.Y >= headPos.Y - padding and mousePos.Y <= legPos.Y + padding
end

local function findClosestTarget()
    local closestTarget, shortestDistance = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            if not isPlayerKnockedOrKO(player) then
                local targetPart = nil
                if Config['Silent Aim']['Hit Part'] == 'Closest Part' then
                    targetPart = getClosestBodyPart(player.Character)
                else
                    targetPart = player.Character:FindFirstChild(Config['Silent Aim']['Hit Part'])
                end
                if targetPart and canSeeTarget(targetPart) and isMouseInFOV(player.Character) then
                    local screenPos = Camera:WorldToViewportPoint(targetPart.Position)
                    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                    if dist < shortestDistance then
                        shortestDistance = dist; closestTarget = targetPart
                    end
                end
            end
        end
    end
    return closestTarget
end

local function getPredictedPosition(part, config)
    if not config['Use Prediction'] then return part.Position end
    local vel = part.AssemblyLinearVelocity or part.Velocity or Vector3.zero
    local pred = config['Prediction']
    if type(pred) == "table" then
        return part.Position + Vector3.new(vel.X * (pred.X or 0.133), vel.Y * (pred.Y or 0.133), vel.Z * (pred.Z or 0.133))
    else
        if pred == 0 then pred = 0.1245 end
        return part.Position + vel * pred
    end
end

-- ========== DRAWING OBJECTS ==========
if not fovBox then
    fovBox = Drawing.new("Square"); fovBox.Visible = false; fovBox.Thickness = Config['FOV']['Thickness']
    fovBox.Color = Config['FOV']['Color']; fovBox.Filled = false; fovBox.Size = Vector2.new(0,0)
end

local function updateFOVBox()
    if not Config['FOV']['Enabled'] or not Config['FOV']['Visible'] then fovBox.Visible = false; return end
    if currentTarget then
        local char = currentTarget.Parent
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            local head = char:FindFirstChild("Head")
            if root and head then
                local hpos, hon = Camera:WorldToViewportPoint(head.Position + Vector3.new(0,0.5,0))
                local lpos, lon = Camera:WorldToViewportPoint(root.Position - Vector3.new(0,3,0))
                if hon and lon then
                    local h = math.abs(hpos.Y - lpos.Y); local w = h/2
                    local rpos = Camera:WorldToViewportPoint(root.Position)
                    local pad = 10
                    fovBox.Size = Vector2.new(w + pad*2, h + pad*2)
                    fovBox.Position = Vector2.new(rpos.X - w/2 - pad, hpos.Y - pad)
                    fovBox.Visible = true; return
                end
            end
        end
    end
    fovBox.Visible = false
end

local function TriggerBot()
    if not Config['Trigger Bot']['Enabled'] or not triggerEnabled then return end
    if tick() - lastTriggerClick < Config['Trigger Bot']['Delay'] then return end
    if not currentTarget then return end
    local char = currentTarget.Parent; if not char then return end
    local player = Players:GetPlayerFromCharacter(char); if not player then return end
    if isPlayerKnockedOrKO(player) or not canSeeTarget(currentTarget) then return end
    if Config['FOV']['Enabled'] and not isMouseInFOV(char) then return end
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool"); if not tool then return end
    if Config['Trigger Bot']['Specific Weapons']['Enabled'] then
        local ok = false
        for _, wn in ipairs(Config['Trigger Bot']['Specific Weapons']['Weapons']) do
            if tool.Name == wn:gsub("[%[%]]", "") or tool.Name:find(wn:gsub("[%[%]]", "")) then ok = true break end
        end
        if not ok then return end
    end
    tool:Activate()
    lastTriggerClick = tick()
end

-- ========== UNIVERSAL SILENT AIM HOOK ==========
local oldIndex = getrawmetatable(game).__index
setreadonly(getrawmetatable(game), false)
getrawmetatable(game).__index = function(self, key)
    if not cheatActive or not Config['Silent Aim']['Enabled'] or not self:IsA("Mouse") then
        return oldIndex(self, key)
    end
    if key ~= "Hit" and key ~= "Target" then return oldIndex(self, key) end
    if not currentTarget then return oldIndex(self, key) end
    local char = currentTarget.Parent; if not char then return oldIndex(self, key) end
    local player = Players:GetPlayerFromCharacter(char)
    if not player or isPlayerKnockedOrKO(player) or not canSeeTarget(currentTarget) then
        return oldIndex(self, key)
    end
    if Config['FOV']['Enabled'] and not isMouseInFOV(char) then return oldIndex(self, key) end
    if key == "Hit" then
        return CFrame.new(getPredictedPosition(currentTarget, Config['Silent Aim']))
    else
        return currentTarget
    end
end

-- ========== SPREAD HOOK ==========
local oldRandom = math.random
hookfunction(math.random, function(...)
    local args = {...}
    if not cheatActive or checkcaller() then return oldRandom(...) end
    if (#args == 0) or (args[1] == -0.05 and args[2] == 0.05) or (args[1] == -0.1) or (args[1] == -0.05) then
        if Config['Spread']['Enabled'] then
            if Config['Spread']['Specific Weapons']['Enabled'] then
                local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
                if tool then
                    for _, wn in ipairs(Config['Spread']['Specific Weapons']['Weapons']) do
                        if tool.Name == wn then return oldRandom(...) * (Config['Spread']['Amount']/100) end
                    end
                end
            else return oldRandom(...) * (Config['Spread']['Amount']/100) end
        end
    end
    return oldRandom(...)
end)

-- ========== ESP ==========
local function addESPToPlayer(player)
    if player == LocalPlayer then return end
    local esp = { player = player, nameTag = Drawing.new("Text") }
    esp.nameTag.Size = 14; esp.nameTag.Center = true; esp.nameTag.Outline = true
    esp.nameTag.OutlineColor = Color3.new(0,0,0); esp.nameTag.Color = Config['Visual Awareness']['Color']
    esp.nameTag.Visible = false; esp.nameTag.ZIndex = 1000
    espLabels[player.UserId] = esp
end

local function removeESPFromPlayer(player)
    local esp = espLabels[player.UserId]
    if esp then esp.nameTag:Remove(); espLabels[player.UserId] = nil end
end

local function refreshESP()
    if not Config['Visual Awareness']['Enabled'] then
        for _, esp in pairs(espLabels) do esp.nameTag.Visible = false end
        return
    end
    for userId, esp in pairs(espLabels) do
        local player = esp.player
        if not player or not player.Parent then esp.nameTag.Visible = false; esp.nameTag:Remove(); espLabels[userId] = nil; continue end
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Head") then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then esp.nameTag.Visible = false; continue end
            local root = player.Character.HumanoidRootPart
            local legPos, onScreen = Camera:WorldToViewportPoint(root.Position - Vector3.new(0,3,0))
            if onScreen and legPos.Z > 0 then
                esp.nameTag.Position = Vector2.new(legPos.X, legPos.Y + 15)
                esp.nameTag.Text = player.DisplayName ~= "" and player.DisplayName or player.Name
                esp.nameTag.Color = (currentTarget and currentTarget.Parent == player.Character) and Config['Visual Awareness']['Target Color'] or Config['Visual Awareness']['Color']
                esp.nameTag.Visible = true
            else esp.nameTag.Visible = false end
        else esp.nameTag.Visible = false end
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then addESPToPlayer(player) end
    player.CharacterAdded:Connect(function(char) removeESPFromPlayer(player); char:WaitForChild("HumanoidRootPart"); task.wait(0.1); addESPToPlayer(player) end)
    player.CharacterRemoving:Connect(function() removeESPFromPlayer(player) end)
end
Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function(char) removeESPFromPlayer(player); char:WaitForChild("HumanoidRootPart"); task.wait(0.1); addESPToPlayer(player) end)
        player.CharacterRemoving:Connect(function() removeESPFromPlayer(player) end)
    end
end)
Players.PlayerRemoving:Connect(removeESPFromPlayer)

-- ========== SUPER JUMP ==========
RunService.Heartbeat:Connect(function()
    if not cheatActive or not Config['Super Jump']['Enabled'] then return end
    local character = LocalPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end
    local holdingB = UserInputService:IsKeyDown(Enum.KeyCode[Config['Keybinds']['Super Jump']])
    if holdingB and (humanoid:GetState() == Enum.HumanoidStateType.Landed or humanoid.FloorMaterial ~= Enum.Material.Air) then
        rootPart.Velocity = Vector3.new(rootPart.Velocity.X, Config['Super Jump']['Power'], rootPart.Velocity.Z)
        task.wait(Config['Super Jump']['Cooldown'])
    end
end)

-- ========== SNAPLINE DRAWING ==========
if not snaplineDrawing then
    snaplineDrawing = Drawing.new("Line"); snaplineDrawing.Visible = false
    snaplineDrawing.Thickness = Config['Snapline']['Thickness']; snaplineDrawing.Color = Config['Snapline']['Color']
end

-- ========== MAIN LOOP ==========
RunService.RenderStepped:Connect(function()
    if not cheatActive then return end
    if isSelfKnocked() and isLocking then currentTarget = nil; isLocking = false; lastVisibleTarget = nil end

    TriggerBot()

    if SpeedEnabled and Config['Speed']['Enabled'] then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then hum.WalkSpeed = BaseSpeed * Config['Speed']['Multiplier'] end
        if Config['Speed']['Anti Fling'] then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then local vel = hrp.Velocity; if vel.Y > 50 or vel.Y < -50 then hrp.Velocity = Vector3.new(vel.X, 0, vel.Z) end end
        end
    end

    if Config['Hitbox Expander']['Enabled'] then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.Size = Vector3.new(Config['Hitbox Expander']['Size'], Config['Hitbox Expander']['Size'], Config['Hitbox Expander']['Size'])
                    hrp.Transparency = Config['Hitbox Expander']['Visualize'] and 0.7 or 1
                end
            end
        end
    end

    updateFOVBox()
    refreshESP()

    if Config['Snapline']['Enabled'] and currentTarget then
        local targetPart = nil
        local targetChar = currentTarget.Parent
        if targetChar then targetPart = targetChar:FindFirstChild(Config['Snapline']['TargetPart']) end
        if targetPart then
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            local startPos = Vector2.new(Mouse.X, Mouse.Y + Config['Snapline']['MouseOffsetY'])
            snaplineDrawing.From = startPos; snaplineDrawing.To = Vector2.new(screenPos.X, screenPos.Y)
            snaplineDrawing.Visible = onScreen
        else snaplineDrawing.Visible = false end
    else snaplineDrawing.Visible = false end
end)

-- ========== INPUT HANDLING ==========
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.End then
        Cleanup()
        return
    end

    if not cheatActive then return end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Target Lock']['Key']] then
        local mode = Config['Keybinds']['Target Lock']['Mode']
        if mode == 'Toggle' then
            if Config['Settings']['Target Aim'] then
                if isLocking then isLocking = false; currentTarget = nil; lastVisibleTarget = nil
                else local t = findClosestTarget(); if t then currentTarget = t; lastVisibleTarget = t; isLocking = true end
                end
            else isLocking = not isLocking end
        elseif mode == 'Hold' then
            if Config['Settings']['Target Aim'] then
                local t = findClosestTarget(); if t then currentTarget = t; lastVisibleTarget = t; isLocking = true end
            else isLocking = true end
        end
    end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Trigger Bot']['Key']] then
        if Config['Keybinds']['Trigger Bot']['Mode'] == 'Toggle' then triggerEnabled = not triggerEnabled
        else triggerEnabled = true end
    end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Speed']] then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            if not SpeedEnabled then BaseSpeed = 16; SpeedEnabled = true else hum.WalkSpeed = BaseSpeed; SpeedEnabled = false end
        end
    end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['ESP']] then
        Config['Visual Awareness']['Enabled'] = not Config['Visual Awareness']['Enabled']
    end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Super Jump']] then
        superJumpActive = not superJumpActive
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Target Lock']['Key']] then
        if Config['Keybinds']['Target Lock']['Mode'] == 'Hold' then isLocking = false; currentTarget = nil; lastVisibleTarget = nil end
    end
end)

LocalPlayer.CharacterAdded:Connect(function() task.wait(1) end)

-- ========== INFINITE RANGE ==========
local infRangeActive = false
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode[Config['Infinite Range']['Key']] then
        infRangeActive = not infRangeActive
    end
end)
RunService.RenderStepped:Connect(function()
    if not cheatActive or not Config['Infinite Range']['Enabled'] or not infRangeActive then return end
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not tool then return end
    local rangeProps = {"Range", "MaxRange", "FireRange", "Distance", "MaxDistance"}
    for _, propName in ipairs(rangeProps) do
        for _, container in ipairs({tool, tool:FindFirstChild("Configuration"), tool:FindFirstChild("GunConfig")}) do
            if container then
                local r = container:FindFirstChild(propName)
                if r and r:IsA("NumberValue") then r.Value = Config['Infinite Range']['Max Range'] end
            end
        end
    end
end)

-- ========== GUI ==========
local gui = Instance.new("ScreenGui")
gui.Parent = game.CoreGui

local text = Instance.new("TextLabel")
text.Parent = gui
text.AnchorPoint = Vector2.new(0.5, 1)
text.Position = UDim2.new(0.5, 0, 1, -80)
text.Size = UDim2.new(0, 200, 0, 110)
text.BackgroundTransparency = 1
text.TextXAlignment = Enum.TextXAlignment.Center
text.TextYAlignment = Enum.TextYAlignment.Bottom
text.Font = Enum.Font.Code
text.TextSize = 16
text.RichText = true
text.TextStrokeTransparency = 0
text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

game:GetService("RunService").RenderStepped:Connect(function()
    if not cheatActive then text.Text = ""; return end
    local lines = {}
    table.insert(lines, '<b><font color="rgb(102,178,255)">Xanax.wtf</font></b>')

    if SpeedEnabled then
        table.insert(lines, '<font color="rgb(255,255,255)">speed-walk</font><font color="rgb(102,178,255)"> [ON]</font>')
    else
        table.insert(lines, '<font color="rgb(255,255,255)">speed-walk</font>')
    end

    if Config["Silent Aim"]["Enabled"] and currentTarget then
        local targetName = ""
        local targetChar = currentTarget.Parent
        if targetChar then
            local player = Players:GetPlayerFromCharacter(targetChar)
            if player then
                targetName = player.DisplayName ~= "" and player.DisplayName or player.Name
            end
        end
        table.insert(lines, '<font color="rgb(255,255,255)">silent-aim</font><font color="rgb(102,178,255)"> [ ' .. targetName .. ' ]</font>')
    else
        table.insert(lines, '<font color="rgb(255,255,255)">silent-aim</font>')
    end

    if Config["Trigger Bot"]["Enabled"] and triggerEnabled then
        table.insert(lines, '<font color="rgb(255,255,255)">trigger-bot</font><font color="rgb(102,178,255)"> [ON]</font>')
    else
        table.insert(lines, '<font color="rgb(255,255,255)">trigger-bot</font>')
    end

    if infRangeActive then
        table.insert(lines, '<font color="rgb(255,255,255)">infinite-range</font><font color="rgb(102,178,255)"> [ON]</font>')
    else
        table.insert(lines, '<font color="rgb(255,255,255)">infinite-range</font>')
    end

    text.Text = table.concat(lines, "\n")
end)
