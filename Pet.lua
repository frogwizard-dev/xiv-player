local ADDON, ns = ...
local UI = ns.UI
local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local Unit, Secure = FrogLib.Unit, FrogLib.Secure

-- Your pet's frame in the player bar's look (its name over HP and resource gauges, texts under them,
-- a portrait, a hunter's pet's happiness, clicks), and its target's frame, on its own. Each has its
-- own place and scale. Values the game may keep secret go only into the gauges and text templates;
-- a secret range is the game's to turn into an opacity (SetAlphaFromBoolean).

local Pet = {}
ns.Pet = Pet

ns.defaults.pet = {
    enabled = true,
    point = { "BOTTOM", "UIParent", "BOTTOM", -330, 300 },
    scale = 1,
    width = 110, height = 6, spacing = 14, labelSize = 10, numberSize = 15,
    showName = true, nameText = "name", nameSize = 12,
    showPortrait = false, portraitSize = 34,
    showHealth = true, showPower = true,
    -- Text under each gauge: left (after its HP / MP label), centre and right. Words: value, max,
    -- percent (percent.1), name.
    health = { left = "value", center = "", right = "percent" },
    power = { left = "value", center = "", right = "" },
    smooth = true,    -- gauges ease to new values (off: they jump)
    happiness = { shown = true, size = 18, x = 0, y = 0 }, -- a hunter's pet's mood, past the gauges
    noPet = "hide",   -- "hide", or "empty": the frame stays, empty
    dead = "dim",     -- "dim", "hide" or "show"
    deadAlpha = 0.35,
    range = true,     -- dim while out of range
    rangeAlpha = 0.5,
    clicks = true,    -- left-click to target your pet, right-click for its menu
    hideBlizzard = false, -- Blizzard's pet frame
    target = {
        enabled = false,
        point = { "BOTTOM", "UIParent", "BOTTOM", -330, 360 },
        scale = 1,
        width = 90, height = 4, spacing = 10, labelSize = 9, numberSize = 12,
        nameText = "name", nameSize = 11,
        showHealth = true, showPower = true,
        healthText = "percent", powerText = "",
    },
}

local SAMPLE = { name = "Wolf", value = 820, max = 1000, percent = 82 }
local SAMPLE_TARGET = { name = "Kobold Miner", value = 300, max = 500, percent = 60 }
local WORDS = { "name" }
local POLL = 0.05

local function Settings() return ns.db.pet end

------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------

local function Text(parent, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetShadowOffset(1, -1)
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

-- A gauge block (the player bar's), with a centre and a right-hand text under the gauge too.
local function Block(parent, label)
    local block = ns.Block(parent, label)
    block.center = Text(parent, "CENTER")
    block.right = Text(parent, "RIGHT")
    return block
end

local function Frame(name, save)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    FrogLib.Mover.Make(frame, { save = save, tint = 6 })
    frame.name = Text(frame)
    return frame
end

function Pet:Init()
    local frame = Frame("XIVPlayerPetFrame", function(point) Settings().point = point end)
    self.frame = frame
    frame.health = Block(frame, "HP")
    frame.power = Block(frame, "MP")
    frame.portrait = frame:CreateTexture(nil, "ARTWORK")
    local mask = frame:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(frame.portrait)
    frame.portrait:AddMaskTexture(mask)
    frame.happiness = frame:CreateTexture(nil, "OVERLAY")

    local target = Frame("XIVPlayerPetTargetFrame", function(point) Settings().target.point = point end)
    self.target = target
    target.health = Block(target, "HP")
    target.power = Block(target, "MP")

    local events = CreateFrame("Frame")
    -- (PORTRAITS_UPDATED: a portrait painted during a loading screen gets no picture till this.) Unit events only for
    -- the pet and you, not every unit in a raid.
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PET_UI_UPDATE", "PLAYER_REGEN_ENABLED", "PORTRAITS_UPDATED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    for _, event in ipairs({ "UNIT_PET", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_HAPPINESS",
        "UNIT_NAME_UPDATE", "UNIT_DISPLAYPOWER" }) do
        pcall(events.RegisterUnitEvent, events, event, "pet", "player")
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then
            if self.clicksPending then self:SetupClicks() end
            return
        end
        if unit and unit ~= "pet" and unit ~= "player" and event ~= "PLAYER_ENTERING_WORLD" then return end
        self:Update(true)
    end)
    -- Health and power, the target's too, read often: the pet's target sends no events of its own.
    local since = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < POLL then return end
        since = 0
        self:Update(false)
    end)
    -- The frame hides with no pet; this keeps the target's frame (and the sample) going then.
    target:SetScript("OnUpdate", function(_, elapsed)
        if frame:IsShown() then return end
        since = since + elapsed
        if since < POLL then return end
        since = 0
        self:Update(false)
    end)
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

