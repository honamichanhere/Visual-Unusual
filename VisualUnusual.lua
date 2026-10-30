-- Visual Unusual (standalone) - by Honami
-- UI is built in this file (styled after Mugiwara UI); the Unusual logic is ported from Mugiwara HUB's
-- Games/Evade/VisualUnusual.lua (and the rig lookup of Rigs.lua).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local FOLDER = "VisualUnusual"
if makefolder and isfolder and not isfolder(FOLDER) then makefolder(FOLDER) end

local cleanupFns = {}
local function RegisterCleanup(fn)
    table.insert(cleanupFns, fn)
end

-- Run again while an older copy is still open: that copy takes its effects off first.
local env = getgenv()
if env.VisualUnusualCleanup then pcall(env.VisualUnusualCleanup) end
env.VisualUnusualCleanup = function()
    for _, fn in ipairs(cleanupFns) do pcall(fn) end
end

-- ==========================================================
-- Rigs (from Games/Evade/Rigs.lua, only what Visual Unusual needs)
-- ==========================================================
-- Evade can have TWO rigs named after the player in Workspace.Rigs (menu/inventory and in-game); both
-- are visual copies and both get the effects. The real controlled character is LocalPlayer.Character.
local Rigs = {}
do
    local LocalPlayer = Players.LocalPlayer

    function Rigs.GetAll()
        local list = {}

        local container = workspace:FindFirstChild("Rigs")
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") and child.Name == LocalPlayer.Name then
                    local humanoid = child:FindFirstChildOfClass("Humanoid")
                    if humanoid then table.insert(list, { Rig = child, Humanoid = humanoid }) end
                end
            end
        end

        if #list == 0 then
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid then table.insert(list, { Rig = character, Humanoid = humanoid }) end
        end

        return list
    end
end

-- ==========================================================
-- Unusual engine (ported from Games/Evade/VisualUnusual.lua)
-- ==========================================================
local LocalPlayer = Players.LocalPlayer

local Unusual = {}

local entries = {}      -- { { Name, Display, Header, Rarity, Image, Id, Instance, Limbs, Data } } terurut menurut nama
local byInstance = {}   -- [instance] = entry
local applied = {}      -- [entry] = record { Entry, Subs = { [rig] = sub }, RootSub }; sub = { Host, Roots = { { Instance, Host } }, Missing }
local loaded = false
local source = "none"
local watching = false

Unusual.OnChange = nil -- dipanggil (tanpa argumen) tiap daftar terpasang berubah, termasuk saat dipasang ulang

-- Nama anggota badan yang jointnya milik rig sendiri: tidak boleh ditimpa/dipindah (sama dengan game).
local BODY_JOINTS = {}
for _, name in ipairs({
    "Head", "Torso", "TorsoRot", "Left Arm", "Left Leg", "Right Arm", "Right Leg", "ArmRot", "Neck", "Root",
    "LeftAnkle", "RightAnkle", "LeftKnee", "RightKnee", "LeftElbow", "RightElbow", "LeftShoulder", "RightShoulder",
    "LeftHip", "RightHip", "LeftWrist", "RightWrist", "Waist",
}) do
    BODY_JOINTS[name] = true
end

local function Changed()
    if Unusual.OnChange then task.spawn(Unusual.OnChange) end
end

--// daftar item ------------------------------------------------------------------

local function AddEntry(module, id, info)
    if byInstance[module] then return end
    local character = module:FindFirstChild("Character")
    local classic = module:FindFirstChild("CharacterClassic")
    if not character and not classic then return end -- aura RELICS (menempel ke boombox) bukan efek karakter

    local appearance = type(info.AppearanceInfo) == "table" and info.AppearanceInfo or {}
    local ui = type(info.UIInfo) == "table" and info.UIInfo or {}
    local icon = appearance.Icon
    local limbs = {}
    for _, part in ipairs((character or classic):GetChildren()) do
        if part:IsA("BasePart") then table.insert(limbs, part.Name) end
    end
    if #limbs == 0 then return end -- item kosong ("Nothing")

    local entry = {
        Name = module.Name,
        Display = type(appearance.Name) == "string" and appearance.Name or module.Name,
        Header = type(ui.Header) == "string" and ui.Header or "Other",
        Rarity = type(ui.Rarity) == "string" and ui.Rarity or nil,
        Image = (type(icon) == "number" and icon ~= 0) and ("rbxassetid://" .. icon) or nil,
        Id = id,
        Instance = module,
        Limbs = limbs,
        HasRoot = table.find(limbs, "HumanoidRootPart") ~= nil,
    }
    table.insert(entries, entry)
    byInstance[module] = entry
end

local function IsUnusual(info)
    return type(info) == "table" and type(info.CosmeticInfo) == "table" and info.CosmeticInfo.Unusual == true
end

local function LoadFromRegistry()
    local items = ReplicatedStorage:FindFirstChild("Items")
    local registryModule = items and items:FindFirstChild("Registry")
    if not registryModule then return false end

    local ok, Registry = pcall(require, registryModule)
    if not ok or type(Registry) ~= "table" or type(Registry.GetByCategory) ~= "function" then return false end

    local okList, list = pcall(Registry.GetByCategory, "Cosmetics")
    if not okList or type(list) ~= "table" then return false end

    for id, record in pairs(list) do
        local module = type(record) == "table" and record.Module
        if typeof(module) == "Instance" then
            local okInfo, info = pcall(require, module)
            if okInfo and IsUnusual(info) then AddEntry(module, id, info) end
        end
    end
    return #entries > 0
end

-- Cadangan: semua ModuleScript di folder Items yang bertanda Unusual.
local function LoadFromScan()
    local items = ReplicatedStorage:FindFirstChild("Items")
    if not items then return end
    for _, descendant in ipairs(items:GetDescendants()) do
        if descendant:IsA("ModuleScript") and (descendant:FindFirstChild("Character") or descendant:FindFirstChild("CharacterClassic")) then
            local ok, info = pcall(require, descendant)
            if ok and IsUnusual(info) then AddEntry(descendant, descendant:GetAttribute("ID"), info) end
        end
    end
end

-- Daftar ditemukan sekali; menunggu folder Items sebentar kalau game belum selesai memuat.
function Unusual.Load()
    if loaded then return #entries end
    loaded = true

    if not ReplicatedStorage:FindFirstChild("Items") then
        pcall(function() ReplicatedStorage:WaitForChild("Items", 8) end)
    end

    if LoadFromRegistry() then
        source = "registry"
    else
        table.clear(entries)
        table.clear(byInstance)
        LoadFromScan()
        source = "scan"
    end

    table.sort(entries, function(a, b)
        return string.lower(a.Display) < string.lower(b.Display)
    end)
    return #entries
