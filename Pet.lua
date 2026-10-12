local ADDON, ns = ...
local UI = ns.UI
local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local Unit, Secure = FrogLib.Unit, FrogLib.Secure

------------------------------------------------------------------------------
-- Your pet's frame, in the player bar's FFXIV look (the same gauges, style, texture and font):
--   the pet's name over an HP gauge and a resource gauge (mana, focus, energy: whatever the pet
--   has), each with the small label and big number under it, plus text in the middle and at the
--   right end; an optional round portrait; a hunter's pet's happiness; clicks to target it and
--   open its menu.
-- And its target's frame, on its own (turned on or off by itself): the name, its HP and its
-- resource, the same way.
-- Each has its own place (drag it while unlocked) and scale. Visibility: with no pet, hidden
-- (or an empty frame); dead, dimmed or hidden; out of range, dimmed. Values the game may keep
-- secret only go into the gauges and text templates; range, when secret, is the game's to
-- turn into an opacity (SetAlphaFromBoolean).
------------------------------------------------------------------------------

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

local function Cfg() return ns.db.pet end

------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------

local function Text(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A gauge block (the player bar's), with a centre and a right-hand text under the gauge too.
local function Block(parent, label)
    local b = ns.Block(parent, label)
    b.center = Text(parent, "CENTER")
    b.right = Text(parent, "RIGHT")
    return b
end

local function Frame(name, save)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    FrogLib.Mover.Make(f, { save = save, tint = 6 })
    f.name = Text(f)
    return f
end

function Pet:Init()
    local f = Frame("XIVPlayerPetFrame", function(point) Cfg().point = point end)
    self.frame = f
    f.health = Block(f, "HP")
    f.power = Block(f, "MP")
    f.portrait = f:CreateTexture(nil, "ARTWORK")
    local mask = f:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(f.portrait)
    f.portrait:AddMaskTexture(mask)
    f.happiness = f:CreateTexture(nil, "OVERLAY")

    local t = Frame("XIVPlayerPetTargetFrame", function(point) Cfg().target.point = point end)
    self.target = t
    t.health = Block(t, "HP")
    t.power = Block(t, "MP")

    local ev = CreateFrame("Frame")
    for _, event in ipairs({ "UNIT_PET", "PLAYER_ENTERING_WORLD", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED",
        "UNIT_HAPPINESS", "PET_UI_UPDATE", "UNIT_NAME_UPDATE", "UNIT_DISPLAYPOWER", "PLAYER_REGEN_ENABLED" }) do
        pcall(ev.RegisterEvent, ev, event)
    end
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then
            if self.clicksPending then self:SetupClicks() end
            return
        end
        if unit and unit ~= "pet" and unit ~= "player" and event ~= "PLAYER_ENTERING_WORLD" then return end
        self:Update(true)
    end)
    -- Health and power, the target's too, read often: the pet's target sends no events of its own.
    local since = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < POLL then return end
        since = 0
        self:Update(false)
    end)
    -- The frame hides with no pet; this keeps the target's frame (and the sample) going then.
    t:SetScript("OnUpdate", function(_, elapsed)
        if f:IsShown() then return end
        since = since + elapsed
        if since < POLL then return end
        since = 0
        self:Update(false)
    end)
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

local function SizeText(b, db, sizes)
    local size = math.max(sizes.labelSize + 1, math.floor(sizes.numberSize * 0.7))
    for _, fs in ipairs({ b.center, b.right }) do ns.Media:SetFont(fs, db.font, size, db.outline) end
    b.center:ClearAllPoints()
    b.center:SetPoint("BOTTOM", b.number, "BOTTOM", 0, 0)
    b.center:SetPoint("LEFT", b.gauge.bar, "LEFT")
    b.center:SetPoint("RIGHT", b.gauge.bar, "RIGHT")
    b.right:ClearAllPoints()
    b.right:SetPoint("BOTTOMRIGHT", b.gauge.bar, "BOTTOMRIGHT", -2, 0)
    b.right:SetPoint("TOP", b.number, "TOP")
    b.right:SetPoint("BOTTOM", b.number, "BOTTOM")
