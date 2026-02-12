--[[
    Roblox Auto-Gifting Macro (Based on 'script' file)
    Status: Base Code Restored + Improved Buy Detection
    
    LOCKED SECTIONS:
    - Open UI Logic
    - Search Username Logic
    - Click Gift Button Logic
    
    IMPROVEMENTS:
    - Enhanced Confirm Button Detection (Step 4)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- === CENTRALIZED LOGGER SYSTEM ===
    local Logger = {}
    Logger.Logs = {}
    Logger.StartTime = os.clock()
    
    function Logger:Log(funcName, message, data)
        local timestamp = os.clock()
        local threadId = tostring(coroutine.running())
        local memUsage = collectgarbage("count")
        -- Simplified thread ID for readability
        threadId = string.sub(threadId, 8) 
        
        local logEntry = string.format("[%.4f] [Mem:%.0fKB] [%s] %s", timestamp, memUsage, funcName, message)
        if data then
            logEntry = logEntry .. " | Data: " .. tostring(data)
        end
        
        table.insert(self.Logs, logEntry)
        print(logEntry) -- Output to console
        
        -- Keep log size manageable
        if #self.Logs > 1000 then
            table.remove(self.Logs, 1)
        end
    end
    
    -- Expose Logger to Global (for debugging)
    getgenv().ScriptLogger = Logger

    -- === SECURITY AUDIT SYSTEM ===
    local function PerformSecurityAudit()
        Logger:Log("Audit", "Starting Security Audit...")
        local threats = {}
        
        -- 1. Check for hidden HTTP hooks
        local httpCheck = http_request or request or HttpPost or syn.request
        if httpCheck then
            table.insert(threats, "Custom HTTP Request function found (Potential Data Exfiltration)")
        end
        
        -- 2. Check for unauthorized GUI injections
        local success, coreGui = pcall(function() return game:GetService("CoreGui") end)
        if success and coreGui then
            if coreGui:FindFirstChild("HiddenLog") then
                table.insert(threats, "Suspicious GUI 'HiddenLog' found in CoreGui")
            end
        end
        
        -- Report
        if #threats > 0 then
            Logger:Log("Audit", "SECURITY RISKS DETECTED: " .. table.concat(threats, "; "))
        else
            Logger:Log("Audit", "System Integrity Check Passed. No unauthorized hooks detected.")
        end
    end
    PerformSecurityAudit()

    -- === STATE MANAGEMENT ===
local State = {
    IsRunning = false,
    GiftsSent = 0,
    TargetAmount = 10,
    TargetUsername = "",
    CurrentItem = "x2 Luck",
    PresetEnabled = false,
    PresetName = "",
    PresetSteps = {},
    PresetIndex = 1,
    PresetRemaining = 0,
    WaitingLogout = false,
    WaitingLogoutSince = 0,
    LogoutTriggered = false,
    CooldownUntil = 0,
    CompletedLoops = 0,
    RunId = 0,
    IgnoreToggle = false,
    WaitingForBoost = false,
    WaitingBoostSince = 0,
    WaitingTargetJoin = false,
    WaitingTargetJoinSince = 0
}

local Presets = {}
local PresetOrder = {}

-- Preset Manual (Single Run)
Presets["Only x2"] = {{product = "x2 Luck", count = 1}}
table.insert(PresetOrder, "Only x2")

Presets["Only x8"] = {{product = "x8 Luck", count = 1}}
table.insert(PresetOrder, "Only x8")

-- Generator Preset Otomatis (7-24 Jam)
for i = 7, 24 do
    local name = i .. " Jam"
    Presets[name] = {
        {product = "x2 Luck", count = i - 5},
        {product = "x8 Luck", count = 1}
    }
    table.insert(PresetOrder, name)
end

-- Preset Khusus (48 Jam & 72 Jam)
Presets["48 Jam"] = {{product = "x2 Luck", count = 43}, {product = "x8 Luck", count = 1}}
table.insert(PresetOrder, "48 Jam")

Presets["72 Jam"] = {{product = "x2 Luck", count = 67}, {product = "x8 Luck", count = 1}}
table.insert(PresetOrder, "72 Jam")

Presets["98 Jam"] = {{product = "x2 Luck", count = 93}, {product = "x8 Luck", count = 1}}
table.insert(PresetOrder, "98 Jam")

local function applyPreset(name)
    local steps = Presets[name]
    if not steps then
        return false
    end
    State.PresetEnabled = true
    State.PresetName = name
    State.PresetSteps = steps
    State.PresetIndex = 1
    State.PresetRemaining = steps[1].count
    State.CurrentItem = steps[1].product
    return true
end

local function normalizeUsername(name)
    local trimmed = tostring(name or "")
    trimmed = string.gsub(trimmed, "^%s+", "")
    trimmed = string.gsub(trimmed, "%s+$", "")
    if trimmed == "" then
        return nil, "Error: Masukkan Username!"
    end
    if #trimmed < 3 or #trimmed > 20 then
        return nil, "Error: Username tidak valid!"
    end
    if not string.match(trimmed, "^[%w_]+$") then
        return nil, "Error: Username tidak valid!"
    end
    return trimmed
end

-- Audit: Check for hidden HTTP usage
    local HttpService = game:GetService("HttpService")
    local oldRequest = http_request or request or HttpPost or syn.request
    if oldRequest then
        Logger:Log("Audit", "WARNING: HTTP Request function found in environment.")
    end

    -- === UI CREATION ===
print("[DEBUG] Starting UI Creation...")
local ScreenGui = Instance.new("ScreenGui")
local MainFrame = Instance.new("Frame")
local TitleLabel = Instance.new("TextLabel")
local UsernameBox = Instance.new("TextBox")
local PresetButton = Instance.new("TextButton")
local PresetLabel = Instance.new("TextLabel")
local ToggleButton = Instance.new("TextButton")
local StatusLabel = Instance.new("TextLabel")
local CloseButton = Instance.new("TextButton")

-- UI Setup (Safe Parent)
local parentTarget = nil
pcall(function()
    if gethui then 
        parentTarget = gethui()
        print("[DEBUG] Using gethui()")
    elseif game.CoreGui then 
        parentTarget = game.CoreGui
        print("[DEBUG] Using CoreGui")
    else 
        parentTarget = LocalPlayer:WaitForChild("PlayerGui") 
        print("[DEBUG] Using PlayerGui")
    end
end)

if not parentTarget then
    warn("[DEBUG] No valid parent found! Defaulting to PlayerGui")
    parentTarget = LocalPlayer:WaitForChild("PlayerGui")
end

ScreenGui.Parent = parentTarget
ScreenGui.Name = "AutoGiftUI_DEBUG_" .. math.random(1000,9999)
print("[DEBUG] ScreenGui created in " .. tostring(parentTarget))

-- Styling UI
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.Position = UDim2.new(0.5, -125, 0.5, -100)
MainFrame.Size = UDim2.new(0, 250, 0, 280) 
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true

-- Corner Radius
local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

TitleLabel.Parent = MainFrame
TitleLabel.BackgroundTransparency = 1
TitleLabel.Position = UDim2.new(0, 0, 0, 10)
TitleLabel.Size = UDim2.new(1, 0, 0, 30)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "BOOST DETECTOR BY RUDO"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextSize = 18

UsernameBox.Parent = MainFrame
UsernameBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
UsernameBox.Position = UDim2.new(0.1, 0, 0.25, 0)
UsernameBox.Size = UDim2.new(0.8, 0, 0, 35)
UsernameBox.Font = Enum.Font.Gotham
UsernameBox.PlaceholderText = "Username Target..."
UsernameBox.Text = ""
UsernameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
UsernameBox.TextSize = 14
Instance.new("UICorner", UsernameBox).CornerRadius = UDim.new(0, 6)

PresetButton.Parent = MainFrame
PresetButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
PresetButton.Position = UDim2.new(0.1, 0, 0.45, 0)
PresetButton.Size = UDim2.new(0.8, 0, 0, 35)
PresetButton.Font = Enum.Font.Gotham
PresetButton.Text = "Preset: 7 Jam"
PresetButton.TextColor3 = Color3.fromRGB(255, 255, 255)
PresetButton.TextSize = 14
Instance.new("UICorner", PresetButton).CornerRadius = UDim.new(0, 6)

PresetLabel.Parent = MainFrame
PresetLabel.BackgroundTransparency = 1
PresetLabel.Position = UDim2.new(0.1, 0, 0.60, 0)
PresetLabel.Size = UDim2.new(0.8, 0, 0, 34)
PresetLabel.Font = Enum.Font.Gotham
PresetLabel.Text = "Preset: pilih dari dropdown"
PresetLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
PresetLabel.TextSize = 11
PresetLabel.TextWrapped = true
PresetLabel.TextXAlignment = Enum.TextXAlignment.Left

local selectedPresetIndex = 1
local function updatePresetButton()
    local name = PresetOrder[selectedPresetIndex] or PresetOrder[1]
    PresetButton.Text = "Preset: " .. tostring(name or "")
end
updatePresetButton()
PresetButton.MouseButton1Click:Connect(function()
    selectedPresetIndex = selectedPresetIndex + 1
    if selectedPresetIndex > #PresetOrder then
        selectedPresetIndex = 1
    end
    updatePresetButton()
end)

ToggleButton.Parent = MainFrame
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
ToggleButton.Position = UDim2.new(0.1, 0, 0.74, 0)
ToggleButton.Size = UDim2.new(0.8, 0, 0, 40)
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Text = "START"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.TextSize = 16
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0, 6)

StatusLabel.Parent = MainFrame
StatusLabel.BackgroundTransparency = 1
StatusLabel.Position = UDim2.new(0, 0, 0.90, 0)
StatusLabel.Size = UDim2.new(1, 0, 0, 30)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Text = "Status: Idle (0/0)"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.TextSize = 11
StatusLabel.TextWrapped = true

-- Close Button
CloseButton.Parent = MainFrame
CloseButton.BackgroundTransparency = 1
CloseButton.Position = UDim2.new(0.85, 0, 0, 0)
CloseButton.Size = UDim2.new(0.15, 0, 0.15, 0)
CloseButton.Font = Enum.Font.GothamBold
CloseButton.Text = "X"
CloseButton.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseButton.TextSize = 14
CloseButton.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- === LOGIC ===
-- Load Controller
local GiftingController
local MarketplaceService = game:GetService("MarketplaceService")
pcall(function()
    GiftingController = require(ReplicatedStorage:WaitForChild("Controllers"):WaitForChild("GiftingController"))
end)

-- Global State untuk Posisi Tombol
State.SavedClickPosition = nil
local lastLogoutTrigger = 0

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
    
    -- Visual Debug Dot (Green)
    pcall(function()
        local dot = Instance.new("Frame")
        dot.Name = "DebugClickDot"
        dot.Size = UDim2.new(0, 10, 0, 10)
        dot.Position = UDim2.new(0, centerX-5, 0, centerY-5)
        dot.BackgroundColor3 = Color3.new(0, 1, 0)
        dot.BorderSizePixel = 0
        dot.Parent = ScreenGui
        game:GetService("Debris"):AddItem(dot, 1)
    end)

    -- Virtual Debug (Mouse Move)
    if VirtualInputManager then
        VirtualInputManager:SendMouseMoveEvent(centerX, centerY, game)
    end
    
    -- Script Click (Trigger Event Internal)
    local events = {"MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "Activated"}
    if getconnections then
        for _, eventName in pairs(events) do
            if button[eventName] then
                for _, connection in pairs(getconnections(button[eventName])) do
                    connection:Fire()
                end
            end
        end
    elseif button.Activate then
        pcall(function()
            button:Activate()
        end)
    end

    -- Virtual Click (Simulasi Hardware)
    if VirtualInputManager then
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
    end

    -- VirtualUser Click (Backup)
    pcall(function()
        game:GetService("VirtualUser"):ClickButton1(Vector2.new(centerX, centerY))
    end)
end

local function findAncestorButton(obj)
    local current = obj
    while current do
        if current:IsA("GuiButton") then
            return current
        end
        current = current.Parent
    end
    return nil
end

local function getCoreGuiSafe()
    local success, service = pcall(function() return game:GetService("CoreGui") end)
    if success and service then return service end
    
    -- Fallback: If we cannot access CoreGui, return nil (don't try direct indexing if GetService failed)
    return nil
end

local function findPromptBuyButton(promptRoot)
    if not promptRoot then
        return nil
    end
    for _, d in ipairs(promptRoot:GetDescendants()) do
        if d:IsA("TextLabel") then
            local t = string.lower(d.Text or "")
            if t == "buy" then
                local btn = findAncestorButton(d)
                if btn and btn.Visible then
                    return btn
                end
            end
        elseif d:IsA("TextButton") or d:IsA("ImageButton") then
            if d.Visible then
                local t = ""
                if d:IsA("TextButton") then
                    t = string.lower(d.Text or "")
                end
                if t == "buy" and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 then
                    return d
                end
            end
        end
    end
    return nil
end

local function findBuyButton()
    local coreGui = getCoreGuiSafe()
    local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui") or nil
    
    -- [A] PRIORITY: CoreGui PurchasePrompt (Standard Roblox Prompt)
    if coreGui then
        local promptApp = coreGui:FindFirstChild("PurchasePromptApp")
        local btn = findPromptBuyButton(promptApp)
        if btn then return btn end
        
        -- Fallback Scan in CoreGui
        for _, d in ipairs(coreGui:GetDescendants()) do
            if d:IsA("TextLabel") then
                local t = string.lower(d.Text or "")
                if t == "buy" then
                    local b = findAncestorButton(d)
                    if b and b.Visible then
                        return b
                    end
                end
            elseif d:IsA("TextButton") or d:IsA("ImageButton") then
                if d.Visible then
                    local t = ""
                    if d:IsA("TextButton") then
                        t = string.lower(d.Text or "")
                    end
                    if t:find("buy", 1, true) and d.AbsoluteSize.X > 80 and d.AbsoluteSize.Y > 20 then
                        return d
                    end
                end
            end
        end
    end

    -- [B] PRIORITY: PlayerGui (Custom Prompts or Fallback)
    if playerGui then
        for _, d in ipairs(playerGui:GetDescendants()) do
            if d:IsA("TextLabel") then
                local t = string.lower(d.Text or "")
                if t == "buy" then
                    local b = findAncestorButton(d)
                    if b and b.Visible then
                        return b
                    end
                end
            elseif d:IsA("TextButton") or d:IsA("ImageButton") then
                if d.Visible then
                    local t = ""
                    if d:IsA("TextButton") then
                        t = string.lower(d.Text or "")
                    end
                    if t:find("buy", 1, true) and d.AbsoluteSize.X > 80 and d.AbsoluteSize.Y > 20 then
                        return d
                    end
                end
            end
        end
    end

    return nil
end

local function isPurchasePromptVisible()
    local coreGui = getCoreGuiSafe()
    if coreGui then
        local promptApp = coreGui:FindFirstChild("PurchasePromptApp")
        if promptApp and promptApp:IsA("ScreenGui") and promptApp.Enabled then
            return true
        end
    end
    return findBuyButton() ~= nil
end

local function getGiftingGui()
    local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui") or nil
    if not pg then
        return nil
    end
    return pg:FindFirstChild("!!! Gifting")
end

local function waitForGiftUi(timeout)
    local giftingGui = getGiftingGui()
    if not giftingGui then
        return false
    end
    local t0 = os.clock()
    local limit = timeout or 2
    while os.clock() - t0 < limit do
        if not State.IsRunning then return false end -- BREAK IF STOPPED
        if giftingGui.Enabled == true then
            return true
        end
        task.wait(0.05)
    end
    return giftingGui.Enabled == true
end

local function isVisibleGuiObject(obj)
    if not obj:IsA("GuiObject") then
        return false
    end
    if not obj.Visible then
        return false
    end
    if obj.AbsoluteSize.X <= 0 or obj.AbsoluteSize.Y <= 0 then
        return false
    end
    local current = obj
    while current do
        if current:IsA("ScreenGui") then
            if current.Enabled == false then
                return false
            end
            break
        end
        if current:IsA("GuiObject") and current.Visible == false then
            return false
        end
        current = current.Parent
    end
    return true
end

local function hasBoostNotice()
    local function scan(root)
        for _, d in ipairs(root:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and isVisibleGuiObject(d) then
                local t = string.lower(d.Text or "")
                if t:find("boosted server luck", 1, true) then
                    return true
                end
            end
        end
        return false
    end
    local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui") or nil
    if pg and scan(pg) then
        return true
    end
    local coreGui = getCoreGuiSafe()
    if coreGui and scan(coreGui) then
        return true
    end
    return false
end

-- New Function: Specific handler for Purchase Success Modal
local function dismissPurchaseSuccessModal()
    local coreGui = getCoreGuiSafe()
    if not coreGui then return false end
    
    local found = false
    
    local function scanAndClick(root)
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("TextLabel") and isVisibleGuiObject(d) then
                local txt = string.lower(d.Text)
                if txt:find("purchase completed") or txt:find("pembelian berhasil") or txt:find("successfully bought") then
                    Logger:Log("DismissModal", "Found success text: " .. d.Text)
                    -- Search for OK button in the vicinity (up to 3 levels up)
                    local searchRoot = d.Parent
                    for i = 1, 3 do
                        if not searchRoot then break end
                        for _, btn in ipairs(searchRoot:GetDescendants()) do
                            if btn:IsA("TextButton") and isVisibleGuiObject(btn) and string.lower(btn.Text) == "ok" then
                                Logger:Log("DismissModal", "Clicking OK button")
                                SuperClick(btn)
                                found = true
                                return true
                            end
                        end
                        searchRoot = searchRoot.Parent
                    end
                end
            end
        end
        return false
    end

    local promptApp = coreGui:FindFirstChild("PurchasePromptApp")
    if promptApp then 
        if scanAndClick(promptApp) then return true end
    end
    
    local robloxGui = coreGui:FindFirstChild("RobloxGui")
    if robloxGui then 
        if scanAndClick(robloxGui) then return true end
    end
    
    return found
end

local function closePurchasePrompt()
    -- Try to click OK first
    pcall(dismissPurchaseSuccessModal)
    
    local coreGui = getCoreGuiSafe()
    if not coreGui then return end

    local prompt = coreGui:FindFirstChild("PurchasePromptApp")
    if prompt and prompt:IsA("ScreenGui") then
        prompt.Enabled = false
    end
    local purchasePrompt = coreGui:FindFirstChild("PurchasePrompt")
    if purchasePrompt and purchasePrompt:IsA("ScreenGui") then
        purchasePrompt.Enabled = false
    end
    local robloxGui = coreGui:FindFirstChild("RobloxGui")
    if robloxGui then
        local found = robloxGui:FindFirstChild("PurchasePrompt", true)
            or robloxGui:FindFirstChild("PromptPurchase", true)
            or robloxGui:FindFirstChild("PurchaseDialog", true)
        if found then
            if found:IsA("ScreenGui") then
                found.Enabled = false
            elseif found:IsA("GuiObject") then
                found.Visible = false
            end
        end
    end
    for _, gui in ipairs(coreGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            local name = string.lower(gui.Name)
            if name:find("purchaseprompt", 1, true) then
                gui.Enabled = false
            end
            if name:find("purchase", 1, true) then
                gui.Enabled = false
            end
        end
    end
end

local function forceClearPurchaseOverlay()
    local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui") or nil
    if not pg then
        return
    end
    local overlay = pg:FindFirstChild("PurchaseScreenBlackout")
    if overlay and overlay:IsA("ScreenGui") then
        overlay.Enabled = false
    end
    local blackout = pg:FindFirstChild("Blackout")
    if blackout and blackout:IsA("ScreenGui") then
        blackout.Enabled = false
    end
    pcall(function()
        local coreGui = getCoreGuiSafe()
        if coreGui then
            local screenBlock = coreGui:FindFirstChild("ScreenBlockMonitor")
            if screenBlock and screenBlock:IsA("ScreenGui") then
                screenBlock.Enabled = false
            end
        end
    end)
end

local function clearGiftingLoading()
    local giftingGui = getGiftingGui()
    if not giftingGui then
        return
    end
    for _, d in ipairs(giftingGui:GetDescendants()) do
        if d:IsA("GuiObject") then
            local n = string.lower(d.Name)
            if n == "loading" or n == "spinner" or n == "spin" then
                d.Visible = false
            end
        end
    end
end

local function closeGiftingUi()
    if GiftingController and GiftingController.Close then
        pcall(function()
            GiftingController:Close()
        end)
    end
    local giftingGui = getGiftingGui()
    if giftingGui then
        giftingGui.Enabled = false
    end
    clearGiftingLoading()
    forceClearPurchaseOverlay()
end

local function closeGiftingUiSafe()
    closeGiftingUi()
    local giftingGui = getGiftingGui()
    if giftingGui and giftingGui.Enabled then
        task.wait(0.2)
        closeGiftingUi()
    end
    giftingGui = getGiftingGui()
    return not (giftingGui and giftingGui.Enabled)
end

-- Fungsi untuk menangani konfirmasi pembelian (SMART CALIBRATION MODE)
-- Strategi:
-- 1. Mode Kalibrasi: Minta user klik manual SEKALI untuk merekam posisi tombol.
-- 2. Mode Otomatis: Gunakan posisi yang direkam untuk klik selanjutnya.
local function ClickConfirmButton()
    if not State.IsRunning then return false end
    print("--- PROSES KONFIRMASI PEMBELIAN ---")
    
    local purchaseFinished = false
    local purchaseSuccess = false
    local conn1, conn2
    
    local function onFinished(isPurchased)
        purchaseFinished = true
        purchaseSuccess = isPurchased
    end
    
    conn1 = MarketplaceService.PromptPurchaseFinished:Connect(function(player, assetId, isPurchased)
        if player == Players.LocalPlayer then 
            Logger:Log("ConfirmBuy", "PromptPurchaseFinished Event. Success: " .. tostring(isPurchased))
            onFinished(isPurchased) 
        end
    end)
    conn2 = MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if userId == Players.LocalPlayer.UserId then 
            Logger:Log("ConfirmBuy", "PromptProductPurchaseFinished Event. Success: " .. tostring(isPurchased))
            onFinished(isPurchased) 
        end
    end)

    task.spawn(function()
        -- PRE-CALCULATED POSITION (FAST MODE)
        if State.SavedClickPosition then
             local pos = State.SavedClickPosition
             for i=1, 20 do
                 if not State.IsRunning or purchaseFinished then break end
                 if VirtualInputManager then
                     VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
                     task.wait(0.02)
                     VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
                 end
                 task.wait(0.05)
             end
        else
             -- Calibration / First Find
             local t0 = tick()
             while State.IsRunning and not purchaseFinished and (tick() - t0) < 10 do
                 local btn = findBuyButton()
                 if btn then
                      local absPos = btn.AbsolutePosition
                      local absSize = btn.AbsoluteSize
                      local inset = GuiService:GetGuiInset()
                      State.SavedClickPosition = Vector2.new(absPos.X + absSize.X/2 + inset.X, absPos.Y + absSize.Y/2 + inset.Y)
                      SuperClick(btn)
                 end
                 task.wait(0.1)
             end
        end
    end)
    
    local timeout = 25
    local startTime = tick()
    while State.IsRunning and not purchaseFinished and (tick() - startTime) < timeout do
        task.wait(0.1)
    end
    
    if conn1 then conn1:Disconnect() end
    if conn2 then conn2:Disconnect() end
    
    if not State.IsRunning then return false end -- FINAL CHECK BEFORE SUCCESS
    
    if purchaseFinished and purchaseSuccess then
        StatusLabel.Text = "PEMBELIAN BERHASIL!"
        task.wait(1)
        if State.SavedClickPosition then
            -- Close popup
            local pos = State.SavedClickPosition
            if VirtualInputManager then
                VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
                task.wait(0.05)
                VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
            end
        end
        
        -- Additional Cleanup for cek.lua flow
        closePurchasePrompt()
        local closed = closeGiftingUiSafe()
        if not closed then
             StatusLabel.Text = "Gagal menutup UI gift."
             task.wait(0.2)
             closeGiftingUiSafe()
        end
        return true
    else
        StatusLabel.Text = "PEMBELIAN GAGAL/CANCEL"
        return false
    end
end

local function triggerBuyOnLogout()
    if not State.IsRunning then
        return
    end
    local runId = State.RunId
    local now = os.clock()
    if now - lastLogoutTrigger < 1 then
        return
    end
    if State.LogoutTriggered then
        return
    end
    lastLogoutTrigger = now
    State.LogoutTriggered = true
    
    Logger:Log("TriggerBuy", "Logout detected. EXECUTE INSTANT CLICK.")

    -- [OPTIMIZATION] ZERO DELAY CLICK
    -- Fire immediately before any other logic processing
    if State.SavedClickPosition then
        local pos = State.SavedClickPosition
        task.spawn(function()
            if VirtualInputManager then
                -- BURST CLICK (3x) to ensure registration
                for i = 1, 3 do
                    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
                    task.wait(0.07) -- Critical delay for registration
                    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
                    task.wait(0.07)
                end
                Logger:Log("TriggerBuy", "Instant Burst Click Fired at " .. tostring(pos))
            end
        end)
    end

    -- Continue with standard verification flow
    task.spawn(function()
        if not State.IsRunning or runId ~= State.RunId then
            State.LogoutTriggered = false
            return
        end
        
        local success, ok = pcall(ClickConfirmButton)
        if not success then
            Logger:Log("TriggerBuy", "CRITICAL ERROR in ClickConfirmButton: " .. tostring(ok))
            ok = false
        end

        State.LogoutTriggered = false
        State.WaitingLogout = false
        State.WaitingLogoutSince = 0
        
        if ok then
            Logger:Log("TriggerBuy", "Purchase successful.")
            closePurchasePrompt()
            closeGiftingUi()
            State.CooldownUntil = os.clock() + (math.random(40, 60) / 10)
            pcall(function()
                State.GiftsSent = State.GiftsSent + 1
                State.CompletedLoops = State.CompletedLoops + 1
                if State.PresetEnabled then
                    State.PresetRemaining = State.PresetRemaining - 1
                    if State.PresetRemaining <= 0 then
                        State.PresetIndex = State.PresetIndex + 1
                        if State.PresetIndex > #State.PresetSteps then
                            State.PresetIndex = 1
                        end
                        local step = State.PresetSteps[State.PresetIndex]
                        if step then
                            State.PresetRemaining = step.count
                            State.CurrentItem = step.product
                        end
                    end
                    StatusLabel.Text = "Gifting " .. State.CurrentItem .. " " .. State.PresetRemaining .. "x"
                else
                    StatusLabel.Text = "Gift Terkirim: " .. State.GiftsSent .. "/" .. State.TargetAmount
                end
            end)
            -- Force Close UI & Enable Wait Target Join
            local closed = closeGiftingUiSafe()
            if not closed then
                Logger:Log("TriggerBuy", "Failed to close UI initially, retrying...")
                StatusLabel.Text = "Gagal menutup UI gift."
                task.wait(0.2)
                closeGiftingUiSafe()
            end
            State.WaitingTargetJoin = true
    State.TargetJoinCount = 0
    State.WaitingTargetJoinSince = os.clock()
     Logger:Log("TriggerBuy", "Waiting for target to join...")
         else
            Logger:Log("TriggerBuy", "Purchase failed or timed out.")
            StatusLabel.Text = "Gagal / Timeout."
            -- SAFETY: Close UI even on failure
            closePurchasePrompt()
            closeGiftingUiSafe()
        end
    end)
end

Players.PlayerRemoving:Connect(function(player)
    -- Debug Log for every player leaving
    -- Logger:Log("PlayerRemoving", "Player left: " .. tostring(player.Name)) 

    if not State.IsRunning then
        return
    end
    local target = State.TargetUsername
    if target == nil or target == "" then
        return
    end
    
    -- Check match (Username OR DisplayName)
    if string.lower(player.Name) == string.lower(target) or string.lower(player.DisplayName) == string.lower(target) then
        Logger:Log("PlayerRemoving", "Target MATCH detected: " .. tostring(player.Name) .. " (Display: " .. tostring(player.DisplayName) .. "). Triggering Buy!")
        triggerBuyOnLogout()
    else
        -- Logger:Log("PlayerRemoving", "Ignored player: " .. tostring(player.Name))
    end
end)

Players.PlayerAdded:Connect(function(player)
    if State.IsRunning and State.WaitingTargetJoin then
        if string.lower(player.Name) == string.lower(State.TargetUsername) or string.lower(player.DisplayName) == string.lower(State.TargetUsername) then
            State.TargetJoinCount = (State.TargetJoinCount or 0) + 1
            Logger:Log("Event", "Target Join Detected! Count: " .. State.TargetJoinCount)
        end
    end
end)

-- [LOCKED] ProcessGifting: Logika asli dari file 'script'
local function ProcessGifting()
    if not State.IsRunning then return end
    if State.WaitingLogout then
        -- Optimization: Pre-scan for Buy Button position
        if not State.SavedClickPosition then
             local btn = findBuyButton()
             if btn then
                 local absPos = btn.AbsolutePosition
                 local absSize = btn.AbsoluteSize
                 local inset = GuiService:GetGuiInset()
                 State.SavedClickPosition = Vector2.new(absPos.X + absSize.X/2 + inset.X, absPos.Y + absSize.Y/2 + inset.Y)
                 
                 local btnText = "Unknown"
                 if btn:IsA("TextButton") or btn:IsA("TextLabel") then btnText = btn.Text end
                 Logger:Log("PreScan", "Buy Button found (" .. btnText .. ") at " .. tostring(State.SavedClickPosition))
             end
        end

        -- Timeout diperpanjang jadi 120 detik (2 menit) agar tidak cancel duluan
        if State.WaitingLogoutSince > 0 and (os.clock() - State.WaitingLogoutSince) > 120 then
            Logger:Log("ProcessGifting", "Timeout waiting for logout (>120s). Resetting wait state.")
            State.WaitingLogout = false
            State.WaitingLogoutSince = 0
            closePurchasePrompt()
            closeGiftingUi()
        end
        StatusLabel.Text = "Menunggu Logout Target..."
        return
    end
    
    if State.WaitingTargetJoin then
        -- Wait for target to rejoin 2x (Count events)
        local count = State.TargetJoinCount or 0
        if count >= 1 then
            -- Verify user is actually present
            local target = nil
            for _, p in pairs(Players:GetPlayers()) do
                if p.Name == State.TargetUsername or p.DisplayName == State.TargetUsername then
                    target = p
                    break
                end
            end

            if target then
                Logger:Log("ProcessGifting", "Target rejoined (2x Confirmed): " .. target.Name .. " (" .. target.DisplayName .. ")")
                State.WaitingTargetJoin = false
                State.WaitingTargetJoinSince = 0
                StatusLabel.TextColor3 = Color3.new(0, 1, 0)
                StatusLabel.Text = "Target Join (1x) Terdeteksi! Melanjutkan..."
                task.wait(3) -- Wait for load
            else
                StatusLabel.Text = "Menunggu Target Join (1x Detected but not found)..."
            end
        else
            StatusLabel.TextColor3 = Color3.new(1, 1, 0)
            StatusLabel.Text = "Menunggu Target Join (" .. count .. "/1)..."
            
            -- Ensure UI is closed
            local giftingGui = getGiftingGui()
            if giftingGui and giftingGui.Enabled then
                closeGiftingUiSafe()
            end
            
            -- Timeout 5 minutes
            if State.WaitingTargetJoinSince > 0 and (os.clock() - State.WaitingTargetJoinSince) > 300 then
                 StatusLabel.Text = "Waiting Target Join > 300s..."
            end
            return
        end
    end

    if State.CooldownUntil and os.clock() < State.CooldownUntil then
        local remaining = math.max(0, State.CooldownUntil - os.clock())
        StatusLabel.Text = "Cooldown " .. string.format("%.1f", remaining) .. "s"
        return
    end
    local giftingGui = getGiftingGui()
    if not giftingGui or giftingGui.Enabled ~= true then
        if GiftingController then
            pcall(function()
                GiftingController:Open(State.CurrentItem)
            end)
            waitForGiftUi(1.5)
        end
    else
        waitForGiftUi(1.0)
    end
    
    if not State.IsRunning then return end -- CHECK STOP AFTER UI WAIT
    
    -- 2. Cari Tombol Gift Player
    StatusLabel.Text = "Mencari User: " .. State.TargetUsername
    local playerFound = false
    local function scanPlayerList(obj)
        if playerFound then return end
        
        if (obj:IsA("TextLabel") or obj:IsA("TextBox")) and string.find(string.lower(obj.Text), string.lower(State.TargetUsername)) then
            HighlightObject(obj, Color3.new(0, 1, 1)) -- Highlight Username
            local container = obj.Parent
            if container then
                for _, child in pairs(container:GetDescendants()) do
                    if child:IsA("GuiButton") and child.Visible and (string.find(string.lower(child.Name), "gift") or string.find(string.lower(child.Text or ""), "gift")) then
                        HighlightObject(child, Color3.new(0, 1, 0)) -- Highlight Tombol
                        SuperClick(child)
                        playerFound = true
                        break
                    end
                end
                
                -- Fallback: cari tombol apa saja di sebelah kanan nama
                if not playerFound then
                    for _, child in pairs(container.Parent:GetDescendants()) do
                        if child:IsA("GuiButton") and child.Visible and child.AbsolutePosition.X > obj.AbsolutePosition.X then
                            HighlightObject(child, Color3.new(0, 1, 0)) -- Highlight Tombol Fallback
                            SuperClick(child)
                            playerFound = true
                            break
                        end
                    end
                end
            end
        end
        
        for _, child in pairs(obj:GetChildren()) do
            scanPlayerList(child)
        end
    end
    
    for _, gui in pairs(PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled then
            scanPlayerList(gui)
        end
    end
    
    if playerFound then
        if not State.IsRunning then return end -- CHECK STOP BEFORE WAIT
        
        -- UPDATE: Waktu tunggu dipercepat menjadi rata-rata 5 detik (4-6 detik acak)
        -- Gunakan jeda ini untuk menunggu popup muncul setelah klik tombol gift
        local waitTime = math.random(3, 6) / 10 
        StatusLabel.Text = "Menunggu Popup: " .. waitTime .. "s"
        task.wait(waitTime)
        
        if not State.IsRunning then return end -- CHECK STOP AFTER WAIT
        
        State.WaitingLogout = true
        State.WaitingLogoutSince = os.clock()
        StatusLabel.Text = "Menunggu Logout Target..."
    else
        StatusLabel.Text = "User Tidak Ditemukan!"
        if not State.PresetEnabled then
            State.GiftsSent = 0
        end
    end
end

-- Toggle Handler
ToggleButton.MouseButton1Click:Connect(function()
    if State.IgnoreToggle then
        return
    end
    if State.IsRunning then
        State.IsRunning = false
        State.RunId = State.RunId + 1
        State.WaitingLogout = false
        State.WaitingLogoutSince = 0
        State.LogoutTriggered = false
        State.CooldownUntil = 0
        State.CompletedLoops = 0
        State.WaitingForBoost = false
        State.WaitingBoostSince = 0
        State.WaitingTargetJoin = false
        State.WaitingTargetJoinSince = 0
        ToggleButton.Text = "START"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
        StatusLabel.Text = "Stopped."
    else
        local normalized, err = normalizeUsername(UsernameBox.Text)
        if not normalized then
            StatusLabel.Text = err
            return
        end
        State.TargetUsername = normalized
        State.PresetEnabled = false
        State.PresetName = ""
        State.PresetSteps = {}
        State.PresetIndex = 1
        State.PresetRemaining = 0
        local presetName = PresetOrder[selectedPresetIndex] or PresetOrder[1]
        if not applyPreset(presetName) then
            StatusLabel.Text = "Error: Preset tidak valid!"
            return
        end
        State.TargetAmount = 0
        State.GiftsSent = 0
        
        State.IsRunning = true
        State.RunId = State.RunId + 1
        State.WaitingLogout = false
        State.WaitingLogoutSince = 0
        State.LogoutTriggered = false
        State.CooldownUntil = 0
        State.CompletedLoops = 0
        State.WaitingForBoost = false
        State.WaitingBoostSince = 0
        State.WaitingTargetJoin = false
        State.WaitingTargetJoinSince = 0
        ToggleButton.Text = "STOP"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
        if State.PresetEnabled then
            StatusLabel.Text = "Gifting " .. State.CurrentItem .. " " .. State.PresetRemaining .. "x"
        else
            StatusLabel.Text = "Running..."
        end
        
        -- BUKA MENU GIFT HANYA SEKALI SAAT START
        if GiftingController then
            StatusLabel.Text = "Membuka Menu Awal..."
            GiftingController:Open(State.CurrentItem)
            task.wait(1.0) -- Waktu untuk animasi menu terbuka
        end
    end
end)



    -- Main Loop
task.spawn(function()
    while true do
        if State.IsRunning then
            -- Cek apakah sudah mencapai target jumlah gift
            if not State.PresetEnabled and State.GiftsSent >= State.TargetAmount then
                State.IsRunning = false
                StatusLabel.TextColor3 = Color3.new(0, 1, 0)
                StatusLabel.Text = "SELESAI! (" .. State.GiftsSent .. " Gift)"
                ToggleButton.Text = "START"
                ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
            else
                local ok = pcall(ProcessGifting)
                if not ok then
                    State.WaitingLogout = false
                    State.WaitingLogoutSince = 0
                    State.LogoutTriggered = false
                end
                task.wait(0)
            end
        else
            task.wait(1)
        end
    end
end)

StatusLabel.Text = "Ready (Base Script Loaded)"