end

function Unusual.GetSource() return source end
function Unusual.GetEntries() return entries end

--// memori -----------------------------------------------------------------------

local function SafeClone(instance)
    if not instance then return nil end
    local ok, clone = pcall(instance.Clone, instance)
    return ok and clone or nil
end

-- Menyalin isi Unusual (model R15 dan R6) ke memori. Dipanggil sekali per item; hasilnya di entry.Data.
function Unusual.Capture(entry)
    if entry.Data then return entry.Data end
    entry.Data = {
        R15 = SafeClone(entry.Instance:FindFirstChild("Character")),
        R6 = SafeClone(entry.Instance:FindFirstChild("CharacterClassic")),
    }
    return entry.Data
end

-- Menyalin semua Unusual pelan-pelan di latar belakang. Mengembalikan jumlah yang disalin.
function Unusual.CaptureAll(onProgress)
    local count = 0
    for index, entry in ipairs(entries) do
        if not entry.Data then
            Unusual.Capture(entry)
            count = count + 1
        end
        if index % 6 == 0 then
            if onProgress then onProgress(index, #entries) end
            task.wait()
        end
    end
    return count
end

function Unusual.CapturedCount()
    local count = 0
    for _, entry in ipairs(entries) do
        if entry.Data then count = count + 1 end
    end
    return count
end

--// rig dan penempelan ----------------------------------------------------------------

local function RigIsR6(rig)
    local humanoid = rig:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
end

-- Semua rig yang terlihat milik pemain lokal: Evade punya DUA dengan nama yang sama di Workspace.Rigs (rig
-- inventory/menu dan rig dalam game), keduanya dipasangi. Rigs.lua yang menentukan; tanpanya dipakai pencarian
-- sederhana dengan aturan yang sama (karakter biasa kalau tidak ada rig sama sekali).
local function Targets()
    local list = {}
    local entries = Rigs and Rigs.GetAll() or nil
    if entries then
        for _, entry in ipairs(entries) do
            if entry.Rig:FindFirstChild("Head") then table.insert(list, entry.Rig) end
        end
        return list
    end

    local container = workspace:FindFirstChild("Rigs")
    if container then
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Model") and child.Name == LocalPlayer.Name and child:FindFirstChild("Head") then
                table.insert(list, child)
            end
        end
    end
    local character = LocalPlayer.Character
    if #list == 0 and character and character:FindFirstChild("Head") then table.insert(list, character) end
    return list
end
Unusual.GetTargets = Targets

local function LimbOf(host, name)
    local limb = host:FindFirstChild(name)
    if limb and limb:IsA("BasePart") then return limb end
    return nil
end

local function Tame(instance)
    if instance:IsA("BasePart") then
        instance.Anchored = false
        instance.Massless = true
        instance.CanCollide = false
        instance.CanQuery = false
        instance.CanTouch = false
    end
end

-- Menempelkan satu Unusual ke `host` (meniru applyCosmeticRig milik game, tanpa merusak isi rig). Mengembalikan sub:
-- { Host, Roots = { { Instance, Host } }, Missing }.
-- Rig game tidak punya HumanoidRootPart, jadi bagian untuk HumanoidRootPart dilewati di rig dan ditempel sekali ke
-- karakter (onlyRoot = true, host = karakter). Rig yang punya HumanoidRootPart (karakter biasa) memasangnya sendiri.
local function Attach(entry, host, onlyRoot)
    local data = Unusual.Capture(entry)
    local model = RigIsR6(host) and data.R6 or data.R15
    local sub = { Host = host, Roots = {}, Missing = 0 }
    if not model then
        sub.Missing = #entry.Limbs
        return sub
    end

    local clone = model:Clone()
    for _, descendant in ipairs(clone:GetDescendants()) do
        if descendant:IsA("Script") then descendant.Enabled = true end
    end

    for _, stand in ipairs(clone:GetChildren()) do
        if stand:IsA("BasePart") then
            local isRootStand = stand.Name == "HumanoidRootPart"
            local wanted
            if onlyRoot then
                wanted = isRootStand
            else
                wanted = not isRootStand or host:FindFirstChild("HumanoidRootPart") ~= nil
            end

            if wanted then
                local limb = LimbOf(host, stand.Name)
                if limb then
                    if stand.Name == "Head" then
                        -- mesh/tekstur kepala pengganti tidak dipakai, kepala asli tetap
                        for _, child in ipairs(stand:GetChildren()) do
                            if child:IsA("DataModelMesh") or child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance") then
                                child:Destroy()
                            end
                        end
                    end
                    -- Game memberi attachment yang bernama sama dengan milik rig posisi milik rig. Di sini TIDAK
                    -- ditiru: tidak ada Unusual yang bentrok dengan nama attachment rig, sedangkan nama umum seperti
                    -- "Attachment" atau "ParticleAttachment" dipakai belasan Unusual di kepala yang sama, jadi
                    -- kalau ditumpuk yang kedua ikut posisi yang pertama (halo Angelic Redemption jatuh ke tengah kepala).
                    for _, child in ipairs(stand:GetChildren()) do
                        if not (child:IsA("Motor6D") and BODY_JOINTS[child.Name]) then
                            child.Parent = limb
                            table.insert(sub.Roots, { Instance = child, Host = limb })
                        end
                    end
                else
                    sub.Missing = sub.Missing + 1
                end
            end
        end
    end

    -- joint yang menunjuk part pengganti diarahkan ke anggota badan yang namanya sama
    for _, root in ipairs(sub.Roots) do
        local instance = root.Instance
        local list = instance:GetDescendants()
        table.insert(list, instance)
        for _, item in ipairs(list) do
            if (item:IsA("Weld") or item:IsA("Motor6D")) and not BODY_JOINTS[item.Name] then
                if item.Part0 and item.Part0.Parent == clone then item.Part0 = LimbOf(host, item.Part0.Name) end
                if item.Part1 and item.Part1.Parent == clone then item.Part1 = LimbOf(host, item.Part1.Name) end
            elseif item:IsA("WeldConstraint") then
                if item.Part0 and item.Part0.Parent == clone then item.Part0 = LimbOf(host, item.Part0.Name) end
                if item.Part1 and item.Part1.Parent == clone then item.Part1 = LimbOf(host, item.Part1.Name) end
            end
            Tame(item)
        end
    end

    clone:Destroy()
    return sub
end

local function Detach(sub)
    for _, root in ipairs(sub.Roots) do
        pcall(root.Instance.Destroy, root.Instance)
    end
    sub.Roots = {}
end

-- Masih utuh: host-nya masih ada di game dan semua akar masih menempel di tempatnya (kalau game menghapus atau
-- memindahkan salah satu, sub ini dipasang ulang).
local function Intact(sub)
    if not sub.Host:IsDescendantOf(workspace) then return false end
    for _, root in ipairs(sub.Roots) do
        if root.Instance.Parent ~= root.Host or not root.Host:IsDescendantOf(workspace) then return false end
    end
    return true
end

local function SafeAttach(entry, host, onlyRoot)
    local ok, sub = pcall(Attach, entry, host, onlyRoot)
    if ok then return sub end
    warn("[Visual Unusual] Visual Unusual: " .. entry.Display .. ": " .. tostring(sub))
    return { Host = host, Roots = {}, Missing = 0 }
end

-- Menyamakan satu record dengan keadaan sekarang: rig yang hilang dilepas, rig baru dipasangi, dan yang efeknya
-- terhapus oleh game dipasang ulang. Mengembalikan true kalau ada yang berubah.
local function Sync(record, rigs)
    local changed = false

    local present = {}
    for _, rig in ipairs(rigs) do present[rig] = true end
    for host, sub in pairs(table.clone(record.Subs)) do
        if not present[host] then
            Detach(sub)
            record.Subs[host] = nil
            changed = true
        end
    end

    local rootCovered = false
    for _, rig in ipairs(rigs) do
        if rig:FindFirstChild("HumanoidRootPart") then rootCovered = true end
        local sub = record.Subs[rig]
        if not sub or not Intact(sub) then
            if sub then Detach(sub) end
            record.Subs[rig] = SafeAttach(record.Entry, rig, false)
            changed = true
        end
    end

    -- bagian HumanoidRootPart: satu kali di karakter, kalau tidak ada rig yang punya HumanoidRootPart sendiri
    local character = LocalPlayer.Character
    local wantRoot = record.Entry.HasRoot and not rootCovered and character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
    if wantRoot then
        local sub = record.RootSub
        if not sub or sub.Host ~= character or not Intact(sub) then
            if sub then Detach(sub) end
            record.RootSub = SafeAttach(record.Entry, character, true)
            changed = true
        end
    elseif record.RootSub and not (record.Entry.HasRoot and not rootCovered) then
        Detach(record.RootSub)
        record.RootSub = nil
        changed = true
    end

    return changed
end

local function DetachAll(record)
    for _, sub in pairs(record.Subs) do Detach(sub) end
    record.Subs = {}
    if record.RootSub then
        Detach(record.RootSub)
        record.RootSub = nil
    end
end

local function RootCount(record)
    local count = record.RootSub and #record.RootSub.Roots or 0
    for _, sub in pairs(record.Subs) do count = count + #sub.Roots end
    return count
end

-- Pemeriksa latar belakang: hidup hanya selama ada yang terpasang. Tiap 0.3 detik semua efek dicek di semua rig.
local function Watch()
    if watching then return end
    watching = true
    task.spawn(function()
        while next(applied) ~= nil do
            task.wait(0.3)
            local rigs = Targets()
            local redone = false
            for entry, record in pairs(table.clone(applied)) do
                if applied[entry] == record then
                    local ok, changed = pcall(Sync, record, rigs)
                    if ok and changed then redone = true end
                end
            end
            if redone then Changed() end
        end
        watching = false
    end)
end

--// API ---------------------------------------------------------------------------------

function Unusual.IsApplied(entry)
    return applied[entry] ~= nil
end

-- Daftar yang sedang terpasang, urut nama.
function Unusual.GetApplied()
    local list = {}
    for entry in pairs(applied) do table.insert(list, entry) end
    table.sort(list, function(a, b) return string.lower(a.Display) < string.lower(b.Display) end)
    return list
end

function Unusual.AppliedCount()
    local count = 0
    for _ in pairs(applied) do count = count + 1 end
    return count
end

-- Mengembalikan true, pesan atau false, alasan. Item yang sama dua kali tidak ditumpuk.
function Unusual.Apply(entry)
    if applied[entry] then return true, entry.Display .. " is already applied." end
    local rigs = Targets()
    if #rigs == 0 then return false, "No character found. Spawn into a round first." end

    local record = { Entry = entry, Subs = {}, RootSub = nil }
    local ok, err = pcall(Sync, record, rigs)
    if not ok then
        DetachAll(record)
        return false, "Could not apply " .. entry.Display .. ": " .. tostring(err)
    end
    if RootCount(record) == 0 and not entry.HasRoot then
        DetachAll(record)
        return false, entry.Display .. " has no effect for this character type."
    end

    applied[entry] = record
    Watch()
    Changed()
    return true, entry.Display .. " applied."
end

function Unusual.Remove(entry)
    local record = applied[entry]
    if not record then return false, entry.Display .. " is not applied." end
    applied[entry] = nil
    DetachAll(record)
    Changed()
    return true, entry.Display .. " removed."
end

-- Membersihkan semua. Mengembalikan jumlah yang dilepas.
function Unusual.Clear()
    local count = 0
    for entry, record in pairs(table.clone(applied)) do
        applied[entry] = nil
        DetachAll(record)
        count = count + 1
    end
    if count > 0 then Changed() end
    return count
end

-- Saat hub dimatikan semua efek dilepas.
RegisterCleanup(function()
    Unusual.OnChange = nil
    pcall(Unusual.Clear)
end)


-- ==========================================================
-- UI: own implementation that copies the look of Mugiwara UI (Gear 5 theme): glass window,
-- spinning neon border, gradient title / badge / buttons, white translucent cards,
-- dark inset fields and picture cells with a check badge. Layout: one list with a category
-- dropdown, a search box and an always-open grid of effect icons.
-- ==========================================================
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local VERSION = "v2.0"

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local THEME = {
    Background = rgb(12, 13, 21), BackgroundAlpha = 0.12,
    Card = rgb(255, 255, 255), CardAlpha = 0.91,
    Stroke = rgb(255, 255, 255), StrokeAlpha = 0.84,
    Field = rgb(0, 0, 0), FieldAlpha = 0.45,
    Popup = rgb(14, 14, 20), PopupAlpha = 0.08,
    Text = rgb(252, 252, 255), SubText = rgb(200, 204, 220), Muted = rgb(142, 146, 164),
    Accent = rgb(255, 255, 255), OnAccent = rgb(16, 18, 30),
    Success = rgb(80, 230, 150), Danger = rgb(255, 72, 92),
    Swapped = rgb(255, 200, 62),
}
local GRADIENT_STOPS = { rgb(255, 255, 255), rgb(224, 234, 255), rgb(255, 247, 226), rgb(255, 224, 160) }

local function Linear(stops)
    local points = {}
    for index, color in ipairs(stops) do
        points[index] = ColorSequenceKeypoint.new((index - 1) / (#stops - 1), color)
    end
    return ColorSequence.new(points)
end
local GRADIENT = Linear(GRADIENT_STOPS)
local CYCLE = (function()
    local mirrored = table.clone(GRADIENT_STOPS)
    for index = #GRADIENT_STOPS - 1, 1, -1 do table.insert(mirrored, GRADIENT_STOPS[index]) end
    return Linear(mirrored)
end)()

local FONT_TITLE, FONT_LABEL, FONT_BODY = Enum.Font.GothamBold, Enum.Font.GothamSemibold, Enum.Font.GothamMedium

local function New(class, props, parent)
    local instance = Instance.new(class)
    for key, value in pairs(props) do instance[key] = value end
    instance.Parent = parent
    return instance
end

local function Round(instance, radius)
    return New("UICorner", { CornerRadius = UDim.new(0, radius) }, instance)
end

local function Stroke(instance, transparency, thickness, color)
    return New("UIStroke", {
        Color = color or THEME.Stroke,
        Transparency = transparency,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, instance)
end

local function Gradient(parent, rotation, sequence)
    return New("UIGradient", { Rotation = rotation or 0, Color = sequence or GRADIENT }, parent)
end

local function Label(parent, props)
    local merged = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = FONT_BODY,
        TextColor3 = THEME.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }
    for key, value in pairs(props) do merged[key] = value end
    return New("TextLabel", merged, parent)
end

local function Tween(instance, props, duration, style)
    TweenService:Create(instance, TweenInfo.new(duration or 0.2, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local spinTweens = {}
local function Spin(gradient, seconds)
    local tween = TweenService:Create(gradient, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = gradient.Rotation + 360 })
    tween:Play()
    table.insert(spinTweens, tween)
end
RegisterCleanup(function()
    for _, tween in ipairs(spinTweens) do pcall(function() tween:Cancel() end) end
end)

-- Icons drawn from rotated bars, like Mugiwara UI draws its own glyphs.
local function Glyph(parent, size)
    return New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
    }, parent)
end

local function Bar(root, length, thickness, rotation, x, y, color)
    local bar = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(x, y),
        Size = UDim2.fromOffset(length, thickness),
        Rotation = rotation,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, root)
    Round(bar, thickness)
    return bar
end

local function ChevronGlyph(parent, size, color)
    local root = Glyph(parent, size)
    local length = size * 0.56
    return root, { Bar(root, length, 2, 45, 0.31, 0.5, color), Bar(root, length, 2, -45, 0.69, 0.5, color) }
end

local function CheckGlyph(parent, size, color)
    local root = Glyph(parent, size)
    Bar(root, size * 0.34, 2, 42, 0.3, 0.63, color)
    Bar(root, size * 0.64, 2, -48, 0.63, 0.51, color)
    return root
end

local function CloseGlyph(parent, size, color)
    local root = Glyph(parent, size)
    return { Bar(root, size * 0.78, 2, 45, 0.5, 0.5, color), Bar(root, size * 0.78, 2, -45, 0.5, 0.5, color) }
end

local function MinusGlyph(parent, size, color)
    local root = Glyph(parent, size)
    return { Bar(root, size * 0.7, 2, 0, 0.5, 0.5, color) }
end

-- A pill button: gradient fill (primary) or a white translucent card (secondary).
local function MakeButton(parent, text, primary, width)
    local pill = New("Frame", {
        Size = UDim2.fromOffset(width, 32),
        BackgroundColor3 = primary and Color3.new(1, 1, 1) or THEME.Card,
        BackgroundTransparency = primary and 0 or THEME.CardAlpha,
        BorderSizePixel = 0,
    }, parent)
    Round(pill, 9)
    if primary then Gradient(pill, 0) else Stroke(pill, THEME.StrokeAlpha) end
    local label = Label(pill, {
        Text = text,
        Font = FONT_TITLE,
        TextColor3 = primary and THEME.OnAccent or THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    })
    local hit = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, pill)
    local button = { Frame = pill, Label = label, Hit = hit, Primary = primary, Width = width }
    hit.MouseButton1Down:Connect(function()
        Tween(pill, { Size = UDim2.fromOffset(width - 6, 28) }, 0.08)
    end)
    hit.MouseButton1Up:Connect(function()
        Tween(pill, { Size = UDim2.fromOffset(width, 32) }, 0.3, Enum.EasingStyle.Back)
    end)
    hit.MouseLeave:Connect(function()
        Tween(pill, { Size = UDim2.fromOffset(width, 32) }, 0.2)
    end)
    if not primary then
        hit.MouseEnter:Connect(function() Tween(pill, { BackgroundTransparency = 0.84 }, 0.15) end)
        hit.MouseLeave:Connect(function() Tween(pill, { BackgroundTransparency = THEME.CardAlpha }, 0.2) end)
    end
    return button
