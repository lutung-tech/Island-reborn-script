-- ISLAND HUB - ISLAND REBORN (v8)
-- Satu menu bertab: MANCING | NAMBANG | SLIME | LOG.
-- Gabungan dari Script (mancing v6.1), Miner (nambang v1.1), Logger (v2), plus farm slime.
-- Satu mesin klik (tombol MODE / TES KLIK) dan satu pemantau event dipakai bareng.
-- Cuma satu auto yang jalan sekali waktu: START di satu tab menghentikan yang lain.
--
-- Kalau game update dan berhenti jalan:
--   Mancing : lihat tulisan "suara:" pas ikan nyambar, tambah namanya di FISH.biteSounds
--             (atau biarkan FISH.autoLearn = true supaya dipelajari sendiri).
--   Nambang : tab LOG -> REKAM ON -> SCAN SEKITAR -> nambang sekali -> SALIN, kirim ke Claude.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

-- ===== Config =====
local clickDelay = 0.08       -- lama ketukan ditahan

local FISH = {
    castSound = "fishing_rod_splash",
    -- Nama suara sambaran diacak game dan bisa berganti tiap update.
    biteSounds = {
        ["AY3OmfC4erEBAFr5eLlknQJU"] = true,
        ["L0qV033RBb6qSdo3H"] = true,
    },
    -- true: suara tak dikenal dekat kail saat menunggu dianggap sambaran lalu diingat.
    -- Ubah ke false kalau script reel terlalu cepat sebelum ikan nyambar.
    autoLearn = true,
    caughtSound = "fish_caught",
    escapedSound = "fish_escaped",
    castTimeout = 6,          -- tunggu splash setelah lempar
    waitTimeout = 60,         -- tunggu sambaran, lewat ini kail ditarik lalu lempar ulang
    resultTimeout = 6,        -- tunggu hasil setelah reel
    afterDelay = 1.5,         -- jeda sebelum lempar berikutnya
    biteRadius = 12,          -- sambaran harus dekat posisi kail (stud)
    castMaxDist = 150,        -- splash harus dekat karakter lu (stud)
}

local MINE = {
    distance = 8,             -- jarak ke batu sebelum mulai mukul (stud)
    searchRadius = 250,       -- batu yang lebih jauh dari ini diabaikan
    walkTimeout = 12,         -- batas waktu jalan ke satu batu
    swingInterval = 1.4,      -- mode tool: jeda antar pukulan
    noGainSwings = 7,         -- mode tool: segini pukulan tanpa hasil = ganti batu
    noGainSeconds = 10,       -- mode tahan: segini detik tanpa hasil = ganti batu
    targetTimeout = 45,       -- batas waktu mukul satu batu
    blacklistTime = 90,       -- batu bermasalah dilewati selama ini
    faceRock = true,          -- karakter dihadapkan ke batu sebelum memukul
    targets = {
        { label = "iron", words = { "rockiron" } },
        { label = "coal", words = { "rockcoal" } },
        { label = "stone", words = { "rockstone" } },
        { label = "semua", words = { "rock" } },
    },
}

local SLIME = {
    attackDistance = 10,      -- jarak serang (stud). Dari log lu, pukulan kena di sekitar 13 stud
    searchRadius = 120,       -- slime yang lebih jauh dari ini diabaikan
    walkTimeout = 10,         -- batas waktu jalan ke satu slime
    probeInterval = 1.0,      -- sebelum jeda ayunan terukur: ketuk tiap ini (ketukan saat cooldown diabaikan game)
    swingJitter = 0.3,        -- tambahan acak 0..ini di atas jeda ayunan supaya ritmenya tidak kaku
    minCooldown = 0.8,        -- jarak antar damage di luar rentang ini tidak dipakai buat mengukur
    maxCooldown = 8,
    healItem = "",            -- nama item penyembuh di tas/hotbar (cocok sebagian nama). Kosong = tidak dipakai
    healBelowPercent = 55,    -- pakai item penyembuh kalau HP di bawah ini
    healCooldown = 4,         -- jeda minimal antar pemakaian item penyembuh
    noHitSeconds = 8,         -- tidak ada damage segini detik = ganti target
    targetTimeout = 40,       -- batas waktu melawan satu slime
    blacklistTime = 40,       -- target bermasalah dilewati selama ini
    afterKillDelay = { 0.5, 1.2 }, -- jeda acak setelah slime mati
    minHpPercent = 35,        -- berhenti otomatis kalau HP lu di bawah ini
    faceTarget = true,        -- hadapkan karakter ke slime (hanya memutar, tidak pindah tempat)
    folderName = "Entities",  -- Workspace.Entities
    targets = {
        { label = "pink", words = { "slimepink" } },
        { label = "semua", words = { "slime" } },
    },
}

local LOGC = {
    ignore = { "QuestsUpdate" },  -- event berisik yang tidak dicatat (cocok sebagian nama)
    maxLines = 1000,
    maxDepth = 3,
    maxItems = 14,
    scanRadius = 80,
    scanMax = 60,
    scanWords = { "ore", "rock", "stone", "mine", "crop", "plant", "farm", "wheat", "seed", "tree", "node", "resource", "slime", "mob", "enemy" },
}

local GRAY = Color3.fromRGB(150, 150, 150)
local GREEN = Color3.fromRGB(30, 150, 70)
local RED = Color3.fromRGB(170, 45, 45)
local BLUE = Color3.fromRGB(60, 80, 110)

-- ===== Parent GUI (aman kalau CoreGui/gethui gagal) =====
local function getGuiParent()
    local ok, result = pcall(function()
        return (gethui and gethui()) or CoreGui
    end)
    if ok and result then
        return result
    end
    return player:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()

-- Hapus GUI lama (termasuk script terpisah versi sebelumnya)
for _, name in ipairs({ "IslandHub", "IslandAutoFish", "IslandAutoMine", "IslandRemoteLogger" }) do
    pcall(function()
        local old = guiParent:FindFirstChild(name)
        if old then old:Destroy() end
    end)
    pcall(function()
        local old = player:WaitForChild("PlayerGui"):FindFirstChild(name)
        if old then old:Destroy() end
    end)
end

