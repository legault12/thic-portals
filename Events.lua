-- Events.lua
local Config = _G.Config
local InviteTrade = _G.InviteTrade
local UI = _G.UI
local Utils = _G.Utils
local Events = {}

_G.Events = Events

Events.pendingInvites = {} -- Table to store pending invites with all relevant data
Events.uiInitialized = false -- Flag to track if UI has been created

-- Example structure:
-- Events.pendingInvites["PlayerName"] = {
--     name = "PlayerName",
--     fullName = "PlayerName-Realm",
--     class = "Warrior",
--     destination = "Darna",
--     joinedAt = nil,   -- set when they accept the invite
--     paidAt = nil,     -- set when a trade completes with payment
--     completedAt = nil, -- set when they are inferred to have taken the portal
--     ticketFrame = nil, -- Reference to the ticket frame for this player
--     targetted = false, -- Whether this player is currently targeted
-- }

local function printEvent(event)
    if Config.Settings then
        Utils.debugPrint(event .. " event fired.")
    end
end

-- Function to initialize UI (called with delay to ensure spellbook is loaded)
function Events.initializeUI()
    if Events.uiInitialized then
        return -- Already initialized
    end

    -- Final verification that spellbook is readable
    local testSpell = GetSpellBookItemName(1, BOOKTYPE_SPELL)
    if not testSpell then
        Utils.print("ERROR: Cannot initialize - spellbook not accessible!")
        return
    end

    -- Mark as initialized
    Events.uiInitialized = true

    Utils.print("Initializing UI with spellbook loaded...")

    -- Print gold info to the console
    Utils.printGoldInformation()

    -- Create the in-game toggle button for the addon
    UI.createToggleButton()

    -- Create the in-game options panel for the addon
    UI.createOptionsPanel()
    UI.hideOptionsPanel()

    -- Create the global interface options panel
    UI.createInterfaceOptionsPanel()

    Utils.print("UI initialization complete!")
end

-- Function to handle consecutive leaves without payment
local function handleConsecutiveLeavesWithoutPayment()
    Config.Settings.consecutiveLeavesWithoutPayment = Config.Settings.consecutiveLeavesWithoutPayment + 1
    Utils.print("Consecutive players who have left the party without payment: " ..
              Config.Settings.consecutiveLeavesWithoutPayment)

    if Config.Settings.consecutiveLeavesWithoutPayment >= Config.Settings.leaveWithoutPaymentThreshold then
        Utils.print("Two people in a row left without payment - you are likely AFK. Shutting down the addon.")
        if Config.Settings.addonEnabled then
            UI.toggleAddonEnabledState()
        end
    end
end