local function SizeText(block, db, sizes)
    local size = math.max(sizes.labelSize + 1, math.floor(sizes.numberSize * 0.7))
    for _, text in ipairs({ block.center, block.right }) do ns.Media:SetFont(text, db.font, size, db.outline) end
    block.center:ClearAllPoints()
    block.center:SetPoint("BOTTOM", block.number, "BOTTOM", 0, 0)
    block.center:SetPoint("LEFT", block.gauge.bar, "LEFT")
    block.center:SetPoint("RIGHT", block.gauge.bar, "RIGHT")
    block.right:ClearAllPoints()
    block.right:SetPoint("BOTTOMRIGHT", block.gauge.bar, "BOTTOMRIGHT", -2, 0)
    block.right:SetPoint("TOP", block.number, "TOP")
    block.right:SetPoint("BOTTOM", block.number, "BOTTOM")
end

-- Lays out a frame's portrait (pet only), name, and the gauges that are shown, side by side.
local function Lay(frame, db, sizes, showHealth, showPower, portrait)
    local x = 0
    if portrait then
        local size = sizes.portraitSize
        frame.portrait:SetSize(size, size)
        frame.portrait:ClearAllPoints()
        frame.portrait:SetPoint("LEFT", frame, "LEFT", 0, 0)
        x = size + 6
    end
    ns.Media:SetFont(frame.name, db.font, sizes.nameSize, db.outline)
    local top = sizes.nameSize + 4
    frame.name:ClearAllPoints()
    frame.name:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 2, 0)
    local first = true
    local width = x
    for _, key in ipairs({ "health", "power" }) do
        local block = frame[key]
        local shown = (key == "health" and showHealth) or (key == "power" and showPower)
        ns.ShowBlock(block, shown)
        block.center:SetShown(shown)
        block.right:SetShown(shown)
        if shown then
            ns.StyleBlock(block, db, sizes)
            SizeText(block, db, sizes)
            block.gauge.bar:ClearAllPoints()
            local gap = first and 0 or sizes.spacing
            block.gauge.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", width + gap, -top)
            width = width + gap + sizes.width
            first = false
        end
    end
    frame.name:SetWidth(math.max(40, width - x))
    local height = top + sizes.height + sizes.numberSize + 8
    if portrait then height = math.max(height, sizes.portraitSize) end
    frame:SetSize(math.max(width, 40), height)
    return width
end

function Pet:Apply()
    if not self.frame then return end
    local db, settings = ns.db, Settings()
    local frame, target = self.frame, self.target
    for _, each in ipairs({ frame, target }) do
        local own = each == frame and settings or settings.target
        each:SetScale(own.scale)
        each:ClearAllPoints()
        each:SetPoint(own.point[1], UIParent, own.point[3], own.point[4], own.point[5])
        each:EnableMouse(not db.locked)
        each.unlockTint:SetShown(not db.locked)
    end
    local width = Lay(frame, db, settings, settings.showHealth, settings.showPower, settings.showPortrait)
    frame.portrait:SetShown(settings.showPortrait)
    frame.name:SetShown(settings.showName)
    local happiness = settings.happiness
    frame.happiness:SetSize(happiness.size, happiness.size)
    frame.happiness:ClearAllPoints()
    frame.happiness:SetPoint("LEFT", frame, "TOPLEFT", width + 6 + happiness.x,
        -(settings.nameSize + 4) - settings.height / 2 + happiness.y)
    Lay(target, db, settings.target, settings.target.showHealth, settings.target.showPower, false)
    -- Blizzard's pet frame, gone or back (the player frame's hiding leaves it be).
    FrogLib.Hider.Set(ADDON, "PetFrame", settings.enabled and settings.hideBlizzard or false)
    self:SetupClicks()
    self:Update(true)