end

local function SetEnabled(button, enabled)
    button.Frame.BackgroundTransparency = enabled and (button.Primary and 0 or THEME.CardAlpha) or 0.6
    button.Label.TextTransparency = enabled and 0 or 0.45
end

local guiParent
pcall(function() guiParent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not guiParent then guiParent = Players.LocalPlayer:WaitForChild("PlayerGui") end

local Gui = New("ScreenGui", {
    Name = "VisualUnusual",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 10000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)
RegisterCleanup(function() pcall(function() Gui:Destroy() end) end)

local camera = workspace.CurrentCamera
local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)
local WIDTH, HEIGHT = 400, 470
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 340, 340, 640, 760
local TOPBAR, BAR_H = 54, 56
-- Small screens (phones) shrink the whole UI so it fits instead of being cut off.
local UI_SCALE = math.clamp(math.min(1, (screen.X - 24) / WIDTH, (screen.Y - 24) / HEIGHT), 0.45, 1)

local Main = New("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(WIDTH, HEIGHT),
    BackgroundTransparency = 1,
}, Gui)
New("UIScale", { Scale = UI_SCALE }, Main)

local Pop = New("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
}, Main)
local PopScale = New("UIScale", { Scale = 0.9 }, Pop)

-- neon glow rings behind the window
local glowRings = {}
for _, layer in ipairs({ { 0, 3, 0.5 }, { 3, 7, 0.8 }, { 10, 14, 0.92 } }) do
    local pad, thickness, transparency = layer[1], layer[2], layer[3]
    local ring = New("Frame", {
        Name = "Glow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, pad * 2, 1, pad * 2),
        BackgroundTransparency = 1,
    }, Pop)
    Round(ring, 16 + pad)
    local stroke = Stroke(ring, 1, thickness)
    Spin(Gradient(stroke, 0, CYCLE), 9)
    table.insert(glowRings, { Stroke = stroke, Base = transparency })
