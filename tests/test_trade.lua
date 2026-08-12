-- Standalone regression tests for trade and tip handling.
--
-- Three defects motivated these. A customer who tipped an item was told they had not tipped, since
-- only coin was inspected. The money snapshot was read with no nil guard, so a trade that completed
-- without an accept-update crashed on the arithmetic. And the trade contents were only ever read
-- from events, one of which was handled but never registered.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_trade.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false,
        DestinationKeywords = {"sw", "if"},
        totalGold = 0,
        dailyGold = 0,
        totalTradesCompleted = 0,
        itemTipsReceived = 0,
        lastUpdateDate = "2026-08-11",
        tipMessage = "thanks!",
        noTipMessage = "safe travels!",
        soundEnabled = false
    },
    Portals = {"Portal: Stormwind"}
}

local tradeMoney = 0
local tradeItems = {}
local whispers = {}
local emotes = {}
local printed = {}

local clock = 5000

_G.time = function()
    return clock
end
-- A different domain on purpose: lifecycle moments must all come from time().
_G.GetTime = function()
    return clock + 100000
end
_G.date = function()
    return "2026-08-11"
end
_G.MAX_TRADE_ITEMS = 6
_G.GetTargetTradeMoney = function()
    return tradeMoney
end
_G.GetTradeTargetItemInfo = function(slot)
    local item = tradeItems[slot]
    if not item then
        return nil
    end
    return item.name, "texture", item.quantity
end
_G.UnitName = function()
    return "Gralint", ""
end
_G.SendChatMessage = function(message, _, _, target)
    whispers[#whispers + 1] = {
        message = message,
        target = target
    }
