-- Auto Race | Based on the supplied Loot to Forge client dump.
-- Uses existing roll credits. Stars are the race's accumulated Level.
-- Run on the client in an environment supporting loadstring and game:HttpGet.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
if env.LootForgeAutoRace then env.LootForgeAutoRace:Destroy() end

local function notify(message)
    warn("[Auto Race] " .. tostring(message))
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title = "Auto Race", Text = tostring(message), Duration = 6})
    end)
end
local function child(parent, name)
    local value = parent:WaitForChild(name, 15)
    assert(value, "Missing: " .. parent:GetFullName() .. "." .. name)
    return value
end
local ok, data, helper, roll, resultEvent = pcall(function()
    local d = require(child(child(RS, "LocalData"), "ClassData"))
    local h = require(child(child(child(RS, "Config"), "Class"), "Helper"))
    local remotes = child(child(RS, "Remote"), "Class_Server")
    return d, h, child(remotes, "LuckOnceRE"), child(remotes, "ShowLuckResultRE")
end)
if not ok then notify(data); return end
local deadline = os.clock() + 20
while not data.GetData() and os.clock() < deadline do task.wait(0.1) end
if not data.GetData() then notify("ClassData ยังไม่พร้อม ลองรันใหม่หลังเกมโหลดเสร็จ"); return end

-- Read the actual replicated profile stream instead of relying on a cached
-- ClassData module. Some client environments keep its initial snapshot.
local originalData = data
local liveClass
local profileConnections = {}
local function path(root, ...)
    for _, name in ipairs({...}) do
        if not root then return nil end
        root = root:FindFirstChild(name)
    end
    return root
end
local function clean(text)
    return tostring(text or ""):gsub("<[^>]*>", ""):match("^%s*(.-)%s*$")
end
local function numberText(object)
    if not object then return nil end
    return tonumber((clean(object.Text):gsub(",", "")):match("%d+"))
end
local function classUI()
    return path(player, "PlayerGui", "ScreenMain", "Class")
end
local function slotUI(slot)
    return path(classUI(), "Right", "Info", "Slot", tostring(slot))
end
local function uiRace(slot)
    local label = path(slotUI(slot), "Tx", "TextLabel")
    if not label then return nil end
    local name = clean(label.Text)
    for id in pairs(helper.GetConfig()) do
        if clean(helper.GetDisName(id) or id) == name then return id end
    end
end
local function uiLevel(race)
    local slots = path(classUI(), "Right", "Info", "Slot")
    if not slots then return nil end
    for _, slot in ipairs(slots:GetChildren()) do
        if uiRace(slot.Name) == race then
            return numberText(path(slot, "Tx", "Frame", "Val"))
        end
    end
end
data = setmetatable({
    GetEquipedIndex = function()
        if liveClass then return liveClass.equiped end
        local slots = path(classUI(), "Right", "Info", "Slot")
        if slots then
            for _, slot in ipairs(slots:GetChildren()) do
                local selected = path(slot, "Info", "Select")
                if selected and selected.Enabled then return slot.Name end
            end
        end
        return originalData.GetEquipedIndex()
    end,
    GetClassByIndex = function(slot)
        if liveClass then return liveClass.have and liveClass.have[slot] end
        return uiRace(slot) or originalData.GetClassByIndex(slot)
    end,
    GetClassLevel = function(race)
        if liveClass then
            local record = liveClass.recored and liveClass.recored[race]
            return record and record.Level
        end
        return uiLevel(race) or originalData.GetClassLevel(race)
    end,
    GetLuckTimes = function()
        if liveClass then return tonumber(liveClass.luckTimes) or 0 end
        return numberText(path(classUI(), "Bottom", "Txt", "LuckTimes")) or originalData.GetLuckTimes()
    end,
    IsLockedIndex = function(slot)
        if liveClass then return liveClass.lock and liveClass.lock[slot] or false end
        local locked = path(slotUI(slot), "Locksuoding", "Select")
        if locked then return locked.Enabled end
        return originalData.IsLockedIndex(slot)
    end,
}, {__index = originalData})
local profileRemotes = path(RS, "Remote", "Profile_Server")
local update = path(profileRemotes, "UpdateDataRE")
local total = path(profileRemotes, "UpdateTotalDataRE")
if update then
    table.insert(profileConnections, update.OnClientEvent:Connect(function(storeName, storeData)
        if storeName == "Class" and type(storeData) == "table" then liveClass = storeData end
    end))
end
if total then
    table.insert(profileConnections, total.OnClientEvent:Connect(function(stores)
        if type(stores) == "table" and type(stores.Class) == "table" then liveClass = stores.Class end
    end))
end

