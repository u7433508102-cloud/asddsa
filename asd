-- ================== SCRIPT CODE ==================
local Config = shared.Xanax
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

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
local camlockEnabled = false
local camlockTarget = nil
local snaplineDrawing = nil

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
    if (isAirborne or velY > 8) and isLocking then
        return true
    end
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
    local closestPart = nil
    local shortestDist = math.huge
    local bodyParts = {
        character:FindFirstChild("Head"),
        character:FindFirstChild("UpperTorso"),
        character:FindFirstChild("HumanoidRootPart"),
        character:FindFirstChild("LowerTorso"),
        character:FindFirstChild("LeftUpperArm"),
        character:FindFirstChild("RightUpperArm"),
        character:FindFirstChild("LeftLowerArm"),
        character:FindFirstChild("RightLowerArm"),
        character:FindFirstChild("LeftHand"),
        character:FindFirstChild("RightHand"),
        character:FindFirstChild("LeftUpperLeg"),
        character:FindFirstChild("RightUpperLeg"),
        character:FindFirstChild("LeftLowerLeg"),
        character:FindFirstChild("RightLowerLeg"),
        character:FindFirstChild("LeftFoot"),
        character:FindFirstChild("RightFoot"),
    }
    for _, part in pairs(bodyParts) do
        if part then
            local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
            local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
            local dist = (Vector2.new(pos.X, pos.Y) - screenCenter).Magnitude
            if dist < shortestDist then
                shortestDist = dist
                closestPart = part
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
    local headPos, headOnScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
    local legPos, legOnScreen = Camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0))
    if not headOnScreen or not legOnScreen then return false end
    local height = math.abs(headPos.Y - legPos.Y)
    local width = height / 2
    local rootPos = Camera:WorldToViewportPoint(rootPart.Position)
    local padding = Config['FOV']['BoxSize'] or 10
    local topLeftX = rootPos.X - width/2 - padding
    local topLeftY = headPos.Y - padding
    local bottomRightX = rootPos.X + width/2 + padding
    local bottomRightY = legPos.Y + padding
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    return mousePos.X >= topLeftX and mousePos.X <= bottomRightX and mousePos.Y >= topLeftY and mousePos.Y <= bottomRightY
end

-- Target selection for silent aim (closest to screen center)
local function findClosestTarget()
    local closestTarget = nil
    local shortestDistance = math.huge
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            if not isPlayerKnockedOrKO(player) then
                local targetPart = nil
                if Config['Silent Aim']['Hit Part'] == 'Closest Part' then
                    targetPart = getClosestBodyPart(player.Character)
                else
                    targetPart = player.Character:FindFirstChild(Config['Silent Aim']['Hit Part'])
                end
                if targetPart and canSeeTarget(targetPart) then
                    local pos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                    if isMouseInFOV(player.Character) then
                        local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                        local dist = (Vector2.new(pos.X, pos.Y) - screenCenter).Magnitude
                        if dist < shortestDistance then
                            shortestDistance = dist
                            closestTarget = targetPart
                        end
                    end
                end
            end
        end
    end
    return closestTarget
end

-- Camlock target finder (respects FOV)
local function findCamlockTarget()
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local bestPlayer, bestDist = nil, math.huge
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            if not isPlayerKnockedOrKO(player) then
                local part = player.Character:FindFirstChild("HumanoidRootPart")
                if part and canSeeTarget(part) then
                    if Config['FOV']['Enabled'] and not isMouseInFOV(player.Character) then
                        -- not inside FOV, skip this player
                    else
                        local screenPos = Camera:WorldToViewportPoint(part.Position)
                        local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                        if dist < bestDist then
                            bestDist = dist
                            bestPlayer = player
                        end
                    end
                end
            end
        end
    end
    return bestPlayer
end

local function getPredictedPosition(part, config)
    if not config['Use Prediction'] then return part.Position end
    local velocity = part.AssemblyLinearVelocity or part.Velocity or Vector3.new(0, 0, 0)
    local prediction = config['Prediction']
    if type(prediction) == "table" then
        local predX = prediction['X'] or 0.133
        local predY = prediction['Y'] or 0.133
        local predZ = prediction['Z'] or 0.133
        return part.Position + Vector3.new(velocity.X * predX, velocity.Y * predY, velocity.Z * predZ)
    else
        if prediction == 0 then prediction = 0.1245 end
        return part.Position + (velocity * prediction)
    end
end

