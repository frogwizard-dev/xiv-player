local _, ns = ...
local UI = ns.UI
local Auras = {}
ns.Auras = Auras

-- Your buffs and debuffs above the gauges: whitelisted buffs over HP, every debuff except a
-- blacklist over MP. Rendered by 12.1's AuraContainer, like PersonalResourceTweaks and
-- XIVTarget: the engine picks and draws the auras from a spell-ID filter, so it keeps working
-- where addons can't read aura data. Lessons carried over: position a container before setting
-- it up, never anchor anything to it, and size its buttons ourselves (the engine makes them 0x0).

local issecret = FrogLib.issecret
local KINDS = { "buffs", "debuffs" }
local SORT = AuraContainerSortMethod and AuraContainerSortMethod.Default
local SORT_DIR = AuraContainerSortDirection and AuraContainerSortDirection.Normal
-- Timers and stacks use the narrow bundled face; Michroma is too wide for a gap one icon wide.
local TIMER_FONT = "Interface\\AddOns\\XIVPlayer\\Fonts\\SourceSans3.ttf"
local TIMER_ROOM = 12 -- the countdown prints under each icon, FFXIV-style

local containers, signatures, groupKeys = {}, {}, {}
local styled = { buffs = {}, debuffs = {} }

local A = FrogLib.Auras -- the rows' building blocks (FrogLib's Auras.lua)

local function StyleButton(d)
    local cfg = ns.db[d.kind]
    -- Denied while auras are secret; retried on the next restyle.
    if d.size ~= cfg.size and pcall(d.button.SetSize, d.button, cfg.size, cfg.size) then
        d.size = cfg.size
    end
    local size = math.max(9, math.floor(cfg.size * 0.46))
    ns.Media:SetFont(d.stack, TIMER_FONT, size, ns.db.outline)
    ns.Media:SetFont(d.duration, TIMER_FONT, size, ns.db.outline)
    d.duration:SetShown(cfg.showTimer)
end

-- Runs once per engine-made button. Fonts go on before the regions are handed over, because
-- handing them over makes the engine write text straight away.
local function MakeInit(kind)
    return function(button)
        local d = A.InitButton(button, { border = kind == "debuffs" and { 0.75, 0.12, 0.08 } or nil,
            style = function(new)
                new.kind = kind
                StyleButton(new)
            end })
        table.insert(styled[kind], d)
    end
end

local function Layout(cfg)
    return { elementWidth = cfg.size, elementHeight = cfg.size, elementSpacing = cfg.spacing,
        lineSpacing = cfg.spacing + (cfg.showTimer and TIMER_ROOM or 0) }
end

-- Whatever changes which groups exist; groups can't be removed, so a change means a rebuild.
local function Signature(kind)
    local cfg = ns.db[kind]
    if kind == "buffs" then return "w|" .. table.concat(cfg.list, ",") end
    return "b|" .. cfg.max .. "|" .. (cfg.maxMinutes or 0) .. "|" .. table.concat(cfg.blacklist, ",")
end

