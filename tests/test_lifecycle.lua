-- Standalone regression tests for the ticket lifecycle.
--
-- Service used to be three independent booleans - hasJoined, hasPaid, travelled - which could
-- disagree with each other and carried no record of when anything happened. Each stage is now the
-- moment it occurred, and the state is derived from which moments exist.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_lifecycle.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false
    },
    Portals = {}
}

local now = 500

_G.time = function()
    return now
end
_G.GetTime = function()
    return now
end

local Utils = dofile(addonDirectory .. "/Utils.lua")

local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        print("  FAIL: " .. message)
    end
end

-- 1. State is derived from the moments that exist -------------------------------------------------

local ticket = {
    timestamp = 100
}

check(Utils.getTicketState(ticket) == Utils.TICKET_INVITED, "a fresh ticket is invited, got " ..
    tostring(Utils.getTicketState(ticket)))

ticket.joinedAt = 110
check(Utils.getTicketState(ticket) == Utils.TICKET_JOINED, "joining moves the ticket to joined")

ticket.portalCastAt = 120
check(Utils.getTicketState(ticket) == Utils.TICKET_SERVED, "a cast portal moves the ticket to served")

ticket.completedAt = 130
check(Utils.getTicketState(ticket) == Utils.TICKET_COMPLETE, "taking the portal completes the ticket")

check(Utils.getTicketState(nil) == nil, "no ticket has no state")

-- Later stages win over earlier ones however the fields arrive. A customer can be inferred to have
-- travelled without the addon ever seeing the portal cast.
check(Utils.getTicketState({
    completedAt = 1
}) == Utils.TICKET_COMPLETE, "completion wins on its own")
check(Utils.getTicketState({
    joinedAt = 1,
    completedAt = 2
}) == Utils.TICKET_COMPLETE, "completion outranks joining")
check(Utils.getTicketState({
    joinedAt = 1,
    portalCastAt = 2
}) == Utils.TICKET_SERVED, "a served ticket is past joined")
check(Utils.getTicketState({
    portalCastAt = 1
}) == Utils.TICKET_SERVED, "a portal cast implies service even without a recorded join")

-- 2. Payment is a fact about the transaction, not a stage -------------------------------------------

local paidWhileWaiting = {
    joinedAt = 1,
    paidAt = 2
}

check(Utils.getTicketState(paidWhileWaiting) == Utils.TICKET_JOINED,
    "paying before the portal must not move the ticket past joined, got " ..
        tostring(Utils.getTicketState(paidWhileWaiting)))
check(Utils.isTicketPaid(paidWhileWaiting), "the payment is still recorded")

local paidAfterService = {
    joinedAt = 1,
    portalCastAt = 2,
    paidAt = 3
}
check(Utils.getTicketState(paidAfterService) == Utils.TICKET_SERVED, "paying after the portal leaves it served")
check(Utils.isTicketPaid(paidAfterService), "the payment is recorded either way")

check(Utils.isTicketPaid({
    joinedAt = 1
}) == false, "an unpaid ticket is not paid")
check(Utils.isTicketPaid(nil) == false, "no ticket is not paid")

-- 3. Predicates -------------------------------------------------------------------------------------

check(Utils.hasTicketJoined({
    joinedAt = 1
}) == true, "joinedAt means joined")
check(Utils.hasTicketJoined({}) == false, "no joinedAt means not joined")
check(Utils.hasTicketJoined(nil) == false, "no ticket has not joined")

check(Utils.isTicketComplete({
    completedAt = 1
}) == true, "completedAt means complete")
check(Utils.isTicketComplete({}) == false, "no completedAt means not complete")
check(Utils.isTicketComplete(nil) == false, "no ticket is not complete")

-- 4. Marking records the moment, once ---------------------------------------------------------------

local marked = {}

now = 700
Utils.markTicketJoined(marked)
check(marked.joinedAt == 700, "joining should record when, got " .. tostring(marked.joinedAt))

-- The roster updates constantly; "when did they join" has one answer.
now = 900
Utils.markTicketJoined(marked)
check(marked.joinedAt == 700, "re-marking must keep the first moment, got " .. tostring(marked.joinedAt))

Utils.markTicketPaid(marked)
check(marked.paidAt == 900, "payment should record when")
now = 1000
Utils.markTicketPaid(marked)
check(marked.paidAt == 900, "re-marking payment keeps the first moment")

Utils.markTicketComplete(marked)
check(marked.completedAt == 1000, "completion should record when")
now = 1100
Utils.markTicketComplete(marked)
check(marked.completedAt == 1000, "re-marking completion keeps the first moment")

-- An explicit moment overrides the clock, which is what the tests and any replay need.
local backdated = {}
Utils.markTicketJoined(backdated, 42)
check(backdated.joinedAt == 42, "an explicit moment should be used as given")

-- Marking nothing is harmless rather than an error.
local ok = pcall(function()
    Utils.markTicketJoined(nil)
    Utils.markTicketPaid(nil)
    Utils.markTicketComplete(nil)
end)
check(ok, "marking a missing ticket must not error")

-- 5. The moments are usable as history ----------------------------------------------------------------

-- The point of storing moments rather than booleans: how long the customer waited to be served is
-- answerable afterwards, which three booleans could never do.
local served = {
    timestamp = 100,
    joinedAt = 130,
    portalCastAt = 190
}

check(served.joinedAt - served.timestamp == 30, "time from request to joining is recoverable")
check(served.portalCastAt - served.joinedAt == 60, "time from joining to service is recoverable")

-- ------------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("lifecycle: %d check(s) failed", failures))
end

print("lifecycle: derived states, payment as a separate fact, predicates and marking all passed")