local function applyCameraLock()
    if not camlockEnabled then return end
    if not Config['Camera Lock']['Enabled'] then return end -- master switch off
    if isSelfKnocked() then
        camlockTarget = nil
        return
    end
    if camlockTarget then
        local char = camlockTarget.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 or isPlayerKnockedOrKO(camlockTarget) then
            camlockTarget = nil
        end
    end
    if not camlockTarget then
        camlockTarget = findCamlockTarget()
    end
    if not camlockTarget then return end

    local part = camlockTarget.Character:FindFirstChild("HumanoidRootPart")
    if not part then return end

    local targetPos = getPredictedPosition(part, Config['Camera Lock'])
    local camCF = Camera.CFrame
    local targetCF = CFrame.new(camCF.Position, targetPos)
    local smooth = Config['Camera Lock']['Smoothing']
    local alpha = 1 / smooth
    Camera.CFrame = camCF:Lerp(targetCF, math.min(alpha, 1))
end

-- ========== DRAWING OBJECTS ==========
if not fovBox then
    fovBox = Drawing.new("Square")
    fovBox.Visible = false
    fovBox.Thickness = Config['FOV']['Thickness']
    fovBox.Color = Config['FOV']['Color']
    fovBox.Filled = false
    fovBox.Size = Vector2.new(0, 0)
end

local function updateFOVBox()
    if not Config['FOV']['Enabled'] or not Config['FOV']['Visible'] then
        fovBox.Visible = false
        return
    end
    if currentTarget then
        local character = currentTarget.Parent
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local head = character:FindFirstChild("Head")
            if rootPart and head then
                local headPos, headOnScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local legPos, legOnScreen = Camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0))
                if headOnScreen and legOnScreen then
                    local height = math.abs(headPos.Y - legPos.Y)
                    local width = height / 2
                    local rootPos = Camera:WorldToViewportPoint(rootPart.Position)
                    local padding = Config['FOV']['BoxSize'] or 10
                    local topLeft = Vector2.new(rootPos.X - width/2 - padding, headPos.Y - padding)
                    fovBox.Size = Vector2.new(width + padding * 2, height + padding * 2)
                    fovBox.Position = topLeft
                    fovBox.Visible = true
                    return
                end
            end
        end
    end
    fovBox.Visible = false
end

local function TriggerBot()
    if not Config['Trigger Bot']['Enabled'] then return end
    if not triggerEnabled then return end
    if tick() - lastTriggerClick < Config['Trigger Bot']['Delay'] then return end
    if not currentTarget then return end
    local character = currentTarget.Parent
    if not character then return end
    local player = Players:GetPlayerFromCharacter(character)
    if not player then return end
    if isPlayerKnockedOrKO(player) then return end
    if not canSeeTarget(currentTarget) then return end
    if Config['FOV']['Enabled'] and not isMouseInFOV(character) then return end
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not tool then return end
    if Config['Trigger Bot']['Specific Weapons']['Enabled'] then
        local weaponValid = false
        for _, weaponName in pairs(Config['Trigger Bot']['Specific Weapons']['Weapons']) do
            local cleanName = weaponName:gsub("%[", ""):gsub("%]", "")
            if tool.Name == weaponName or tool.Name:find(cleanName) then
                weaponValid = true
                break
            end
        end
        if not weaponValid then return end
    end
    tool:Activate()
    lastTriggerClick = tick()
end

-- ========== UNIVERSAL SILENT AIM HOOK ==========
local oldIndex = getrawmetatable(game).__index
setreadonly(getrawmetatable(game), false)
getrawmetatable(game).__index = function(self, key)
    if not checkcaller() and Config['Silent Aim']['Enabled'] and self:IsA("Mouse") then
        if key == "Hit" or key == "Target" then
            if currentTarget then
                local char = currentTarget.Parent
                if char then
                    local player = Players:GetPlayerFromCharacter(char)
                    if player and not isPlayerKnockedOrKO(player) and canSeeTarget(currentTarget) then
                        if not Config['FOV']['Enabled'] or isMouseInFOV(char) then
                            if key == "Hit" then
                                local hitPos = getPredictedPosition(currentTarget, Config['Silent Aim'])
                                return CFrame.new(hitPos)
                            else
                                return currentTarget
                            end
                        end
                    end
                end
            end
        end
    end
    return oldIndex(self, key)
end