end

local Win = New("CanvasGroup", {
    Name = "Window",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = THEME.Background,
    BackgroundTransparency = THEME.BackgroundAlpha,
    GroupTransparency = 1,
    BorderSizePixel = 0,
}, Pop)
Round(Win, 16)

-- glass wash + sheen
local wash = New("Frame", { Name = "Wash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, Win)
Gradient(wash, 35).Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.9),
})
local sheen = New("Frame", { Name = "Sheen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, Win)
New("UIGradient", {
    Rotation = 20,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.92), NumberSequenceKeypoint.new(0.35, 1), NumberSequenceKeypoint.new(1, 0.97),
    }),
}, sheen)

-- spinning neon border above the window
local border = New("Frame", { Name = "Border", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, Pop)
Round(border, 16)
local borderStroke = Stroke(border, 1, 1.5)
Spin(Gradient(borderStroke, 0, CYCLE), 9)
table.insert(glowRings, { Stroke = borderStroke, Base = 0.3 })

-- topbar
local TopBar = New("Frame", { Name = "Topbar", Size = UDim2.new(1, 0, 0, TOPBAR), BackgroundTransparency = 1 }, Win)

local brand = New("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 16, 0.5, 0),
    Size = UDim2.fromOffset(30, 30),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, TopBar)
Round(brand, 9)
Gradient(brand, 45)
Label(brand, {
    Text = "V",
    Font = Enum.Font.GothamBlack,
    TextSize = 17,
    TextColor3 = THEME.OnAccent,
    TextXAlignment = Enum.TextXAlignment.Center,
    Size = UDim2.fromScale(1, 1),
})

local titleRow = New("Frame", {
    Position = UDim2.fromOffset(56, 8),
    Size = UDim2.new(1, -200, 0, 22),
    BackgroundTransparency = 1,
}, TopBar)
New("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 8),
}, titleRow)
local titleLabel = Label(titleRow, {
    Text = "Visual Unusual",
    Font = FONT_TITLE,
    TextSize = 16,
    TextColor3 = Color3.new(1, 1, 1),
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 20),
    LayoutOrder = 1,
})
Gradient(titleLabel, 0)

