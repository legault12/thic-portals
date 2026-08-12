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

-- ------------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("travel state: %d check(s) failed", failures))
end

print("travel state: unit token resolution, keyed deferrals and stale-update guards all passed")
