-- Standalone regression tests for resolving a tracked customer to a party unit token, and for the
-- deferred travel-button state that hangs off it.
--
-- These cover the integration the pure zone-name tests do not: a ticket is keyed by player name,
-- but C_Map wants a unit token, and the protected button's update can be deferred past combat and
-- land after the ticket has moved on.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_travel_state.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false
    },
    Portals = {}
}

-- Fake party roster -----------------------------------------------------------------------------

local party = {}

_G.MAX_PARTY_MEMBERS = 4
_G.UnitExists = function(token)
    return party[token] ~= nil
end
_G.UnitName = function(token)
    local member = party[token]
    if not member then
        return nil
    end
    return member.name, member.realm
end
-- UnitName reports a blank realm for units on our own realm, so resolving that needs our name.
_G.GetRealmName = function()
    return "Spineshatter"
end

local Utils = dofile(addonDirectory .. "/Utils.lua")

local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        print("  FAIL: " .. message)
    end
end

-- 1. Resolving a tracked name to a party unit token ---------------------------------------------

party = {
    party1 = {
        name = "Gralint",
        realm = ""
    },
    party2 = {
        name = "Keefs",
        realm = "Spineshatter"
    }
}

check(Utils.getPartyUnitToken("Gralint") == "party1", "a same-realm customer should resolve to their token")
check(Utils.getPartyUnitToken("Keefs") == "party2", "a cross-realm customer should resolve from the bare name")
check(Utils.getPartyUnitToken("Keefs-Spineshatter") == "party2", "a Name-Realm ticket should resolve to its token")
check(Utils.getPartyUnitToken("gralint") == "party1", "name matching should be case-insensitive")
check(Utils.getPartyUnitToken("Nobody") == nil, "a customer who is not grouped must not resolve")
check(Utils.getPartyUnitToken("Keefs-Otherrealm") == nil, "a mismatched realm must not resolve")
check(Utils.getPartyUnitToken(nil) == nil, "a nil name must not resolve")
check(Utils.getPartyUnitToken("") == nil, "an empty name must not resolve")

-- A ticket that names a realm must not settle for a unit whose realm is blank: UnitName reports
-- an empty realm for our own, so a blank is our realm, not a wildcard.
check(Utils.getPartyUnitToken("Gralint-Somewhereelse") == nil,
    "a realm-qualified ticket must not match a same-realm namesake")
check(Utils.getPartyUnitToken("Gralint-Spineshatter") == "party1",
    "a realm-qualified ticket should match when the blank realm resolves to ours")
check(Utils.getPartyUnitToken("Gralint-Spine Shatter") == "party1", "realm suffixes ignore spaces")

-- The gap that made this necessary: the ticket key is a name, and the map API wants a token.
check(Utils.getUnitZoneName("Gralint") == nil, "a bare name is not a unit token and must not be mapped")

party = {}
check(Utils.getPartyUnitToken("Gralint") == nil, "nobody resolves once the party is empty")

-- 2. Deferred secure updates are keyed, not a single slot ---------------------------------------

-- Reproduces the real sequence: one ticket refresh queues the portal button and then the travel
-- button while in combat. With a single slot the first was silently discarded.
local UI = {
    pendingSecureUpdates = {}
}

local inCombat = true

function UI.runWhenOutOfCombat(key, updateFunction)
    if inCombat then
        UI.pendingSecureUpdates[key] = updateFunction
        return false
    end
    UI.pendingSecureUpdates[key] = nil
    updateFunction()
    return true
end

function UI.flush()
    local pending = UI.pendingSecureUpdates
    UI.pendingSecureUpdates = {}
    for _, updateFunction in pairs(pending) do
        updateFunction()
    end
end

local applied = {}