local versionPill = New("Frame", {
    Size = UDim2.fromOffset(0, 16),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    LayoutOrder = 2,
}, titleRow)
Round(versionPill, 8)
New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, versionPill)
Gradient(versionPill, 0)
Label(versionPill, {
    Text = VERSION,
    Font = FONT_TITLE,
    TextSize = 11,
    TextColor3 = THEME.OnAccent,
    TextXAlignment = Enum.TextXAlignment.Center,
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 16),
})

Label(TopBar, {
    Text = "by Honami  ·  K to hide or show",
    TextSize = 12,
    TextColor3 = THEME.SubText,
    Position = UDim2.fromOffset(56, 30),
    Size = UDim2.new(1, -200, 0, 14),
})

local function ControlButton(offset, makeGlyph, hoverColor)
    local button = New("TextButton", {
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, offset, 0.5, 0),
        Size = UDim2.fromOffset(34, 34),
    }, TopBar)
    Round(button, 9)
    local bars = makeGlyph(button, 20, THEME.SubText)
    button.MouseEnter:Connect(function()
        Tween(button, { BackgroundTransparency = 0.88 }, 0.15)
        for _, bar in ipairs(bars) do Tween(bar, { BackgroundColor3 = hoverColor or THEME.Text }, 0.15) end
    end)
    button.MouseLeave:Connect(function()
        Tween(button, { BackgroundTransparency = 1 }, 0.2)
        for _, bar in ipairs(bars) do Tween(bar, { BackgroundColor3 = THEME.SubText }, 0.2) end
    end)
    return button
end

local CloseButton = ControlButton(-12, CloseGlyph, THEME.Danger)
local MinimizeButton = ControlButton(-50, MinusGlyph)

local topLine = New("Frame", {
    Position = UDim2.fromOffset(0, TOPBAR),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, Win)
Gradient(topLine, 0).Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 0.9),
})

local Body = New("Frame", {
    Name = "Body",
    Position = UDim2.fromOffset(0, TOPBAR + 1),
    Size = UDim2.new(1, 0, 1, -(TOPBAR + 1)),
    BackgroundTransparency = 1,
}, Win)

local PaneHolder = New("Frame", { Name = "Panes", Size = UDim2.new(1, 0, 1, -BAR_H), BackgroundTransparency = 1 }, Body)
New("UIPadding", {
    PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 8),
}, PaneHolder)
New("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 10),
}, PaneHolder)

local BottomBar = New("Frame", {
    Name = "BottomBar",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.fromScale(0, 1),
    Size = UDim2.new(1, 0, 0, BAR_H),
    BackgroundTransparency = 1,
}, Body)
New("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = THEME.Stroke,
    BackgroundTransparency = THEME.StrokeAlpha,
    BorderSizePixel = 0,
}, BottomBar)

local StatusLabel = Label(BottomBar, {
    Position = UDim2.fromOffset(16, 0),
    Size = UDim2.new(1, -150, 1, 0),
    TextColor3 = THEME.SubText,
    TextTruncate = Enum.TextTruncate.AtEnd,
})
local RemoveAllButton = MakeButton(BottomBar, "Remove All", false, 116)
RemoveAllButton.Frame.AnchorPoint = Vector2.new(1, 0.5)
RemoveAllButton.Frame.Position = UDim2.new(1, -12, 0.5, 0)