-- Event handler function
function Events.onEvent(self, event, ...)
    if event == "VARIABLES_LOADED" then
        printEvent(event)

        -- Initialize saved variables (doesn't need spellbook)
        Config.initializeSavedVariables()

        -- Reset daily gold if it's a new day
        Utils.resetDailyGoldIfNeeded()

        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
        printEvent(event)

        -- Only initialize UI once, and only after spellbook is available
        if not Events.uiInitialized then
            -- Use a delayed initialization to ensure spellbook is fully loaded
            -- This is especially important on first login when client is freshly started
            C_Timer.After(2, function()
                if Events.uiInitialized then
                    return -- Already initialized
                end

                -- Verify spells are loaded by checking if we can read the spellbook
                local testSpell = GetSpellBookItemName(1, BOOKTYPE_SPELL)
                if not testSpell then
                    -- Spellbook still not ready, try again with longer delay
                    Utils.print("Spellbook not ready yet, waiting...")
                    C_Timer.After(3, function()
                        Events.initializeUI()
                    end)
                    return
                end

                Events.initializeUI()
            end)
        end

        return
    end

    -- If the addon is disabled, don't do anything
    if not Config.Settings.addonEnabled then
        return
    end

    local checkGlobal = false

    if event == "CHAT_MSG_CHANNEL" then
        if not Config.Settings.disableGlobalChannels then
            checkGlobal = true
        else
            Utils.debugPrint("Global channels disabled. Skipping global channel message.")
        end
    end

    if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_PARTY" or
        checkGlobal then
        printEvent(event)

        local args = {...}

        if args[12] then
            local localizedClass, englishClass, localizedRace, englishRace, sex, name, realm = GetPlayerInfoByGUID(
                args[12])
            local message, nameAndServer = args[1], args[2]

            -- Check if addon is enabled
            if message and name then
                -- If name is not "Thicfury" or "Thic", return
                -- if not (name == "Thicfury" or name == "Thic") then
                --     Utils.debugPrint("Ignoring message from: " .. name)
                --     return
                -- end

                local destinationOnly = false

                -- If we are running approach mode, when we are handling say/whisper messages, we should evaluate destination only for a match
                if Config.Settings.ApproachMode and (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_SAY") then
                    destinationOnly = true
                end

                -- Handle the invite and message logic
                InviteTrade.handleInviteAndMessage(nameAndServer, name, englishClass, message, destinationOnly)
            end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        printEvent(event)

        -- Collect senders to remove after iteration to avoid table modification during loop
        local toRemove = {}
        for sender, inviteData in pairs(Events.pendingInvites) do
            if UnitInParty(sender) and not Utils.hasTicketJoined(inviteData) then
                Utils.markTicketJoined(inviteData)

                FlashClientIcon() -- Flash the WoW icon in the taskbar

                UI.showPaginatedTicketWindow(sender, inviteData.destination)

                if inviteData.destination then
                    local message = Utils.replacePlaceholders(Config.Settings.inviteMessage, inviteData.destination)
                    SendChatMessage(message, "WHISPER", nil, inviteData.fullName)
                else
                    SendChatMessage(Config.Settings.inviteMessageWithoutDestination, "WHISPER", nil, inviteData.fullName)
                end
                if Config.Settings.enableFoodWaterSupport then
                    InviteTrade.sendFoodAndWaterStockMessage(inviteData.name, inviteData.class)
                end

                InviteTrade.markSelfWithStar()
                InviteTrade.watchForPlayerProximity(sender)
            elseif not UnitInParty(sender) and Utils.hasTicketJoined(inviteData) then
                table.insert(toRemove, sender)
            end
        end

        -- Now process removals
        for _, sender in ipairs(toRemove) do
            local inviteData = Events.pendingInvites[sender]
            if inviteData and inviteData.ticketFrame then
                inviteData.ticketFrame:Hide()
            end
            Events.pendingInvites[sender] = nil
            InviteTrade.clearTravelAnnouncement(sender)
            Utils.debugPrint(sender .. " has left the party and has been removed from tracking.")
            if not Utils.isTicketPaid(inviteData) and not Config.Settings.disableAFKProtection then
                handleConsecutiveLeavesWithoutPayment()
            end
        end

        -- Update the ticket window after removals
        if UI and UI.ticketList then
            local numTickets = #UI.ticketList or 0

            UI.updateTicketList()

            if numTickets > 0 and UI.ticketFrame then
                -- If current index is out of bounds, move to next available
                if UI.currentTicketIndex > numTickets then
                    UI.currentTicketIndex = numTickets
                end

                UI.updateTicketFrame()

            elseif UI.ticketFrame then
                UI.ticketFrame:Hide()
            end
        end

    elseif event == "TRADE_SHOW" then
        printEvent(event)

        -- Reset the counter when a trade is initiated
        Events.resetConsecutiveLeavesWithoutPaymentCounter()

        Events.beginTrade()

    elseif event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_PLAYER_ITEM_CHANGED" then
        Events.captureTradeContents()

    elseif event == "TRADE_CLOSED" then
        printEvent(event)

        Events.scheduleTradeCleanup()

    elseif event == "TRADE_MONEY_CHANGED" then
        printEvent(event)

        Events.captureTradeContents()

    elseif event == "TRADE_ACCEPT_UPDATE" then
        printEvent(event)

        Events.captureTradeContents()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then
            local spellName = GetSpellInfo(spellID)

            -- Only the teleport this intent was armed for ends it; the whisper itself went out at
            -- the start of the cast, not here.
            InviteTrade.clearTravelAnnouncement(nil, spellName)

            if spellName and spellName:match("^Portal: ") then
                -- Credited to one ticket rather than to the spell, so casting for one customer no
                -- longer flips every ticket wanting that city.
                local servedSender = InviteTrade.attributePortalCast(spellName)

                if servedSender then
                    Utils.debugPrint(spellName .. " cast for " .. servedSender .. ".")

                    UI.updateTicketFrame()

                    -- One refresh when it lapses, so the ticket stops offering a trade for a portal
                    -- that is no longer standing.
                    C_Timer.After(Utils.PORTAL_ALIVE_WINDOW, function()
                        UI.updateTicketFrame()
                    end)
                else
                    Utils.debugPrint(spellName .. " cast, but no waiting ticket matched it.")
                end
            end
        end

    elseif event == "UNIT_SPELLCAST_START" then
        local unit, _, spellID = ...
        if unit == "player" then
            -- Announce as soon as the cast is genuinely under way. A teleport takes about ten
            -- seconds and that is exactly the wait during which a customer gives up and leaves.
            InviteTrade.announceTravelStart(GetSpellInfo(spellID))
        end

    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, _, spellID = ...
        if unit == "player" then
            -- Only when it is the teleport we armed. Any other spell failing during the cast is
            -- unrelated and must not cancel the announcement.
            local failedSpell = GetSpellInfo(spellID)

            InviteTrade.clearTravelAnnouncement(nil, failedSpell)
            InviteTrade.clearPortalCast(nil, failedSpell)
        end

    elseif event == "UI_INFO_MESSAGE" then
        printEvent(event)

        local type, msg = ...
        if (msg == ERR_TRADE_COMPLETE) then
            Events.handleTradeComplete()
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        if UI.ticketFrame and UI.ticketFrame:IsShown() then
            -- Clear existing targetted flags
            for _, inviteData in pairs(Events.pendingInvites) do
                inviteData.targetted = false
            end

            -- Get the name and realm of the current target
            local targetName, targetRealm = UnitName("target", true)
            if targetName then
                -- Check if the target is in the pending invites
                for sender, inviteData in pairs(Events.pendingInvites) do
                    if inviteData.name == targetName then
                        inviteData.targetted = true
                        Utils.debugPrint("Target set to: " .. targetName)

                        break
                    end
                end
            end

            -- Refresh the ticket frame in case we need to change the trade icon
            -- from "target" to "trade" or vice versa
            UI.updateTicketFrame()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Secure button updates are blocked during combat, so replay whatever was deferred.
        UI.flushPendingSecureUpdate()
    end
end

-- Function to reset the consecutive leaves without payment counter
function Events.resetConsecutiveLeavesWithoutPaymentCounter()
    Config.Settings.consecutiveLeavesWithoutPayment = 0
    Utils.debugPrint("Trade initiated. Resetting consecutive leaves without payment counter.")
end

-- Function to store the current trader's information
function Events.storeCurrentTrader()
    Config.currentTraderName, Config.currentTraderRealm = UnitName("NPC", true)
    Utils.debugPrint("Current trader: " .. (Config.currentTraderName or "Unknown"))
end

-- Snapshot what the customer has put in the trade window.
--
-- Taken while the window is open rather than read at completion: by the time ERR_TRADE_COMPLETE
-- arrives the trade is over and its contents are no longer there to inspect. Money already worked
-- this way; items now do too, and the snapshot refreshes on every change so it reflects whatever
-- was on the table when the trade closed.
function Events.captureTradeContents()
    Config.currentTraderMoney = tonumber(GetTargetTradeMoney and GetTargetTradeMoney()) or 0

    local items = {}

    if GetTradeTargetItemInfo then
        for slot = 1, (MAX_TRADE_ITEMS or 6) do
            local name, _, quantity = GetTradeTargetItemInfo(slot)

            if name then
                items[#items + 1] = {
                    name = name,
                    quantity = quantity or 1
                }
            end
        end
    end

    Config.currentTraderItems = items

    Utils.debugPrint("Trade holds " .. Config.currentTraderMoney .. "c and " .. #items .. " item(s).")
end

-- Kept as the old name so nothing that called it breaks.
function Events.updateTradeMoney()
    Events.captureTradeContents()
end

-- Each trade gets an id, so cleanup scheduled for one cannot wipe another.
local tradeGenerationCounter = 0

Events.tradeGeneration = 0

function Events.beginTrade()
    tradeGenerationCounter = tradeGenerationCounter + 1
    Events.tradeGeneration = tradeGenerationCounter

    Events.storeCurrentTrader()
    Events.captureTradeContents()
end

-- Clear what we know about a trade, but only if it is still the one being tracked.
--
-- Passing no generation clears whatever is current, which is what a completed trade wants.
function Events.forgetTrade(generation)
    if generation and generation ~= Events.tradeGeneration then
        Utils.debugPrint("Ignoring cleanup for a trade that is no longer current.")
        return false
    end

    Events.tradeGeneration = 0
    Config.currentTraderName = nil
    Config.currentTraderRealm = nil
    Config.currentTraderMoney = nil
    Config.currentTraderItems = nil

    return true
end

-- Tidy up after the trade window closes, a frame later.
--
-- The window closing and the trade completing are reported separately, and the order is not
-- guaranteed. Clearing immediately would erase the trader and the snapshot before
-- ERR_TRADE_COMPLETE could be handled, so a completed trade would pay nobody and count nothing.
-- Deferring by a frame lets the completion, which clears the generation itself, get there first.
function Events.scheduleTradeCleanup()
    local closing = Events.tradeGeneration

    C_Timer.After(0, function()
        Events.forgetTrade(closing)
    end)
end

-- Function to handle trade completion
function Events.handleTradeComplete()
    if Config.currentTraderName then
        if Events.pendingInvites[Config.currentTraderName] then
            if InviteTrade.checkTradeTip() then
                -- Send them a thank you!
                local message = Utils.replacePlaceholders(Config.Settings.tipMessage,
                    Events.pendingInvites[Config.currentTraderName].destination)
                SendChatMessage(message, "WHISPER", nil, Events.pendingInvites[Config.currentTraderName].fullName)
            else
                local message = Utils.replacePlaceholders(Config.Settings.noTipMessage,
                    Events.pendingInvites[Config.currentTraderName].destination)
                SendChatMessage(message, "WHISPER", nil, Events.pendingInvites[Config.currentTraderName].fullName)
            end

            Utils.markTicketPaid(Events.pendingInvites[Config.currentTraderName])
            Events.forgetTrade()
        else
            Utils.debugPrint("No pending invite found for current trader, ignoring transaction.")
        end
    else
        Utils.debugPrint("No current trader found.")
    end
end

return Events
