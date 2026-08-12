-- Standalone regression tests for closing a ticket when the customer arrives.
--
-- Knowing a customer is standing in the city they asked for is a much better signal than the
-- distance heuristic, which only infers that somebody wandered off. But it is only safe with
-- guards: a request naming the city the customer is already in would otherwise complete before
-- anything was done for them, and closing mid-trade would lose the thank-you still owed.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_auto_complete.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false,
        autoCompleteOnArrival = true,
        DestinationKeywords = {"sw", "if", "org"},
        soundEnabled = false
    },
    Portals = {"Portal: Stormwind", "Portal: Ironforge"}
}

local now = 2000
local zones = {}
local roster = {}
local uninvited = {}
local printed = {}
local uiCalls = {}

_G.time = function()
    return now
end
_G.GetTime = function()
    return now
end
_G.MAX_PARTY_MEMBERS = 4
_G.UnitExists = function(token)
    return roster[token] ~= nil
end
_G.UnitName = function(token)
    return roster[token], ""
end
_G.GetRealmName = function()
    return "Spineshatter"
end
_G.C_Map = {
    GetBestMapForUnit = function(unit)
        return zones[unit] and unit or nil
    end,
    GetMapInfo = function(unit)
        return {
            name = zones[unit]
        }
    end
}
_G.UnitFactionGroup = function()
    return "Alliance"