-- ========== SPREAD HOOK ==========
local oldRandom
oldRandom = hookfunction(math.random, function(...)
    local args = {...}
    if checkcaller() then
        return oldRandom(...)
    end
    if (#args == 0) or (args[1] == -0.05 and args[2] == 0.05) or (args[1] == -0.1) or (args[1] == -0.05) then
        if Config['Spread']['Enabled'] then
            if Config['Spread']['Specific Weapons']['Enabled'] then
                local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
                if tool then
                    local weaponName = tool.Name
                    local foundWeapon = false
                    for _, weapon in pairs(Config['Spread']['Specific Weapons']['Weapons']) do
                        if weaponName == weapon then
                            foundWeapon = true
                            break
                        end
                    end
                    if foundWeapon then
                        return oldRandom(...) * (Config['Spread']['Amount'] / 100)
                    end
                end
            else
                return oldRandom(...) * (Config['Spread']['Amount'] / 100)
            end
        end
    end
    return oldRandom(...)
end)

-- ========== ESP ==========
local function addESPToPlayer(player)
    if player == LocalPlayer then return end
    local esp = {
        player = player,
        nameTag = Drawing.new("Text"),
    }
    esp.nameTag.Size = 14
    esp.nameTag.Center = true
    esp.nameTag.Outline = true
    esp.nameTag.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.nameTag.Color = Config['Visual Awareness']['Color']
    esp.nameTag.Visible = false
    esp.nameTag.ZIndex = 1000
    espLabels[player.UserId] = esp
end

local function removeESPFromPlayer(player)
    local esp = espLabels[player.UserId]
    if esp then
        esp.nameTag:Remove()
        espLabels[player.UserId] = nil
    end
end

local function refreshESP()
    if not Config['Visual Awareness']['Enabled'] then
        for _, esp in pairs(espLabels) do
            esp.nameTag.Visible = false
        end
        return
    end
    for userId, esp in pairs(espLabels) do
        local player = esp.player
        if not player or not player.Parent then
            esp.nameTag.Visible = false
            esp.nameTag:Remove()
            espLabels[userId] = nil
            continue
        end
        if player.Character and player.Character.Parent and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Head") then
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then
                esp.nameTag.Visible = false
                continue
            end
            local head = player.Character.Head
            local rootPart = player.Character.HumanoidRootPart
            local legPos, onScreen = Camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0))
            if onScreen and legPos.Z > 0 then
                esp.nameTag.Position = Vector2.new(legPos.X, legPos.Y + 15)
                if player.DisplayName and player.DisplayName ~= "" then
                    esp.nameTag.Text = player.DisplayName
                else
                    esp.nameTag.Text = player.Name
                end
                if currentTarget and currentTarget.Parent == player.Character then
                    esp.nameTag.Color = Config['Visual Awareness']['Target Color']
                else
                    esp.nameTag.Color = Config['Visual Awareness']['Color']
                end
                esp.nameTag.Visible = true
            else
                esp.nameTag.Visible = false
            end
        else
            esp.nameTag.Visible = false
        end
    end
end

for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        addESPToPlayer(player)
    end
    player.CharacterAdded:Connect(function(char)
        removeESPFromPlayer(player)
        char:WaitForChild("HumanoidRootPart")
        task.wait(0.1)
        addESPToPlayer(player)
    end)
    player.CharacterRemoving:Connect(function()
        removeESPFromPlayer(player)
    end)
end

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function(char)
            removeESPFromPlayer(player)
            char:WaitForChild("HumanoidRootPart")
            task.wait(0.1)
            addESPToPlayer(player)
        end)
        player.CharacterRemoving:Connect(function()
            removeESPFromPlayer(player)
        end)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeESPFromPlayer(player)
end)

-- ========== SUPER JUMP ==========
RunService.Heartbeat:Connect(function()
    if not Config['Super Jump']['Enabled'] then return end
    local character = LocalPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end
    local holdingB = UserInputService:IsKeyDown(Enum.KeyCode[Config['Keybinds']['Super Jump']])
    if holdingB and (humanoid:GetState() == Enum.HumanoidStateType.Landed or humanoid.FloorMaterial ~= Enum.Material.Air) then
        rootPart.Velocity = Vector3.new(
            rootPart.Velocity.X,
            Config['Super Jump']['Power'],
            rootPart.Velocity.Z
        )
        task.wait(Config['Super Jump']['Cooldown'])
    end
end)

-- ========== SNAPLINE DRAWING ==========
if not snaplineDrawing then
    snaplineDrawing = Drawing.new("Line")
    snaplineDrawing.Visible = false
    snaplineDrawing.Thickness = Config['Snapline']['Thickness']
    snaplineDrawing.Color = Config['Snapline']['Color']
