-- Standalone regression tests for group capacity and the invite gate.
--
-- maxSimultaneousTickets defaults to 15, but a party seats four customers however that setting is
-- configured. Nothing checked the group, so past four the addon kept firing invites that could not
-- succeed, and each failed invite still created a record that blocked the customer from asking
-- again until it expired.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_capacity.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false,
        DestinationKeywords = {"sw", "stormwind", "if", "ironforge", "org"},
        IntentKeywords = {"wtb"},
        ServiceKeywords = {"portal", "port"},
        commonPhrases = {"wtb portal", "wtb port"},
        KeywordBanList = {},
        BanList = {},
        soundEnabled = false,
        removeRealmFromInviteCommand = false,
        inviteCooldown = 300,
        maxSimultaneousTickets = 15,
        disableSmartMatching = false,
        requireDestination = false
    },
    Portals = {"Portal: Stormwind", "Portal: Ironforge", "Portal: Orgrimmar"}
}

local now = 10000
local groupSize = 0
local inRaid = false
local invited = {}
local printed = {}

_G.time = function()
    return now
end
_G.GetTime = function()
    return now
end
_G.GetNumGroupMembers = function()
    return groupSize
end
_G.IsInRaid = function()
    return inRaid
end

local isLeader = true
local converted = 0

_G.UnitIsGroupLeader = function()
    return isLeader
end
_G.ConvertToRaid = function()
    converted = converted + 1
end
_G.MEMBERS_PER_RAID_GROUP = 5
_G.MAX_RAID_MEMBERS = 40
_G.UnitFactionGroup = function()
    return "Alliance"