end
_G.UninviteUnit = function(name)
    uninvited[#uninvited + 1] = name
end
_G.SendChatMessage = function()
end
_G.C_Timer = {
    After = function()
    end
}
_G.UI = {
    updateTicketList = function()
        uiCalls[#uiCalls + 1] = "list"
    end,
    updateTicketFrame = function()
        uiCalls[#uiCalls + 1] = "frame"
    end
}

local realPrint = print
_G.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    printed[#printed + 1] = table.concat(parts, " ")
end

_G.Events = {
    pendingInvites = {}
}

local Utils = dofile(addonDirectory .. "/Utils.lua")
local InviteTrade = dofile(addonDirectory .. "/InviteTrade.lua")

local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        realPrint("  FAIL: " .. message)
    end
end

local function said(fragment)
    for _, line in ipairs(printed) do
        if line:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

-- A customer in the party, standing somewhere, who asked to go somewhere.
local function customer(options)
    roster = {
        party1 = "Gralint"
    }
    zones = {
        player = "Stormwind City",
        party1 = options.standingIn
    }
    uninvited = {}
    printed = {}
    uiCalls = {}
    Config.currentTraderName = options.trading and "Gralint" or nil
    Config.Settings.autoCompleteOnArrival = options.setting ~= false

    Events.pendingInvites = {
        Gralint = {
            name = "Gralint",
            fullName = "Gralint-Spineshatter",
            destination = options.wants,
            timestamp = 1900,
            joinedAt = 1900,
            portalCastAt = options.served and 1950 or nil
        }
    }

    return Events.pendingInvites.Gralint
end

-- 1. The case it exists for -------------------------------------------------------------------------

local ticket = customer({
    wants = "if",
    standingIn = "Ironforge",
    served = true
})

check(InviteTrade.completeIfArrived("Gralint") == true, "a served customer standing in their destination is done")
check(Utils.isTicketComplete(ticket), "the ticket should be marked complete")
check(ticket.completedAt == now, "completion should be recorded on the lifecycle clock")
check(Events.pendingInvites.Gralint == nil, "the ticket should be closed")
check(uninvited[1] == "Gralint-Spineshatter", "the customer should be dropped from the group, got " ..
    tostring(uninvited[1]))
check(said("arrived in Ironforge"), "the seller should be told why the ticket closed")

local sawRefresh = false
for _, call in ipairs(uiCalls) do
    if call == "list" then
        sawRefresh = true
    end
end
check(sawRefresh, "the queue should be refreshed")

-- Aliases resolve, so it is the city that matters and not the spelling.
ticket = customer({
    wants = "ironforge",
    standingIn = "Ironforge",
    served = true
})
check(InviteTrade.completeIfArrived("Gralint") == true, "the destination should be compared by city, not by keyword")

-- 2. Still travelling ---------------------------------------------------------------------------------

customer({
    wants = "if",
    standingIn = "Stormwind City",
    served = true
})
check(InviteTrade.completeIfArrived("Gralint") == false, "a customer who has not arrived is not done")
check(Events.pendingInvites.Gralint ~= nil, "their ticket should stay open")
check(#uninvited == 0, "they should stay in the group")

-- Somewhere else entirely, including a city that is not their destination.
customer({
    wants = "if",
    standingIn = "Orgrimmar",
    served = true
})
check(InviteTrade.completeIfArrived("Gralint") == false, "the wrong city is not arrival")

-- 3. The guard that matters most ------------------------------------------------------------------------

-- Somebody asking for a portal to the city they are already standing in must not be completed
-- before a portal has been cast for them.
customer({
    wants = "if",
    standingIn = "Ironforge",
    served = false
})
check(InviteTrade.completeIfArrived("Gralint") == false,
    "a customer already standing in their destination must not be completed before being served")
check(Events.pendingInvites.Gralint ~= nil, "their ticket should stay open")
check(#uninvited == 0, "and they should certainly not be kicked")

-- 4. Never mid-trade ---------------------------------------------------------------------------------------

customer({
    wants = "if",
    standingIn = "Ironforge",
    served = true,
    trading = true
})
check(InviteTrade.completeIfArrived("Gralint") == false, "an open trade should hold the ticket open")
check(Events.pendingInvites.Gralint ~= nil, "the ticket must survive until the trade finishes")
check(#uninvited == 0, "and the customer must not be dropped mid-trade")

-- Once the trade is over it completes as normal.
Config.currentTraderName = nil
check(InviteTrade.completeIfArrived("Gralint") == true, "after the trade it should complete")

-- 5. Cases we cannot judge -----------------------------------------------------------------------------------

-- A destination we cannot place cannot be compared against where they are.
customer({
    wants = "somewhere",
    standingIn = "Ironforge",
    served = true
})
check(InviteTrade.completeIfArrived("Gralint") == false, "an unresolvable destination cannot be judged arrived")

-- No destination at all.
ticket = customer({
    wants = nil,
    standingIn = "Ironforge",
    served = true
})
check(InviteTrade.completeIfArrived("Gralint") == false, "a ticket with no destination cannot arrive")

-- A customer whose location the client will not report.
customer({
    wants = "if",
    standingIn = nil,
    served = true
})
check(InviteTrade.completeIfArrived("Gralint") == false, "an unlocatable customer is not known to have arrived")

-- Somebody we are not tracking at all.
customer({
    wants = "if",
    standingIn = "Ironforge",
    served = true
})
Events.pendingInvites = {}
check(InviteTrade.completeIfArrived("Gralint") == false, "an untracked name completes nothing")

-- 6. The setting turns it off entirely ---------------------------------------------------------------------

customer({
    wants = "if",
    standingIn = "Ironforge",
    served = true,
    setting = false
})
check(InviteTrade.completeIfArrived("Gralint") == false, "the setting should switch the behaviour off")
check(Events.pendingInvites.Gralint ~= nil, "with it off, the seller closes tickets themselves")
check(#uninvited == 0, "with it off, nobody is dropped from the group")

-- 7. The contract: auto-completion closes the ticket rather than showing it as complete ------------

-- Worth pinning because it looks like an omission. The ticket is marked complete and removed in the
-- same breath, so a customer closed this way never appears as "complete" anywhere - the state is
-- reachable only through the distance heuristic, which leaves the ticket up for the seller to
-- dismiss. Arrival needs no confirming, so it does not wait to be dismissed.
ticket = customer({
    wants = "if",
    standingIn = "Ironforge",
    served = true
})

check(InviteTrade.completeIfArrived("Gralint") == true, "precondition: it completes")
check(Utils.isTicketComplete(ticket), "the record itself is marked complete before removal")
check(Events.pendingInvites.Gralint == nil, "but it is gone from the queue immediately")
check(Utils.getTicketState(ticket) == Utils.TICKET_COMPLETE,
    "the detached record still reports complete, for anything holding a reference")

-- The distance heuristic is the path that does leave a visible complete ticket.
ticket = customer({
    wants = "if",
    standingIn = "Stormwind City",
    served = true
})
Utils.markTicketComplete(ticket)
check(Events.pendingInvites.Gralint ~= nil, "the heuristic leaves the ticket in place")
check(Utils.getTicketState(Events.pendingInvites.Gralint) == Utils.TICKET_COMPLETE,
    "and that is where a visible complete state comes from")

-- ------------------------------------------------------------------------------------------------

_G.print = realPrint

if failures > 0 then
    error(string.format("auto complete: %d check(s) failed", failures))
end

print("auto complete: arrival, guards, mid-trade, unjudgeable cases and the setting all passed")