-- Window behaviour: drag by the topbar, minimize, close.
do
    local dragging, dragStart, startPosition = false, nil, nil
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPosition = true, input.Position, Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    local moveConnection = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = (input.Position - dragStart) / UI_SCALE
            Main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    RegisterCleanup(function() moveConnection:Disconnect() end)

    -- resize grip in the bottom-right corner (the window grows from its top-left corner)
    local grip = New("TextButton", {
        Name = "ResizeGrip",
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -4, 1, -4),
        Size = UDim2.fromOffset(22, 22),
        ZIndex = 8,
    }, Pop)
    Bar(grip, 14, 2, -45, 0.58, 0.58, THEME.Muted)
    Bar(grip, 7, 2, -45, 0.78, 0.78, THEME.Muted)

    local resizing, resizeStart, startSize, resizeOrigin = false, nil, nil, nil
    grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing, resizeStart, startSize, resizeOrigin = true, input.Position, Main.Size, Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then resizing = false end
            end)
        end
    end)
    local resizeConnection = UserInputService.InputChanged:Connect(function(input)
        if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = (input.Position - resizeStart) / UI_SCALE
            local maxWidth = math.max(MIN_WIDTH, math.min(MAX_WIDTH, (screen.X - 24) / UI_SCALE))
            local maxHeight = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, (screen.Y - 24) / UI_SCALE))
            local width = math.clamp(startSize.X.Offset + delta.X, MIN_WIDTH, maxWidth)
            local height = math.clamp(startSize.Y.Offset + delta.Y, MIN_HEIGHT, maxHeight)
            Main.Size = UDim2.fromOffset(width, height)
            Main.Position = UDim2.new(
                resizeOrigin.X.Scale, resizeOrigin.X.Offset + (width - startSize.X.Offset) / 2,
                resizeOrigin.Y.Scale, resizeOrigin.Y.Offset + (height - startSize.Y.Offset) / 2
            )
        end
    end)
    RegisterCleanup(function() resizeConnection:Disconnect() end)

    -- floating round open button (like Mugiwara UI's), shown while the window is hidden
    local OpenButton = New("TextButton", {
        Name = "OpenButton",
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 36, 0.5, 0),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = THEME.Popup,
        BackgroundTransparency = THEME.PopupAlpha,
        Visible = false,
    }, Gui)
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, OpenButton)
    New("UIScale", { Scale = UI_SCALE }, OpenButton)
    Spin(Gradient(Stroke(OpenButton, 0.15, 2), 0, CYCLE), 6)
    Spin(Gradient(Stroke(OpenButton, 0.7, 6), 0, CYCLE), 6)
    local openMark = Label(OpenButton, {
        Text = "V",
        Font = Enum.Font.GothamBlack,
        TextSize = 22,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    })
    Gradient(openMark, 45)

    local opened = true
    local function SetOpen(state)
        if state == opened then return end
        opened = state
        if state then
            Main.Visible = true
            PopScale.Scale = 0.9
            Tween(PopScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Quint)
            Tween(Win, { GroupTransparency = 0 }, 0.3)
            for _, ring in ipairs(glowRings) do Tween(ring.Stroke, { Transparency = ring.Base }, 0.4) end
            Tween(OpenButton, { Size = UDim2.fromOffset(0, 0) }, 0.18)
            task.delay(0.18, function()
                if opened then OpenButton.Visible = false end
            end)
        else
            Tween(PopScale, { Scale = 0.92 }, 0.3, Enum.EasingStyle.Quint)
            Tween(Win, { GroupTransparency = 1 }, 0.24)
            for _, ring in ipairs(glowRings) do Tween(ring.Stroke, { Transparency = 1 }, 0.2) end
            task.delay(0.3, function()
                if not opened then Main.Visible = false end
            end)
            OpenButton.Visible = true
            Tween(OpenButton, { Size = UDim2.fromOffset(52, 52) }, 0.5, Enum.EasingStyle.Back)
        end
    end

    -- the open button can be dragged; a tap (no drag) opens the window again
    local pressed, moved, pressStart, pressPosition = false, false, nil, nil
    OpenButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pressed, moved, pressStart, pressPosition = true, false, input.Position, OpenButton.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    pressed = false
                    if not moved then SetOpen(true) end
                end
            end)
        end
    end)
    local openMoveConnection = UserInputService.InputChanged:Connect(function(input)
        if pressed and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = (input.Position - pressStart) / UI_SCALE
            if delta.Magnitude * UI_SCALE > 6 then moved = true end
            if moved then
                OpenButton.Position = UDim2.new(pressPosition.X.Scale, pressPosition.X.Offset + delta.X, pressPosition.Y.Scale, pressPosition.Y.Offset + delta.Y)
            end
        end
    end)
    RegisterCleanup(function() openMoveConnection:Disconnect() end)

    MinimizeButton.MouseButton1Click:Connect(function() SetOpen(false) end)

    local keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.K then SetOpen(not opened) end
    end)
    RegisterCleanup(function() keyConnection:Disconnect() end)

    -- close asks first: every applied effect is taken off, and the script has to be run again to reopen
    local dialogOpen = false
    local function ConfirmClose()
        if dialogOpen then return end
        dialogOpen = true

        local overlay = New("TextButton", {
            Name = "Dialog",
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 1,
            ZIndex = 50,
        }, Win)
        Tween(overlay, { BackgroundTransparency = 0.42 }, 0.25)

        local card = New("CanvasGroup", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(0, 330, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = THEME.Popup,
            BackgroundTransparency = THEME.PopupAlpha,
            GroupTransparency = 1,
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 51,
        }, overlay)
        Round(card, 14)
        local outline = Stroke(card, 1, 1.4, Color3.new(1, 1, 1))
        Spin(Gradient(outline, 45, CYCLE), 8)
        New("UIPadding", {
            PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18),
            PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
        }, card)
        New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }, card)
        local cardScale = New("UIScale", { Scale = 0.9 }, card)
        Tween(cardScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
        Tween(card, { GroupTransparency = 0 }, 0.25)
        Tween(outline, { Transparency = 0.3 }, 0.25)

        local title = Label(card, {
            Text = "Close Visual Unusual?",
            Font = FONT_TITLE,
            TextSize = 16,
            TextColor3 = Color3.new(1, 1, 1),
            TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            LayoutOrder = 1,
        })
        Gradient(title, 0)
        Label(card, {
            Text = "The interface will be closed and every applied effect will be taken off. Run the script again to reopen it.",
            TextSize = 14,
            TextColor3 = THEME.SubText,
            TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            LayoutOrder = 2,
        })

        local row = New("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 3 }, card)
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
        }, row)

        local function CloseDialog()
            Tween(cardScale, { Scale = 0.93 }, 0.2)
            Tween(card, { GroupTransparency = 1 }, 0.2)
            Tween(outline, { Transparency = 1 }, 0.2)
            Tween(overlay, { BackgroundTransparency = 1 }, 0.2)
            task.delay(0.22, function()
                overlay:Destroy()
                dialogOpen = false
            end)
        end

        local function DialogButton(text, danger, order, callback)
            local button = New("TextButton", {
                Text = text,
                Font = FONT_TITLE,
                TextSize = 13,
                TextColor3 = danger and THEME.OnAccent or THEME.Text,
                AutoButtonColor = false,
                BorderSizePixel = 0,
                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromOffset(0, 36),
                BackgroundColor3 = danger and THEME.Danger or THEME.Card,
                BackgroundTransparency = danger and 0 or 0.84,
                LayoutOrder = order,
            }, row)
            Round(button, 9)
            New("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, button)
            button.MouseButton1Click:Connect(callback)
        end

        DialogButton("Cancel", false, 1, CloseDialog)
        DialogButton("Close", true, 2, function()
            local fns = cleanupFns
            cleanupFns = {}
            for _, fn in ipairs(fns) do pcall(fn) end
        end)
    end
    CloseButton.MouseButton1Click:Connect(ConfirmClose)

    -- open animation: pop in and fade the glow up
    Tween(PopScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Back)
    Tween(Win, { GroupTransparency = 0 }, 0.35)
    for _, ring in ipairs(glowRings) do Tween(ring.Stroke, { Transparency = ring.Base }, 0.45) end
end

-- ==========================================================
-- Unusual grid logic (ported from Games/Evade/VisualUnusualUI.lua, rebuilt on the UI above)
-- One list: picking an effect wears it, picking it again takes it off, and several can be stacked.
-- ==========================================================
local HEADER_ORDER = { "Normal", "Gamepasses", "Halloween", "Winter Holidays", "Summer", "Spring", "Valentines", "Event", "Special" }
local NAMES_SHOWN = 6
local CELL_HEIGHT, TITLE_HEIGHT, GAP = 112, 20, 6

local function BuildGroups(entries)
    local byHeader = {}
    for _, entry in ipairs(entries) do
        byHeader[entry.Header] = byHeader[entry.Header] or {}
        table.insert(byHeader[entry.Header], entry)
    end

    local order, seen = {}, {}
    for _, header in ipairs(HEADER_ORDER) do
        if byHeader[header] then
            table.insert(order, header)
            seen[header] = true
        end
    end
    local rest = {}
    for header in pairs(byHeader) do
        if not seen[header] then table.insert(rest, header) end
    end
    table.sort(rest)
    for _, header in ipairs(rest) do table.insert(order, header) end

    local groups = {}
    for _, header in ipairs(order) do
        table.insert(groups, { Title = header, Entries = byHeader[header] })
    end
    return groups
end

local function BuildUnusualUI()
    if Unusual.Load() == 0 then
        Label(PaneHolder, {
            Text = "No Unusual effects were found in this game. The game may have changed its item folders.",
            TextWrapped = true,
            TextColor3 = THEME.SubText,
            TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(1, 1),
        })
        RemoveAllButton.Frame.Visible = false
        return
    end

    local groups = BuildGroups(Unusual.GetEntries())
    local side = { Group = 1, Query = "", TileList = {}, TileByEntry = {} }
    local statusUntil = 0
    local PaintAll

    local function ShowHint()
        local list = Unusual.GetApplied()
        if #list == 0 then
            StatusLabel.Text = "Pick an effect to wear it. Pick it again to take it off."
        else
            local names = {}
            for index, entry in ipairs(list) do
                if index > NAMES_SHOWN then break end
                table.insert(names, entry.Display)
            end
            local more = #list > NAMES_SHOWN and (" +" .. (#list - NAMES_SHOWN) .. " more") or ""
            StatusLabel.Text = "Applied: " .. #list .. "  ·  " .. table.concat(names, ", ") .. more
        end
        StatusLabel.TextColor3 = THEME.SubText
    end

    local function SetStatus(text, color)
        statusUntil = os.clock() + 3.5
        StatusLabel.Text = text
        StatusLabel.TextColor3 = color or THEME.SubText
        task.delay(3.6, function()
            if os.clock() >= statusUntil then ShowHint() end
        end)
    end

    -- ---------- cells ----------
    local function PaintTile(tile, hovered)
        local on = Unusual.IsApplied(tile.Entry)
        tile.Button.BackgroundTransparency = on and 0.82 or (hovered and 0.9 or 0.95)
        tile.Badge.Visible = on
        tile.Stroke.Color = on and THEME.Accent or THEME.Stroke
        tile.Stroke.Transparency = on and 0.2 or (hovered and 0.7 or THEME.StrokeAlpha)
        tile.Stroke.Thickness = on and 1.5 or 1
    end

    PaintAll = function()
        for _, tile in ipairs(side.TileList) do PaintTile(tile, false) end
        side.CountLabel.Text = "Applied: " .. Unusual.AppliedCount()
        side.CountLabel.TextColor3 = Unusual.AppliedCount() > 0 and THEME.Text or THEME.Muted
        if os.clock() >= statusUntil then ShowHint() end
    end

    local function Toggle(entry)
        if Unusual.IsApplied(entry) then
            Unusual.Remove(entry)
            PaintAll()
        else
            local ok, message = Unusual.Apply(entry)
            PaintAll()
            if not ok then SetStatus(message, THEME.Danger) end
        end
    end

    local function MakeTile(entry)
        local button = New("TextButton", {
            Name = entry.Name,
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.95,
        }, side.Scroll)
        Round(button, 10)
        local stroke = Stroke(button, THEME.StrokeAlpha)

        local thumb = New("Frame", {
            Name = "Thumb",
            Position = UDim2.fromOffset(5, 5),
            Size = UDim2.new(1, -10, 0, CELL_HEIGHT - 10 - TITLE_HEIGHT),
            BackgroundColor3 = THEME.Field,
            BackgroundTransparency = THEME.FieldAlpha,
            ClipsDescendants = true,
            BorderSizePixel = 0,
        }, button)
        Round(thumb, 7)
        if entry.Image then
            New("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.new(1, -8, 1, -8),
                BackgroundTransparency = 1,
                Image = entry.Image,
                ScaleType = Enum.ScaleType.Fit,
            }, thumb)
        else
            Label(thumb, {
                Text = string.upper(string.sub(entry.Display, 1, 1)),
                Font = FONT_TITLE,
                TextSize = 26,
                TextColor3 = THEME.Muted,
                TextXAlignment = Enum.TextXAlignment.Center,
                Size = UDim2.fromScale(1, 1),
            })
        end
        Label(button, {
            Text = entry.Display,
            Font = FONT_LABEL,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.new(0, 6, 0, CELL_HEIGHT - TITLE_HEIGHT - 2),
            Size = UDim2.new(1, -12, 0, TITLE_HEIGHT),
        })

        local badge = New("Frame", {
            Name = "Badge",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -9, 0, 9),
            Size = UDim2.fromOffset(18, 18),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 3,
        }, button)
        Round(badge, 9)
        CheckGlyph(badge, 12, THEME.OnAccent)

        local tile = { Entry = entry, Button = button, Stroke = stroke, Badge = badge }
        button.MouseEnter:Connect(function() PaintTile(tile, true) end)
        button.MouseLeave:Connect(function() PaintTile(tile, false) end)
        button.MouseButton1Click:Connect(function() Toggle(entry) end)
        return tile
    end

    local function Render()
        local query = string.lower(side.Query)
        local list, map = {}, {}
        for _, entry in ipairs(groups[side.Group].Entries) do
            if query == "" or string.find(string.lower(entry.Display), query, 1, true) then
                local tile = side.TileByEntry[entry] or MakeTile(entry)
                tile.Button.LayoutOrder = #list + 1
                table.insert(list, tile)
                map[entry] = tile
            end
        end
        for entry, tile in pairs(side.TileByEntry) do
            if not map[entry] then tile.Button:Destroy() end
        end
        side.TileList, side.TileByEntry = list, map
        PaintAll()
    end

    -- dark inset field (Base.Field in Mugiwara UI)
    local function Field(parent, position, size, class, props)
        local merged = {
            BorderSizePixel = 0,
            BackgroundColor3 = THEME.Field,
            BackgroundTransparency = THEME.FieldAlpha,
            Position = position,
            Size = size,
        }
        for key, value in pairs(props or {}) do merged[key] = value end
        local field = New(class, merged, parent)
        Round(field, 8)
        Stroke(field, 0.9)
        return field
    end

    local frame = New("Frame", {
        Name = "Effects",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = THEME.Card,
        BackgroundTransparency = THEME.CardAlpha,
        BorderSizePixel = 0,
    }, PaneHolder)
    Round(frame, 10)
    Stroke(frame, 0.9)

    local inner = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, frame)
    New("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
    }, inner)

    Label(inner, { Text = "Unusual Effects", Font = FONT_TITLE, TextSize = 15, Size = UDim2.new(0.5, 0, 0, 20) })
    side.CountLabel = Label(inner, {
        Text = "Applied: 0",
        TextSize = 12,
        TextColor3 = THEME.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.fromScale(0.5, 0),
        Size = UDim2.new(0.5, 0, 0, 20),
    })

    -- category dropdown
    local categoryButton = Field(inner, UDim2.fromOffset(0, 26), UDim2.new(1, 0, 0, 32), "TextButton", { Text = "", AutoButtonColor = false })
    local categoryLabel = Label(categoryButton, {
        Text = groups[1].Title,
        Font = FONT_LABEL,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -36, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local chevronHolder = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
    }, categoryButton)
    ChevronGlyph(chevronHolder, 14, THEME.SubText)

    -- search
    local search = Field(inner, UDim2.fromOffset(0, 64), UDim2.new(1, 0, 0, 32), "TextBox", {
        Text = "",
        PlaceholderText = "Search effect...",
        PlaceholderColor3 = THEME.Muted,
        TextColor3 = THEME.Text,
        Font = FONT_BODY,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
    })
    New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, search)

    -- grid, open from the start
    side.Scroll = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 104),
        Size = UDim2.new(1, 0, 1, -104),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Muted,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    }, inner)
    New("UIPadding", {
        PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3),
        PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 6),
    }, side.Scroll)
    New("UIGridLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        CellSize = UDim2.new(1 / 3, -math.ceil(GAP * 2 / 3), 0, CELL_HEIGHT),
        CellPadding = UDim2.fromOffset(GAP, GAP),
    }, side.Scroll)

    -- category drawer: opens under the field and pushes the search box and the grid down
    local DRAWER_Y = 62
    local drawerHeight = math.min(#groups * 36 + 10, 150)
    local drawer = Field(inner, UDim2.fromOffset(0, DRAWER_Y), UDim2.new(1, 0, 0, drawerHeight), "Frame", { ClipsDescendants = true })
    drawer.Visible = false
    local list = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Muted,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    }, drawer)
    New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, list)
    New("UIPadding", {
        PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
        PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 8),
    }, list)

    local rows = {}
    local function PaintRow(index, hovered)
        local row = rows[index]
        local on = index == side.Group
        row.Button.BackgroundTransparency = on and 0.78 or (hovered and 0.92 or 1)
        row.Check.Visible = on
        row.Stroke.Color = on and THEME.Accent or THEME.Stroke
        row.Stroke.Transparency = on and 0.45 or (hovered and 0.78 or THEME.StrokeAlpha)
    end

    local drawerOpen = false
    local function Layout(open)
        drawerOpen = open
        drawer.Visible = open
        Tween(chevronHolder, { Rotation = open and 180 or 0 }, 0.2)
        local searchY = open and (DRAWER_Y + drawerHeight + 6) or 64
        local gridY = searchY + 40
        Tween(search, { Position = UDim2.fromOffset(0, searchY) }, 0.2)
        Tween(side.Scroll, { Position = UDim2.fromOffset(0, gridY), Size = UDim2.new(1, 0, 1, -gridY) }, 0.2)
    end

    for index, group in ipairs(groups) do
        local button = New("TextButton", {
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 1,
            LayoutOrder = index,
            Size = UDim2.new(1, 0, 0, 32),
        }, list)
        Round(button, 8)
        Gradient(button, 0)
        local stroke = Stroke(button, THEME.StrokeAlpha)
        Label(button, {
            Text = group.Title,
            Font = FONT_LABEL,
            Position = UDim2.fromOffset(12, 0),
            Size = UDim2.new(1, -80, 1, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        Label(button, {
            Text = tostring(#group.Entries),
            TextSize = 12,
            TextColor3 = THEME.Muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -34, 0, 0),
            Size = UDim2.new(0, 36, 1, 0),
        })
        local checkSlot = New("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            Visible = false,
        }, button)
        CheckGlyph(checkSlot, 14, THEME.Accent)
        rows[index] = { Button = button, Stroke = stroke, Check = checkSlot }

        button.MouseEnter:Connect(function() PaintRow(index, true) end)
        button.MouseLeave:Connect(function() PaintRow(index, false) end)
        button.MouseButton1Click:Connect(function()
            side.Group = index
            categoryLabel.Text = group.Title
            for rowIndex in ipairs(rows) do PaintRow(rowIndex, false) end
            side.Scroll.CanvasPosition = Vector2.zero
            Layout(false)
            Render()
        end)
    end
    for rowIndex in ipairs(rows) do PaintRow(rowIndex, false) end

    categoryButton.MouseButton1Click:Connect(function() Layout(not drawerOpen) end)

    search:GetPropertyChangedSignal("Text"):Connect(function()
        side.Query = search.Text
        side.Scroll.CanvasPosition = Vector2.zero
        Render()
    end)

    -- the effects are re-applied by the watcher or removed elsewhere: keep the cells in step
    Unusual.OnChange = function() PaintAll() end

    RemoveAllButton.Hit.MouseButton1Click:Connect(function()
        local count = Unusual.Clear()
        PaintAll()
        SetStatus(count > 0 and ("Removed " .. count .. " effect(s).") or "Nothing is applied.", count > 0 and THEME.Success or THEME.SubText)
    end)

    Render()

    -- Every Unusual is copied to memory in the background (once), so applying never waits.
    task.spawn(function()
        local ok, err = pcall(Unusual.CaptureAll)
        if not ok then warn("[Visual Unusual] capture error: " .. tostring(err)) end
    end)
end

BuildUnusualUI()