end

-- Lays out a frame's portrait (pet only), name, and the gauges that are shown, side by side.
local function Lay(f, db, sizes, showHealth, showPower, portrait)
    local x = 0
    if portrait then
        local p = sizes.portraitSize
        f.portrait:SetSize(p, p)
        f.portrait:ClearAllPoints()
        f.portrait:SetPoint("LEFT", f, "LEFT", 0, 0)
        x = p + 6
    end
    ns.Media:SetFont(f.name, db.font, sizes.nameSize, db.outline)
    local top = sizes.nameSize + 4
    f.name:ClearAllPoints()
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", x + 2, 0)
    local first = true
    local width = x
    for _, key in ipairs({ "health", "power" }) do
        local b = f[key]
        local shown = (key == "health" and showHealth) or (key == "power" and showPower)
        ns.ShowBlock(b, shown)
        b.center:SetShown(shown)
        b.right:SetShown(shown)
        if shown then
            ns.StyleBlock(b, db, sizes)
            SizeText(b, db, sizes)
            b.gauge.bar:ClearAllPoints()
            local gap = first and 0 or sizes.spacing
            b.gauge.bar:SetPoint("TOPLEFT", f, "TOPLEFT", width + gap, -top)
            width = width + gap + sizes.width
            first = false
        end
    end
    f.name:SetWidth(math.max(40, width - x))
    local h = top + sizes.height + sizes.numberSize + 8
    if portrait then h = math.max(h, sizes.portraitSize) end
    f:SetSize(math.max(width, 40), h)
    return width
end

function Pet:Apply()
    if not self.frame then return end
    local db, cfg = ns.db, Cfg()
    local f, t = self.frame, self.target
    for _, frame in ipairs({ f, t }) do
        local c = frame == f and cfg or cfg.target
        frame:SetScale(c.scale)
        frame:ClearAllPoints()
        frame:SetPoint(c.point[1], UIParent, c.point[3], c.point[4], c.point[5])
        frame:EnableMouse(not db.locked)
        frame.unlockTint:SetShown(not db.locked)
    end
    local width = Lay(f, db, cfg, cfg.showHealth, cfg.showPower, cfg.showPortrait)
    f.portrait:SetShown(cfg.showPortrait)
    f.name:SetShown(cfg.showName)
    local h = cfg.happiness
    f.happiness:SetSize(h.size, h.size)
    f.happiness:ClearAllPoints()
    f.happiness:SetPoint("LEFT", f, "TOPLEFT", width + 6 + h.x, -(cfg.nameSize + 4) - cfg.height / 2 + h.y)
    Lay(t, db, cfg.target, cfg.target.showHealth, cfg.target.showPower, false)
    -- Blizzard's pet frame, gone or back (the player frame's hiding leaves it be).
    FrogLib.Hider.Set(ADDON, "PetFrame", cfg.enabled and cfg.hideBlizzard or false)
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
    local cfg, f = Cfg(), self.frame
    if not self.click then
        self.click = Secure.UnitButton("XIVPlayerPetClick", "pet")
        RegisterUnitWatch(self.click)
    end
    local b = self.click
    local p = cfg.point
    b:SetScale(cfg.scale)
    b:ClearAllPoints()
    b:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    b:SetSize(f:GetSize())
    local on = cfg.enabled and cfg.clicks and ns.db.locked
    if on then RegisterUnitWatch(self.click) else UnregisterUnitWatch(self.click); b:Hide() end
end

------------------------------------------------------------------------------
-- Updating
------------------------------------------------------------------------------

local function Paint(b, value, max, percent, name, texts, instant)
    b.gauge:SetValues(value, max, instant)
    local vals = { value = value, max = max, percent = percent, name = name }
    UI.SetTemplateText(b.number, texts.left, vals, WORDS)
    UI.SetTemplateText(b.center, texts.center, vals, WORDS)
    UI.SetTemplateText(b.right, texts.right, vals, WORDS)