local loaded, CaxUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/CaxQler/Gui-library-cax/refs/heads/main/main.lua"))()
end)
if not loaded then
    for _, item in ipairs(profileConnections) do item:Disconnect() end
    notify("โหลด CaxUI ไม่สำเร็จ: " .. tostring(CaxUI)); return
end

local state = {enabled = false, alive = true, selected = {}, stars = 1,
    exact = false, slot = nil, pending = nil, count = 0, message = "พร้อมใช้งาน"}
local rewardState = {enabled = false, selected = {['4'] = true, ['5'] = true, ['6'] = true},
    delay = 0.1, sent = 0, message = "พร้อมใช้งาน"}
env.rayvinz = false
local window
local controller = {}
local connection
function controller:Destroy()
    state.alive = false
    state.enabled = false
    rewardState.enabled = false
    env.rayvinz = false
    if connection then connection:Disconnect() end
    for _, item in ipairs(profileConnections) do item:Disconnect() end
    if window and not window.Destroyed then window:Destroy() end
    if env.LootForgeAutoRace == self then env.LootForgeAutoRace = nil end
end
env.LootForgeAutoRace = controller
window = CaxUI:CreateWindow({Title = "x2spiritz | Race & Reward", Subtitle = "Loot to Forge",
    Theme = "Dark", ConfigName = "LootForge_AutoRace", ToggleKey = Enum.KeyCode.RightShift,
    OnDestroy = function() controller:Destroy() end})
-- Start with explicit choices and OFF, regardless of old saved UI settings.
window.ConfigHandler.data = {}
local tab = window:CreateTab("Auto Race")
tab:CreateParagraph({Title = "วิธีใช้", Content = "เลือกช่องเผ่าในเกมก่อนเริ่ม → เลือกเผ่าหลายเผ่า → เลือกดาว → เปิด Auto Roll\nหยุดเมื่อได้เผ่าใดเผ่าหนึ่งที่เลือกและดาวถึงเกณฑ์ ใช้สิทธิ์สุ่มตามปกติ\nดาวคือ Level สะสมของเผ่า กด RightShift เพื่อซ่อน/แสดงเมนู"})
tab:CreateSection("เป้าหมาย")
local names, ids = {}, {}
local config = helper.GetConfig()
local ordered = {}
for id in pairs(config) do table.insert(ordered, id) end
table.sort(ordered, function(a, b) return (tonumber(a:match("%d+")) or 0) < (tonumber(b:match("%d+")) or 0) end)
for _, id in ipairs(ordered) do
    local label = (helper.GetDisName(id) or id) .. " [" .. (helper.GetRarity(id) or "?") .. "]"
    ids[label] = id
    table.insert(names, label)
end
tab:CreateDropdown({Name = "เลือกเผ่า (เลือกได้หลายเผ่า)", Flag = "RaceTargets", Options = names,
    MultiSelect = true, Searchable = true, CurrentSelected = {}, Callback = function(value, selected)
        if type(value) == "table" then
            state.selected = {}
            for _, label in ipairs(value) do if ids[label] then state.selected[ids[label]] = true end end
        elseif ids[value] then state.selected[ids[value]] = selected or nil end
    end})
tab:CreateDropdown({Name = "ระดับดาวเป้าหมาย", Options = {"1", "2", "3"}, CurrentOption = "1",
    Callback = function(value) state.stars = tonumber(value) or 1 end})
tab:CreateToggle({Name = "ต้องตรงดาวพอดี (ปิด = อย่างน้อย)", CurrentValue = false,
    Callback = function(value) state.exact = value end})
local initialStatus = "พร้อมใช้งาน | Auto: OFF\nช่อง: - | เผ่า: - | ดาว: -\nสิทธิ์สุ่มเหลือ: - | สุ่มแล้ว: 0"
local status = tab:CreateParagraph({Title = "สถานะ", Content = initialStatus})
local statusText
for _, item in ipairs(status:GetChildren()) do
    if item:IsA("TextLabel") and item.Text == initialStatus then statusText = item end
end
-- This CaxUI version stores control setters on window.Flags.
local function stop(reason)
    state.enabled = false
    state.message = reason
    local flag = window.Flags.AutoRaceEnabled
    if flag and flag:GetValue() then flag:SetValue(false) end
    notify(reason)
end
local function matches(slot)
    local race = data.GetClassByIndex(slot)
    local level = tonumber(race and data.GetClassLevel(race))
    if not race or not level or not state.selected[race] then return false end
    return (state.exact and level == state.stars) or (not state.exact and level >= state.stars)