-- ===== Status umum =====
local running = false
local runId = 0               -- supaya loop lama tidak jalan bareng loop baru
local activeName = nil        -- "fish" | "mine" | nil
local uiConnections = {}
local statusLabels = {}       -- nama -> label status tiap tab
local soundLabels = {}        -- label "suara:" tiap tab
local H = {}                  -- penghubung antar bagian (handler event, dll)

local function isActive(id)
    return running and runId == id
end

-- Tulis status hanya kalau loop yang memanggil masih yang aktif
local function say(name, id, text)
    if isActive(id) then
        statusLabels[name].Text = "Status: " .. text
    end
end

-- ===== Kerangka GUI =====
local FRAME_W, FRAME_H, HEADER_H = 230, 270, 26

local gui = Instance.new("ScreenGui")
gui.Name = "IslandHub"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local okParent = pcall(function()
    gui.Parent = guiParent
end)
if not okParent or not gui.Parent then
    gui.Parent = player:WaitForChild("PlayerGui")
end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(FRAME_W, FRAME_H)
frame.Position = UDim2.new(0, 16, 0.5, -FRAME_H / 2)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.Parent = gui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = frame

local function makeLabel(parent, text, x, y, w, h, size, color)
    local l = Instance.new("TextLabel")
    l.Position = UDim2.fromOffset(x, y)
    l.Size = UDim2.fromOffset(w, h)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.fromRGB(220, 220, 220)
    l.TextSize = size or 12
    l.TextWrapped = true
    l.Parent = parent
    return l
end

local function makeButton(parent, text, x, y, w, h, color)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(x, y)
    b.Size = UDim2.fromOffset(w, h)
    b.Text = text
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Parent = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = b

    return b
end

local title = makeLabel(frame, "ISLAND HUB v8", 8, 2, 180, HEADER_H - 4, 15, Color3.new(1, 1, 1))
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true

local minButton = makeButton(frame, "-", FRAME_W - 32, 3, 26, HEADER_H - 6, Color3.fromRGB(70, 70, 80))

local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(0, HEADER_H)
body.Size = UDim2.fromOffset(FRAME_W, FRAME_H - HEADER_H)
body.Parent = frame

local tabButtons, pages = {}, {}
local TAB_DEFS = { { "fish", "MANCING" }, { "mine", "NAMBANG" }, { "slime", "SLIME" }, { "log", "LOG" } }

for i, def in ipairs(TAB_DEFS) do
    local tb = makeButton(body, def[2], 6 + (i - 1) * 55, 4, 52, 26, Color3.fromRGB(45, 45, 55))
    tb.TextSize = 10
    tabButtons[def[1]] = tb

    local p = Instance.new("Frame")
    p.BackgroundTransparency = 1
    p.Position = UDim2.fromOffset(6, 36)
    p.Size = UDim2.fromOffset(218, 170)
    p.Visible = false
    p.Parent = body
    pages[def[1]] = p
end

local modeButton = makeButton(body, "MODE: auto", 6, 210, 92, 28, BLUE)
local testButton = makeButton(body, "TES KLIK", 104, 210, 56, 28, Color3.fromRGB(110, 90, 40))
local afkButton = makeButton(body, "AFK: on", 166, 210, 58, 28, Color3.fromRGB(60, 100, 90))