local function Build(kind)
    local cfg = ns.db[kind]
    A.Release(containers[kind])
    containers[kind] = nil
    local c = A.NewContainer(ns.Player.frame)
    if not c then return end

    -- Placed before anything else: a container without a renderable rect never shows an aura.
    containers[kind] = c
    Auras:Anchor()
    A.Flow(c, "BOTTOMLEFT", "RIGHT", "UP")

    styled[kind] = {}
    local keys, init, layout = {}, MakeInit(kind), Layout(cfg)
    local function add(key, filter, opts)
        opts.sortMethod, opts.sortDirection = SORT, SORT_DIR
        opts.initializeFrame, opts.layout = init, layout
        if pcall(c.AddAuraGroup, c, key, filter, opts) then keys[#keys + 1] = key end
    end
    if kind == "buffs" then
        -- One single-slot group per spell keeps the whitelist's order.
        for i, id in ipairs(cfg.list) do
            add("w" .. i, "HELPFUL", { maxFrameCount = 1, candidateFilters = { includeSpellIDs = { [id] = true } } })
        end
    else
        -- The engine ignores spell-ID filters for debuffs on a unit you can assist, yourself
        -- included, except for the few spells it never hides from addons (EllesmereUI calls it
        -- the identity gate). So the blacklist only catches those; duration does work on you,
        -- so long debuffs (Boosted Rest's hour, say) are hidden by a duration cap instead.
        -- maxDuration also drops debuffs with no duration at all.
        local filters = {}
        local exclude = {}
        for _, id in ipairs(cfg.blacklist) do exclude[id] = true end
        if next(exclude) then filters.excludeSpellIDs = exclude end
        if (cfg.maxMinutes or 0) > 0 then filters.maxDuration = cfg.maxMinutes * 60 end
        add("all", "HARMFUL", { maxFrameCount = cfg.max, candidateFilters = next(filters) and filters or nil })
    end
    groupKeys[kind] = keys
    -- Unit last: the engine only listens for aura events once the container has groups.
    c:SetUnit("player")
    c:UpdateAllAuras()
    signatures[kind] = Signature(kind)
end

-- Buffs over the HP gauge, debuffs over the MP gauge.
function Auras:Anchor()
    local over = { buffs = ns.Player.health.gauge.bar, debuffs = ns.Player.power.gauge.bar }
    for kind, c in pairs(containers) do
        local cfg = ns.db[kind]
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", over[kind], "TOPLEFT", 0, cfg.offsetY + (cfg.showTimer and TIMER_ROOM or 0))
    end
end

function Auras:Apply()
    for _, kind in ipairs(KINDS) do
        local cfg = ns.db[kind]
        if not containers[kind] or signatures[kind] ~= Signature(kind) then Build(kind) end
        local c = containers[kind]
        if c then
            local layout = Layout(cfg)
            for _, key in ipairs(groupKeys[kind]) do
                pcall(c.SetAuraGroupLayout, c, key, layout)
            end
            A.SetLineSize(c, ns.db.width + 0.4)
            c:SetShown(cfg.enabled)
            for _, d in ipairs(styled[kind]) do pcall(StyleButton, d) end
        end
    end
    self:Anchor()
end

------------------------------------------------------------------------------
-- Settings pages: the spell lists
------------------------------------------------------------------------------

-- The lists, and a picker of the auras on you right now (so a spell can be added without knowing
-- its ID): FrogLib's UI.lua.
local SpellInfo, ScrollList, Fill = UI.SpellInfo, UI.ScrollList, UI.FillList
local function Say(text) print("|cfff5dc8fXIVPlayer|r: " .. text) end
local function ShowPicker(window, kind, onAdd)
    UI.AuraPicker(window, kind, onAdd, Say)
end

-- One settings page: buffs are a whitelist (shown in order), debuffs a blacklist.
function Auras.BuildPage(p, kind)
    local cfg = ns.db[kind]
    local whitelist = kind == "buffs"
    local ids = whitelist and cfg.list or cfg.blacklist
    local place = UI.Placer()
    local refreshList

    place(UI.Checkbox(p, "Show " .. kind .. (whitelist and " (only the ones listed below)" or ""),
        function() return cfg.enabled end, function(v) cfg.enabled = v end), 26)
    place(UI.Checkbox(p, "Show countdown under the icons",
        function() return cfg.showTimer end, function(v) cfg.showTimer = v end), 30)
    place(UI.Stepper(p, "Icon size", 14, 48, 2, function() return cfg.size end, function(v) cfg.size = v end), 26)
    if not whitelist then
        place(UI.Stepper(p, "Most shown", 1, 40, 1, function() return cfg.max end, function(v) cfg.max = v end), 26)
        place(UI.Stepper(p, "Hide if over (mins)", 0, 120, 5, function() return cfg.maxMinutes or 0 end,
            function(v) cfg.maxMinutes = v end), 26)
    end
    place(UI.Stepper(p, "Spacing", 0, 12, 1, function() return cfg.spacing end, function(v) cfg.spacing = v end), 26)
    place(UI.Stepper(p, "Raise above the gauge", -20, 80, 2, function() return cfg.offsetY end,
        function(v) cfg.offsetY = v end), 30)

    place(UI.Label(p, whitelist and "Buffs to show (in this order)" or "Debuffs to hide"), 18)
    if whitelist then
        place(UI.Help(p, "Hover any buff or spell to see its Spell ID, or pick from what's on you now.", 400), 20)
    else
        -- The game skips spell-ID lists for debuffs on you (see Build), so say so plainly.
        place(UI.Help(p, "The game only lets addons hide a few debuffs on you by name. For long ones "
            .. "like Boosted Rest (an hour), set \"Hide if over\" above, e.g. to 30. 0 turns it off.", 400), 30)
    end

    local function AddID(id)
        id = tonumber(id)
        if not id then return end
        if not SpellInfo(id) then
            print("|cfff5dc8fXIVPlayer|r: No spell with ID", id)
            return
        end
        for _, v in ipairs(ids) do
            if v == id then return end
        end
        table.insert(ids, id)
        refreshList()
        ns.Refresh()
    end

    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(90, 20)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    place(eb, 22, 6)
    local add = UI.Button(p, "Add ID", 70)
    add:SetPoint("LEFT", eb, "RIGHT", 6, 0)
    local pick = UI.Button(p, "Pick from my current " .. kind, 190)
    pick:SetPoint("LEFT", add, "RIGHT", 6, 0)
    local preview = UI.Label(p, "", "GameFontHighlightSmall")
    place(preview, 20, 6)
    eb:SetScript("OnTextChanged", function(self)
        preview:SetText(SpellInfo(tonumber(self:GetText()) or 0) or "")
    end)
    eb:SetScript("OnEnterPressed", function(self)
        AddID(self:GetText())
        self:SetText("")
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    add:SetScript("OnClick", function()
        AddID(eb:GetText())
        eb:SetText("")
    end)
    pick:SetScript("OnClick", function() ShowPicker(ns.window, kind, AddID) end)
    p:HookScript("OnHide", function()
        local picker = ns.window and ns.window.frogPicker
        if picker then picker:Hide() end
    end)

    local list = ScrollList(p, 400, whitelist and 130 or 104)
    place(list, 0)

    function refreshList()
        Fill(list, ids, function(r, id, i)
            local name, icon = SpellInfo(id)
            r.icon:SetTexture(icon or 134400)
            r.text:SetText((name or "Unknown spell") .. " |cff888888(" .. id .. ")|r")
            if not r.remove then
                r.remove = UI.Button(r, "X", 24, 20)
                r.remove:SetPoint("RIGHT", -2, 0)
                r.down = UI.Button(r, "Dn", 36, 20)
                r.down:SetPoint("RIGHT", r.remove, "LEFT", -2, 0)
                r.up = UI.Button(r, "Up", 36, 20)
                r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
            end
            r.up:SetShown(whitelist)
            r.down:SetShown(whitelist)
            r.up:SetEnabled(i > 1)
            r.down:SetEnabled(i < #ids)
            r.remove:SetScript("OnClick", function()
                table.remove(ids, i)
                refreshList()
                ns.Refresh()
            end)
            r.up:SetScript("OnClick", function()
                ids[i], ids[i - 1] = ids[i - 1], ids[i]
                refreshList()
                ns.Refresh()
            end)
            r.down:SetScript("OnClick", function()
                ids[i], ids[i + 1] = ids[i + 1], ids[i]
                refreshList()
                ns.Refresh()
            end)
        end)
    end
    refreshList()
end

-- Spell IDs on aura and spell tooltips, so adding to a list is "hover, read, type". Left to
-- PersonalResourceTweaks when it's loaded, which adds the same line.
local idFrame = CreateFrame("Frame")
idFrame:RegisterEvent("PLAYER_LOGIN")
idFrame:SetScript("OnEvent", function()
    if FrogLib.Loaded("PersonalResourceTweaks") then return end
    if not (TooltipDataProcessor and Enum.TooltipDataType) then return end
    local function AddID(tooltip, data)
        local id = data and data.id
        if issecret(id) or not id then return end
        tooltip:AddLine("Spell ID: " .. id, 0.5, 0.8, 1)
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, AddID)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AddID)
end)
