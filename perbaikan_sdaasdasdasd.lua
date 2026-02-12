--[[
    Roblox Auto-Gifting Macro - V3 (Stable & Strict)
    Fixes:
    1. UI Rendering Strict Check (Wait for list population)
    2. Prompt Verification (Never proceed to WaitLogout if Prompt missing)
    3. Buy Button Stability Check (Animation/Loading safety)
    4. Infinite Loop Fix (State cleanup on failure)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- === CENTRALIZED LOGGER ===
local Logger = {}
Logger.Logs = {}
function Logger:Log(funcName, message)
    local timestamp = os.clock()
    local logEntry = string.format("[%.4f] [%s] %s", timestamp, funcName, message)
    table.insert(self.Logs, logEntry)
    print(logEntry)
    if #self.Logs > 500 then table.remove(self.Logs, 1) end
end
getgenv().ScriptLogger = Logger

-- === STATE MANAGEMENT ===
local State = {
    IsRunning = false,
    GiftsSent = 0,
    TargetAmount = 10,
    TargetUsername = "",
    CurrentItem = "x2 Luck",
    
    -- Preset System
    PresetEnabled = false,
    PresetName = "",
    PresetSteps = {},
    PresetIndex = 1,
    PresetRemaining = 0,
    
    -- Logic Flags
    WaitingLogout = false,
    WaitingLogoutSince = 0,
    LogoutTriggered = false,
    CooldownUntil = 0,
    CompletedLoops = 0,
    RunId = 0,
    
    -- Wait Flags
    WaitingTargetJoin = false,
    WaitingTargetJoinSince = 0,
    TargetJoinCount = 0,
    
    -- Helper
    SavedClickPosition = nil,
    ReadyToClickButton = nil -- Pre-validated button for instant click
}

local Presets = {}
local PresetOrder = {}

-- Setup Presets
Presets["Only x2"] = {{product = "x2 Luck", count = 1}}
table.insert(PresetOrder, "Only x2")
Presets["Only x8"] = {{product = "x8 Luck", count = 1}}
table.insert(PresetOrder, "Only x8")
for i = 7, 24 do
    local name = i .. " Jam"
    Presets[name] = {{product = "x2 Luck", count = i - 5}, {product = "x8 Luck", count = 1}}
    table.insert(PresetOrder, name)
end
Presets["48 Jam"] = {{product = "x2 Luck", count = 43}, {product = "x8 Luck", count = 1}}
table.insert(PresetOrder, "48 Jam")
Presets["72 Jam"] = {{product = "x2 Luck", count = 67}, {product = "x8 Luck", count = 1}}
table.insert(PresetOrder, "72 Jam")
Presets["98 Jam"] = {{product = "x2 Luck", count = 93}, {product = "x8 Luck", count = 1}}
table.insert(PresetOrder, "98 Jam")

local function applyPreset(name)
    local steps = Presets[name]
    if not steps then return false end
    State.PresetEnabled = true
    State.PresetName = name
    State.PresetSteps = steps
    State.PresetIndex = 1
    State.PresetRemaining = steps[1].count
    State.CurrentItem = steps[1].product
    return true
end

local function normalizeUsername(name)
    local trimmed = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return nil, "Username Empty" end
    return string.lower(trimmed)
end

-- === UI CREATION ===
local ScreenGui = Instance.new("ScreenGui")
local MainFrame = Instance.new("Frame")
local TitleLabel = Instance.new("TextLabel")
local UsernameBox = Instance.new("TextBox")
local PresetButton = Instance.new("TextButton")
local PresetLabel = Instance.new("TextLabel")
local ToggleButton = Instance.new("TextButton")
local StatusLabel = Instance.new("TextLabel")
local CloseButton = Instance.new("TextButton")

local parentTarget = (gethui and gethui()) or (game.CoreGui) or LocalPlayer:WaitForChild("PlayerGui")
ScreenGui.Parent = parentTarget
ScreenGui.Name = "AutoGift_V3_Fix"
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
MainFrame.Position = UDim2.new(0.5, -125, 0.5, -100)
MainFrame.Size = UDim2.new(0, 250, 0, 300)
MainFrame.Active = true
MainFrame.Draggable = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

TitleLabel.Parent = MainFrame
TitleLabel.BackgroundTransparency = 1
TitleLabel.Position = UDim2.new(0, 0, 0, 10)
TitleLabel.Size = UDim2.new(1, 0, 0, 30)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "AUTO GIFT V3 (STRICT)"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextSize = 18

UsernameBox.Parent = MainFrame
UsernameBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
UsernameBox.Position = UDim2.new(0.1, 0, 0.20, 0)
UsernameBox.Size = UDim2.new(0.8, 0, 0, 35)
UsernameBox.Font = Enum.Font.Gotham
UsernameBox.PlaceholderText = "Target Username..."
UsernameBox.Text = ""
UsernameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
UsernameBox.TextSize = 14
Instance.new("UICorner", UsernameBox).CornerRadius = UDim.new(0, 6)

PresetButton.Parent = MainFrame
PresetButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
PresetButton.Position = UDim2.new(0.1, 0, 0.35, 0)
PresetButton.Size = UDim2.new(0.8, 0, 0, 35)
PresetButton.Font = Enum.Font.Gotham
PresetButton.Text = "Preset: Only x2"
PresetButton.TextColor3 = Color3.fromRGB(255, 255, 255)
PresetButton.TextSize = 14
Instance.new("UICorner", PresetButton).CornerRadius = UDim.new(0, 6)

PresetLabel.Parent = MainFrame
PresetLabel.BackgroundTransparency = 1
PresetLabel.Position = UDim2.new(0.1, 0, 0.50, 0)
PresetLabel.Size = UDim2.new(0.8, 0, 0, 30)
PresetLabel.Font = Enum.Font.Gotham
PresetLabel.Text = "Status Preset: -"
PresetLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
PresetLabel.TextSize = 12

ToggleButton.Parent = MainFrame
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
ToggleButton.Position = UDim2.new(0.1, 0, 0.65, 0)
ToggleButton.Size = UDim2.new(0.8, 0, 0, 40)
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Text = "START"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.TextSize = 16
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0, 6)

StatusLabel.Parent = MainFrame
StatusLabel.BackgroundTransparency = 1
StatusLabel.Position = UDim2.new(0, 0, 0.82, 0)
StatusLabel.Size = UDim2.new(1, 0, 0, 40)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Text = "Idle"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.TextSize = 11
StatusLabel.TextWrapped = true

CloseButton.Parent = MainFrame
CloseButton.BackgroundTransparency = 1
CloseButton.Position = UDim2.new(0.85, 0, 0, 0)
CloseButton.Size = UDim2.new(0.15, 0, 0.15, 0)
CloseButton.Font = Enum.Font.GothamBold
CloseButton.Text = "X"
CloseButton.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseButton.TextSize = 14
CloseButton.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

local selectedPresetIndex = 1
local function updatePresetButton()
    local name = PresetOrder[selectedPresetIndex] or PresetOrder[1]
    PresetButton.Text = "Preset: " .. tostring(name)
end
PresetButton.MouseButton1Click:Connect(function()
    selectedPresetIndex = selectedPresetIndex + 1
    if selectedPresetIndex > #PresetOrder then selectedPresetIndex = 1 end
    updatePresetButton()
end)

-- === CORE FUNCTIONS ===

local GiftingController
pcall(function()
    GiftingController = require(ReplicatedStorage:WaitForChild("Controllers"):WaitForChild("GiftingController"))
end)

local function getGiftingGui()
    return PlayerGui:FindFirstChild("!!! Gifting")
end

local function isVisibleGuiObject(obj)
    if not obj or not obj:IsA("GuiObject") then return false end
    if not obj.Visible then return false end
    if obj.AbsoluteSize.X <= 0 or obj.AbsoluteSize.Y <= 0 then return false end
    
    local current = obj
    while current do
        if current == game then return true end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        if current:IsA("GuiObject") and not current.Visible then return false end
        current = current.Parent
    end
    return true
end

-- STRICT UI CHECK: Ensures UI is fully rendered
local function isGiftUiTrulyReady()
    local gui = getGiftingGui()
    if not gui or not gui.Enabled then return false end
    
    -- Check if content is populated
    local scrollFrame = gui:FindFirstChild("ScrollingFrame", true) or gui:FindFirstChild("PlayerList", true)
    if not scrollFrame then return false end
    
    -- Check for at least one player entry (shows data is loaded)
    for _, child in pairs(scrollFrame:GetDescendants()) do
        if child:IsA("TextLabel") and child.Text ~= "" then
            return true
        end
    end
    return false
end

local function HighlightObject(obj, color)
    pcall(function()
        local h = Instance.new("Frame")
        h.Name = "DebugHighlight"
        h.Size = UDim2.new(0, obj.AbsoluteSize.X + 4, 0, obj.AbsoluteSize.Y + 4)
        h.Position = UDim2.new(0, obj.AbsolutePosition.X - 2, 0, obj.AbsolutePosition.Y - 2)
        h.BackgroundTransparency = 1
        h.BorderSizePixel = 2
        h.BorderColor3 = color or Color3.new(1, 0, 0)
        h.Parent = ScreenGui
        game.Debris:AddItem(h, 1)
    end)
end

local function SuperClick(button)
    local absPos = button.AbsolutePosition
    local absSize = button.AbsoluteSize
    local inset = GuiService:GetGuiInset()
    local centerX = absPos.X + absSize.X/2 + inset.X
    local centerY = absPos.Y + absSize.Y/2 + inset.Y
    
    if VirtualInputManager then
        VirtualInputManager:SendMouseMoveEvent(centerX, centerY, game)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
    end
end

-- === BUY BUTTON DETECTION ===

local function findBuyButton()
    local coreGui = game:GetService("CoreGui")
    local purchasePrompt = coreGui:FindFirstChild("PurchasePromptApp") or coreGui:FindFirstChild("PurchasePrompt")
    
    if purchasePrompt then
        for _, d in ipairs(purchasePrompt:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Visible then
                -- Check standard Roblox Buy Button characteristics
                if d.Name == "ConfirmButton" or string.lower(d.Name):find("buy") then
                     return d
                end
                -- Text fallback
                if d:IsA("TextButton") and string.lower(d.Text):find("buy") then
                    return d
                end
            end
        end
    end
    return nil
end

local function isBuyButtonTrulyReady(btn)
    if not btn then return false end
    if not isVisibleGuiObject(btn) then return false end
    
    -- STABILITY CHECK: Animation & Transparency
    if btn:IsA("GuiObject") then
        if btn.BackgroundTransparency > 0.9 and btn.ImageTransparency > 0.9 then
             -- Button might be invisible/fading
             return false
        end
        -- Check for Loading spinner
        if btn:FindFirstChild("Loading", true) or btn:FindFirstChild("Spinner", true) then
            return false
        end
    end
    
    return true
end

local function isPurchasePromptVisible()
    local btn = findBuyButton()
    return isBuyButtonTrulyReady(btn)
end

local function closeGiftingUi()
    if GiftingController and GiftingController.Close then
        pcall(function() GiftingController:Close() end)
    end
    local gui = getGiftingGui()
    if gui then gui.Enabled = false end
end

-- === MAIN LOGIC ===

local function triggerBuyOnLogout()
    if not State.IsRunning or State.LogoutTriggered then return end
    State.LogoutTriggered = true
    
    Logger:Log("Trigger", "Target Logout Detected. EXECUTING INSTANT PURCHASE!")
    
    -- INSTANT CLICK (User Req: "tombol klik benar benar di klik (instant)")
    -- Use the pre-validated button if available
    local btn = State.ReadyToClickButton
    
    -- Fallback check (only if variable is stale, but we trust logic)
    if not btn then btn = findBuyButton() end 
    
    if btn then
        SuperClick(btn)
    else
        Logger:Log("Error", "Buy Button lost at critical moment!")
        StatusLabel.Text = "Error: Buy Button Missing"
        State.LogoutTriggered = false
        State.WaitingLogout = false
        return
    end
    
    -- We wait for the event listener to handle success/failure logic
    -- Do NOT immediately reset state here.
    
    -- Failsafe timeout
    task.delay(5, function()
        if State.LogoutTriggered then
            Logger:Log("Timeout", "Purchase timeout/failed.")
            State.LogoutTriggered = false
            State.WaitingLogout = false
            closeGiftingUi()
        end
    end)
end

-- === EVENT LISTENERS ===

local function onPurchaseFinished(isPurchased)
    if not State.IsRunning then return end
    
    if isPurchased then
        Logger:Log("Success", "Purchase Confirmed!")
        State.GiftsSent = State.GiftsSent + 1
        State.CompletedLoops = State.CompletedLoops + 1
        
        -- Decrement Preset ONLY on success
        if State.PresetEnabled then
            State.PresetRemaining = State.PresetRemaining - 1
            if State.PresetRemaining <= 0 then
                State.PresetIndex = State.PresetIndex + 1
                if State.PresetIndex > #State.PresetSteps then
                    State.PresetIndex = 1
                end
                local step = State.PresetSteps[State.PresetIndex]
                State.PresetRemaining = step.count
                State.CurrentItem = step.product
            end
            PresetLabel.Text = "Preset: " .. State.CurrentItem .. " (" .. State.PresetRemaining .. " left)"
        else
            StatusLabel.Text = "Sent: " .. State.GiftsSent .. "/" .. State.TargetAmount
        end
        
        -- Proceed to Next Cycle
        State.WaitingLogout = false
        State.LogoutTriggered = false
        State.WaitingTargetJoin = true
        State.WaitingTargetJoinSince = os.clock()
        State.TargetJoinCount = 0
        
        closeGiftingUi()
    else
        Logger:Log("Info", "Purchase Cancelled/Failed.")
        State.LogoutTriggered = false
        State.WaitingLogout = false -- Reset to try again
    end
end

MarketplaceService.PromptPurchaseFinished:Connect(function(player, assetId, isPurchased)
    if player == LocalPlayer then onPurchaseFinished(isPurchased) end
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
    if userId == LocalPlayer.UserId then onPurchaseFinished(isPurchased) end
end)

Players.PlayerRemoving:Connect(function(player)
    if not State.IsRunning then return end
    if not State.WaitingLogout then return end
    
    if normalizeUsername(player.Name) == State.TargetUsername or normalizeUsername(player.DisplayName) == State.TargetUsername then
        triggerBuyOnLogout()
    end
end)

Players.PlayerAdded:Connect(function(player)
    if State.IsRunning and State.WaitingTargetJoin then
        if normalizeUsername(player.Name) == State.TargetUsername or normalizeUsername(player.DisplayName) == State.TargetUsername then
            State.TargetJoinCount = State.TargetJoinCount + 1
            Logger:Log("Event", "Target Joined! Count: " .. State.TargetJoinCount)
        end
    end
end)

-- === PROCESS LOOP ===

local function ProcessLogic()
    if not State.IsRunning then return end
    
    -- 1. WAITING FOR TARGET TO REJOIN
    if State.WaitingTargetJoin then
        if State.TargetJoinCount >= 1 then -- Require 1 rejoin (since we clicked on logout)
            Logger:Log("Logic", "Target rejoined. Resuming flow.")
            State.WaitingTargetJoin = false
            task.wait(2) -- Allow character to load
        else
            StatusLabel.Text = "Waiting Target Join..."
            if os.clock() - State.WaitingTargetJoinSince > 300 then
                Logger:Log("Timeout", "Target failed to rejoin.")
                State.IsRunning = false
                ToggleButton.Text = "START"
            end
            return
        end
    end
    
    -- 2. WAITING FOR LOGOUT (Idle State)
    if State.WaitingLogout then
        StatusLabel.Text = "Waiting Logout..."
        -- Safety check: If Prompt disappeared, abort wait
        if not isPurchasePromptVisible() then
             -- Double check
             task.wait(0.5)
             if not isPurchasePromptVisible() then
                 Logger:Log("Error", "Prompt lost while waiting logout. Resetting.")
                 State.WaitingLogout = false
                 closeGiftingUi()
             end
        end
        return
    end
    
    -- 3. OPEN UI
    local gui = getGiftingGui()
    if not gui or not gui.Enabled then
        StatusLabel.Text = "Opening Gift UI..."
        if GiftingController then GiftingController:Open(State.CurrentItem) end
        
        -- Wait for UI Rendering (Strict)
        local t0 = os.clock()
        while os.clock() - t0 < 3 do
            if isGiftUiTrulyReady() then break end
            task.wait(0.1)
        end
    end
    
    if not isGiftUiTrulyReady() then return end -- Retry next loop
    
    -- 4. FIND & CLICK TARGET
    StatusLabel.Text = "Scanning Target..."
    local found = false
    local scrollFrame = gui:FindFirstChild("ScrollingFrame", true) or gui:FindFirstChild("PlayerList", true)
    
    if scrollFrame then
        for _, lbl in pairs(scrollFrame:GetDescendants()) do
            if (lbl:IsA("TextLabel") or lbl:IsA("TextBox")) then
                local lblText = string.lower(lbl.Text)
                local target = State.TargetUsername
                
                -- Smart Match: Exact match OR Contained (e.g. "@Username" or "Display (@Username)")
                if lblText == target or lblText:find(target, 1, true) then
                    HighlightObject(lbl, Color3.new(0, 1, 1))
                    
                    -- Find Gift Button
                    local container = lbl.Parent
                    local giftBtn = nil
                    
                    -- Optimized search
                    for _, child in pairs(container:GetDescendants()) do
                        if child:IsA("GuiButton") and child.Visible and (string.lower(child.Name):find("gift") or string.lower(child.Text):find("gift")) then
                            giftBtn = child
                            break
                        end
                    end
                    
                    if giftBtn then
                        HighlightObject(giftBtn, Color3.new(0, 1, 0))
                        
                        -- CLICK
                        SuperClick(giftBtn)
                        found = true
                        
                        -- 5. VERIFY PROMPT (User Req 1 & 3)
                        StatusLabel.Text = "Verifying Prompt..."
                    local promptOpen = false
                    local waitStart = os.clock()
                    local confirmedBtn = nil
                    
                    while os.clock() - waitStart < 3.0 do
                        local b = findBuyButton()
                        if isBuyButtonTrulyReady(b) then
                            confirmedBtn = b
                            promptOpen = true
                            break
                        end
                        task.wait(0.1)
                    end
                    
                    if promptOpen and confirmedBtn then
                        -- PRE-LOGOUT STABILITY CHECK (Strict Mode)
                        StatusLabel.Text = "Stabilizing Prompt..."
                        local stableStart = os.clock()
                        local isStable = false
                        
                        -- Ensure it remains ready for at least 0.5 seconds continuous
                        while os.clock() - stableStart < 0.8 do 
                             if isBuyButtonTrulyReady(confirmedBtn) then
                                 isStable = true
                             else
                                 isStable = false
                                 break -- Failed stability, will retry loop or fail
                             end
                             task.wait(0.1)
                        end
                        
                        if isStable then
                            Logger:Log("Logic", "Prompt Stable & Ready. Waiting for Logout.")
                            State.ReadyToClickButton = confirmedBtn -- SAVE BUTTON FOR INSTANT CLICK
                            State.WaitingLogout = true
                        else
                            Logger:Log("Warning", "Prompt Unstable (Loading/Animating). Retrying...")
                            closeGiftingUi()
                        end
                    else
                        Logger:Log("Error", "Clicked Gift but Prompt did NOT appear.")
                        closeGiftingUi() 
                    end
                    
                    break -- Stop scanning
                end
            end
        end
    end
    
    if not found then
        StatusLabel.Text = "Target Not Found in List"
        -- Scroll down? Or just retry
    end
end

-- === CONTROLS ===

ToggleButton.MouseButton1Click:Connect(function()
    if State.IsRunning then
        State.IsRunning = false
        ToggleButton.Text = "START"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
        StatusLabel.Text = "Stopped"
    else
        local user, err = normalizeUsername(UsernameBox.Text)
        if not user then StatusLabel.Text = err return end
        
        State.TargetUsername = user
        State.IsRunning = true
        
        -- Reset Flags
        State.WaitingLogout = false
        State.WaitingTargetJoin = false
        State.GiftsSent = 0
        
        -- Apply Preset
        local presetName = PresetOrder[selectedPresetIndex]
        applyPreset(presetName)
        PresetLabel.Text = "Preset: " .. State.CurrentItem .. " (" .. State.PresetRemaining .. " left)"
        
        ToggleButton.Text = "STOP"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
        
        -- Initial Open
        if GiftingController then GiftingController:Open(State.CurrentItem) end
    end
end)

-- Main Loop
task.spawn(function()
    while true do
        task.wait(0.5)
        pcall(ProcessLogic)
    end
end)