end

-- One frame from a unit (or a sample while unlocked). texts: { health = {left, center, right},
-- power = {...} } and nameText.
local function Fill(f, unit, sample, c, instant)
    local db = ns.db
    local name = sample and sample.name or Unit.Name(unit)
    UI.SetTemplateText(f.name, c.nameText, { name = name }, WORDS)
    f.name:SetTextColor(1, 1, 1)
    -- HP
    local hc = db.healthColor
    ns.Tint(f.health, hc.r, hc.g, hc.b)
    local hv, hm, hp
    if sample then hv, hm, hp = sample.value, sample.max, sample.percent
    else hv, hm, hp = UnitHealth(unit), UnitHealthMax(unit), Unit.HealthPercent(unit) end
    Paint(f.health, hv, hm, hp, name, c.htexts, instant)
    -- The resource: whatever the unit has, in its colour and FFXIV letters.
    local pType, token = 0, "MANA"
    if not sample then
        pType, token = UnitPowerType(unit)
        pType, token = Safe(pType) or 0, Safe(token) or "MANA"
    end
    local info = ns.POWER[token]
    f.power.label:SetText(info and info[1] or (token and token:sub(1, 2)) or "PW")
    ns.Tint(f.power, ns.PowerColor(token, db))
    local pv, pm, pp
    if sample then pv, pm, pp = 60, 100, 60
    else pv, pm, pp = UnitPower(unit, pType), UnitPowerMax(unit, pType), Unit.PowerPercent(unit, pType) end
    Paint(f.power, pv, pm, pp, name, c.ptexts, instant)
end

function Pet:Update(full)
    local f, t = self.frame, self.target
    if not f then return end
    local db, cfg = ns.db, Cfg()
    local instant = full or not cfg.smooth
    local unlocked = not db.locked

    -- The pet's frame.
    local has = UnitExists("pet")
    local show = cfg.enabled and (has or unlocked or cfg.noPet == "empty")
    local dead = has and Safe(UnitIsDeadOrGhost("pet"))
    if dead and cfg.dead == "hide" and not unlocked then show = false end
    f:SetShown(show and true or false)
    if show then
        local sample = (not has) and unlocked and SAMPLE or nil
        if has or sample then
            Fill(f, "pet", sample, { nameText = cfg.nameText, htexts = cfg.health, ptexts = cfg.power }, instant)
        else
            -- An empty frame: the gauges at nothing, no text.
            for _, key in ipairs({ "health", "power" }) do
                local b = f[key]
                b.gauge:SetValues(0, 1, true)
                b.number:SetText("")
                b.center:SetText("")
                b.right:SetText("")
            end
            f.name:SetText("")
        end
        if full and has and cfg.showPortrait then SetPortraitTexture(f.portrait, "pet") end
        if full and not has then f.portrait:SetTexture(nil) end
        -- Happiness: a hunter's pet's face, or a sample while unlocked.
        local mood = has and Unit.PetHappiness() or (unlocked and 3) or nil
        local atlas = mood and Unit.HAPPINESS_ATLAS[mood]
        if atlas and cfg.happiness.shown then
            f.happiness:SetAtlas(atlas)
            f.happiness:Show()
        else
            f.happiness:Hide()
        end
        -- Dead: dimmed; out of range: dimmed (the game works the opacity out when range is secret).
        if dead and cfg.dead == "dim" then
            f:SetAlpha(cfg.deadAlpha)
        elseif has and cfg.range and UnitInRange then
            local inRange, checked = UnitInRange("pet")
            if issecret(inRange) and f.SetAlphaFromBoolean then
                f:SetAlphaFromBoolean(inRange, 1, cfg.rangeAlpha)
            elseif not issecret(inRange) and checked and not inRange then
                f:SetAlpha(cfg.rangeAlpha)
            else
                f:SetAlpha(1)
            end
        else
            f:SetAlpha(1)
        end
    end

    -- The pet's target.
    local tc = cfg.target
    local hasTarget = has and UnitExists("pettarget")
    local showT = cfg.enabled and tc.enabled and (hasTarget or unlocked)
    t:SetShown(showT and true or false)
    if showT then
        Fill(t, "pettarget", (not hasTarget) and SAMPLE_TARGET or nil,
            { nameText = tc.nameText, htexts = { left = tc.healthText, center = "", right = "" },
                ptexts = { left = tc.powerText, center = "", right = "" } }, instant)
        -- Its name in the colour of how it feels about you.
        if hasTarget then
            local r, g, b = FrogLib.Color.Unit("pettarget", { hostile = { r = 0.95, g = 0.4, b = 0.35 },
                neutral = { r = 0.95, g = 0.85, b = 0.4 }, friendly = { r = 0.5, g = 0.9, b = 0.5 },
                class = true, fallback = { r = 1, g = 1, b = 1 } })
            if r then t.name:SetTextColor(r, g, b) end
        end
    end