end

-- Clicks: a secure button over the frame (FrogLib.Secure's), placed the frame's way rather than
-- anchored to it, and shown by the game only while you have a pet (a unit watch).
function Pet:SetupClicks()
    if InCombatLockdown() then
        self.clicksPending = true
        return
    end
    self.clicksPending = nil
    local settings, frame = Settings(), self.frame
    if not self.click then
        self.click = Secure.UnitButton("XIVPlayerPetClick", "pet")
    end
    local button = self.click
    local point = settings.point
    button:SetScale(settings.scale)
    button:ClearAllPoints()
    button:SetPoint(point[1], UIParent, point[3], point[4], point[5])
    button:SetSize(frame:GetSize())
    Secure.Watch(button, settings.enabled and settings.clicks and ns.db.locked)
end

------------------------------------------------------------------------------
-- Updating
------------------------------------------------------------------------------

local function Paint(block, value, max, percent, name, texts, instant)
    block.gauge:SetValues(value, max, instant)
    local values = { value = value, max = max, percent = percent, name = name }
    UI.SetTemplateText(block.number, texts.left, values, WORDS)
    UI.SetTemplateText(block.center, texts.center, values, WORDS)
    UI.SetTemplateText(block.right, texts.right, values, WORDS)
end

-- One frame from a unit (or a sample while unlocked). shown: nameText, and the health and power
-- texts ({ left, center, right } each).
local function Fill(frame, unit, sample, shown, instant)
    local db = ns.db
    local name = sample and sample.name or Unit.Name(unit)
    UI.SetTemplateText(frame.name, shown.nameText, { name = name }, WORDS)
    frame.name:SetTextColor(1, 1, 1)
    -- HP
    local healthColor = db.healthColor
    ns.Tint(frame.health, healthColor.r, healthColor.g, healthColor.b)
    local health, healthMax, healthPercent
    if sample then
        health, healthMax, healthPercent = sample.value, sample.max, sample.percent
    else
        health, healthMax, healthPercent = UnitHealth(unit), UnitHealthMax(unit), Unit.HealthPercent(unit)
    end
    Paint(frame.health, health, healthMax, healthPercent, name, shown.healthTexts, instant)
    -- The resource: whatever the unit has, in its colour and FFXIV letters.
    local powerType, token = 0, "MANA"
    if not sample then
        powerType, token = UnitPowerType(unit)
        powerType, token = Safe(powerType) or 0, Safe(token) or "MANA"
    end
    local info = ns.POWER[token]
    frame.power.label:SetText(info and info[1] or (token and token:sub(1, 2)) or "PW")
    ns.Tint(frame.power, ns.PowerColor(token, db))
    local power, powerMax, powerPercent
    if sample then
        power, powerMax, powerPercent = 60, 100, 60
    else
        power, powerMax, powerPercent = UnitPower(unit, powerType), UnitPowerMax(unit, powerType),
            Unit.PowerPercent(unit, powerType)
    end
    Paint(frame.power, power, powerMax, powerPercent, name, shown.powerTexts, instant)
end

function Pet:Update(full)
    local frame, target = self.frame, self.target
    if not frame then return end
    local db, settings = ns.db, Settings()
    local instant = full or not settings.smooth
    local unlocked = not db.locked

    -- The pet's frame.
    local has = UnitExists("pet")
    local show = settings.enabled and (has or unlocked or settings.noPet == "empty")
    local dead = has and Safe(UnitIsDeadOrGhost("pet"))
    if dead and settings.dead == "hide" and not unlocked then show = false end
    frame:SetShown(show and true or false)
    if show then
        local sample = (not has) and unlocked and SAMPLE or nil
        if has or sample then
            Fill(frame, "pet", sample, { nameText = settings.nameText, healthTexts = settings.health,
                powerTexts = settings.power }, instant)
        else
            -- An empty frame: the gauges at nothing, no text.
            for _, key in ipairs({ "health", "power" }) do
                local block = frame[key]
                block.gauge:SetValues(0, 1, true)
                block.number:SetText("")
                block.center:SetText("")
                block.right:SetText("")
            end
            frame.name:SetText("")
        end
        if full and has and settings.showPortrait then SetPortraitTexture(frame.portrait, "pet") end
        if full and not has then frame.portrait:SetTexture(nil) end
        -- Happiness: a hunter's pet's face, or a sample while unlocked.
        local mood = has and Unit.PetHappiness() or (unlocked and 3) or nil
        local atlas = mood and Unit.HAPPINESS_ATLAS[mood]
        if atlas and settings.happiness.shown then
            frame.happiness:SetAtlas(atlas)
            frame.happiness:Show()
        else
            frame.happiness:Hide()
        end
        -- Dead: dimmed; out of range: dimmed (the game works the opacity out when range is secret).
        if dead and settings.dead == "dim" then
            frame:SetAlpha(settings.deadAlpha)
        elseif has and settings.range and UnitInRange then
            local inRange, checked = UnitInRange("pet")
            if issecret(inRange) and frame.SetAlphaFromBoolean then
                frame:SetAlphaFromBoolean(inRange, 1, settings.rangeAlpha)
            elseif not issecret(inRange) and checked and not inRange then
                frame:SetAlpha(settings.rangeAlpha)
            else
                frame:SetAlpha(1)
            end
        else
            frame:SetAlpha(1)
        end
    end

    -- The pet's target.
    local targetSettings = settings.target
    local hasTarget = has and UnitExists("pettarget")
    local showTarget = settings.enabled and targetSettings.enabled and (hasTarget or unlocked)
    target:SetShown(showTarget and true or false)
    if showTarget then
        Fill(target, "pettarget", (not hasTarget) and SAMPLE_TARGET or nil,
            { nameText = targetSettings.nameText,
                healthTexts = { left = targetSettings.healthText, center = "", right = "" },
                powerTexts = { left = targetSettings.powerText, center = "", right = "" } }, instant)
        -- Its name in the colour of how it feels about you.
        if hasTarget then
            local r, g, b = FrogLib.Color.Unit("pettarget", { hostile = { r = 0.95, g = 0.4, b = 0.35 },
                neutral = { r = 0.95, g = 0.85, b = 0.4 }, friendly = { r = 0.5, g = 0.9, b = 0.5 },
                class = true, fallback = { r = 1, g = 1, b = 1 } })
            if r then target.name:SetTextColor(r, g, b) end
        end
    end
end

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

local NO_PET = UI.Options("hide", "Hide the frame", "empty", "Keep an empty frame")
local DEAD = UI.Options("dim", "Dim it", "hide", "Hide it", "show", "Leave it as it is")

local function TextRow(page, place, label, texts)
    place(UI.Label(page, label), 20)
    place(UI.TextBox(page, "Left", texts, "left"), 26)
    place(UI.TextBox(page, "Centre", texts, "center"), 26)
    place(UI.TextBox(page, "Right", texts, "right"), 28)
end

-- A second column, 385 to the right.
local function RightColumn()
    local place = UI.Placer()
    return function(widget, height, dx) place(widget, height, 385 + (dx or 0)) end
end

function Pet.BuildPage(page)
    local settings = Settings()
    local place = UI.Placer()
    local right = RightColumn()
    place(UI.Checkbox(page, "A frame for my pet", settings, "enabled"), 26)
    place(UI.Checkbox(page, "Hide Blizzard's pet frame", settings, "hideBlizzard"), 26)
    place(UI.Checkbox(page, "Click to target my pet, right-click for its menu", settings, "clicks"), 30)
    place(UI.Stepper(page, "Scale", 0.5, 2, 0.05, settings, "scale", "%.2f"), 26)
    place(UI.Stepper(page, "Gauge width", 40, 300, 5, settings, "width"), 26)
    place(UI.Stepper(page, "Gauge height", 2, 16, 1, settings, "height"), 26)
    place(UI.Stepper(page, "Gap between gauges", 0, 80, 2, settings, "spacing"), 26)
    place(UI.Stepper(page, "Number size", 8, 32, 1, settings, "numberSize"), 26)
    place(UI.Stepper(page, "Name size", 8, 24, 1, settings, "nameSize"), 30)
    place(UI.Checkbox(page, "Name", settings, "showName"), 24)
    place(UI.Checkbox(page, "Portrait", settings, "showPortrait"), 24)
    place(UI.Checkbox(page, "HP gauge", settings, "showHealth"), 24)
    place(UI.Checkbox(page, "Resource gauge (mana, focus, energy)", settings, "showPower"), 24)
    place(UI.Checkbox(page, "Gauges ease to new values (off: they jump)", settings, "smooth"), 30)
    place(UI.Dropdown(page, "With no pet", NO_PET, settings, "noPet"), 30)
    place(UI.Dropdown(page, "Pet dead", DEAD, settings, "dead"), 30)
    place(UI.Stepper(page, "Dead opacity", 0, 1, 0.05, settings, "deadAlpha", "%.2f"), 26, 20)
    place(UI.Checkbox(page, "Dim while out of range", settings, "range"), 26)
    place(UI.Stepper(page, "Out of range opacity", 0, 1, 0.05, settings, "rangeAlpha", "%.2f"), 30, 20)

    TextRow(page, right, "HP text (under the gauge)", settings.health)
    TextRow(page, right, "Resource text", settings.power)
    right(UI.TextBox(page, "Name text", settings, "nameText"), 34)
    local happiness = settings.happiness
    right(UI.Checkbox(page, "A hunter's pet's happiness", happiness, "shown"), 26)
    right(UI.Stepper(page, "Size", 8, 48, 1, happiness, "size"), 26, 20)
    right(UI.Stepper(page, "Left / right", -100, 100, 1, happiness, "x"), 26, 20)
    right(UI.Stepper(page, "Up / down", -100, 100, 1, happiness, "y"), 34, 20)
    right(UI.Help(page, "Words: |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r (|cffffd100percent.1|r), "
        .. "|cffffd100name|r. Empty hides a text. Unlock (Layout tab) to drag the frame; a sample shows with no pet. "
        .. "Style, texture and font are the player bar's.", 300), 70)
end

function Pet.BuildTargetPage(page)
    local target = Settings().target
    local place = UI.Placer()
    place(UI.Checkbox(page, "A frame for my pet's target", target, "enabled"), 30)
    place(UI.Stepper(page, "Scale", 0.5, 2, 0.05, target, "scale", "%.2f"), 26)
    place(UI.Stepper(page, "Gauge width", 40, 300, 5, target, "width"), 26)
    place(UI.Stepper(page, "Gauge height", 2, 16, 1, target, "height"), 26)
    place(UI.Stepper(page, "Gap between gauges", 0, 80, 2, target, "spacing"), 26)
    place(UI.Stepper(page, "Number size", 8, 32, 1, target, "numberSize"), 26)
    place(UI.Stepper(page, "Name size", 8, 24, 1, target, "nameSize"), 30)
    place(UI.Checkbox(page, "HP gauge", target, "showHealth"), 24)
    place(UI.Checkbox(page, "Resource gauge", target, "showPower"), 30)
    place(UI.TextBox(page, "Name text", target, "nameText"), 28)
    place(UI.TextBox(page, "HP text", target, "healthText"), 28)
    place(UI.TextBox(page, "Resource text", target, "powerText"), 30)
    place(UI.Help(page, "Shown while your pet has a target (a sample while unlocked). Its name is coloured by how the "
        .. "target feels about you. Unlock on the Layout tab to drag it on its own.", 400), 40)
end