end

-- ========== MAIN LOOP ==========
RunService.RenderStepped:Connect(function()
    if isSelfKnocked() and isLocking then
        currentTarget = nil
        isLocking = false
        lastVisibleTarget = nil
    end

    TriggerBot()

    if SpeedEnabled and Config['Speed']['Enabled'] then
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            local targetSpeed = BaseSpeed * Config['Speed']['Multiplier']
            if humanoid.WalkSpeed ~= targetSpeed then
                humanoid.WalkSpeed = targetSpeed
            end
        end
        if Config['Speed']['Anti Fling'] then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local vel = hrp.Velocity
                if vel.Y > 50 or vel.Y < -50 then
                    hrp.Velocity = Vector3.new(vel.X, 0, vel.Z)
                end
            end
        end
    end

    if Config['Hitbox Expander']['Enabled'] then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.Size = Vector3.new(Config['Hitbox Expander']['Size'], Config['Hitbox Expander']['Size'], Config['Hitbox Expander']['Size'])
                    if Config['Hitbox Expander']['Visualize'] then
                        hrp.Transparency = 0.7
                        hrp.BrickColor = BrickColor.new("Really blue")
                        hrp.Material = "Neon"
                        hrp.CanCollide = false
                    else
                        hrp.Transparency = 1
                    end
                end
            end
        end
    end

    if Config['Spiderman']['Enabled'] then
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if humanoid and hrp then
            local raycastParams = RaycastParams.new()
            raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            local directions = {
                hrp.CFrame.LookVector * 3,
                hrp.CFrame.RightVector * 3,
                -hrp.CFrame.RightVector * 3,
            }
            local foundWall = false
            for _, direction in pairs(directions) do
                local result = Workspace:Raycast(hrp.Position, direction, raycastParams)
                if result and result.Instance then
                    foundWall = true
                    break
                end
            end
            if foundWall then
                if humanoid:GetState() ~= Enum.HumanoidStateType.Climbing then
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
                    humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
                end
                local bodyVelocity = hrp:FindFirstChild("SpidermanVelocity")
                if not bodyVelocity then
                    bodyVelocity = Instance.new("BodyVelocity")
                    bodyVelocity.Name = "SpidermanVelocity"
                    bodyVelocity.MaxForce = Vector3.new(0, 4000, 0)
                    bodyVelocity.Velocity = Vector3.new(0, 0, 0)
                    bodyVelocity.Parent = hrp
                end
            else
                local bodyVelocity = hrp:FindFirstChild("SpidermanVelocity")
                if bodyVelocity then
                    bodyVelocity:Destroy()
                end
            end
        end
    else
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local bodyVelocity = hrp:FindFirstChild("SpidermanVelocity")
            if bodyVelocity then
                bodyVelocity:Destroy()
            end
        end
    end

    updateFOVBox()
    refreshESP()

    if Config['Snapline']['Enabled'] and currentTarget then
        local targetPart = nil
        local targetChar = currentTarget.Parent
        if targetChar then
            targetPart = targetChar:FindFirstChild(Config['Snapline']['TargetPart'])
        end
        if targetPart then
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            local startPos = Vector2.new(Mouse.X, Mouse.Y + Config['Snapline']['MouseOffsetY'])
            snaplineDrawing.From = startPos
            snaplineDrawing.To = Vector2.new(screenPos.X, screenPos.Y)
            snaplineDrawing.Visible = onScreen
        else
            snaplineDrawing.Visible = false
        end
    else
        snaplineDrawing.Visible = false
    end

    applyCameraLock()
end)