end
tab:CreateToggle({Name = "Auto Roll เปิด / ปิด", Flag = "AutoRaceEnabled", CurrentValue = false,
    Callback = function(value)
        if not value then
            state.enabled = false
            return
        end
        if state.pending then stop("กำลังรอผลสุ่มเดิม กรุณารอสักครู่"); return end
        if not next(state.selected) then stop("เลือกเผ่าอย่างน้อย 1 เผ่าก่อน"); return end
        local slot = data.GetEquipedIndex()
        if not slot or not data.GetClassByIndex(slot) then stop("เลือกช่องเผ่าที่ปลดล็อกแล้วในเกมก่อน"); return end
        state.slot = slot
        state.enabled = true
        state.message = "กำลังสุ่ม"
    end})
connection = resultEvent.OnClientEvent:Connect(function(payload)
    local pending = state.pending
    if pending and type(payload) == "table" and payload.Result then
        pending.result = payload.Result
        pending.receivedAt = os.clock()
    end
end)
task.spawn(function()
    while state.alive and not window.Destroyed do
        local success, err = pcall(function()
            if not state.enabled then return end
            local slot = state.slot
            if data.GetEquipedIndex() ~= slot then stop("หยุด: เปลี่ยนช่องเผ่าแล้ว"); return end
            if player:GetAttribute("IntoFight") then stop("หยุด: อยู่ระหว่างต่อสู้"); return end
            if data.IsLockedIndex(slot) then stop("หยุด: ช่องเผ่าถูกล็อก"); return end
            if matches(slot) then stop("สำเร็จ: ได้เผ่าและดาวตามเป้าหมาย"); return end
            if not next(state.selected) then stop("หยุด: ไม่ได้เลือกเผ่า"); return end
            local credits = data.GetLuckTimes()
            if credits <= 0 then stop("หยุด: สิทธิ์สุ่มหมด"); return end
            local pending = {credits = credits, sentAt = os.clock()}
            state.pending = pending
            roll:FireServer(slot)
            local expires = os.clock() + 15
            local confirmed = false
            local lastSnapshot, stableSince
            repeat
                task.wait(0.1)
                local currentRace = data.GetClassByIndex(slot)
                local currentLevel = currentRace and data.GetClassLevel(currentRace)
                local remaining = data.GetLuckTimes()
                local snapshot = tostring(currentRace) .. ":" .. tostring(currentLevel) .. ":" .. tostring(remaining)
                if snapshot ~= lastSnapshot then
                    lastSnapshot = snapshot
                    stableSince = os.clock()
                end
                -- A consumed roll credit is replicated confirmation even when
                -- ShowLuckResultRE is missing. Same-race rolls are valid too.
                -- Allow the normal animation/data updates to settle before another roll.
                confirmed = remaining < credits and currentRace ~= nil and currentLevel ~= nil
                    and os.clock() - pending.sentAt >= 4.5
                    and os.clock() - stableSince >= 0.6
                state.message = string.format("รอข้อมูล %.1fวิ | สิทธิ์ %s → %s | อ่านจาก %s",
                    os.clock() - pending.sentAt, tostring(credits), tostring(remaining),
                    liveClass and "Profile" or (classUI() and "UI" or "ClassData"))
            until confirmed or os.clock() >= expires or not state.alive
            state.pending = nil
            if not state.alive then return end
            if not confirmed then
                stop(string.format("หยุด: ข้อมูลไม่อัปเดต | สิทธิ์ %s → %s | เผ่า %s | ดาว %s | %s",
                    tostring(credits), tostring(data.GetLuckTimes()), tostring(data.GetClassByIndex(slot)),
                    tostring(data.GetClassLevel(data.GetClassByIndex(slot))), liveClass and "Profile" or "UI/ClassData"))
                return
            end
            state.count = state.count + 1
            if state.enabled and matches(slot) then stop("สำเร็จ: ได้เผ่าและดาวตามเป้าหมาย"); return end
            if state.enabled then state.message = "กำลังสุ่ม" end
        end)
        if not success then state.pending = nil; stop("ข้อผิดพลาด: " .. tostring(err)) end
        task.wait(0.6)
    end
end)
task.spawn(function()
    while state.alive and not window.Destroyed do
        pcall(function()
            local slot = state.slot or data.GetEquipedIndex()
            local race = slot and data.GetClassByIndex(slot)
            if statusText then
                statusText.Text = string.format("%s | Auto: %s\nช่อง: %s | เผ่า: %s | ดาว: %s\nสิทธิ์สุ่มเหลือ: %s | สุ่มแล้ว: %d",
                    state.message, state.enabled and "ON" or "OFF", tostring(slot or "-"),
                    race and helper.GetDisName(race) or "-", tostring(race and data.GetClassLevel(race) or "-"),
                    tostring(data.GetLuckTimes()), state.count)
            end
        end)
        task.wait(0.3)
    end
end)
-- Auto Reward: the supplied whitespace-prefix request loop, controlled by CaxUI.
local rewardTab = window:CreateTab("Auto Reward")
rewardTab:CreateParagraph({Title = "Auto Reward", Content = "เลือกรางวัล 4, 5, 6 แล้วเปิดสวิตช์\nใช้โค้ดสุ่มช่องว่าง/Tab นำหน้าหมายเลขตามที่ให้มา\nจำนวนที่ส่งคือคำขอ ไม่ใช่จำนวนรางวัลที่ได้รับ"})
rewardTab:CreateDropdown({Name = "เลือกรางวัล (เลือกได้หลายรายการ)", Flag = "RewardTargets",
    Options = {"4", "5", "6"}, MultiSelect = true, CurrentSelected = {"4", "5", "6"},
    Callback = function(value, selected)
        if type(value) == "table" then
            rewardState.selected = {}
            for _, id in ipairs(value) do
                if id == "4" or id == "5" or id == "6" then rewardState.selected[id] = true end
            end
        elseif value == "4" or value == "5" or value == "6" then
            rewardState.selected[value] = selected or nil
        end
    end})