end

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

local NO_PET = UI.Options("hide", "Hide the frame", "empty", "Keep an empty frame")
local DEAD = UI.Options("dim", "Dim it", "hide", "Hide it", "show", "Leave it as it is")

local function TextRow(p, place, label, t)
    place(UI.Label(p, label), 20)
    place(UI.TextBox(p, "Left", function() return t.left end, function(v) t.left = v end), 26)
    place(UI.TextBox(p, "Centre", function() return t.center end, function(v) t.center = v end), 26)
    place(UI.TextBox(p, "Right", function() return t.right end, function(v) t.right = v end), 28)
end

-- A second column, 385 to the right.
local function RightColumn()
    local place = UI.Placer()
    return function(w, h, dx) place(w, h, 385 + (dx or 0)) end
end

function Pet.BuildPage(p)
    local cfg = Cfg()
    local place = UI.Placer()
    local right = RightColumn()
    place(UI.Checkbox(p, "A frame for my pet", function() return cfg.enabled end,
        function(v) cfg.enabled = v end), 26)
    place(UI.Checkbox(p, "Hide Blizzard's pet frame", function() return cfg.hideBlizzard end,
        function(v) cfg.hideBlizzard = v end), 26)
    place(UI.Checkbox(p, "Click to target my pet, right-click for its menu", function() return cfg.clicks end,
        function(v) cfg.clicks = v end), 30)
    place(UI.Stepper(p, "Scale", 0.5, 2, 0.05, function() return cfg.scale end, function(v) cfg.scale = v end, "%.2f"), 26)
    place(UI.Stepper(p, "Gauge width", 40, 300, 5, function() return cfg.width end, function(v) cfg.width = v end), 26)
    place(UI.Stepper(p, "Gauge height", 2, 16, 1, function() return cfg.height end, function(v) cfg.height = v end), 26)
    place(UI.Stepper(p, "Gap between gauges", 0, 80, 2, function() return cfg.spacing end,
        function(v) cfg.spacing = v end), 26)
    place(UI.Stepper(p, "Number size", 8, 32, 1, function() return cfg.numberSize end,
        function(v) cfg.numberSize = v end), 26)
    place(UI.Stepper(p, "Name size", 8, 24, 1, function() return cfg.nameSize end,
        function(v) cfg.nameSize = v end), 30)
    place(UI.Checkbox(p, "Name", function() return cfg.showName end, function(v) cfg.showName = v end), 24)
    place(UI.Checkbox(p, "Portrait", function() return cfg.showPortrait end, function(v) cfg.showPortrait = v end), 24)
    place(UI.Checkbox(p, "HP gauge", function() return cfg.showHealth end, function(v) cfg.showHealth = v end), 24)
    place(UI.Checkbox(p, "Resource gauge (mana, focus, energy)", function() return cfg.showPower end,
        function(v) cfg.showPower = v end), 24)
    place(UI.Checkbox(p, "Gauges ease to new values (off: they jump)", function() return cfg.smooth end,
        function(v) cfg.smooth = v end), 30)
    place(UI.Dropdown(p, "With no pet", NO_PET, function() return cfg.noPet end, function(v) cfg.noPet = v end), 30)
    place(UI.Dropdown(p, "Pet dead", DEAD, function() return cfg.dead end, function(v) cfg.dead = v end), 30)
    place(UI.Stepper(p, "Dead opacity", 0, 1, 0.05, function() return cfg.deadAlpha end,
        function(v) cfg.deadAlpha = v end, "%.2f"), 26, 20)
    place(UI.Checkbox(p, "Dim while out of range", function() return cfg.range end, function(v) cfg.range = v end), 26)
    place(UI.Stepper(p, "Out of range opacity", 0, 1, 0.05, function() return cfg.rangeAlpha end,
        function(v) cfg.rangeAlpha = v end, "%.2f"), 30, 20)

    TextRow(p, right, "HP text (under the gauge)", cfg.health)
    TextRow(p, right, "Resource text", cfg.power)
    right(UI.TextBox(p, "Name text", function() return cfg.nameText end, function(v) cfg.nameText = v end), 34)
    local h = cfg.happiness
    right(UI.Checkbox(p, "A hunter's pet's happiness", function() return h.shown end, function(v) h.shown = v end), 26)
    right(UI.Stepper(p, "Size", 8, 48, 1, function() return h.size end, function(v) h.size = v end), 26, 20)
    right(UI.Stepper(p, "Left / right", -100, 100, 1, function() return h.x end, function(v) h.x = v end), 26, 20)
    right(UI.Stepper(p, "Up / down", -100, 100, 1, function() return h.y end, function(v) h.y = v end), 34, 20)
    right(UI.Help(p, "Words: |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r (|cffffd100percent.1|r), "
        .. "|cffffd100name|r. Empty hides a text. Unlock (Layout tab) to drag the frame; a sample shows with no pet. "
        .. "Style, texture and font are the player bar's.", 300), 70)
