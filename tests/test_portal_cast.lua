-- Standalone regression tests for crediting a cast portal to one ticket.
--
-- Portal liveness used to be a global table keyed by spell name, so casting Stormwind for one
-- customer flipped every Stormwind ticket in the queue to the trade icon at once. These pin the
-- replacement: the button arms an intent, the completed cast is credited to that ticket alone, and
-- a portal cast any other way falls to whoever has waited longest for it.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_portal_cast.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false,
        DestinationKeywords = {"sw", "stormwind", "if", "ironforge", "org"},
        soundEnabled = false
    },
    Portals = {"Portal: Stormwind", "Portal: Ironforge", "Portal: Orgrimmar"}
}

local now = 1000

-- Deliberately different domains. GetTime counts from client start and time() is wall clock, so
-- any lifecycle moment taken from the wrong one stands out immediately instead of coinciding.
_G.GetTime = function()
    return now + 100000
end
_G.time = function()
    return now
end
_G.UnitFactionGroup = function()
    return "Alliance"
end
_G.SendChatMessage = function()
end

local timers = {}

_G.C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = {
            delay = delay,
            callback = callback
        }
    end
}

_G.Events = {
    pendingInvites = {}
}

local Utils = dofile(addonDirectory .. "/Utils.lua")
local InviteTrade = dofile(addonDirectory .. "/InviteTrade.lua")

local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        print("  FAIL: " .. message)
    end
end

local function ticket(name, destination, arrivedAt)
    local inviteData = {
        name = name,
        fullName = name,
        destination = destination,
        timestamp = arrivedAt,
        joinedAt = arrivedAt,
        completedAt = nil
    }
    Events.pendingInvites[name] = inviteData
    return inviteData
end

local function reset()
    now = 1000
    timers = {}
    Events.pendingInvites = {}
    InviteTrade.pendingPortalCast = nil
end

-- 1. Liveness is per ticket and expires ----------------------------------------------------------

reset()
local anna = ticket("Anna", "sw", 100)

check(Utils.isTicketPortalAlive(anna) == false, "a ticket with no cast portal is not live")

anna.portalCastAt = now
check(Utils.isTicketPortalAlive(anna) == true, "a portal just cast is live")

now = now + Utils.PORTAL_ALIVE_WINDOW
check(Utils.isTicketPortalAlive(anna) == true, "a portal is still live at the edge of the window")

now = now + 1
check(Utils.isTicketPortalAlive(anna) == false, "a portal past the window is not live")

check(Utils.isTicketPortalAlive(nil) == false, "no ticket is not live")
check(Utils.isTicketPortalAlive({}) == false, "a ticket that never had a portal is not live")

-- 2. The bug: one cast must not serve every ticket for that city ---------------------------------

reset()
local first = ticket("Anna", "sw", 100)
local second = ticket("Boris", "sw", 200)
local other = ticket("Cara", "if", 300)

InviteTrade.beginPortalCast("Boris", second, "Portal: Stormwind")
local served = InviteTrade.attributePortalCast("Portal: Stormwind")

check(served == "Boris", "the cast should be credited to the ticket that armed it, got " .. tostring(served))
check(second.portalCastAt == now, "the portal moment must be on the lifecycle clock, got " ..
    tostring(second.portalCastAt) .. " with time() at " .. now)
check(Utils.isTicketPortalAlive(second) == true, "the armed ticket should have a live portal")
check(Utils.isTicketPortalAlive(first) == false, "the other Stormwind ticket must NOT be marked served")
check(Utils.isTicketPortalAlive(other) == false, "an unrelated destination must not be marked served")

-- The intent is spent, so a second completion does not credit anyone else.
served = InviteTrade.attributePortalCast("Portal: Stormwind")
check(served == "Anna", "a further cast falls to the next customer waiting for that city, got " .. tostring(served))
check(Utils.isTicketPortalAlive(first) == true, "the next Stormwind customer is now served")

-- 3. A manual cast falls to the oldest customer waiting for it -----------------------------------

reset()
first = ticket("Anna", "sw", 100)
second = ticket("Boris", "sw", 200)

served = InviteTrade.attributePortalCast("Portal: Stormwind")
check(served == "Anna", "a manual cast should serve the longest wait, got " .. tostring(served))
check(Utils.isTicketPortalAlive(first) == true, "the oldest ticket should be served")
check(Utils.isTicketPortalAlive(second) == false, "the newer ticket should still be waiting")

-- Someone already served is skipped rather than served twice.
served = InviteTrade.attributePortalCast("Portal: Stormwind")
check(served == "Boris", "the next cast should skip the served customer, got " .. tostring(served))

