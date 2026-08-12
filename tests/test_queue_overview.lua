-- Standalone regression tests for the location-grouped queue overview.
--
-- The seller's real question is "who do I serve next", and the answer turns on where everyone is:
-- four customers in one city is one trip, four in four cities is four. Paging through tickets one
-- at a time cannot show that. These pin the grouping, the ordering between groups, and the summary
-- each row carries.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_queue_overview.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false
    },
    Portals = {}
}

local now = 1000
local playerZone = "Stormwind City"
local zones = {} -- unit token -> zone name
local roster = {} -- unit token -> player name
local positions = {} -- unit token -> {x, y, instance}
local knownSpells = {}

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
_G.UnitPosition = function(unit)
    local spot = positions[unit]
    if not spot then
        return nil
    end
    return spot[1], spot[2], spot[3]
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
_G.GetSpellBookItemName = function(index)
    return knownSpells[index]
end
_G.BOOKTYPE_SPELL = "spell"
_G.UnitFactionGroup = function()
    return "Alliance"
end

local Utils = dofile(addonDirectory .. "/Utils.lua")

local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        print("  FAIL: " .. message)
    end
end

-- Party plumbing: party1..partyN map to names, and each has a zone.
local function party(members)
    roster = {}
    zones = {
        player = playerZone
    }
    positions = {}

    for index, member in ipairs(members) do
        local token = "party" .. index
        roster[token] = member.name
        zones[token] = member.zone
        if member.position then
            positions[token] = member.position
        end
    end
end

local function queue(tickets)
    local pendingInvites = {}
    for _, ticket in ipairs(tickets) do
        pendingInvites[ticket.name] = {
            name = ticket.name,
            destination = ticket.destination,
            timestamp = ticket.arrived,
            joinedAt = ticket.arrived,
            portalCastAt = ticket.served,
            paidAt = ticket.paid,
            completedAt = ticket.done
        }
    end
    return pendingInvites
end

local function locations(overview)
    local out = {}
    for _, group in ipairs(overview) do
        out[#out + 1] = group.location or "?"
    end
    return table.concat(out, " | ")
end

local function sendersIn(group)
    local out = {}
    for _, ticket in ipairs(group.tickets) do
        out[#out + 1] = ticket.sender
    end
    return table.concat(out, ",")
end

-- 1. Grouping by location ---------------------------------------------------------------------------

playerZone = "Stormwind City"
party({{
    name = "Anna",
    zone = "Stormwind City"
}, {
    name = "Boris",
    zone = "Darnassus"
}, {
    name = "Cara",
    zone = "Stormwind City"
}})

local overview = Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 900
}, {
    name = "Boris",
    destination = "org",
    arrived = 800
}, {
    name = "Cara",
    destination = "if",
    arrived = 700
}}))

check(#overview == 2, "two zones should produce two groups, got " .. #overview)
check(overview[1].location == "Stormwind City", "our own zone should lead, got " ..
    tostring(overview[1].location))
check(overview[1].here == true, "our own zone should be flagged as here")
check(sendersIn(overview[1]) == "Cara,Anna", "within a group, longest wait first, got " ..
    sendersIn(overview[1]))
check(overview[2].location == "Darnassus", "the other zone should follow")
check(overview[2].here == false, "another zone is not here")

-- 2. Ordering between groups -------------------------------------------------------------------------

-- Our zone leads even when everybody in it arrived most recently.
playerZone = "Ironforge"
party({{
    name = "Anna",
    zone = "Darnassus"
}, {
    name = "Boris",
    zone = "Ironforge"
}})

overview = Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 100
}, {
    name = "Boris",
    destination = "sw",
    arrived = 990
}}))
check(overview[1].location == "Ironforge", "our own zone leads regardless of wait, got " ..
    tostring(overview[1].location))

-- Otherwise the zone holding the longest wait comes first.
playerZone = "Elwynn Forest"
party({{
    name = "Anna",
    zone = "Darnassus"
}, {
    name = "Boris",
    zone = "Orgrimmar"
}})

overview = Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 900
}, {
    name = "Boris",
    destination = "sw",
    arrived = 100
}}))
check(overview[1].location == "Orgrimmar", "the longest wait should pull its zone first, got " ..
    tostring(overview[1].location))

-- Customers we cannot locate go last, not first.
playerZone = "Stormwind City"
party({{
    name = "Boris",
    zone = "Darnassus"
}}) -- Anna is not in the roster, so she has no zone