-- GUI bisa digeser lewat judulnya
do
    local dragging, dragStart, startPos

    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    table.insert(uiConnections, UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end))

    table.insert(uiConnections, UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

-- ===== Mesin klik (dipakai mancing dan nambang) =====
local touchOnly = UIS.TouchEnabled and not UIS.MouseEnabled
local logWindow = nil -- diisi bagian LOG

local function insideRect(g, x, y)
    local p, s = g.AbsolutePosition, g.AbsoluteSize
    return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end

-- Ketukan tidak boleh jatuh di atas GUI sendiri, kalau iya malah kena tombol
local function insideGui(x, y)
    if insideRect(frame, x, y) then
        return true
    end
    return logWindow ~= nil and logWindow.Visible and insideRect(logWindow, x, y)
end

local function getClickPos()
    local mouse = UIS:GetMouseLocation()
    if not touchOnly and not insideGui(mouse.X, mouse.Y) then
        return mouse.X, mouse.Y
    end

    local cam = workspace.CurrentCamera
    local vs = cam and cam.ViewportSize or Vector2.new(800, 600)
    local candidates = {
        Vector2.new(vs.X * 0.5, vs.Y * 0.5),
        Vector2.new(vs.X * 0.7, vs.Y * 0.5),
        Vector2.new(vs.X * 0.5, vs.Y * 0.3),
        Vector2.new(vs.X * 0.3, vs.Y * 0.5),
        Vector2.new(vs.X * 0.5, vs.Y * 0.7),
    }

    for _, c in ipairs(candidates) do
        if not insideGui(c.X, c.Y) then
            return c.X, c.Y
        end
    end

    return mouse.X, mouse.Y
end

-- Mode klik (ganti lewat tombol MODE, coba satu per satu pakai TES KLIK):
--   auto  = touch kalau di HP, mouse kalau di PC
--   touch = ketuk layar (SendTouchEvent)
--   mouse = klik mouse (SendMouseButtonEvent)
--   tool  = langsung aktifkan alat yang dipegang (Tool:Activate)
local CLICK_MODES = { "auto", "touch", "mouse", "tool" }
local clickMode = "auto"

local function effectiveMode()
    local mode = clickMode
    if mode == "auto" then
        mode = touchOnly and "touch" or "mouse"
    end
    return mode
end

local function pickPos(aim)
    local x, y
    if aim then
        x, y = aim.X, aim.Y
    end
    if not x or insideGui(x, y) then
        x, y = getClickPos()
    end
    return x, y
end

local function sendMouse(x, y)
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(clickDelay)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

local function sendTouch(x, y)
    local touchId = 7
    VIM:SendTouchEvent(touchId, 0, x, y) -- 0 = jari menyentuh
    task.wait(clickDelay)
    VIM:SendTouchEvent(touchId, 2, x, y) -- 2 = jari dilepas
end

local function activateTool()
    local char = player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then
        return false
    end
    tool:Activate()
    task.wait(clickDelay)
    return true
end

-- aim = Vector2 posisi di layar yang diketuk (nil = area game yang kosong)
local function click(aim)
    local mode = effectiveMode()

    if mode == "tool" then
        if activateTool() then
            return
        end
        mode = touchOnly and "touch" or "mouse" -- alat tidak dipegang, pakai cara lain
    end

    local x, y = pickPos(aim)

    if mode == "touch" then
        local ok = pcall(sendTouch, x, y)
        if ok then
            return
        end
    end

    sendMouse(x, y)
end

-- Tahan layar (dipakai nambang)
local HOLD_TOUCH_ID = 8
local held = nil -- { mode = "touch" | "mouse", x = ..., y = ... }

local function pressDown(aim)
    if held then return end

    local mode = effectiveMode()
    if mode == "tool" then return end

    local x, y = pickPos(aim)

    if mode == "touch" then
        local ok = pcall(function()
            VIM:SendTouchEvent(HOLD_TOUCH_ID, 0, x, y)
        end)
        if ok then
            held = { mode = "touch", x = x, y = y }
            return
        end
    end

    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    held = { mode = "mouse", x = x, y = y }
end

-- Selama ditahan, sentuhan diikutkan ke posisi target di layar
local function pressUpdate(aim)
    if not held or held.mode ~= "touch" then return end

    local x, y = pickPos(aim)
    pcall(function()
        VIM:SendTouchEvent(HOLD_TOUCH_ID, 1, x, y) -- 1 = jari bergeser
    end)
    held.x, held.y = x, y
end

local function pressUp()
    if not held then return end

    local h = held
    held = nil

    if h.mode == "touch" then
        pcall(function()
            VIM:SendTouchEvent(HOLD_TOUCH_ID, 2, h.x, h.y)
        end)
    else
        pcall(function()
            VIM:SendMouseButtonEvent(h.x, h.y, 0, false, game, 0)
        end)
    end
end

-- ===== Mulai / berhenti =====
local function stopAll()
    local was = activeName

    running = false
    runId += 1
    activeName = nil
    pressUp() -- lepas sentuhan supaya tidak nyangkut

    if was and statusLabels[was] then
        statusLabels[was].Text = "Status: STOPPED"
    end
end

local function startTask(name, fn)
    if activeName == name then return end

    stopAll()
    running = true
    activeName = name
    statusLabels[name].Text = "Status: Starting..."

    task.spawn(fn, runId)
end

-- Kalau GUI dihapus (script dijalankan ulang), hentikan semuanya
gui.Destroying:Connect(function()
    running = false
    runId += 1
    pressUp()
    for _, c in ipairs(uiConnections) do
        c:Disconnect()
    end
end)

-- =====================================================================
-- TAB MANCING
-- =====================================================================
do
    local page = pages.fish
    local status = makeLabel(page, "Status: OFF", 0, 0, 218, 24, 12)
    local stats = makeLabel(page, "dapat: 0 | lepas: 0", 0, 26, 218, 18, 12, Color3.fromRGB(150, 220, 150))
    local sound = makeLabel(page, "suara: -", 0, 46, 218, 30, 11, GRAY)
    local startB = makeButton(page, "START", 0, 82, 104, 36, GREEN)
    local stopB = makeButton(page, "STOP", 114, 82, 104, 36, RED)
    makeLabel(page, "Pegang pancing, berdiri dekat air, lalu START.", 0, 126, 218, 36, 11, GRAY)

    statusLabels.fish = status
    table.insert(soundLabels, sound)

    -- state: idle -> cast (tunggu splash) -> wait (tunggu sambaran) -> reel (tunggu hasil) -> done
    local state = "idle"
    local castPos = nil
    local result = nil
    local caught, escaped = 0, 0

    local function nearMe(pos)
        if not pos then return true end
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return true end
        return (root.Position - pos).Magnitude <= FISH.castMaxDist
    end

    -- Dipanggil tiap ada suara dari server
    H.fishSound = function(name, pos)
        if activeName ~= "fish" then return end

        if name == FISH.castSound and state == "cast" then
            if not nearMe(pos) then return end
            castPos = pos
            state = "wait"
        elseif state == "wait" then
            if name == FISH.castSound or name == FISH.caughtSound or name == FISH.escapedSound then
                return
            end

            local near = pos ~= nil and castPos ~= nil and (pos - castPos).Magnitude <= FISH.biteRadius

            if FISH.biteSounds[name] then
                if castPos and pos and not near then
                    return -- sambaran di kail pemain lain
                end
            elseif FISH.autoLearn and near then
                FISH.biteSounds[name] = true -- suara baru dekat kail, kemungkinan nama sambaran yang baru
                sound.Text = "suara: " .. name .. " (dipelajari)"
            else
                return
            end

            state = "reel"
            status.Text = "Status: SAMBAR! Reel..."
            task.spawn(click) -- klik langsung dari sini supaya secepat mungkin
        elseif (name == FISH.caughtSound or name == FISH.escapedSound) and state == "reel" then
            result = name
            state = "done"
        end
    end

    local function waitWhile(id, wanted, timeout)
        local t = os.clock()
        while isActive(id) and state == wanted and os.clock() - t < timeout do
            task.wait(0.03)
        end
    end

    local function fishingLoop(myRun)
        while isActive(myRun) do
            state = "cast"
            castPos = nil
            result = nil
            say("fish", myRun, "Casting...")
            click()

            waitWhile(myRun, "cast", FISH.castTimeout)
            if not isActive(myRun) then break end

            if state == "cast" then
                say("fish", myRun, "kail tidak mendarat, ulang...")
                state = "idle"
                task.wait(1)
                continue
            end

            say("fish", myRun, "Menunggu ikan...")
            waitWhile(myRun, "wait", FISH.waitTimeout)
            if not isActive(myRun) then break end

            if state == "wait" then
                say("fish", myRun, "tidak ada ikan, tarik kail...")
                state = "idle"
                click() -- tarik kail yang masih di air
                task.wait(2)
                continue
            end

            waitWhile(myRun, "reel", FISH.resultTimeout)
            if not isActive(myRun) then break end

            if state == "done" then
                if result == FISH.caughtSound then
                    caught += 1
                    say("fish", myRun, "dapat ikan!")
                else
                    escaped += 1
                    say("fish", myRun, "ikan lepas")
                end
                stats.Text = string.format("dapat: %d | lepas: %d", caught, escaped)
            else
                say("fish", myRun, "hasil tidak terdeteksi")
            end

            state = "idle"
            task.wait(FISH.afterDelay)
        end

        state = "idle"
    end

    startB.MouseButton1Click:Connect(function()
        startTask("fish", fishingLoop)
    end)
    stopB.MouseButton1Click:Connect(stopAll)
end

-- =====================================================================
-- TAB NAMBANG
-- =====================================================================
do
    local page = pages.mine
    local status = makeLabel(page, "Status: OFF", 0, 0, 218, 24, 12)
    local stats = makeLabel(page, "item: 0 | pukulan: 0", 0, 26, 218, 18, 12, Color3.fromRGB(150, 220, 150))
    local sound = makeLabel(page, "suara: -", 0, 46, 218, 30, 11, GRAY)
    local startB = makeButton(page, "START", 0, 80, 104, 34, GREEN)
    local stopB = makeButton(page, "STOP", 114, 80, 104, 34, RED)
    local targetB = makeButton(page, "TARGET: iron", 0, 120, 218, 28, Color3.fromRGB(90, 70, 110))
    makeLabel(page, "Pegang pickaxe dulu, lalu START.", 0, 152, 218, 18, 11, GRAY)

    statusLabels.mine = status
    table.insert(soundLabels, sound)

    local targetIdx = 1
    local itemEvents, swingCount = 0, 0
    local lastItem = "-"
    local currentRock = nil
    local blacklist = {}
    local rockCache, rockCacheAt = {}, 0

    local function refreshStats()
        stats.Text = string.format("item: %d | pukulan: %d | %s", itemEvents, swingCount, lastItem)
    end

    -- suara batu di dekat batu yang lagi dipukul = pukulan kena
    H.mineSound = function(name, pos)
        if currentRock and name:sub(1, 4) == "rock" and pos
            and (pos - currentRock.Position).Magnitude <= 15 then
            swingCount += 1
            refreshStats()
        end
    end

    -- notifikasi "+ 1 Iron Ore" dst.
    H.item = function(titleText)
        if activeName == "fish" then return end
        itemEvents += 1
        lastItem = titleText
        refreshStats()
    end

    local function getRocks()
        if os.clock() - rockCacheAt > 3 then
            rockCacheAt = os.clock()
            rockCache = {}

            local base = workspace:FindFirstChild("spawnPrefabs")
            base = base and base:FindFirstChild("regenBlocks") or workspace

            for _, d in ipairs(base:GetDescendants()) do
                if d:IsA("BasePart")
                    and (d:GetAttribute("HubRock") ~= nil or d:GetAttribute("Health") ~= nil) then
                    rockCache[#rockCache + 1] = d
                end
            end
        end

        return rockCache
    end

    local function rockAvailable(rock)
        if not rock.Parent then return false end
        if rock.Transparency >= 0.95 then return false end

        local h = rock:GetAttribute("Health")
        if typeof(h) == "number" and h <= 0 then
            return false
        end

        return true
    end

    local function nameMatches(name)
        local n = name:lower()
        for _, w in ipairs(MINE.targets[targetIdx].words) do
            if n:find(w, 1, true) then
                return true
            end
        end
        return false
    end

    local function getRoot()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function findRock()
        local root = getRoot()
        if not root then return nil end

        local best, bestDist
        for _, rock in ipairs(getRocks()) do
            local banned = blacklist[rock]
            if banned and os.clock() > banned then
                blacklist[rock] = nil
                banned = nil
            end

            if not banned and nameMatches(rock.Name) and rockAvailable(rock) then
                local d = (rock.Position - root.Position).Magnitude
                if d <= MINE.searchRadius and (not bestDist or d < bestDist) then
                    best, bestDist = rock, d
                end
            end
        end

        return best
    end

    local function aimFor(rock)
        local cam = workspace.CurrentCamera
        if cam and rock then
            local v, onScreen = cam:WorldToViewportPoint(rock.Position)
            if onScreen then
                return Vector2.new(v.X, v.Y)
            end
        end
        return nil
    end

    local function face(rock)
        local root = getRoot()
        if not root then return end
        local p = rock.Position
        root.CFrame = CFrame.lookAt(root.Position, Vector3.new(p.X, root.Position.Y, p.Z))
    end

    local function ensureTool()
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum or char:FindFirstChildOfClass("Tool") then return end

        local bp = player:FindFirstChildOfClass("Backpack")
        if not bp then return end

        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t.Name:lower():find("pick", 1, true) then
                hum:EquipTool(t)
                return
            end
        end
    end

    local function approach(id, rock)
        local started = os.clock()

        while isActive(id) and rockAvailable(rock) and os.clock() - started < MINE.walkTimeout do
            local root = getRoot()
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if not root or not hum then
                task.wait(0.5)
                return false
            end

            if (root.Position - rock.Position).Magnitude <= MINE.distance then
                return true
            end

            hum:MoveTo(rock.Position)
            task.wait(0.2)
        end

        local root = getRoot()
        return root ~= nil and rockAvailable(rock)
            and (root.Position - rock.Position).Magnitude <= MINE.distance
    end

    -- Mode tool: satu ayunan per klik
    local function mineRockTap(id, rock)
        local started = os.clock()
        local lastCount = itemEvents
        local swingsSinceGain = 0

        while isActive(id) and rockAvailable(rock) and os.clock() - started < MINE.targetTimeout do
            local root = getRoot()
            if not root or (root.Position - rock.Position).Magnitude > MINE.distance + 6 then
                return -- terlalu jauh (terdorong), cari lagi
            end

            if MINE.faceRock then
                face(rock)
            end

            click(aimFor(rock))
            swingsSinceGain += 1

            local t = os.clock()
            while isActive(id) and rockAvailable(rock) and os.clock() - t < MINE.swingInterval do
                task.wait(0.05)
            end

            if itemEvents ~= lastCount then
                lastCount = itemEvents
                swingsSinceGain = 0
            end

            if swingsSinceGain >= MINE.noGainSwings then
                say("mine", id, "tidak ada hasil, ganti batu")
                blacklist[rock] = os.clock() + MINE.blacklistTime
                return
            end
        end
    end

    -- Mode utama: sentuhan ditahan di batu, game memukul terus selama ditahan
    local function mineRock(id, rock)
        if effectiveMode() == "tool" then
            mineRockTap(id, rock)
            return
        end

        local started = os.clock()
        local lastCount = itemEvents
        local lastGainAt = os.clock()
        currentRock = rock

        if MINE.faceRock then
            face(rock)
        end
        pressDown(aimFor(rock))

        while isActive(id) and rockAvailable(rock) and os.clock() - started < MINE.targetTimeout do
            local root = getRoot()
            if not root or (root.Position - rock.Position).Magnitude > MINE.distance + 6 then
                break -- terlalu jauh (terdorong), cari lagi
            end

            pressUpdate(aimFor(rock))
            task.wait(0.15)

            if itemEvents ~= lastCount then
                lastCount = itemEvents
                lastGainAt = os.clock()
            end

            if os.clock() - lastGainAt > MINE.noGainSeconds then
                say("mine", id, "tidak ada hasil, ganti batu")
                blacklist[rock] = os.clock() + MINE.blacklistTime
                break
            end
        end

        pressUp()
        currentRock = nil
        task.wait(0.2)
    end

    local function mineLoop(myRun)
        while isActive(myRun) do
            ensureTool()

            local char = player.Character
            if not (char and char:FindFirstChildOfClass("Tool")) then
                say("mine", myRun, "pegang pickaxe dulu")
                task.wait(1)
                continue
            end

            local rock = findRock()
            if not rock then
                say("mine", myRun, "tidak ada batu " .. MINE.targets[targetIdx].label .. ", tunggu...")
                task.wait(2)
                continue
            end

            say("mine", myRun, "menuju batu...")
            if approach(myRun, rock) then
                say("mine", myRun, "menambang " .. rock.Name)
                mineRock(myRun, rock)
            else
                if isActive(myRun) then
                    blacklist[rock] = os.clock() + MINE.blacklistTime
                end
                task.wait(0.3)
            end
        end

        pressUp()
        currentRock = nil
    end

    -- Dipakai tombol TES KLIK saat tab NAMBANG aktif
    H.testMine = function()
        local rock = findRock()

        if effectiveMode() == "tool" then
            click(aimFor(rock))
            return
        end

        -- tahan 1,6 detik di batu terdekat, lihat apakah "item" / "pukulan" bertambah
        if MINE.faceRock and rock then
            face(rock)
        end
        pressDown(aimFor(rock))
        task.wait(1.6)
        pressUp()
    end

    startB.MouseButton1Click:Connect(function()
        startTask("mine", mineLoop)
    end)
    stopB.MouseButton1Click:Connect(stopAll)

    targetB.MouseButton1Click:Connect(function()
        targetIdx = targetIdx % #MINE.targets + 1
        blacklist = {}
        targetB.Text = "TARGET: " .. MINE.targets[targetIdx].label
    end)
end

-- =====================================================================
-- TAB SLIME (farm musuh, jalan biasa tanpa teleport)
-- =====================================================================
do
    local page = pages.slime
    local status = makeLabel(page, "Status: OFF", 0, 0, 218, 24, 12)
    local stats = makeLabel(page, "kill: 0 | hit: 0 | dmg: 0", 0, 26, 218, 18, 12, Color3.fromRGB(150, 220, 150))
    local info = makeLabel(page, "HP: - | target: -", 0, 46, 218, 18, 11, GRAY)
    local startB = makeButton(page, "START", 0, 70, 104, 34, GREEN)
    local stopB = makeButton(page, "STOP", 114, 70, 104, 34, RED)
    local targetB = makeButton(page, "TARGET: pink", 0, 110, 218, 28, Color3.fromRGB(90, 70, 110))
    makeLabel(page, "Pegang senjata. Jalan biasa, tanpa teleport. Berhenti otomatis kalau HP rendah.", 0, 142, 218, 28, 10, GRAY)

    statusLabels.slime = status

    local targetIdx = 1
    local kills, hits, totalDamage = 0, 0, 0
    local targetHits = 0
    local lastHitAt = os.clock()
    local currentTarget = nil
    local blacklist = {}

    -- Jeda ayunan diukur dari jarak antar damage nyata (animasi pedang lambat, beberapa detik)
    local swingCd = nil      -- nil = belum diukur
    local gapSamples = {}
    local prevHitAt = nil
    local lastHealAt = 0

    local function refreshStats()
        stats.Text = string.format("kill: %d | hit: %d | dmg: %d", kills, hits, math.floor(totalDamage))
    end

    -- Event damage dari server: {entity = <slime>, damage = 15, ...}
    H.damage = function(entity, dmg)
        if entity ~= currentTarget then return end

        local now = os.clock()
        if prevHitAt then
            local gap = now - prevHitAt
            if gap >= SLIME.minCooldown and gap <= SLIME.maxCooldown then
                if swingCd == nil then
                    gapSamples[#gapSamples + 1] = gap
                    if #gapSamples >= 3 then
                        table.sort(gapSamples)
                        swingCd = gapSamples[math.ceil(#gapSamples / 2)] -- median
                    end
                elseif gap > swingCd * 1.6 then
                    swingCd = nil -- jeda berubah (senjata/buff lain), ukur ulang
                    gapSamples = {}
                end
            end
        end
        prevHitAt = now

        hits += 1
        targetHits += 1
        totalDamage += dmg
        lastHitAt = now
        refreshStats()
    end

    local function getRoot()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getHum()
        local char = player.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function entityPos(e)
        if e:IsA("BasePart") then
            return e.Position
        end

        local ok, p = pcall(function()
            return e:GetPivot().Position
        end)
        if ok then
            return p
        end
        return nil
    end

    local function entityAlive(e)
        if not e or not e.Parent then return false end

        local hum = e:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then
            return false
        end

        local h = e:GetAttribute("Health")
        if typeof(h) == "number" and h <= 0 then
            return false
        end

        return true
    end

    local function nameMatches(name)
        local n = name:lower()
        for _, w in ipairs(SLIME.targets[targetIdx].words) do
            if n:find(w, 1, true) then
                return true
            end
        end
        return false
    end

    local function findTarget()
        local root = getRoot()
        local folder = workspace:FindFirstChild(SLIME.folderName)
        if not root or not folder then return nil end

        local best, bestDist
        for _, e in ipairs(folder:GetChildren()) do
            local banned = blacklist[e]
            if banned and os.clock() > banned then
                blacklist[e] = nil
                banned = nil
            end

            if not banned and nameMatches(e.Name) and entityAlive(e) then
                local pos = entityPos(e)
                if pos then
                    local d = (pos - root.Position).Magnitude
                    if d <= SLIME.searchRadius and (not bestDist or d < bestDist) then
                        best, bestDist = e, d
                    end
                end
            end
        end

        return best
    end

    local function aimAt(pos)
        local cam = workspace.CurrentCamera
        if cam and pos then
            local v, onScreen = cam:WorldToViewportPoint(pos)
            if onScreen then
                return Vector2.new(v.X, v.Y)
            end
        end
        return nil
    end

    -- Hanya memutar badan, posisi tidak berubah
    local function face(pos)
        local root = getRoot()
        if not root then return end
        root.CFrame = CFrame.lookAt(root.Position, Vector3.new(pos.X, root.Position.Y, pos.Z))
    end

    -- Jalan biasa ke slime (Humanoid:MoveTo), tidak ada teleport
    local function approach(id, t)
        local started = os.clock()

        while isActive(id) and entityAlive(t) and os.clock() - started < SLIME.walkTimeout do
            local root, hum, pos = getRoot(), getHum(), entityPos(t)

            if not root or not hum or not pos then
                task.wait(0.5)
                return false
            end

            if (root.Position - pos).Magnitude <= SLIME.attackDistance then
                return true
            end

            hum:MoveTo(pos)
            task.wait(0.25)
        end

        local root, pos = getRoot(), entityPos(t)
        return root ~= nil and pos ~= nil and entityAlive(t)
            and (root.Position - pos).Magnitude <= SLIME.attackDistance
    end

    local function findToolByName(part)
        part = part:lower()

        local char = player.Character
        local bp = player:FindFirstChildOfClass("Backpack")

        for _, holder in ipairs({ char, bp }) do
            if holder then
                for _, t in ipairs(holder:GetChildren()) do
                    if t:IsA("Tool") and t.Name:lower():find(part, 1, true) then
                        return t
                    end
                end
            end
        end

        return nil
    end

    -- Pakai item penyembuh (kalau SLIME.healItem diisi), lalu pegang senjata lagi
    local function maybeHeal(id, hum)
        if SLIME.healItem == "" or hum.MaxHealth <= 0 then return end
        if hum.Health / hum.MaxHealth * 100 >= SLIME.healBelowPercent then return end
        if os.clock() - lastHealAt < SLIME.healCooldown then return end
        lastHealAt = os.clock()

        local item = findToolByName(SLIME.healItem)
        if not item then
            say("slime", id, "item penyembuh '" .. SLIME.healItem .. "' tidak ketemu")
            return
        end

        local char = player.Character
        local weapon = char and char:FindFirstChildOfClass("Tool")

        say("slime", id, "pakai " .. item.Name)
        hum:EquipTool(item)
        task.wait(0.4)
        click()
        task.wait(1.0)

        if weapon and weapon ~= item and weapon.Parent then
            hum:EquipTool(weapon)
            task.wait(0.3)
        end
    end

    local function fight(id, t)
        local started = os.clock()
        currentTarget = t
        targetHits = 0
        prevHitAt = nil
        lastHitAt = os.clock()

        while isActive(id) and entityAlive(t) and os.clock() - started < SLIME.targetTimeout do
            local root, hum, pos = getRoot(), getHum(), entityPos(t)
            if not root or not hum or not pos then break end

            maybeHeal(id, hum)

            if hum.MaxHealth > 0 then
                local pct = hum.Health / hum.MaxHealth * 100
                local cdText = swingCd and string.format("%.1fs", swingCd) or "ukur..."
                info.Text = string.format("HP: %d%% | cd: %s | %s", math.floor(pct), cdText, t.Name)

                if pct < SLIME.minHpPercent then
                    break -- HP terlalu rendah, slimeLoop yang menghentikan
                end
            end

            local d = (root.Position - pos).Magnitude

            if d > SLIME.attackDistance then
                hum:MoveTo(pos) -- slime bergeser, dekati lagi dengan jalan biasa
                task.wait(0.2)
            else
                if SLIME.faceTarget then
                    face(pos)
                end

                click(aimAt(pos))

                -- Belum terukur: ketuk tiap probeInterval (ketukan saat cooldown diabaikan game),
                -- supaya jarak antar damage nyata bisa diukur. Sudah terukur: ketuk tiap swingCd
                -- ditambah sedikit acak, jadi tidak ada ketukan yang terbuang.
                local gap = (swingCd or SLIME.probeInterval) + math.random() * SLIME.swingJitter
                local t0 = os.clock()
                while isActive(id) and entityAlive(t) and os.clock() - t0 < gap do
                    task.wait(0.05)
                end
            end

            if os.clock() - lastHitAt > SLIME.noHitSeconds then
                say("slime", id, "tidak ada damage, ganti target")
                blacklist[t] = os.clock() + SLIME.blacklistTime
                break
            end
        end

        currentTarget = nil

        if not entityAlive(t) and targetHits > 0 then
            kills += 1
            refreshStats()
        end

        local lo, hi = SLIME.afterKillDelay[1], SLIME.afterKillDelay[2]
        task.wait(lo + math.random() * (hi - lo))
    end

    local function slimeLoop(myRun)
        while isActive(myRun) do
            local hum = getHum()
            local pct = 100
            if hum and hum.MaxHealth > 0 then
                pct = hum.Health / hum.MaxHealth * 100
            end

            if pct < SLIME.minHpPercent then
                stopAll()
                status.Text = string.format("Status: HP %d%%, berhenti demi aman", math.floor(pct))
                return
            end

            local t = findTarget()
            if not t then
                info.Text = string.format("HP: %d%% | target: -", math.floor(pct))
                say("slime", myRun, "tidak ada slime " .. SLIME.targets[targetIdx].label .. ", tunggu...")
                task.wait(2)
                continue
            end

            info.Text = string.format("HP: %d%% | target: %s", math.floor(pct), t.Name)
            say("slime", myRun, "menuju " .. t.Name)

            if approach(myRun, t) then
                say("slime", myRun, "menyerang " .. t.Name)
                fight(myRun, t)
            else
                if isActive(myRun) then
                    blacklist[t] = os.clock() + SLIME.blacklistTime
                end
                task.wait(0.3)
            end
        end

        currentTarget = nil
    end

    startB.MouseButton1Click:Connect(function()
        startTask("slime", slimeLoop)
    end)
    stopB.MouseButton1Click:Connect(stopAll)

    targetB.MouseButton1Click:Connect(function()
        targetIdx = targetIdx % #SLIME.targets + 1
        blacklist = {}
        targetB.Text = "TARGET: " .. SLIME.targets[targetIdx].label
    end)
end

-- =====================================================================
-- TAB LOG
-- =====================================================================
do
    local ProximityPromptService = game:GetService("ProximityPromptService")

    local page = pages.log
    local status = makeLabel(page, "", 0, 0, 218, 24, 12)
    local recB = makeButton(page, "REKAM: OFF", 0, 28, 218, 28, BLUE)
    local markB = makeButton(page, "TANDAI!", 0, 60, 218, 32, GREEN)
    local copyB = makeButton(page, "SALIN LOG", 0, 96, 104, 28, Color3.fromRGB(60, 100, 90))
    local clearB = makeButton(page, "HAPUS", 114, 96, 104, 28, RED)
    local scanB = makeButton(page, "SCAN SEKITAR", 0, 128, 218, 28, Color3.fromRGB(110, 90, 40))

    statusLabels.log = status
    H.logging = false
    H.hookedCount = 0

    local t0 = os.clock()
    local lines = {}

    local function refreshLog()
        status.Text = string.format("%s | event: %d | baris: %d",
            H.logging and "merekam" or "berhenti", H.hookedCount, #lines)
    end
    H.refreshLog = refreshLog

    local function logLine(msg)
        lines[#lines + 1] = string.format("[%6.2f] %s", os.clock() - t0, msg)
        if #lines > LOGC.maxLines then
            table.remove(lines, 1)
        end
        refreshLog()
    end

    local function ser(v, depth)
        local tv = typeof(v)

        if tv == "string" then
            if #v > 60 then
                v = v:sub(1, 60) .. "..."
            end
            return '"' .. v .. '"'
        elseif tv == "Instance" then
            return "<" .. v:GetFullName() .. ">"
        elseif tv == "table" then
            if depth >= LOGC.maxDepth then
                return "{...}"
            end

            local parts, n = {}, 0
            for k, val in pairs(v) do
                n += 1
                if n > LOGC.maxItems then
                    parts[#parts + 1] = "..."
                    break
                end
                parts[#parts + 1] = "[" .. ser(k, depth + 1) .. "]=" .. ser(val, depth + 1)
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        end

        return tostring(v)
    end

    local function isIgnored(name)
        for _, w in ipairs(LOGC.ignore) do
            if name:find(w, 1, true) then
                return true
            end
        end
        return false
    end

    -- Dipanggil untuk setiap event server saat REKAM ON
    H.logEvent = function(r, ...)
        if isIgnored(r.Name) then return end

        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = ser((select(i, ...)), 0)
        end

        logLine("EVENT " .. r:GetFullName() .. " (" .. table.concat(parts, ", ") .. ")")
    end

    -- Ketukan layar (bukan tombol GUI) ikut dicatat
    table.insert(uiConnections, UIS.InputBegan:Connect(function(input, processed)
        if processed or not H.logging then return end
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            logLine("TAP layar")
        end
    end))

    -- Tombol interaksi (ProximityPrompt) yang lu pakai sendiri
    table.insert(uiConnections, ProximityPromptService.PromptTriggered:Connect(function(prompt)
        if not H.logging then return end
        logLine("PROMPT dipicu: " .. prompt:GetFullName()
            .. string.format(" (aksi=%q, objek=%q)", prompt.ActionText, prompt.ObjectText))
    end))
    table.insert(uiConnections, ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
        if not H.logging then return end
        logLine("PROMPT mulai ditahan: " .. prompt:GetFullName())
    end))

    -- Jendela log (kalau executor tidak punya clipboard)
    local logBox

    local function showLogWindow(text)
        if not logWindow then
            logWindow = Instance.new("Frame")
            logWindow.Size = UDim2.fromOffset(340, 240)
            logWindow.Position = UDim2.new(0.5, -170, 0.5, -120)
            logWindow.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            logWindow.ZIndex = 5
            logWindow.Parent = gui

            local scroll = Instance.new("ScrollingFrame")
            scroll.Size = UDim2.new(1, -10, 1, -45)
            scroll.Position = UDim2.fromOffset(5, 5)
            scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            scroll.ScrollBarThickness = 6
            scroll.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            scroll.ZIndex = 6
            scroll.Parent = logWindow

            logBox = Instance.new("TextBox")
            logBox.Size = UDim2.new(1, -8, 0, 0)
            logBox.AutomaticSize = Enum.AutomaticSize.Y
            logBox.BackgroundTransparency = 1
            logBox.TextColor3 = Color3.new(1, 1, 1)
            logBox.TextSize = 11
            logBox.Font = Enum.Font.Code
            logBox.TextXAlignment = Enum.TextXAlignment.Left
            logBox.TextYAlignment = Enum.TextYAlignment.Top
            logBox.MultiLine = true
            logBox.TextWrapped = true
            logBox.ClearTextOnFocus = false
            logBox.ZIndex = 7
            logBox.Parent = scroll

            local close = Instance.new("TextButton")
            close.Size = UDim2.new(1, -10, 0, 30)
            close.Position = UDim2.new(0, 5, 1, -35)
            close.Text = "TUTUP"
            close.BackgroundColor3 = RED
            close.TextColor3 = Color3.new(1, 1, 1)
            close.ZIndex = 6
            close.Parent = logWindow
            close.MouseButton1Click:Connect(function()
                logWindow.Visible = false
            end)
        end

        logBox.Text = text
        logWindow.Visible = true
    end

    -- Scan objek di sekitar (cari ore, tanaman, tombol interaksi)
    local function scanMatches(n)
        n = n:lower()
        for _, w in ipairs(LOGC.scanWords) do
            if n:find(w, 1, true) then
                return true
            end
        end
        return false
    end

    local function attrString(inst)
        local parts = {}
        for k, v in pairs(inst:GetAttributes()) do
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
        return table.concat(parts, ", ")
    end

    local function inAnyCharacter(inst)
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character and inst:IsDescendantOf(p.Character) then
                return true
            end
        end
        return false
    end

    local function posOf(inst)
        if inst:IsA("BasePart") then
            return inst.Position
        end
        if inst:IsA("Model") then
            local ok, pos = pcall(function()
                return inst:GetPivot().Position
            end)
            if ok then
                return pos
            end
        end
        return nil
    end

    local function scanNearby()
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            logLine("SCAN: karakter tidak ketemu")
            return
        end

        logLine(string.format("SCAN dari posisi %s, radius %d stud", tostring(root.Position), LOGC.scanRadius))

        local found = {}
        for _, inst in ipairs(workspace:GetDescendants()) do
            local isInteract = inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector")
            local isNamed = (inst:IsA("BasePart") or inst:IsA("Model")) and scanMatches(inst.Name)

            if (isInteract or isNamed) and not inAnyCharacter(inst) then
                local target = isInteract and inst.Parent or inst
                local pos = target and posOf(target)

                if pos then
                    local d = (pos - root.Position).Magnitude
                    if d <= LOGC.scanRadius then
                        local extra = ""
                        if inst:IsA("ProximityPrompt") then
                            extra = string.format(" | aksi=%q objek=%q tahan=%s",
                                inst.ActionText, inst.ObjectText, tostring(inst.HoldDuration))
                        end
                        found[#found + 1] = {
                            d = d,
                            text = string.format("%.0f stud | %s | %s | attr: %s%s",
                                d, inst.ClassName, inst:GetFullName(), attrString(inst), extra),
                        }
                    end
                end
            end
        end

        table.sort(found, function(a, b)
            return a.d < b.d
        end)

        for i = 1, math.min(#found, LOGC.scanMax) do
            logLine("  " .. found[i].text)
        end
        logLine(string.format("SCAN selesai: %d objek ketemu (ditampilkan maks %d)", #found, LOGC.scanMax))
    end

    recB.MouseButton1Click:Connect(function()
        H.logging = not H.logging
        recB.Text = H.logging and "REKAM: ON" or "REKAM: OFF"
        recB.BackgroundColor3 = H.logging and Color3.fromRGB(150, 90, 30) or BLUE
        logLine(H.logging and "rekam dimulai" or "rekam dihentikan")
    end)

    markB.MouseButton1Click:Connect(function()
        logLine("=============== TANDA (lu ketuk tombol) ===============")
    end)

    copyB.MouseButton1Click:Connect(function()
        local text = table.concat(lines, "\n")

        local ok = pcall(function()
            if setclipboard then
                setclipboard(text)
            elseif toclipboard then
                toclipboard(text)
            else
                error("tidak ada fungsi clipboard")
            end
        end)

        if ok then
            status.Text = "log disalin ke clipboard"
        else
            status.Text = "log ditampilkan, salin manual"
            showLogWindow(text)
        end
    end)

    clearB.MouseButton1Click:Connect(function()
        lines = {}
        t0 = os.clock()
        logLine("log dihapus")
    end)

    scanB.MouseButton1Click:Connect(scanNearby)

    refreshLog()
end

-- =====================================================================
-- Pemantau event server (satu untuk semua tab)
-- =====================================================================
local function onSound(name, pos)
    for _, l in ipairs(soundLabels) do
        l.Text = "suara: " .. name
    end
    H.fishSound(name, pos)
    H.mineSound(name, pos)
end

local function dispatch(r, ...)
    if H.logging then
        H.logEvent(r, ...)
    end

    local data = ...
    if type(data) ~= "table" then return end

    if type(data.sound) == "string" then
        local pos = nil
        local dir = data.directional
        if type(dir) == "table" and typeof(dir.position) == "Vector3" then
            pos = dir.position
        end
        onSound(data.sound, pos)
    end

    if type(data.Title) == "string" and data.Text == "backpack" then
        H.item(data.Title)
    end

    -- event damage ke musuh: {entity = <model>, damage = angka, ...}
    if typeof(data.entity) == "Instance" and type(data.damage) == "number" then
        H.damage(data.entity, data.damage)
    end
end

local hooked = {}

local function hook(r)
    if hooked[r] then return end
    if not (r:IsA("RemoteEvent") or r.ClassName == "UnreliableRemoteEvent") then return end

    hooked[r] = true
    H.hookedCount += 1

    table.insert(uiConnections, r.OnClientEvent:Connect(function(...)
        dispatch(r, ...)
    end))
end

-- Nama event diacak oleh game, jadi semua RemoteEvent dipantau dan disaring lewat isinya
for _, d in ipairs(game:GetDescendants()) do
    hook(d)
end
table.insert(uiConnections, game.DescendantAdded:Connect(function(d)
    hook(d)
    H.refreshLog()
end))
H.refreshLog()

-- =====================================================================
-- Tombol umum
-- =====================================================================
local currentTab = "fish"

local function showTab(name)
    currentTab = name
    for n, p in pairs(pages) do
        p.Visible = (n == name)
    end
    for n, b in pairs(tabButtons) do
        b.BackgroundColor3 = (n == name) and Color3.fromRGB(70, 110, 170) or Color3.fromRGB(45, 45, 55)
    end
end

for name, b in pairs(tabButtons) do
    b.MouseButton1Click:Connect(function()
        showTab(name)
    end)
end
showTab("fish")

local minimized = false
minButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    frame.Size = UDim2.fromOffset(FRAME_W, minimized and HEADER_H or FRAME_H)
    minButton.Text = minimized and "+" or "-"
end)

modeButton.MouseButton1Click:Connect(function()
    local idx = table.find(CLICK_MODES, clickMode) or 1
    clickMode = CLICK_MODES[idx % #CLICK_MODES + 1]
    modeButton.Text = "MODE: " .. clickMode
end)

testButton.MouseButton1Click:Connect(function()
    if currentTab == "mine" then
        task.spawn(H.testMine)
    else
        task.spawn(click)
    end
end)

-- Anti-AFK: cegah kick karena diam terlalu lama
local antiAfk = true
afkButton.MouseButton1Click:Connect(function()
    antiAfk = not antiAfk
    afkButton.Text = antiAfk and "AFK: on" or "AFK: off"
end)

table.insert(uiConnections, player.Idled:Connect(function()
    if not antiAfk then return end
    pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end)
end))

-- ===== AKHIR ISLAND HUB v8 (kalau baris ini tidak ada di akhir file, filenya kepotong) =====