rewardTab:CreateDropdown({Name = "เวลาพักแต่ละรอบ (วินาที)", Options = {"0.1", "0.25", "0.5", "1"},
    CurrentOption = "0.1", Callback = function(value) rewardState.delay = tonumber(value) or 0.1 end})
local rewardInitial = "พร้อมใช้งาน | OFF\nส่งคำขอแล้ว: 0\nรางวัล: 4, 5, 6"
local rewardStatus = rewardTab:CreateParagraph({Title = "สถานะ Auto Reward", Content = rewardInitial})
local rewardText
for _, item in ipairs(rewardStatus:GetChildren()) do
    if item:IsA("TextLabel") and item.Text == rewardInitial then rewardText = item end
end
local rewardEvent
local function stopReward(reason)
    rewardState.enabled = false
    env.rayvinz = false
    rewardState.message = reason
    local flag = window.Flags.AutoRewardEnabled
    if flag and flag:GetValue() then flag:SetValue(false) end
    notify(reason)
end
rewardTab:CreateToggle({Name = "Auto Reward เปิด / ปิด", Flag = "AutoRewardEnabled", CurrentValue = false,
    Callback = function(value)
        rewardState.enabled = false
        env.rayvinz = false
        if not value then return end
        if not next(rewardState.selected) then stopReward("เลือกรางวัลอย่างน้อย 1 รายการก่อน"); return end
        rewardEvent = path(RS, "Remote", "UpdateLog_Server", "TryClaimUPDRewardRE")
        if not rewardEvent or not rewardEvent:IsA("RemoteEvent") then
            stopReward("ไม่พบ TryClaimUPDRewardRE ในเกมนี้"); return
        end
        rewardState.enabled = true
        env.rayvinz = true
        rewardState.message = "กำลังส่งคำขอ"
    end})
-- One worker for the lifetime of the UI; toggling cannot create extra loops.
task.spawn(function()
    while state.alive and not window.Destroyed do
        if rewardState.enabled and env.rayvinz then
            if not next(rewardState.selected) then
                stopReward("หยุด: ไม่ได้เลือกรางวัล")
            else
                for _, rewardNumber in ipairs({"4", "5", "6"}) do
                    if not state.alive or not rewardState.enabled or not env.rayvinz then break end
                    if rewardState.selected[rewardNumber] then
                        local prefix = {}
                        for i = 1, math.random(5, 15) do
                            prefix[i] = math.random(1, 2) == 1 and " " or "\t"
                        end
                        local sent, err = pcall(function()
                            rewardEvent:FireServer(table.concat(prefix) .. rewardNumber)
                        end)
                        if not sent then stopReward("ส่งคำขอไม่สำเร็จ: " .. tostring(err)); break end
                        rewardState.sent = rewardState.sent + 1
                    end
                end
            end
        elseif rewardState.enabled then
            rewardState.enabled = false
            local flag = window.Flags.AutoRewardEnabled
            if flag and flag:GetValue() then flag:SetValue(false) end
        end
        if rewardText then
            local chosen = {}
            for _, id in ipairs({"4", "5", "6"}) do
                if rewardState.selected[id] then table.insert(chosen, id) end
            end
            rewardText.Text = string.format("%s | %s\nส่งคำขอแล้ว: %d\nรางวัล: %s",
                rewardState.message, rewardState.enabled and "ON" or "OFF", rewardState.sent, table.concat(chosen, ", "))
        end
        task.wait(rewardState.delay)
    end
end)
notify("พร้อมใช้งาน: Auto Race และ Auto Reward | RightShift เปิด/ปิด UI")
