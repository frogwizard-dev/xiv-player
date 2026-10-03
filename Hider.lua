local _, ns = ...

-- Shared by the XIV addons (each keeps its own copy; keep them identical).
-- Hides one of Blizzard's frames by moving it under a hidden frame, the way XIVPlayer hides
-- the cast bar; its events keep running, so anything it drives still updates. Usage:
--   ns.HideBlizzardFrame("PlayerFrame", on, { "PetFrame" })
-- The names in the last list are children with a life of their own: they move out to UIParent
-- while the frame is hidden, keeping their place and size, and go back when it's shown.
-- Unit frames are protected, so nothing moves in combat or Edit Mode (where re-parenting runs
-- Blizzard's layout code under our taint); changes made then wait.

local hiddenParent
local frames = {}
local pending

local function Blocked()
    return InCombatLockdown() or (EditModeManagerFrame and EditModeManagerFrame:IsShown())
end

local function Apply(s)
    local frame = s.frame
    if s.on then
        if frame:GetParent() ~= hiddenParent then
            s.parent = frame:GetParent()
            frame:SetParent(hiddenParent)
        end
        for _, name in ipairs(s.keep) do
            local child = _G[name]
            if child and child:GetParent() == frame then
                -- Its size came partly from the frame's scale (Edit Mode's frame size).
                s.kept[child] = child:GetScale()
                child:SetParent(UIParent)
                child:SetScale(s.kept[child] * frame:GetScale())
            end
        end
    else
        for child, scale in pairs(s.kept) do
            if child:GetParent() == UIParent then
                child:SetParent(frame)
                child:SetScale(scale)
            end
        end
        wipe(s.kept)
        if s.parent and frame:GetParent() == hiddenParent then frame:SetParent(s.parent) end
    end
end

local function Flush()
    if Blocked() then
        pending = true
        return
    end
    pending = nil
    for _, s in pairs(frames) do Apply(s) end
end

function ns.HideBlizzardFrame(name, on, keep)
    local frame = _G[name]
    if not frame then return end
    local s = frames[name]
    if not s then
        if not on then return end
        if not hiddenParent then
            hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
        end
        s = { frame = frame, keep = keep or {}, kept = {} }
        frames[name] = s
        -- Edit Mode and vehicles can put it back under its old parent; hide it again after.
        hooksecurefunc(frame, "SetParent", function(_, parent)
            if s.on and parent ~= hiddenParent then C_Timer.After(0, Flush) end
        end)
    end
    s.on = on
    Flush()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    if pending then Flush() end
end)
if EventRegistry then
    EventRegistry:RegisterCallback("EditMode.Exit", function() C_Timer.After(0, Flush) end)
end