overview = Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 100
}, {
    name = "Boris",
    destination = "sw",
    arrived = 900
}}))
check(overview[#overview].location == nil, "an unknown location should sort last, got " ..
    locations(overview))

-- 3. What each row carries ----------------------------------------------------------------------------

playerZone = "Stormwind City"
party({{
    name = "Anna",
    zone = "Stormwind City",
    position = {0, 0, 1}
}})
positions.player = {30, 40, 1} -- 50 yards away

now = 1000
overview = Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 880,
    paid = 900
}}))

local row = overview[1].tickets[1]
check(row.sender == "Anna", "the row should name the customer")
check(row.destination == "if", "the row should carry the destination")
check(row.state == Utils.TICKET_JOINED, "the row should carry the lifecycle state, got " .. tostring(row.state))
check(row.paid == true, "payment should be flagged")
check(row.waited == 120, "the wait should be counted, got " .. tostring(row.waited))
check(math.abs(row.distance - 50) < 0.01, "distance should be measured in our own zone, got " ..
    tostring(row.distance))

-- Distance is not reported for somebody in another zone, where it would be meaningless.
party({{
    name = "Anna",
    zone = "Darnassus",
    position = {0, 0, 2}
}})
overview = Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 880
}}))
check(overview[1].tickets[1].distance == nil, "distance across zones should be omitted")

-- 4. Teleport availability is a property of the group ---------------------------------------------------

playerZone = "Stormwind City"
party({{
    name = "Anna",
    zone = "Darnassus"
}})
knownSpells = {"Teleport: Darnassus"}

overview = Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 900
}}))
check(overview[1].teleport == "Teleport: Darnassus", "a known teleport should be offered for the group, got " ..
    tostring(overview[1].teleport))

knownSpells = {}
overview = Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 900
}}))
check(overview[1].teleport == nil, "a teleport we do not know is not offered")

-- Nor for a zone that is not a city at all.
party({{
    name = "Anna",
    zone = "Elwynn Forest"
}})
knownSpells = {"Teleport: Stormwind"}
overview = Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 900
}}))
check(overview[1].teleport == nil, "a non-city zone offers no teleport")
check(overview[1].city == nil, "a non-city zone resolves to no city")

-- 5. Only joined customers appear -----------------------------------------------------------------------

playerZone = "Stormwind City"
party({{
    name = "Anna",
    zone = "Stormwind City"
}})

local pending = queue({{
    name = "Anna",
    destination = "if",
    arrived = 900
}})
pending.Waiting = {
    name = "Waiting",
    destination = "if",
    timestamp = 800
} -- invited, never joined

overview = Utils.buildQueueOverview(pending)
check(#overview == 1 and #overview[1].tickets == 1, "an invited-but-not-joined customer has no place in the queue")
check(overview[1].tickets[1].sender == "Anna", "only the joined customer should be listed")

-- 6. Formatting ---------------------------------------------------------------------------------------------

check(table.concat(Utils.formatQueueOverview({}), "") == "No customers waiting.", "an empty queue says so")

party({{
    name = "Anna",
    zone = "Darnassus"
}})
knownSpells = {"Teleport: Darnassus"}
local lines = Utils.formatQueueOverview(Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 880,
    paid = 900
}})))

check(lines[1]:find("Darnassus", 1, true) ~= nil, "the header should name the zone, got " .. lines[1])
check(lines[1]:find("teleport available", 1, true) ~= nil, "the header should advertise the teleport, got " ..
    lines[1])
check(lines[2]:find("Anna", 1, true) ~= nil, "the row should name the customer")
check(lines[2]:find("paid", 1, true) ~= nil, "the row should show payment")
check(lines[2]:find("2m 00s", 1, true) ~= nil, "the row should show the wait, got " .. lines[2])

-- party() snapshots the player's zone, so move both together.
playerZone = "Darnassus"
zones.player = playerZone
lines = Utils.formatQueueOverview(Utils.buildQueueOverview(queue({{
    name = "Anna",
    destination = "if",
    arrived = 880
}})))
check(lines[1]:find("(here)", 1, true) ~= nil, "our own zone should be marked, got " .. lines[1])
check(lines[1]:find("teleport available", 1, true) == nil,
    "no point offering a teleport to where we already are, got " .. lines[1])

-- ------------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("queue overview: %d check(s) failed", failures))
end

print("queue overview: grouping, ordering, row detail, teleport availability and formatting all passed")