end

function Pet.BuildTargetPage(p)
    local c = Cfg().target
    local place = UI.Placer()
    place(UI.Checkbox(p, "A frame for my pet's target", function() return c.enabled end,
        function(v) c.enabled = v end), 30)
    place(UI.Stepper(p, "Scale", 0.5, 2, 0.05, function() return c.scale end, function(v) c.scale = v end, "%.2f"), 26)
    place(UI.Stepper(p, "Gauge width", 40, 300, 5, function() return c.width end, function(v) c.width = v end), 26)
    place(UI.Stepper(p, "Gauge height", 2, 16, 1, function() return c.height end, function(v) c.height = v end), 26)
    place(UI.Stepper(p, "Gap between gauges", 0, 80, 2, function() return c.spacing end,
        function(v) c.spacing = v end), 26)
    place(UI.Stepper(p, "Number size", 8, 32, 1, function() return c.numberSize end,
        function(v) c.numberSize = v end), 26)
    place(UI.Stepper(p, "Name size", 8, 24, 1, function() return c.nameSize end, function(v) c.nameSize = v end), 30)
    place(UI.Checkbox(p, "HP gauge", function() return c.showHealth end, function(v) c.showHealth = v end), 24)
    place(UI.Checkbox(p, "Resource gauge", function() return c.showPower end, function(v) c.showPower = v end), 30)
    place(UI.TextBox(p, "Name text", function() return c.nameText end, function(v) c.nameText = v end), 28)
    place(UI.TextBox(p, "HP text", function() return c.healthText end, function(v) c.healthText = v end), 28)
    place(UI.TextBox(p, "Resource text", function() return c.powerText end, function(v) c.powerText = v end), 30)
    place(UI.Help(p, "Shown while your pet has a target (a sample while unlocked). Its name is coloured by how the "
        .. "target feels about you. Unlock on the Layout tab to drag it on its own.", 400), 40)
end