-- With everyone served, a further cast matches nobody.
served = InviteTrade.attributePortalCast("Portal: Stormwind")
check(served == nil, "a cast with nobody left waiting should credit nobody, got " .. tostring(served))

-- 4. Casts that match no ticket ------------------------------------------------------------------

reset()
ticket("Anna", "sw", 100)

check(InviteTrade.attributePortalCast("Portal: Orgrimmar") == nil, "a city nobody asked for credits nobody")
check(InviteTrade.attributePortalCast(nil) == nil, "no spell credits nobody")

-- Customers who have already travelled are not candidates.
reset()
local gone = ticket("Anna", "sw", 100)
gone.completedAt = 1
check(InviteTrade.attributePortalCast("Portal: Stormwind") == nil, "a travelled customer must not be credited")

-- Nor are customers who have not joined yet.
reset()
local waiting = ticket("Anna", "sw", 100)
waiting.joinedAt = nil
check(InviteTrade.attributePortalCast("Portal: Stormwind") == nil, "an un-joined customer has no ticket to credit")

-- 5. Stale and mismatched intents fall back rather than misfire ----------------------------------

-- Ticket removed between click and cast.
reset()
first = ticket("Anna", "sw", 100)
second = ticket("Boris", "sw", 200)
InviteTrade.beginPortalCast("Boris", second, "Portal: Stormwind")
Events.pendingInvites["Boris"] = nil

served = InviteTrade.attributePortalCast("Portal: Stormwind")
check(served == "Anna", "a removed ticket should fall back to the queue, got " .. tostring(served))

-- Ticket replaced by a fresh request from the same player.
reset()
second = ticket("Boris", "sw", 200)
InviteTrade.beginPortalCast("Boris", second, "Portal: Stormwind")
local replacement = ticket("Boris", "sw", 400)

served = InviteTrade.attributePortalCast("Portal: Stormwind")
check(served == "Boris", "the replacement ticket is the one waiting")
check(Utils.isTicketPortalAlive(replacement) == true, "the credit should land on the current record")
check(Utils.isTicketPortalAlive(second) == false, "the replaced record must not be credited")

-- A different portal than the one armed.
reset()
first = ticket("Anna", "sw", 100)
local ironforge = ticket("Cara", "if", 300)
InviteTrade.beginPortalCast("Anna", first, "Portal: Stormwind")

served = InviteTrade.attributePortalCast("Portal: Ironforge")
check(served == "Cara", "a different portal should credit its own queue, got " .. tostring(served))
check(Utils.isTicketPortalAlive(first) == false, "the armed ticket must not be credited by another spell")
check(Utils.isTicketPortalAlive(ironforge) == true, "the Ironforge customer should be served")

-- An intent that sat too long is ignored.
reset()
first = ticket("Anna", "sw", 100)
second = ticket("Boris", "sw", 200)
InviteTrade.beginPortalCast("Boris", second, "Portal: Stormwind")
now = now + 300

served = InviteTrade.attributePortalCast("Portal: Stormwind")
check(served == "Anna", "an expired intent should fall back to the queue, got " .. tostring(served))

-- 6. Clearing --------------------------------------------------------------------------------------

reset()
second = ticket("Boris", "sw", 200)
first = ticket("Anna", "sw", 100)
InviteTrade.beginPortalCast("Boris", second, "Portal: Stormwind")

check(InviteTrade.clearPortalCast(nil, "Portal: Ironforge") == false, "an unrelated spell must not clear the intent")
check(InviteTrade.pendingPortalCast ~= nil, "the intent should survive an unrelated spell")

check(InviteTrade.clearPortalCast(nil, "Portal: Stormwind") == true, "the matching spell should clear the intent")
check(InviteTrade.pendingPortalCast == nil, "nothing should remain pending")

served = InviteTrade.attributePortalCast("Portal: Stormwind")
check(served == "Anna", "after a failed cast the next completion falls back to the queue, got " .. tostring(served))

-- The expiry timer clears its own intent and not a later one.
reset()
second = ticket("Boris", "sw", 200)
InviteTrade.beginPortalCast("Boris", second, "Portal: Stormwind")
check(#timers >= 1, "arming should schedule an expiry")

local firstTimer = timers[#timers].callback
InviteTrade.beginPortalCast("Boris", second, "Portal: Ironforge")
firstTimer()

check(InviteTrade.pendingPortalCast ~= nil, "a superseded timer must not clear the newer intent")
check(InviteTrade.pendingPortalCast.spellName == "Portal: Ironforge", "the newer intent should survive")

-- ------------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("portal cast: %d check(s) failed", failures))
end

print("portal cast: per-ticket liveness, attribution, fallback and stale intents all passed")