UI.runWhenOutOfCombat("actionButton", function()
    applied[#applied + 1] = "actionButton"
end)
UI.runWhenOutOfCombat("travelButton", function()
    applied[#applied + 1] = "travelButton"
end)

check(#applied == 0, "nothing should apply while in combat")

inCombat = false
UI.flush()

table.sort(applied)
check(table.concat(applied, ",") == "actionButton,travelButton",
    "both deferred button updates must survive combat, got " .. table.concat(applied, ","))

-- The newest update for a given button replaces the older one rather than stacking.
inCombat = true
local spellAssigned = nil

UI.runWhenOutOfCombat("travelButton", function()
    spellAssigned = "Teleport: Darnassus"
end)
UI.runWhenOutOfCombat("travelButton", function()
    spellAssigned = "Teleport: Ironforge"
end)

inCombat = false
UI.flush()

check(spellAssigned == "Teleport: Ironforge", "the latest state for a button should win, got " .. tostring(spellAssigned))

-- 3. A deferred travel update must not apply to a ticket that has moved on ----------------------

-- Mirrors applyTravelState: validate the displayed sender before touching the button.
local ticketFrame = {
    currentSender = "Gralint"
}
local button = {
    shown = false,
    spell = nil
}

local function applyTravelState(sender, teleportSpell)
    UI.runWhenOutOfCombat("travelButton", function()
        if sender and ticketFrame.currentSender ~= sender then
            return -- stale
        end
        if not teleportSpell then
            button.spell = nil
            button.shown = false
            return
        end
        button.spell = teleportSpell
        button.shown = true
    end)
end

inCombat = true
applyTravelState("Gralint", "Teleport: Darnassus")

-- While that waits, the user pages to a different customer.
ticketFrame.currentSender = "Keefs"

inCombat = false
UI.flush()

check(button.shown == false, "a stale travel update must not show the button for a different ticket")
check(button.spell == nil, "a stale travel update must not assign a teleport")

-- The same update for the customer actually on screen does apply.
inCombat = true
applyTravelState("Keefs", "Teleport: Ironforge")
inCombat = false
UI.flush()

check(button.shown == true, "the current ticket's travel update should apply")
check(button.spell == "Teleport: Ironforge", "the current ticket's teleport should be assigned")

-- Losing location detection clears the action as well as hiding, so nothing stale can be cast.
applyTravelState("Keefs", nil)
check(button.shown == false, "the travel button should hide when there is no teleport to offer")
check(button.spell == nil, "hiding the travel button must also clear its assigned spell")

-- An unconditional hide (customer gone) applies regardless of which ticket is displayed.
inCombat = true
applyTravelState("Keefs", "Teleport: Ironforge")
inCombat = false
UI.flush()
ticketFrame.currentSender = "SomeoneElse"
applyTravelState(nil, nil)

check(button.shown == false, "an unconditional hide must apply whatever ticket is displayed")
check(button.spell == nil, "an unconditional hide must clear the assigned spell")

-- 4. Flush order: replayed callbacks must not undo a window created in the same flush -----------

-- The dangerous sequence. An unconditional hide carries no sender, so the staleness check cannot
-- catch it; if the window were created first, that hide would land afterwards and clear the new
-- ticket's perfectly valid travel action.
UI.pendingTicketWindow = false

local flushOrder = {}

local function createTicketWindow()
    -- Stands in for showPaginatedTicketWindow -> updateTicketFrame settling the new ticket.
    flushOrder[#flushOrder + 1] = "window"
    ticketFrame.currentSender = "Newcustomer"
    applyTravelState("Newcustomer", "Teleport: Darnassus")
end

local function flushPendingSecureUpdate()
    -- Replay first...
    local pending = UI.pendingSecureUpdates
    UI.pendingSecureUpdates = {}
    for _, updateFunction in pairs(pending) do
        flushOrder[#flushOrder + 1] = "replay"
        updateFunction()
    end

    -- ...then build the window, so its refresh is the authoritative final state.
    if UI.pendingTicketWindow then
        UI.pendingTicketWindow = false
        createTicketWindow()
    end
end

button.shown = false
button.spell = nil
flushOrder = {}

inCombat = true
applyTravelState(nil, nil) -- unconditional hide queued from the outgoing ticket
UI.pendingTicketWindow = true -- first ticket of the fight, window creation deferred

inCombat = false
flushPendingSecureUpdate()

-- The ordering itself is the contract under test. Asserting only the end state does not
-- discriminate: runWhenOutOfCombat's immediate path clears its key, so a window built first would
-- delete the stale hide before the replay loop ever captured it. That masking is an invariant of
-- another function, which is exactly what this ordering removes the dependence on.
check(table.concat(flushOrder, ",") == "replay,window",
    "deferred updates must be replayed before a deferred window is built, got " .. table.concat(flushOrder, ","))

check(button.shown == true, "a stale unconditional hide must not clear the newly created ticket's travel button")
check(button.spell == "Teleport: Darnassus", "the new ticket's teleport must survive the flush")

-- 5. The travel announcement is scoped to the click that started it ------------------------------

Config.Settings.travelMessage = "On my way to %location% - meet me there for your %destination% portal."

local whispers = {}
local now = 1000

_G.GetTime = function()
    return now
end

-- Captured rather than run, so the expiry timer can be fired deliberately.
local scheduled = {}

_G.C_Timer = {
    After = function(delay, callback)
        scheduled[#scheduled + 1] = {
            delay = delay,
            callback = callback
        }
    end
}

_G.SendChatMessage = function(message, channel, _, target)
    whispers[#whispers + 1] = {
        message = message,
        channel = channel,
        target = target
    }
end

_G.Events = {
    pendingInvites = {}
}

local InviteTrade = dofile(addonDirectory .. "/InviteTrade.lua")

local function newTicket(name, destination)
    local inviteData = {
        name = name,
        fullName = name .. "-Spineshatter",
        destination = destination,
        joinedAt = 1
    }
    _G.Events.pendingInvites[name] = inviteData
    return inviteData
end

local TRAVEL_TEMPLATE = "On my way to %location% - meet me there for your %destination% portal."

local function reset()
    whispers = {}
    scheduled = {}
    now = 1000
    -- Restored every time: one case below blanks it to prove the feature can be switched off, and
    -- leaving it blank silently disabled every check that followed.
    Config.Settings.travelMessage = TRAVEL_TEMPLATE
    _G.Events.pendingInvites = {}
    InviteTrade.pendingTravelAnnouncement = nil
end

-- A manual teleport, cast from the spellbook with no ticket behind it, must say nothing.
reset()
newTicket("Gralint", "if")
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false, "a manual teleport must not announce")
check(#whispers == 0, "a manual teleport must whisper nobody")

-- The travel button's own cast whispers exactly its customer, exactly once.
reset()
local gralint = newTicket("Gralint", "if")
newTicket("Keefs", "org") -- also waiting, must not be whispered

InviteTrade.beginTravelAnnouncement("Gralint", gralint, "Darnassus", "Teleport: Darnassus")

check(InviteTrade.announceTravelStart("Teleport: Darnassus") == true, "the button's own cast should announce")
check(#whispers == 1, "exactly one customer should be whispered, got " .. #whispers)
check(whispers[1].target == "Gralint-Spineshatter", "the whisper should go to the ticket that started it")
check(whispers[1].channel == "WHISPER", "the announcement should be a whisper")
check(whispers[1].message == "On my way to Darnassus - meet me there for your if portal.",
    "both placeholders should be filled, got " .. whispers[1].message)

-- A repeated cast event must not resend it.
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false, "a repeated start event must not resend")
check(#whispers == 1, "a repeated start event must not produce a second whisper")

-- A different teleport while one is pending is the mage's own business.
reset()
local gralint2 = newTicket("Gralint", "if")
InviteTrade.beginTravelAnnouncement("Gralint", gralint2, "Darnassus", "Teleport: Darnassus")
check(InviteTrade.announceTravelStart("Teleport: Ironforge") == false, "a different teleport must not announce")
check(#whispers == 0, "a different teleport must whisper nobody")

-- A failed or interrupted cast clears the intent, so nothing is sent afterwards.
reset()
local gralint3 = newTicket("Gralint", "if")
InviteTrade.beginTravelAnnouncement("Gralint", gralint3, "Darnassus", "Teleport: Darnassus")
InviteTrade.clearTravelAnnouncement() -- what UNIT_SPELLCAST_FAILED / _INTERRUPTED do
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false, "an interrupted cast must not announce")
check(#whispers == 0, "an interrupted cast must whisper nobody")

-- A ticket removed between click and cast sends nothing.
reset()
local gralint4 = newTicket("Gralint", "if")
InviteTrade.beginTravelAnnouncement("Gralint", gralint4, "Darnassus", "Teleport: Darnassus")
_G.Events.pendingInvites["Gralint"] = nil
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false, "a removed ticket must not announce")
check(#whispers == 0, "a removed ticket must whisper nobody")
check(InviteTrade.pendingTravelAnnouncement == nil, "a removed ticket should drop the pending announcement")

-- A ticket replaced by a fresh invite for the same player is also stale.
reset()
local gralint5 = newTicket("Gralint", "if")
InviteTrade.beginTravelAnnouncement("Gralint", gralint5, "Darnassus", "Teleport: Darnassus")
newTicket("Gralint", "org") -- they asked again; this is a different record
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false, "a replaced ticket must not announce")
check(#whispers == 0, "a replaced ticket must whisper nobody")

-- Clearing for one customer leaves another customer's pending announcement alone.
reset()
local keefs = newTicket("Keefs", "org")
InviteTrade.beginTravelAnnouncement("Keefs", keefs, "Orgrimmar", "Teleport: Orgrimmar")
InviteTrade.clearTravelAnnouncement("Gralint") -- a different ticket was torn down
check(InviteTrade.announceTravelStart("Teleport: Orgrimmar") == true,
    "clearing another customer's ticket must not cancel this announcement")
check(#whispers == 1, "the surviving announcement should still whisper once")

-- An empty travel message disables the feature entirely.
reset()
local gralint6 = newTicket("Gralint", "if")
Config.Settings.travelMessage = ""
InviteTrade.beginTravelAnnouncement("Gralint", gralint6, "Darnassus", "Teleport: Darnassus")
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false, "an empty travel message should send nothing")
check(#whispers == 0, "an empty travel message must whisper nobody")

-- 6. Arming order, expiry, and clearing only on the matching spell -------------------------------

-- PreClick arms before the secure action casts, so the very next event can be the cast starting.
-- Nothing may elapse in between for the announcement to work.
reset()
local armed = newTicket("Gralint", "if")
InviteTrade.beginTravelAnnouncement("Gralint", armed, "Darnassus", "Teleport: Darnassus")
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == true,
    "a cast starting in the same instant as the click must still announce")
check(#whispers == 1, "the immediate start should whisper once")

-- A click that never became a cast expires instead of lying in wait.
reset()
local neverCast = newTicket("Gralint", "if")
InviteTrade.beginTravelAnnouncement("Gralint", neverCast, "Darnassus", "Teleport: Darnassus")
now = now + 30
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false, "an expired intent must not announce")
check(#whispers == 0, "an expired intent must whisper nobody")
check(InviteTrade.pendingTravelAnnouncement == nil, "an expired intent should be dropped")

-- And a manual teleport minutes later must not inherit it.
reset()
local abandoned = newTicket("Gralint", "if")
InviteTrade.beginTravelAnnouncement("Gralint", abandoned, "Darnassus", "Teleport: Darnassus")
now = now + 600
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false,
    "a manual teleport long after an abandoned click must not announce")
check(#whispers == 0, "a manual teleport after expiry must whisper nobody")

-- An unrelated spell failing, being interrupted, or succeeding during the teleport must leave the
-- intent alone: those events carry their own spell, and cancelling on them loses a live trip.
for _, unrelated in ipairs({"Fireball", "Frost Nova", "Portal: Ironforge"}) do
    reset()
    local survives = newTicket("Gralint", "if")
    InviteTrade.beginTravelAnnouncement("Gralint", survives, "Darnassus", "Teleport: Darnassus")

    check(InviteTrade.clearTravelAnnouncement(nil, unrelated) == false, unrelated .. " must not clear the intent")
    check(InviteTrade.pendingTravelAnnouncement ~= nil, unrelated .. " must leave the intent armed")
    check(InviteTrade.announceTravelStart("Teleport: Darnassus") == true,
        "the teleport should still announce after an unrelated " .. unrelated)
    check(#whispers == 1, "the surviving intent should whisper once despite " .. unrelated)
end

-- The matching teleport's own end - however it ended - does clear it.
for _, ending in ipairs({"success", "failure", "interruption"}) do
    reset()
    local ends = newTicket("Gralint", "if")
    InviteTrade.beginTravelAnnouncement("Gralint", ends, "Darnassus", "Teleport: Darnassus")

    check(InviteTrade.clearTravelAnnouncement(nil, "Teleport: Darnassus") == true,
        "the matching teleport's " .. ending .. " should clear the intent")
    check(InviteTrade.pendingTravelAnnouncement == nil, "nothing should stay pending after " .. ending)
    check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false,
        "no announcement should follow a cleared " .. ending)
    check(#whispers == 0, "a cleared " .. ending .. " must whisper nobody")
end

-- Tokens keep a re-armed intent distinct from the one it replaced.
reset()
local first = newTicket("Gralint", "if")
local firstToken = InviteTrade.beginTravelAnnouncement("Gralint", first, "Darnassus", "Teleport: Darnassus")
local secondToken = InviteTrade.beginTravelAnnouncement("Gralint", first, "Ironforge", "Teleport: Ironforge")

check(firstToken ~= secondToken, "each arming should get its own token")
check(InviteTrade.clearTravelAnnouncement(nil, nil, firstToken) == false,
    "a late clear carrying the old token must not drop the new intent")
check(InviteTrade.announceTravelStart("Teleport: Ironforge") == true, "the re-armed intent should still announce")
check(#whispers == 1, "the re-armed intent should whisper once")

-- 7. Expiry is scheduled, not merely checked when something else happens ------------------------

-- A click that never cast should stop being pending on its own, without waiting for another event
-- to come along and notice.
reset()
local abandonedClick = newTicket("Gralint", "if")
InviteTrade.beginTravelAnnouncement("Gralint", abandonedClick, "Darnassus", "Teleport: Darnassus")

check(#scheduled == 1, "arming should schedule an expiry, got " .. #scheduled .. " timers")
check(scheduled[1].delay == 2, "the expiry should fire after the announcement window, got " .. tostring(scheduled[1].delay))
check(InviteTrade.pendingTravelAnnouncement ~= nil, "the intent is armed until the timer fires")

scheduled[1].callback()

check(InviteTrade.pendingTravelAnnouncement == nil, "the scheduled expiry should clear its own intent")
check(InviteTrade.announceTravelStart("Teleport: Darnassus") == false, "an expired intent announces nothing")
check(#whispers == 0, "an expired intent whispers nobody")

-- The timer belonging to a superseded arming must not take the newer one with it. This is what the
-- token is for in production, rather than only in tests.
reset()
local rearmed = newTicket("Gralint", "if")
InviteTrade.beginTravelAnnouncement("Gralint", rearmed, "Darnassus", "Teleport: Darnassus")
InviteTrade.beginTravelAnnouncement("Gralint", rearmed, "Ironforge", "Teleport: Ironforge")

check(#scheduled == 2, "each arming schedules its own expiry")

scheduled[1].callback() -- the first arming's timer, firing after it was superseded

check(InviteTrade.pendingTravelAnnouncement ~= nil, "a superseded timer must not clear the newer intent")
check(InviteTrade.announceTravelStart("Teleport: Ironforge") == true, "the newer intent should still announce")
check(#whispers == 1, "the newer intent should whisper once")

-- And the newer arming's own timer still works.
scheduled[2].callback()
check(InviteTrade.pendingTravelAnnouncement == nil, "the newer intent's own timer should clear it")

-- ------------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("travel state: %d check(s) failed", failures))
end

print("travel state: unit token resolution, keyed deferrals, stale-update guards and scoped travel announcements all passed")