-- ========== INPUT HANDLING ==========
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Target Lock']['Key']] then
        local mode = Config['Keybinds']['Target Lock']['Mode']
        if mode == 'Toggle' then
            if Config['Settings']['Target Aim'] then
                if isLocking then
                    isLocking = false
                    currentTarget = nil
                    lastVisibleTarget = nil
                else
                    local target = findClosestTarget()
                    if target then
                        currentTarget = target
                        lastVisibleTarget = target
                        isLocking = true
                    end
                end
            else
                isLocking = not isLocking
            end
        elseif mode == 'Hold' then
            if Config['Settings']['Target Aim'] then
                local target = findClosestTarget()
                if target then
                    currentTarget = target
                    lastVisibleTarget = target
                    isLocking = true
                end
            else
                isLocking = true
            end
        end
    end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Trigger Bot']['Key']] then
        local mode = Config['Keybinds']['Trigger Bot']['Mode']
        if mode == 'Toggle' then
            triggerEnabled = not triggerEnabled
        elseif mode == 'Hold' then
            triggerEnabled = true
        end
    end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Speed']] then
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            if not SpeedEnabled then
                BaseSpeed = 16
                SpeedEnabled = true
            else
                humanoid.WalkSpeed = BaseSpeed
                SpeedEnabled = false
            end
        end
    end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['ESP']] then
        Config['Visual Awareness']['Enabled'] = not Config['Visual Awareness']['Enabled']
    end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Super Jump']] then
        superJumpActive = not superJumpActive
        print("Super Jump: " .. (superJumpActive and "ON" or "OFF"))
    end

    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Camera Lock']] then
        if Config['Camera Lock']['Enabled'] then -- master switch must be on
            camlockEnabled = not camlockEnabled
            camlockTarget = nil
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Target Lock']['Key']] then
        if Config['Keybinds']['Target Lock']['Mode'] == 'Hold' then
            isLocking = false
            currentTarget = nil
            lastVisibleTarget = nil
        end
    end
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Trigger Bot']['Key']] then
        if Config['Keybinds']['Trigger Bot']['Mode'] == 'Hold' then
            triggerEnabled = false
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
end)

-- Rapid Fire
local rapidFireActive = false
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        rapidFireActive = true
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        rapidFireActive = false
    end
end)

RunService.Heartbeat:Connect(function()
    if not Config['Rapid Fire']['Enabled'] or not rapidFireActive then return end
    local character = LocalPlayer.Character
    if not character then return end
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then return end
    if Config['Rapid Fire']['Specific Weapons']['Enabled'] then
        local valid = false
        for _, wName in pairs(Config['Rapid Fire']['Specific Weapons']['Weapons']) do
            if tool.Name == wName then
                valid = true
                break
            end
        end
        if not valid then return end
    end
    tool:Activate()
    task.wait(Config['Rapid Fire']['Delay'])
end)

-- Infinite Range
local infRangeActive = false
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode[Config['Infinite Range']['Key']] then
        infRangeActive = not infRangeActive
        print("Infinite Range: " .. (infRangeActive and "ON" or "OFF"))
    end
end)

RunService.RenderStepped:Connect(function()
    if not Config['Infinite Range']['Enabled'] or not infRangeActive then return end
    local character = LocalPlayer.Character
    if not character then return end
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then return end
    local rangeProps = {"Range", "MaxRange", "FireRange", "Distance", "MaxDistance"}
    for _, propName in pairs(rangeProps) do
        local rangeValue = tool:FindFirstChild(propName)
        if rangeValue and rangeValue:IsA("NumberValue") then
            rangeValue.Value = Config['Infinite Range']['Max Range']
        end
        local config = tool:FindFirstChild("Configuration") or tool:FindFirstChild("GunConfig")
        if config then
            local r = config:FindFirstChild(propName)
            if r and r:IsA("NumberValue") then
                r.Value = Config['Infinite Range']['Max Range']
            end
        end
    end
end)

-- ========== GUI (Status Text) ==========
if Config['UI'] and Config['UI']['Enabled'] then
    local gui = Instance.new("ScreenGui")
    gui.Parent = game.CoreGui

    local text = Instance.new("TextLabel")
    text.Parent = gui
    text.AnchorPoint = Vector2.new(0.5, 1)
    text.Position = UDim2.new(0.5, 0, 1, -110)
    text.Size = UDim2.new(0, 260, 0, 180)
    text.BackgroundTransparency = 1
    text.TextXAlignment = Enum.TextXAlignment.Center
    text.TextYAlignment = Enum.TextYAlignment.Bottom
    text.Font = Enum.Font.Arial
    text.TextSize = 19
    text.RichText = true
    text.TextStrokeTransparency = 0
    text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

    game:GetService("RunService").RenderStepped:Connect(function()
        local lines = {}
        table.insert(lines, '<b><font color="rgb(102,178,255)">2349.wtf</font></b>')

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

        if camlockEnabled then
            local name = camlockTarget and (camlockTarget.DisplayName ~= "" and camlockTarget.DisplayName or camlockTarget.Name) or "none"
            table.insert(lines, '<font color="rgb(255,255,255)">camlock</font><font color="rgb(102,178,255)"> [' .. name .. ']</font>')
        else
            table.insert(lines, '<font color="rgb(255,255,255)">camlock</font>')
        end

        text.Text = table.concat(lines, "\n")
    end)
end