end
_G.DoEmote = function(emote, target)
    emotes[#emotes + 1] = emote .. ":" .. tostring(target)
end
_G.UnitFactionGroup = function()
    return "Alliance"
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
_G.ERR_TRADE_COMPLETE = "Trade complete."
_G.UnitInParty = function()
    return true
end
_G.FlashClientIcon = function()
end
_G.UI = {
    toggleAddonEnabledState = function()
    end,
    updateTicketFrame = function()
    end,
    updateTicketList = function()
    end,
    showPaginatedTicketWindow = function()
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

local Utils = dofile(addonDirectory .. "/Utils.lua")
local InviteTrade = dofile(addonDirectory .. "/InviteTrade.lua")
local Events = dofile(addonDirectory .. "/Events.lua")

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

local function whispered(fragment)
    for _, whisper in ipairs(whispers) do
        if whisper.message:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

local function reset(customerMoney, customerItems)
    tradeMoney = customerMoney or 0
    tradeItems = customerItems or {}
    whispers = {}
    emotes = {}
    printed = {}

    Config.Settings.totalGold = 0
    Config.Settings.dailyGold = 0
    Config.Settings.totalTradesCompleted = 0
    Config.Settings.itemTipsReceived = 0

    Events.pendingInvites = {
        Gralint = {
            name = "Gralint",
            fullName = "Gralint-Spineshatter",
            destination = "if",
            joinedAt = 1
        }
    }

    Config.currentTraderName = "Gralint"
    Config.currentTraderMoney = nil
    Config.currentTraderItems = nil
    timers = {}
end

local function fireTimers()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        timer.callback()
    end
end

-- 1. Capturing what is on the table ---------------------------------------------------------------

reset(12345, {{
    name = "Rune of Portals",
    quantity = 5
}})
Events.captureTradeContents()

check(Config.currentTraderMoney == 12345, "money should be captured, got " .. tostring(Config.currentTraderMoney))
check(#Config.currentTraderItems == 1, "items should be captured, got " .. #Config.currentTraderItems)
check(Config.currentTraderItems[1].name == "Rune of Portals", "the item name should be captured")
check(Config.currentTraderItems[1].quantity == 5, "the stack size should be captured")

-- Items in later slots are found, and gaps do not stop the scan.
reset(0, {nil, nil, {
    name = "Arcane Dust",
    quantity = 2
}})
Events.captureTradeContents()
check(#Config.currentTraderItems == 1, "an item in a later slot should still be seen")

-- An empty trade captures cleanly rather than leaving stale values.
reset(0, {})
Config.currentTraderMoney = 999
Events.captureTradeContents()
check(Config.currentTraderMoney == 0, "an empty trade should capture as zero, not keep the old value")
check(#Config.currentTraderItems == 0, "an empty trade should hold no items")

-- Closing a trade forgets it, so its contents cannot be read as the next trade's tip.
reset(500, {})
Events.captureTradeContents()
Events.forgetTrade()
check(Config.currentTraderMoney == nil, "a closed trade should forget its money")
check(Config.currentTraderItems == nil, "a closed trade should forget its items")
check(Config.currentTraderName == nil, "a closed trade should forget the trader")

-- 2. Gold tips ---------------------------------------------------------------------------------------

reset(25000, {}) -- 2g 50s
Events.captureTradeContents()

check(InviteTrade.checkTradeTip() == true, "a gold tip should count as a tip")
check(Config.Settings.totalGold == 25000, "the gold should be added to the running total")
check(Config.Settings.totalTradesCompleted == 1, "the trade should be counted")
check(Config.Settings.itemTipsReceived == 0, "a gold tip is not an item tip")
check(said("Received 2g 50s 0c"), "the amount received should be reported")

-- 3. The bug: an item tip is still a tip -----------------------------------------------------------

reset(0, {{
    name = "Rune of Portals",
    quantity = 20
}})
Events.captureTradeContents()

check(InviteTrade.checkTradeTip() == true, "an item tip must count as a tip")
check(Config.Settings.itemTipsReceived == 1, "the item tip should be counted")
check(Config.Settings.totalTradesCompleted == 1, "an item tip is a completed transaction")
check(Config.Settings.totalGold == 0, "an item must not be given an invented gold value")
check(said("20x Rune of Portals"), "the item should be named, got: " .. table.concat(printed, " | "))

-- And the customer gets thanked rather than told they did not pay.
Events.handleTradeComplete()
check(whispered("thanks!"), "an item tipper should get the thank-you message")
check(whispered("safe travels!") == false, "an item tipper must not get the no-tip message")

-- Both together are counted in both places, once each.
reset(10000, {{
    name = "Arcane Dust",
    quantity = 3
}})
Events.captureTradeContents()

check(InviteTrade.checkTradeTip() == true, "coin and items together count")
check(Config.Settings.totalGold == 10000, "the coin should be counted")
check(Config.Settings.itemTipsReceived == 1, "the items should be counted")
check(Config.Settings.totalTradesCompleted == 1, "the trade should be counted once, not twice")

-- A single item does not get a quantity prefix.
reset(0, {{
    name = "Hearthstone",
    quantity = 1
}})
Events.captureTradeContents()
InviteTrade.checkTradeTip()
check(said("Received Hearthstone from the trade."), "a single item should read plainly, got: " ..
    table.concat(printed, " | "))

-- 4. No tip at all -------------------------------------------------------------------------------------

reset(0, {})
Events.captureTradeContents()

check(InviteTrade.checkTradeTip() == false, "an empty trade is not a tip")
check(Config.Settings.totalTradesCompleted == 0, "an empty trade should not be counted")
check(Config.Settings.itemTipsReceived == 0, "an empty trade is not an item tip")

Events.handleTradeComplete()
check(whispered("safe travels!"), "an empty trade should get the no-tip message")

-- 5. Nil safety ----------------------------------------------------------------------------------------

-- A trade that completed without any snapshot at all used to error on the arithmetic.
reset(0, {})
Config.currentTraderMoney = nil
Config.currentTraderItems = nil

local ok, err = pcall(InviteTrade.checkTradeTip)
check(ok, "a missing snapshot must not error, got: " .. tostring(err))
check(ok and err == false, "a missing snapshot means no tip")

-- 6. Flourishes are about coin, and only fire for coin --------------------------------------------------

reset(90000, {}) -- 9g
Events.captureTradeContents()
InviteTrade.checkTradeTip()
check(whispered("<3"), "a generous gold tip should get the heart")
check(emotes[1] == "thank:Gralint", "a generous gold tip should emote thanks, got " .. tostring(emotes[1]))

reset(0, {{
    name = "Rune of Portals",
    quantity = 40
}})
Events.captureTradeContents()
InviteTrade.checkTradeTip()
check(whispered("<3") == false, "an item tip must not trigger the coin flourish")
check(#emotes == 0, "an item tip must not emote")

reset(690000, {}) -- 69g
Events.captureTradeContents()
InviteTrade.checkTradeTip()
check(whispered("Nice"), "69 should be noticed")

reset(42000, {}) -- 4g 20s
Events.captureTradeContents()
InviteTrade.checkTradeTip()
check(whispered("420 blaze it"), "4g20s should be noticed")

-- An untracked trader is not whispered, and does not error.
reset(90000, {})
Events.captureTradeContents()
Events.pendingInvites = {}
ok, err = pcall(InviteTrade.checkTradeTip)
check(ok, "an untracked trader must not error, got: " .. tostring(err))
check(#whispers == 0, "an untracked trader should not be whispered")

-- 7. Event order around closing and completing -----------------------------------------------------

-- The window closing and the trade completing are separate events with no guaranteed order.
-- Clearing on close used to be immediate, which meant that if close landed first the completion
-- found no trader and the customer was neither thanked nor counted.
Config.Settings.addonEnabled = true
Config.Settings.consecutiveLeavesWithoutPayment = 0

local function openTrade(money, items)
    reset(money, items)
    Config.currentTraderName = nil
    Events.onEvent(nil, "TRADE_SHOW")
    Events.onEvent(nil, "TRADE_ACCEPT_UPDATE")
end

-- Order A: completion first, then the window closes.
openTrade(30000, {})
Events.onEvent(nil, "UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)
check(whispered("thanks!"), "completion first should thank the customer")
check(Config.Settings.totalGold == 30000, "completion first should count the gold")
-- Completion consumes the trade. Nothing is in progress afterwards, so anything still holding that
-- generation is answering about a trade that is over.
check(Events.tradeGeneration == 0, "completion should consume the trade generation, got " ..
    tostring(Events.tradeGeneration))

Events.onEvent(nil, "TRADE_CLOSED")
fireTimers()
check(Config.currentTraderName == nil, "the deferred cleanup should leave nothing behind")

-- Order B: the window closes first, completion arrives in the same frame.
openTrade(30000, {})
Events.onEvent(nil, "TRADE_CLOSED")
check(Config.currentTraderName == "Gralint", "closing must not erase the trader before completion")
check(Config.currentTraderMoney == 30000, "closing must not erase the snapshot before completion")

Events.onEvent(nil, "UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)
check(whispered("thanks!"), "close-first order should still thank the customer")
check(Config.Settings.totalGold == 30000, "close-first order should still count the gold")

fireTimers()
check(Config.currentTraderName == nil, "cleanup still runs afterwards")

-- Same again for an item-only tip, since that is the path with no coin to fall back on.
openTrade(0, {{
    name = "Rune of Portals",
    quantity = 20
}})
Events.onEvent(nil, "TRADE_CLOSED")
Events.onEvent(nil, "UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)
check(whispered("thanks!"), "close-first order should thank an item tipper")
check(Config.Settings.itemTipsReceived == 1, "close-first order should count the item tip")
fireTimers()

-- A cancelled trade is cleaned up: closed, never completed.
openTrade(30000, {})
Events.onEvent(nil, "TRADE_CLOSED")
fireTimers()
check(Config.currentTraderName == nil, "a cancelled trade should be forgotten")
check(Config.currentTraderMoney == nil, "a cancelled trade should drop its snapshot")
check(Config.Settings.totalGold == 0, "a cancelled trade must not count as a tip")

-- Cleanup scheduled for an old trade must not erase a newer one.
openTrade(30000, {})
Events.onEvent(nil, "TRADE_CLOSED") -- schedules cleanup for this trade
local staleCleanup = timers
timers = {}

Events.onEvent(nil, "TRADE_SHOW") -- a new trade starts before the old cleanup runs
tradeMoney = 77000
Events.onEvent(nil, "TRADE_ACCEPT_UPDATE")

for _, timer in ipairs(staleCleanup) do
    timer.callback()
end

check(Config.currentTraderName == "Gralint", "a stale cleanup must not erase the new trade's trader")
check(Config.currentTraderMoney == 77000, "a stale cleanup must not erase the new trade's snapshot")

-- The new trade's own cleanup still works.
Events.onEvent(nil, "TRADE_CLOSED")
fireTimers()
check(Config.currentTraderName == nil, "the current trade's own cleanup should still run")

-- 8. Payment is only recorded when something was actually received -----------------------------------

local function completeTradeFor(money, items)
    reset(money, items)
    Events.pendingInvites.Gralint.joinedAt = clock - 30
    Events.captureTradeContents()
    Events.handleTradeComplete()
    return Events.pendingInvites.Gralint
end

-- An empty trade is not payment. Marking it as one made a settled-looking ticket out of nothing and
-- suppressed the unpaid-leave count that AFK protection runs on.
local settled = completeTradeFor(0, {})
check(settled.paidAt == nil, "an empty trade must not record payment, got " .. tostring(settled.paidAt))
check(Utils.isTicketPaid(settled) == false, "an empty trade leaves the ticket unpaid")
check(whispered("safe travels!"), "an empty trade still gets the no-tip message")

-- Every kind of real payment does record it.
settled = completeTradeFor(15000, {})
check(settled.paidAt ~= nil, "a gold tip should record payment")

settled = completeTradeFor(0, {{
    name = "Rune of Portals",
    quantity = 20
}})
check(settled.paidAt ~= nil, "an item tip should record payment")

settled = completeTradeFor(15000, {{
    name = "Arcane Dust",
    quantity = 2
}})
check(settled.paidAt ~= nil, "coin and items together should record payment")

-- Paying does not move the ticket along the service sequence.
check(Utils.getTicketState(settled) == Utils.TICKET_JOINED, "payment must not change the service state, got " ..
    tostring(Utils.getTicketState(settled)))

-- 9. One clock for the lifecycle -----------------------------------------------------------------------

-- The whole point of recording moments is being able to subtract them. That only works if they come
-- from the same clock: portalCastAt was taken from GetTime while everything else used time(), which
-- made every difference between them meaningless.
reset(20000, {})

clock = 1000
local journey = Events.pendingInvites.Gralint
journey.timestamp = clock
-- reset() seeds a joined ticket; clear it so the join is recorded here, since marking is
-- deliberately once-only.
journey.joinedAt = nil

clock = 1030
Utils.markTicketJoined(journey)

clock = 1090
Events.captureTradeContents()
InviteTrade.attributePortalCast("Portal: Ironforge")

clock = 1100
Events.handleTradeComplete()

clock = 1150
Utils.markTicketComplete(journey)

check(journey.joinedAt == 1030, "the join moment should be on the wall clock, got " .. tostring(journey.joinedAt))
check(journey.portalCastAt == 1090, "the portal moment should be on the wall clock, got " ..
    tostring(journey.portalCastAt))
check(journey.paidAt == 1100, "the payment moment should be on the wall clock, got " .. tostring(journey.paidAt))
check(journey.completedAt == 1150, "the completion moment should be on the wall clock, got " ..
    tostring(journey.completedAt))

-- And the durations the model exists to make answerable are numerically right.
check(journey.joinedAt - journey.timestamp == 30, "time from request to joining should be 30s, got " ..
    tostring(journey.joinedAt - journey.timestamp))
check(journey.portalCastAt - journey.joinedAt == 60, "service time should be 60s, got " ..
    tostring(journey.portalCastAt - journey.joinedAt))
check(journey.completedAt - journey.timestamp == 150, "the whole journey should be 150s, got " ..
    tostring(journey.completedAt - journey.timestamp))

clock = 5000

-- ------------------------------------------------------------------------------------------------

_G.print = realPrint

if failures > 0 then
    error(string.format("trade: %d check(s) failed", failures))
end

print("trade: capture, tips, payment semantics, one clock, nil safety and ordering all passed")