end
_G.InviteUnit = function(name)
    invited[#invited + 1] = name
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
_G.UI = {
    setIconSpell = function()
    end
}

local failures = 0
local realPrint = io.write

local function check(condition, message)
    if not condition then
        failures = failures + 1
        realPrint("  FAIL: " .. message .. "\n")
    end
end

local function reset()
    now = 10000
    groupSize = 0
    inRaid = false
    isLeader = true
    converted = 0
    timers = {}
    InviteTrade.raidConversionPending = false
    invited = {}
    printed = {}
    Events.pendingInvites = {}
    InviteTrade.capacityNoticeShown = false
    Config.Settings.autoConvertToRaid = false
end

local function said(fragment)
    for _, line in ipairs(printed) do
        if line:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

-- 1. Raw capacity ---------------------------------------------------------------------------------

reset()
local free, used, maximum = Utils.getGroupCapacity()
check(free == 4 and used == 1 and maximum == 5, "solo should be 1 of 5 with 4 free, got " .. free .. "/" .. used)

groupSize = 3 -- the mage plus two customers
free, used = Utils.getGroupCapacity()
check(free == 2 and used == 3, "a party of three should have two seats free, got " .. free)

groupSize = 5
free = Utils.getGroupCapacity()
check(free == 0, "a full party has no seats free, got " .. free)

groupSize = 7 -- defensive: never report negative headroom
free = Utils.getGroupCapacity()
check(free == 0, "an over-full group should clamp to zero, got " .. free)

inRaid = true
groupSize = 12
free, used, maximum = Utils.getGroupCapacity()
check(maximum == 40 and free == 28, "a raid should seat forty, got " .. free .. " free of " .. maximum)
inRaid = false

-- 2. Invites already out hold a seat ---------------------------------------------------------------

reset()
groupSize = 3 -- two seats free

local function outstandingInvite(name, at)
    Events.pendingInvites[name] = {
        name = name,
        fullName = name,
        joinedAt = nil,
        timestamp = at
    }
end

local slots, capacityFree, outstanding = Utils.availableInviteSlots(Events.pendingInvites)
check(slots == 2 and outstanding == 0, "no invites out means every free seat is offerable, got " .. slots)

outstandingInvite("Anna", now)
slots, capacityFree, outstanding = Utils.availableInviteSlots(Events.pendingInvites)
check(slots == 1 and outstanding == 1, "an invite already out should hold a seat, got " .. slots)

outstandingInvite("Boris", now)
slots = Utils.availableInviteSlots(Events.pendingInvites)
check(slots == 0, "two invites out fill the two free seats, got " .. slots)

-- An invite old enough that WoW's own popup has lapsed stops holding its seat.
now = now + Utils.INVITE_SEAT_HOLD + 1
slots, capacityFree, outstanding = Utils.availableInviteSlots(Events.pendingInvites)
check(outstanding == 0, "a lapsed invite should stop holding a seat, got " .. outstanding)
check(slots == 2, "the seats should come back, got " .. slots)

-- Customers who have joined are already counted by the group itself, so they must not be
-- double-counted as outstanding invites.
reset()
groupSize = 3
Events.pendingInvites["Anna"] = {
    name = "Anna",
    joinedAt = 1,
    timestamp = now
}
slots, capacityFree, outstanding = Utils.availableInviteSlots(Events.pendingInvites)
check(outstanding == 0, "a joined customer is not an outstanding invite")
check(slots == 2, "a joined customer must not be counted twice, got " .. slots)

-- Reset the group explicitly rather than inheriting it from the case above.
reset()
check(select(1, Utils.availableInviteSlots(nil)) == 4, "a nil queue solo should report four seats")
groupSize = 3
check(select(1, Utils.availableInviteSlots(nil)) == 2, "a nil queue still reports the group's own capacity")
check(select(1, Utils.availableInviteSlots({})) == 2, "an empty queue behaves the same as no queue")

-- 3. The gate: no seat, no invite -------------------------------------------------------------------

reset()
groupSize = 5 -- full party

InviteTrade.handleInviteAndMessage("Newcomer", "Newcomer", "MAGE", "wtb portal sw", false)

check(#invited == 0, "a full group must not send an invite")
check(Events.pendingInvites["Newcomer"] == nil,
    "a refused invite must not leave a record burning the customer's cooldown")
check(said("Group is full"), "the user should be told the shop is turning people away")

-- The notice is shown once, not on every request that arrives while full.
printed = {}
InviteTrade.handleInviteAndMessage("Another", "Another", "MAGE", "wtb portal sw", false)
check(said("Group is full") == false, "the full-group notice should not repeat for every request")
check(#invited == 0, "still no invite while full")

-- A seat opening up lets the next customer in, and re-arms the notice.
groupSize = 4
InviteTrade.handleInviteAndMessage("Lucky", "Lucky", "MAGE", "wtb portal sw", false)

check(#invited == 1 and invited[1] == "Lucky", "a free seat should invite, got " .. tostring(invited[1]))
check(Events.pendingInvites["Lucky"] ~= nil, "an accepted invite should be tracked")
check(InviteTrade.capacityNoticeShown == false, "the notice should re-arm once the group has room")

-- Filling again warns again.
groupSize = 5
printed = {}
InviteTrade.handleInviteAndMessage("Late", "Late", "MAGE", "wtb portal sw", false)
check(said("Group is full"), "the notice should return the next time the group fills")

-- 4. Outstanding invites gate too, not just bodies in the group -------------------------------------

reset()
groupSize = 4 -- one seat free

InviteTrade.handleInviteAndMessage("First", "First", "MAGE", "wtb portal sw", false)
check(#invited == 1, "the free seat should be offered to the first customer")

InviteTrade.handleInviteAndMessage("Second", "Second", "MAGE", "wtb portal sw", false)
check(#invited == 1, "the seat is spoken for, so the second customer must not be invited")
check(Events.pendingInvites["Second"] == nil, "and must not be left with a record")

-- Once the first invite lapses, the seat is offered again.
now = now + Utils.INVITE_SEAT_HOLD + 1
InviteTrade.handleInviteAndMessage("Third", "Third", "MAGE", "wtb portal sw", false)
check(#invited == 2 and invited[2] == "Third", "a lapsed invite should free the seat, got " .. tostring(invited[2]))

-- 5. A raid does not hit the party ceiling ----------------------------------------------------------

reset()
inRaid = true
groupSize = 6

InviteTrade.handleInviteAndMessage("Raider", "Raider", "MAGE", "wtb portal sw", false)
check(#invited == 1, "a raid has room well past four customers")

-- 6. Raid conversion -----------------------------------------------------------------------------------

-- When it can be done at all.
reset()
groupSize = 3
check(InviteTrade.canConvertToRaid() == true, "a led party of three can convert")

inRaid = true
check(InviteTrade.canConvertToRaid() == false, "a raid is already a raid")
inRaid = false

groupSize = 1
check(InviteTrade.canConvertToRaid() == false, "there is no party to convert when solo")
groupSize = 3

isLeader = false
check(InviteTrade.canConvertToRaid() == false, "a non-leader cannot convert")
local allowed, reason = InviteTrade.canConvertToRaid()
check(reason and reason:find("leader", 1, true), "and should be told why, got " .. tostring(reason))
isLeader = true

-- Converting says what it did, and warns what it costs the customers.
reset()
groupSize = 5
check(InviteTrade.convertToRaid() == true, "converting a full led party should succeed")
check(converted == 1, "the client call should be made once, got " .. converted)
check(said("Converting the group to a raid"), "the conversion should be announced")
check(said("cannot queue for dungeons"), "the cost to customers should be stated")

-- Refusing explains itself rather than failing quietly.
reset()
groupSize = 5
isLeader = false
check(InviteTrade.convertToRaid() == false, "a non-leader cannot convert")
check(converted == 0, "and no client call should be made")
check(said("Cannot convert to a raid"), "the refusal should be explicit")

-- Off by default: a full group offers the command rather than taking the decision.
reset()
groupSize = 5
InviteTrade.handleInviteAndMessage("Newcomer", "Newcomer", "MAGE", "wtb portal sw", false)
check(converted == 0, "the default must not convert the group on its own")
check(said("/Tp raid"), "the option should be offered, got: " .. table.concat(printed, " | "))

-- The offer is not made when it could not be taken.
reset()
groupSize = 5
isLeader = false
InviteTrade.handleInviteAndMessage("Newcomer", "Newcomer", "MAGE", "wtb portal sw", false)
check(said("Group is full"), "a full group still says so")
check(said("/Tp raid") == false, "do not offer a conversion the seller cannot perform")

-- Switched on, a full group converts. The seats arrive with the server, so this customer is still
-- turned away; the next one gets in.
reset()
groupSize = 5
Config.Settings.autoConvertToRaid = true
InviteTrade.handleInviteAndMessage("Newcomer", "Newcomer", "MAGE", "wtb portal sw", false)
check(converted == 1, "with the setting on, a full group should convert")
check(#invited == 0, "the conversion is not instant, so this request is still refused")
check(said("/Tp raid") == false, "no point offering what just happened")

-- And once the client reports a raid, there is room again.
reset()
groupSize = 6
inRaid = true
Config.Settings.autoConvertToRaid = true
InviteTrade.handleInviteAndMessage("Later", "Later", "MAGE", "wtb portal sw", false)
check(#invited == 1, "a raid has room for the next customer")
check(converted == 0, "and nothing further needs converting")

-- 7. A conversion already in flight ------------------------------------------------------------------

-- Converting is a server round trip. Requests keep arriving in the second it takes, and each one
-- would have fired another conversion at a group that is already becoming a raid.
reset()
groupSize = 5
Config.Settings.autoConvertToRaid = true

for _ = 1, 5 do
    InviteTrade.handleInviteAndMessage("Asker", "Asker", "MAGE", "wtb portal sw", false)
end

check(converted == 1, "repeated requests during the round trip should convert once, got " .. converted)
check(InviteTrade.raidConversionPending == true, "the conversion should be marked in flight")
check(InviteTrade.canConvertToRaid() == false, "nothing else should convert while one is in flight")

local _, reasonWhilePending = InviteTrade.canConvertToRaid()
check(reasonWhilePending and reasonWhilePending:find("already been requested", 1, true),
    "and should say why, got " .. tostring(reasonWhilePending))

-- The roster confirming a raid is what releases it.
inRaid = true
Events = Events or {}
InviteTrade.clearRaidConversionPending()
check(InviteTrade.raidConversionPending == false, "confirmation should clear the flag")

-- A conversion that never lands must not wedge the shop into refusing forever.
reset()
groupSize = 5
check(InviteTrade.convertToRaid() == true, "the first conversion should go out")
check(InviteTrade.raidConversionPending == true, "and be held in flight")

local timeout
for _, timer in ipairs(timers) do
    if timer.delay and timer.delay >= 5 then
        timeout = timer.callback
    end
end
check(timeout ~= nil, "a timeout should be scheduled")

timeout()
check(InviteTrade.raidConversionPending == false, "the timeout should release the flag")
check(InviteTrade.canConvertToRaid() == true, "and allow another attempt")

-- The timeout does not undo a conversion that did land.
reset()
groupSize = 5
InviteTrade.convertToRaid()
inRaid = true
InviteTrade.clearRaidConversionPending()
check(InviteTrade.canConvertToRaid() == false, "an actual raid still cannot be converted again")

-- ------------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("capacity: %d check(s) failed", failures))
end

realPrint("capacity: group seats, invite holds, the full-group gate, raid headroom and conversion all passed\n")
