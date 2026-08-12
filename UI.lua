-- UI.lua
local Config = _G.Config
local Utils = _G.Utils

local UI = {}

_G.UI = UI

local optionsPanel
local toggleButton
local toggleButtonOverlayTexture

local fixedLabelWidth = 150 -- Set a fixed width for the labels
local maxTicketsEditBox = nil

local AceGUI = LibStub("AceGUI-3.0") -- Use LibStub to load AceGUI

if not AceGUI then
    print("Error: AceGUI-3.0 is not loaded properly.")
    return UI
end

-- Initialize saved variables to Config (Version 1.3.0)
UI.hideIconCheckbox = AceGUI:Create("CheckBox")
UI.approachModeCheckbox = AceGUI:Create("CheckBox");
UI.enableFoodWaterSupportCheckbox = AceGUI:Create("CheckBox");
UI.disableSmartMatchingCheckbox = AceGUI:Create("CheckBox");
UI.requireDestinationCheckbox = AceGUI:Create("CheckBox");
UI.removeRealmFromInviteCommandCheckbox = AceGUI:Create("CheckBox");
UI.addonEnabledCheckbox = AceGUI:Create("CheckBox");
UI.disableGlobalChannelsCheckbox = AceGUI:Create("CheckBox");
UI.disableAFKProtectionCheckbox = AceGUI:Create("CheckBox");
UI.soundEnabledCheckbox = AceGUI:Create("CheckBox");
UI.debugModeCheckbox = AceGUI:Create("CheckBox");

-- Paginated Ticket Window State
UI.ticketFrame = nil
UI.ticketList = {}
UI.currentTicketIndex = 1

-- Helper to update the ticket frame with current ticket
local currentTicker = nil

local function addCheckbox(group, label, checkbox, initialValue, callback, tooltipText)
    -- Add spacer between checkboxes
    local spacer = AceGUI:Create("Label")
    spacer:SetWidth(30)
    group:AddChild(spacer)

    -- Create checkbox
    checkbox:SetLabel(label)
    checkbox:SetValue(initialValue)
    checkbox:SetCallback("OnValueChanged", callback)
    checkbox:SetWidth(300)
    group:AddChild(checkbox)

    -- Add tooltip functionality
    if tooltipText then
        checkbox:SetCallback("OnEnter", function()
            GameTooltip:SetOwner(checkbox.frame, "ANCHOR_TOPRIGHT")
            -- SetText takes (text, r, g, b, alpha, wrap) - unlike AddLine, whose wrap flag is the
            -- fifth argument. Passing the wrap boolean as alpha errors on every checkbox hover.
            GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)

        checkbox:SetCallback("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Add tiny vertical gap
    local tinyVerticalGap = AceGUI:Create("Label")
    tinyVerticalGap:SetText("")
    tinyVerticalGap:SetFullWidth(true)
    group:AddChild(tinyVerticalGap)
end

-- Helper function to create a label-value pair with a fixed label width and bold value
local function addLabelValuePair(labelText, valueText)
    local group = AceGUI:Create("SimpleGroup")
    group:SetFullWidth(true)
    group:SetLayout("Flow")

    local spacer = AceGUI:Create("Label")
    spacer:SetWidth(30)
    group:AddChild(spacer)

    local label = AceGUI:Create("Label")
    label:SetText(labelText)
    label:SetWidth(fixedLabelWidth)
    group:AddChild(label)

    local value = AceGUI:Create("Label")
    value:SetText("|cFFFFD700" .. valueText .. "|r") -- Make the value bold
    group:AddChild(value)

    return group
end

-- Helper function to create a label and small edit that only needs to support 6 number digits
local function addNumberEditBox(labelText, numberVar, callback)
    local group = AceGUI:Create("SimpleGroup")
    group:SetFullWidth(true)
    group:SetLayout("Flow")

    -- Add spacer between checkboxes
    local spacer = AceGUI:Create("Label")
    spacer:SetWidth(30)
    group:AddChild(spacer)

    -- Create a label element with the formatted copper value (0g, 0s, 0c) that updates after the user confirms a new numberVar value
    local valueLabel = AceGUI:Create("Label")
    valueLabel:SetText(Utils.formatCopperValue(numberVar) .. " each (20x " .. Utils.formatCopperValue(numberVar * 20) ..
                           ")")
    valueLabel:SetWidth(100)

    -- Create an edit box for the number
    local editBox = AceGUI:Create("EditBox")
    editBox:SetText(numberVar)
    editBox:SetWidth(150)
    editBox:SetLabel(labelText)
    editBox:SetCallback("OnEnterPressed", function(_, _, text)
        local value = tonumber(text)
        callback(value)
        valueLabel:SetText(Utils.formatCopperValue(value) .. " each (20x " .. Utils.formatCopperValue(value * 20) .. ")")
    end)
    group:AddChild(editBox)

    -- Add spacer between checkboxes
    local spacer = AceGUI:Create("Label")
    spacer:SetWidth(10)
    group:AddChild(spacer)

    -- Finally add the value label
    group:AddChild(valueLabel)

    return group
end

-- Helper function to add price edit boxes for a category (food or water)
-- Now smart: only shows items the player can actually conjure
local function addPriceEditBoxes(group, category, prices)
    local items = {}

    -- Get the list of items based on category
    if category == "Food" then
        items = Utils.getAvailableFoodItems()
    elseif category == "Water" then
        items = Utils.getAvailableWaterItems()
    end

    -- If no items are available, show a message
    if #items == 0 then
        local noItemsLabel = AceGUI:Create("Label")
        noItemsLabel:SetText("|cFFFF6B6BNo " .. category:lower() .. " spells known yet.|r")
        noItemsLabel:SetFullWidth(true)
        group:AddChild(noItemsLabel)
        return
    end

    -- Create edit boxes for each available item
    for _, item in ipairs(items) do
        local priceEditBox = addNumberEditBox(item.name .. ":", item.price, function(value)
            -- Update the price in both the new structure and legacy structure
            item.price = value
            if prices and prices[item.name] then
                prices[item.name] = value
            end
            Utils.print("" .. item.name .. " price updated to " .. value .. ".")
        end)
        group:AddChild(priceEditBox)
    end
end

-- Helper function to create a label and editbox pair
local function addMessageMultiLineEditBox(labelText, messageVar, callback)
    local group = AceGUI:Create("SimpleGroup")
    group:SetFullWidth(true)
    group:SetLayout("Flow")

    local editBoxGroup = AceGUI:Create("SimpleGroup")
    editBoxGroup:SetFullWidth(true)
    editBoxGroup:SetLayout("Flow")

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetText(messageVar)
    editBox:SetFullWidth(true)
    editBox:SetNumLines(3)
    editBox:SetLabel(labelText)

    -- Callback for when the text changes
    editBox:SetCallback("OnTextChanged", function(widget, _, text)
        if #text > 255 then
            -- Truncate the text to 255 characters
            widget:SetText(string.sub(text, 1, 255))
        end
    end)

    -- Callback for when Enter is pressed
    editBox:SetCallback("OnEnterPressed", function(_, _, text)
        if #text > 255 then
            text = string.sub(text, 1, 255) -- Ensure no overflow
        end
        callback(text)
    end)

    editBoxGroup:AddChild(editBox)
    group:AddChild(editBoxGroup)

    return group
end

-- Function to set the min width allowed of a frame
local function setMinWidth(frame, minWidth)
    frame.frame:SetScript("OnSizeChanged", function(self, width, height)
        if width < minWidth then
            frame:SetWidth(minWidth)
        end
    end)
end

-- Function to update the button text and color of the interface configuration options
function UI.toggleAddonEnabledState()
    Config.Settings.addonEnabled = not Config.Settings.addonEnabled -- Toggle the state

    if Config.Settings.addonEnabled then
        toggleButtonOverlayTexture:SetTexture("Interface\\AddOns\\ThicPortals\\Media\\Logo\\thicportalsopen.tga") -- Replace with the path to your image
        UI.addonEnabledCheckbox:SetValue(true)
        Utils.print("The portal shop is open!")

        -- Say the stock out loud on opening, good or bad: running dry mid-session stops the shop.
        Utils.checkAllReagentStock(true)
    else
        toggleButtonOverlayTexture:SetTexture("Interface\\AddOns\\ThicPortals\\Media\\Logo\\thicportalsclosed.tga") -- Replace with the path to your image
        UI.addonEnabledCheckbox:SetValue(false)
        Utils.print("You closed the shop.")

        -- Clear any tracked players and their data
        Events.pendingInvites = {}
    end
end

-- Function to create the toggle button
function UI.createToggleButton()
    toggleButton = CreateFrame("Button", "ToggleButton", UIParent, "UIPanelButtonTemplate")
    toggleButton:SetSize(64, 64) -- Width, Height

    -- Set the point using the saved position in the config or default to 0, 200
    toggleButton:SetPoint(Config.Settings.toggleButtonPosition.point or "CENTER",
        Config.Settings.toggleButtonPosition.x or 0, Config.Settings.toggleButtonPosition.y or 200)

    -- Disable the default draw layers to hide the button's default textures
    toggleButton:DisableDrawLayer("BACKGROUND")
    toggleButton:DisableDrawLayer("BORDER")
    toggleButton:DisableDrawLayer("ARTWORK")

    -- Make the button moveable
    toggleButton:SetMovable(true)
    toggleButton:EnableMouse(true)
    toggleButton:RegisterForDrag("LeftButton")
    toggleButton:SetScript("OnDragStart", toggleButton.StartMoving)
    toggleButton:SetScript("OnDragStop", toggleButton.StopMovingOrSizing)

    -- Create the background texture
    toggleButtonOverlayTexture = toggleButton:CreateTexture(nil, "OVERLAY")
    toggleButtonOverlayTexture:SetTexture("Interface\\AddOns\\ThicPortals\\Media\\Logo\\thicportalsclosed.tga") -- Replace with the path to your image
    toggleButtonOverlayTexture:SetAllPoints(toggleButton)
    toggleButtonOverlayTexture:SetTexCoord(0, 1, 1, 0)

    -- Script to handle button clicks
    toggleButton:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            UI.toggleAddonEnabledState() -- Update the button text
        elseif button == "RightButton" then
            -- If debug mode log the current options panel state
            Utils.debugPrint("Options Panel Hidden: " .. tostring(Config.Settings.optionsPanelHidden))

            if Config.Settings.optionsPanelHidden then
                UI.showOptionsPanel()
            else
                UI.hideOptionsPanel()
            end
        end
    end)

    -- Script to handle dragging
    toggleButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        -- Get the current position
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()

        -- If debug mode is enabled, print the position
        Utils.debugPrint("Icon moved to Point: " .. point)
        Utils.debugPrint("Icon moved to X: " .. xOfs)
        Utils.debugPrint("Icon moved to Y: " .. yOfs)

        -- Save the position in the config
        Config.Settings.toggleButtonPosition = {
            point = point,
            x = xOfs,
            y = yOfs
        }
    end)

    -- Save the button reference in the config for other modules to use
    UI.toggleButton = toggleButton

    -- If hideIcon is true, toggleButton should be set to hidden
    if Config.Settings.hideIcon then
        UI.toggleButton:Hide()
    end
end

-- Function to apply an icon texture representing the portal spell attributed to the button
-- SetAttribute and SetEnabled on a SecureActionButtonTemplate are protected while in combat.
-- Run the update now if we can, otherwise stash it and replay it on PLAYER_REGEN_ENABLED.
-- Only the most recent update is kept, since each one rebuilds the button from scratch.
UI.pendingSecureUpdates = {}

-- Defer a protected-frame mutation past combat, keyed by what it touches.
--
-- Keyed rather than a single slot: one ticket refresh updates both the portal button and the
-- travel button, and a single slot meant the second call silently discarded the first - leaving a
-- button shown with a stale spell assigned to it.
function UI.runWhenOutOfCombat(key, updateFunction)
    if InCombatLockdown() then
        UI.pendingSecureUpdates[key] = updateFunction
        return false
    end

    UI.pendingSecureUpdates[key] = nil
    updateFunction()
    return true
end

-- Called on PLAYER_REGEN_ENABLED to apply whatever was deferred during combat.
function UI.flushPendingSecureUpdate()
    -- Replay what combat deferred BEFORE building any window that combat also deferred.
    --
    -- The other order lets a callback captured from the old ticket land on a window created a
    -- moment ago and undo it: an unconditional hideTravelButton carries no sender, so the
    -- staleness check cannot catch it, and it would clear a brand new ticket's valid travel
    -- action. Replayed first, these either no-op or act on the outgoing frame, and the window
    -- refresh below is then the authoritative final state.
    local pending = UI.pendingSecureUpdates
    UI.pendingSecureUpdates = {}

    for key, updateFunction in pairs(pending) do
        Utils.debugPrint("Leaving combat - applying deferred secure update: " .. key)
        updateFunction()
    end

    if UI.pendingTicketWindow then
        UI.pendingTicketWindow = nil
        UI.showPaginatedTicketWindow()
    end
end

function UI.setIconSpellTexture(actionButton, portal)
    if not actionButton.icon then
        -- Apply the icon texture to the button
        local icon = actionButton:CreateTexture(nil, "BACKGROUND")

        icon:SetAllPoints()

        actionButton.icon = icon
    end

    -- If portal.matched === false, the player's destination did not match any known portal so disable the button
    if portal.matched then
        -- Enable the button
        actionButton:SetEnabled(true)

        -- Get the icon texture for the portal spell
        local iconTexture = GetSpellTexture(portal.spellID)
        if iconTexture then
            -- Set the icon texture for the portal spell
            actionButton.icon:SetTexture(iconTexture)

            -- Set the icon to full color
            actionButton.icon:SetDesaturated(false)
        else
            print("Error: Could not fetch icon for spell name " .. portal.spellName)
        end
    else
        -- Disable the button
        actionButton:SetEnabled(false)

        -- Set the icon to a question mark
        actionButton.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        -- Grey it out
        actionButton.icon:SetDesaturated(true)
    end
end

function UI.setIconSpell(inviteData, destination)
    -- Set up secure actions for casting the spell
    inviteData.actionButton:SetAttribute("type", "spell")
    inviteData.actionButton:SetAttribute("spell", inviteData.portal.spellName)
    inviteData.actionButton:SetScript("OnEnter", nil)
    inviteData.actionButton:SetScript("OnLeave", nil)

    if inviteData.portal.matched then
        Utils.debugPrint("Setting icon spell for " .. destination)
    end

    -- Set the icon texture for the portal spell
    UI.setIconSpellTexture(inviteData.actionButton, inviteData.portal)

    -- The button had no tooltip at all. Naming the spell and the reagents left is the cheapest
    -- place to notice you are about to run dry.
    inviteData.actionButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")

        if inviteData.portal.matched then
            GameTooltip:SetText(inviteData.portal.spellName)
        else
            GameTooltip:SetText("No portal matches this destination")
        end

        local runes = Utils.getReagentCount("portal")

        if runes > 0 then
            GameTooltip:AddLine(Utils.REAGENTS.portal.name .. ": " .. runes, 0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine("No " .. Utils.REAGENTS.portal.name .. " - " .. Utils.REAGENTS.portal.casts ..
                                    " will fail.", 1, 0.3, 0.3, true)
        end

        GameTooltip:Show()
    end)

    inviteData.actionButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function UI.setTradeIcon(inviteData)
    -- If debug, log the action
    Utils.debugPrint("Setting trade icon for " .. inviteData.name)

    if not inviteData.actionButton.icon then
        -- Create the icon texture if it doesn't exist
        local icon = inviteData.actionButton:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        inviteData.actionButton.icon = icon
    end
    if inviteData.targetted then
        -- Update the icon texture to a "trade" icons
        inviteData.actionButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01") -- Example trade icon

        -- If the player is already targeted, enable /trade
        inviteData.actionButton:SetAttribute("type", "macro")
        inviteData.actionButton:SetAttribute("macrotext", "/trade")
        inviteData.actionButton:SetEnabled(true)
        inviteData.actionButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Click to trade with " .. inviteData.name)
            GameTooltip:Show()
        end)
    else
        -- Update the icon texture to a "target" icon (use hunter's mark)
        inviteData.actionButton.icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot") -- Example target icon

        -- Otherwise, clicking will target the player
        inviteData.actionButton:SetAttribute("type", "macro")
        inviteData.actionButton:SetAttribute("macrotext", "/target " .. inviteData.name)
        inviteData.actionButton:SetEnabled(true)
        inviteData.actionButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Click to target " .. inviteData.name .. ". Then click again to trade.")
            GameTooltip:Show()
        end)
    end

    inviteData.actionButton.icon:SetDesaturated(false)

    inviteData.actionButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

-- Roughly two wrapped lines at the ticket's width. Anything longer is trimmed and the full
-- text stays available on hover, so the ticket never grows unpredictably tall.
local REQUEST_TEXT_MAX_CHARS = 60
local DESTINATION_CHIP_SPACING = 4
local DESTINATION_CHIP_PADDING = 6 -- breathing room either side of a chip's text
local DESTINATION_CHIP_MAX = 4 -- past four locations a message is an advert, not a request
local DESTINATION_ROW_WIDTH = 180 -- the chip row cannot wrap: distanceLabel sits a fixed 28px below

local function utf8Prefix(text, maxBytes)
    local position = 1
    local lastComplete = 0

    while position <= #text and position <= maxBytes do
        local firstByte = text:byte(position)
        local characterBytes = 1

        if firstByte >= 240 then
            characterBytes = 4
        elseif firstByte >= 224 then
            characterBytes = 3
        elseif firstByte >= 194 then
            characterBytes = 2
        end

        if position + characterBytes - 1 > maxBytes then
            break
        end

        lastComplete = position + characterBytes - 1
        position = position + characterBytes
    end

    return text:sub(1, lastComplete)
end

local function truncateForDisplay(text, maxChars)
    if #text <= maxChars then
        return text
    end

    local cut = utf8Prefix(text, maxChars)

    -- Prefer breaking on a word boundary, but only if it does not throw away most of the text.
    local lastSpace = cut:find("%s[^%s]*$")
    if lastSpace and lastSpace > maxChars * 0.6 then
        cut = cut:sub(1, lastSpace - 1)
    end

    return cut .. "..."
end

-- Show the customer's own words on the ticket, so the user never has to scroll trade chat
-- back to work out what was actually asked for.
function UI.updateRequestText(inviteData)
    local ticketFrame = UI.ticketFrame

    if not ticketFrame or not ticketFrame.requestText then
        return
    end

    local message = inviteData.originalMessage

    if not message or message == "" then
        ticketFrame.requestText:SetText("|cff808080(no request recorded)|r")
        ticketFrame.requestHitBox.message = nil
        return
    end

    ticketFrame.requestText:SetText("\"" .. truncateForDisplay(message, REQUEST_TEXT_MAX_CHARS) .. "\"")
    ticketFrame.requestHitBox.message = message
end

-- Destination chips. When a request names more than one city we cannot know which the customer
-- meant, so show every candidate and let the user pick. Buttons are pooled on the ticket frame
-- and reused, because frames cannot be destroyed once created.
local function acquireDestinationChip(ticketFrame, index)
    ticketFrame.destinationChips = ticketFrame.destinationChips or {}

    local chip = ticketFrame.destinationChips[index]

    if not chip then
        chip = CreateFrame("Button", nil, ticketFrame.labelContainer)
        chip:SetHeight(14)

        local label = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetWordWrap(false)
        chip.label = label

        local highlight = chip:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        highlight:SetBlendMode("ADD")

        ticketFrame.destinationChips[index] = chip
    end

    return chip
end

local function hideDestinationChipsFrom(ticketFrame, fromIndex)
    if not ticketFrame.destinationChips then
        return
    end

    for i = fromIndex, #ticketFrame.destinationChips do
        ticketFrame.destinationChips[i]:Hide()
    end
end

-- A hidden FontString in the chip font, so candidate widths can be measured without disturbing a
-- chip that is currently on screen.
local function measureChipWidth(ticketFrame, text)
    if not ticketFrame.chipMeasure then
        local measure = ticketFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        measure:Hide()
        ticketFrame.chipMeasure = measure
    end

    ticketFrame.chipMeasure:SetWidth(0)
    ticketFrame.chipMeasure:SetText(text)

    return ticketFrame.chipMeasure:GetStringWidth() + DESTINATION_CHIP_PADDING
end

-- Greedy left-to-right pack. A candidate that does not fit is skipped rather than ending the pack,
-- because a later, shorter keyword may still have room. Index 1 is always placed: callers put the
-- selected destination there so the current pick can never be the one squeezed out.
local function packDestinationChips(ticketFrame, ordered, reserve)
    local picked, omitted, used = {}, {}, 0

    for index, candidate in ipairs(ordered) do
        local width = measureChipWidth(ticketFrame, candidate.keyword)

        -- Index 1 is placed whether or not it fits, so an oversized custom keyword would otherwise
        -- push the overflow chip past the edge of the frame. Clamp it to what the row can give.
        if index == 1 then
            width = math.max(1, math.min(width, DESTINATION_ROW_WIDTH - reserve))
        end

        local spacing = (#picked > 0) and DESTINATION_CHIP_SPACING or 0
        local fits = (used + spacing + width + reserve) <= DESTINATION_ROW_WIDTH

        if index == 1 or (#picked < DESTINATION_CHIP_MAX and fits) then
            picked[#picked + 1] = {
                keyword = candidate.keyword,
                width = width,
                offset = used + spacing
            }
            used = used + spacing + width
        else
            omitted[#omitted + 1] = candidate.keyword
        end
    end

    return picked, omitted, used
end

local function hideOverflowMenu(ticketFrame)
    if ticketFrame.overflowMenu then
        ticketFrame.overflowMenu:Hide()
    end
end

-- The destinations with no room in the row are still choices, so the "+N" chip opens them as a
-- list rather than just reporting them. Picking one makes it the selected destination, and the
-- selected destination is always packed first, so it takes a place in the row immediately.
local function showOverflowMenu(ticketFrame, anchorChip, keywords, onSelect)
    local menu = ticketFrame.overflowMenu

    if not menu then
        menu = CreateFrame("Frame", nil, ticketFrame, "BackdropTemplate")
        menu:SetFrameStrata("DIALOG")
        menu:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = {
                left = 3,
                right = 3,
                top = 3,
                bottom = 3
            }
        })
        -- Fully opaque, and above every layer of the ticket: the request text sits directly
        -- underneath and showed through at 0.95.
        menu:SetBackdropColor(0, 0, 0, 1)
        menu:SetFrameLevel(ticketFrame:GetFrameLevel() + 10)
        menu:EnableMouse(true)
        menu:Hide()
        menu.rows = {}
        ticketFrame.overflowMenu = menu
    end

    local rowHeight = 14
    local widest = 0

    for index, keyword in ipairs(keywords) do
        local row = menu.rows[index]

        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(rowHeight)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", 6, 0)
            label:SetJustifyH("LEFT")
            row.label = label

            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
            highlight:SetBlendMode("ADD")

            menu.rows[index] = row
        end

        row.label:SetWidth(0)
        row.label:SetText(keyword)
        row.label:SetTextColor(0.5, 0.5, 0.5)

        row:SetScript("OnClick", function()
            menu:Hide()
            onSelect(keyword)
        end)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -(4 + (index - 1) * rowHeight))
        row:Show()

        widest = math.max(widest, row.label:GetStringWidth() + 12)
    end

    for index = #keywords + 1, #menu.rows do
        menu.rows[index]:Hide()
    end

    for index = 1, #keywords do
        menu.rows[index]:SetWidth(widest)
    end

    menu:SetSize(widest + 8, #keywords * rowHeight + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchorChip, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

-- Apply the travel button's protected state.
--
-- SetAttribute, Show and Hide are all protected, so they belong in ONE deferred update: splitting
-- them risked a button that is visible with no action, or worse, visible with a stale teleport.
-- By the time a deferred update runs the ticket may have paged to another customer, so it
-- re-checks the sender before touching anything. Passing no spell clears the action as well as
-- hiding, so nothing stale survives to be cast if the button is shown again.
local function applyTravelState(sender, teleportSpell, zoneName, city)
    UI.runWhenOutOfCombat("travelButton", function()
        local ticketFrame = UI.ticketFrame

        if not ticketFrame or not ticketFrame.travelButton then
            return
        end

        -- Stale: the displayed ticket changed while this waited for combat to end.
        if sender and ticketFrame.currentSender ~= sender then
            return
        end

        local travelButton = ticketFrame.travelButton

        if not teleportSpell then
            travelButton:SetAttribute("type", nil)
            travelButton:SetAttribute("spell", nil)
            travelButton:SetScript("OnEnter", nil)
            travelButton:SetScript("PreClick", nil)
            travelButton:Hide()

            -- The trip this ticket was going to announce is no longer on offer.
            InviteTrade.clearTravelAnnouncement(sender)
            return
        end

        travelButton:SetAttribute("type", "spell")
        travelButton:SetAttribute("spell", teleportSpell)

        local texture = GetSpellTexture(teleportSpell)

        if texture then
            travelButton.icon:SetTexture(texture)
        end

        travelButton:SetScript("OnEnter", function(self)
            local runes = Utils.getReagentCount("teleport")

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(teleportSpell)
            GameTooltip:AddLine((sender or "The customer") .. " is in " .. (zoneName or "another zone") ..
                                    ". Click to travel to them.", 1, 1, 1, true)

            if runes > 0 then
                GameTooltip:AddLine(Utils.REAGENTS.teleport.name .. ": " .. runes, 0.6, 0.6, 0.6, true)
            else
                GameTooltip:AddLine("No " .. Utils.REAGENTS.teleport.name .. " - " ..
                                        Utils.REAGENTS.teleport.casts .. " will fail.", 1, 0.3, 0.3, true)
            end

            GameTooltip:Show()
        end)

        -- PreClick, not PostClick: the secure action starts the cast on click, and
        -- UNIT_SPELLCAST_START can dispatch before a PostClick handler ever runs - the
        -- announcement would then arrive too late and miss its own cast.
        travelButton:SetScript("PreClick", function()
            local inviteData = Events.pendingInvites[sender]

            if not inviteData then
                return
            end

            InviteTrade.beginTravelAnnouncement(sender, inviteData, city, teleportSpell)
        end)

        travelButton:Show()
    end)
end

-- Refresh the waiting time on the displayed ticket. Called on every ticket refresh and once a
-- second by the same ticker that drives the location line.
function UI.updateWaitLabel(sender)
    local ticketFrame = UI.ticketFrame

    if not ticketFrame or not ticketFrame.waitValue then
        return
    end

    local inviteData = Events.pendingInvites[sender]

    if not inviteData or not inviteData.timestamp then
        ticketFrame.waitValue:SetText("")
        return
    end

    ticketFrame.waitValue:SetText(Utils.formatWaitTime(time() - inviteData.timestamp))
end

function UI.hideTravelButton()
    -- No sender: unconditional, for when the customer has gone entirely.
    applyTravelState(nil, nil, nil)
end

-- The location line, and the travel shortcut that may sit beside it.
--
-- While the customer is in the same zone the line keeps showing a distance, which is the useful
-- number then. Once they are somewhere else the distance is meaningless - often "Unknown" across
-- a continent - so the line says where they actually are instead, which is the thing you would
-- otherwise go and read off the party frame.
--
-- The travel button appears only when all of it checks out: we can resolve them to a party unit,
-- they are elsewhere, that somewhere is a city with a portal spell, and the mage genuinely knows
-- the teleport for it.
function UI.updateLocationLine(sender, distanceLabel)
    -- C_Map wants a unit token; a player name resolves for UnitInParty but not for the map calls.
    local unit = Utils.getPartyUnitToken(sender)
    local customerZone = unit and Utils.getUnitZoneName(unit)
    local playerZone = Utils.getUnitZoneName("player")

    if not customerZone or not playerZone or customerZone == playerZone then
        local playerX, playerY, playerInstanceID = UnitPosition("player")
        local targetX, targetY, targetInstanceID = UnitPosition(unit or sender)

        if playerX and targetX and playerInstanceID == targetInstanceID then
            distanceLabel:SetText(string.format("Distance: %.1f yards",
                Utils.calculateDistance(playerX, playerY, targetX, targetY)))
        else
            distanceLabel:SetText("Distance: Unknown")
        end

        UI.hideTravelButton()
        return
    end

    distanceLabel:SetText("In: " .. customerZone)

    local city = Utils.resolveCityFromZoneName(customerZone)

    applyTravelState(sender, city and Utils.getKnownTeleportSpell(city) or nil, customerZone, city)
end


function UI.updateDestinationChoices(sender, inviteData, currentCity)
    local ticketFrame = UI.ticketFrame

    if not ticketFrame or not ticketFrame.destinationLabel then
        return
    end

    -- Any open overflow list belongs to the layout we are about to replace.
    hideOverflowMenu(ticketFrame)

    -- Aliases for one city ("sw" and "stormwind") collapse to a single chip, but only when both
    -- resolve through the explicit map - see Utils.dedupeDestinationCandidates.
    local candidates = Utils.rejectCurrentCityCandidates(Utils.dedupeDestinationCandidates(
        Utils.findAllKeywordPositions(inviteData.originalMessage, Config.Settings.DestinationKeywords),
        inviteData.destination), currentCity)

    -- Filtering the standing city can leave the selected destination off the row. When that
    -- happens the plain label stays visible so the current pick is still readable, and even a
    -- single remaining chip is worth showing - it is the correction being offered.
    local selectionOffered = false

    for _, candidate in ipairs(candidates) do
        if candidate.keyword == inviteData.destination then
            selectionOffered = true
        end
    end

    -- Nothing to disambiguate: one candidate and it is already what we are casting.
    if #candidates < 2 and selectionOffered then
        ticketFrame.destinationValue:Show()
        hideDestinationChipsFrom(ticketFrame, 1)
        return
    end

    if #candidates == 0 then
        ticketFrame.destinationValue:Show()
        hideDestinationChipsFrom(ticketFrame, 1)
        return
    end

    -- Selected destination first so it is never the one dropped; the rest follow in the order the
    -- customer named them.
    local ordered = {}

    for _, candidate in ipairs(candidates) do
        if inviteData.destination == candidate.keyword then
            ordered[#ordered + 1] = candidate
        end
    end

    for _, candidate in ipairs(candidates) do
        if inviteData.destination ~= candidate.keyword then
            ordered[#ordered + 1] = candidate
        end
    end

    -- Reserving room for the overflow chip can push a further candidate out, which changes the
    -- number the chip has to report. Re-pack until the count settles; adding reserve only ever
    -- removes chips, so this converges.
    local picked, omitted, usedWidth = packDestinationChips(ticketFrame, ordered, 0)

    -- Bounded fixed point: each pass can only omit more, so it settles in at most #ordered steps.
    for _ = 1, #ordered do
        if #omitted == 0 then
            break
        end

        local previous = #omitted
        local reserve = DESTINATION_CHIP_SPACING + measureChipWidth(ticketFrame, "+" .. previous)

        picked, omitted, usedWidth = packDestinationChips(ticketFrame, ordered, reserve)

        if #omitted == previous then
            break
        end
    end

    -- A lone chip with nothing beside it is not a choice - unless it is the correction we are
    -- offering because the selected destination was filtered out.
    if #picked < 2 and #omitted == 0 and selectionOffered then
        ticketFrame.destinationValue:Show()
        hideDestinationChipsFrom(ticketFrame, 1)
        return
    end

    -- Keep the label when the row cannot show the current pick, so it is never invisible.
    if selectionOffered then
        ticketFrame.destinationValue:Hide()
    else
        ticketFrame.destinationValue:Show()
    end

    for index, entry in ipairs(picked) do
        local chip = acquireDestinationChip(ticketFrame, index)
        local keyword = entry.keyword

        chip.label:SetWidth(0)
        chip.label:SetText(keyword)

        if inviteData.destination == keyword then
            chip.label:SetTextColor(1, 0.82, 0) -- gold: the destination we will cast
        else
            chip.label:SetTextColor(0.5, 0.5, 0.5) -- grey: an alternative the request also named
        end

        chip:SetWidth(entry.width)
        chip.label:SetWidth(entry.width)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", ticketFrame.destinationLabel, "BOTTOMLEFT", entry.offset, -4)

        chip:SetScript("OnClick", function()
            if inviteData.destination == keyword then
                inviteData.destinationLocked = true
                Utils.print("Destination for " .. sender .. " confirmed as " .. keyword .. ".")
                return
            end

            inviteData.destination = keyword
            -- Stop a later whisper from silently overwriting a deliberate choice.
            inviteData.destinationLocked = true

            Utils.print("Destination for " .. sender .. " set to " .. keyword .. ".")

            UI.updateTicketFrame()
        end)

        chip:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Send " .. sender .. " to " .. keyword)
            GameTooltip:AddLine("This request named more than one location - click to choose.", 1, 1, 1,
                true)
            GameTooltip:Show()
        end)

        chip:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        chip:Show()
    end

    local nextChipIndex = #picked + 1

    -- Never cap silently. debugPrint is off for normal users and the request text is truncated, so
    -- the row itself has to say that choices were left off, and name them on hover.
    if #omitted > 0 then
        local chip = acquireDestinationChip(ticketFrame, nextChipIndex)
        local label = "+" .. #omitted
        local width = measureChipWidth(ticketFrame, label)
        local omittedList = table.concat(omitted, ", ")

        chip.label:SetWidth(0)
        chip.label:SetText(label)
        chip.label:SetTextColor(0.5, 0.5, 0.5)
        chip:SetWidth(width)
        chip.label:SetWidth(width)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", ticketFrame.destinationLabel, "BOTTOMLEFT",
            usedWidth + DESTINATION_CHIP_SPACING, -4)

        -- These are still real choices, so the chip opens them as a list. Picking one makes it the
        -- selected destination, and the selected destination is packed first, so it takes a place
        -- in the row straight away.
        chip:SetScript("OnClick", function(self)
            if ticketFrame.overflowMenu and ticketFrame.overflowMenu:IsShown() then
                hideOverflowMenu(ticketFrame)
                return
            end

            showOverflowMenu(ticketFrame, self, omitted, function(keyword)
                inviteData.destination = keyword
                -- Stop a later whisper from silently overwriting a deliberate choice.
                inviteData.destinationLocked = true

                Utils.print("Destination for " .. sender .. " set to " .. keyword .. ".")

                UI.updateTicketFrame()
            end)
        end)

        chip:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(#omitted .. " more named - click to choose")
            GameTooltip:AddLine(omittedList, 1, 1, 1, true)
            GameTooltip:Show()
        end)

        chip:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        chip:Show()

        nextChipIndex = nextChipIndex + 1

        Utils.debugPrint("Showing " .. #picked .. " of " .. #candidates ..
                             " destinations named in this request; omitted: " .. omittedList)
    end

    hideDestinationChipsFrom(ticketFrame, nextChipIndex)
end

-- Helper to update ticketList from pendingInvites
function UI.updateTicketList()
    -- Oldest request first, following the customer being handled rather than the position they
    -- happened to occupy: the queue reorders underneath as tickets come and go, and paging out from
    -- under the user mid-click is how you cast the wrong portal.
    local displayedSender = UI.ticketFrame and UI.ticketFrame.currentSender

    UI.ticketList, UI.currentTicketIndex, UI.totalTickets = Utils.buildTicketQueue(Events.pendingInvites,
        displayedSender, UI.currentTicketIndex)

    UI.refreshQueueOverview()

    if Config.Settings then
        Utils.debugPrint("Total ticket count updated: " .. tostring(UI.totalTickets))
    end
end

-- Function to update the ticket frame with the current ticket data
function UI.updateTicketFrame()
    -- This code will hide the ticket frame if there are no tickets
    if #UI.ticketList == 0 then
        Utils.cancelDistanceTicker()

        if UI.ticketFrame then
            UI.ticketFrame:Hide()
        end
        return
    end

    -- e.g. sender === "Thic"
    local sender = UI.ticketList[UI.currentTicketIndex]
    local inviteData = Events.pendingInvites[sender]

    if not inviteData then
        return
    end

    -- Where the customer is standing refines which choices we offer. It never changes which
    -- destination the ticket has selected: only the user picking a chip does that.
    local currentCity = Utils.getCustomerCity(sender)

    local destination = inviteData.destination or "Requesting..."

    -- Update all relevant UI elements
    UI.ticketFrame.senderValue:SetText(sender)
    UI.ticketFrame.destinationValue:SetText(destination)
    UI.ticketFrame.currentSender = sender -- Track which sender's distance is being displayed
    Utils.updateDistanceLabel(sender, UI.ticketFrame.distanceLabel)
    -- Update ticket index in title
    if UI.ticketFrame.title then
        UI.ticketFrame.title:SetText(
            "TICKET (" .. tostring(UI.currentTicketIndex) .. "/" .. tostring(UI.totalTickets) .. ")")
    end

    -- Show the request as it was actually typed, plus a choice of destinations when the
    -- customer named more than one ("wtb port from sw to if").
    UI.updateWaitLabel(sender)
    UI.updateRequestText(inviteData)
    UI.updateDestinationChoices(sender, inviteData, currentCity)

    -- Enable/disable navigation buttons based on current index
    if UI.ticketFrame.prevButton then
        local prevEnabled = UI.currentTicketIndex > 1
        UI.ticketFrame.prevButton:SetEnabled(prevEnabled)
    end
    if UI.ticketFrame.nextButton then
        local nextEnabled = UI.currentTicketIndex < #UI.ticketList
        local moreThanOneTicket = #UI.ticketList > 1
        UI.ticketFrame.nextButton:SetEnabled(nextEnabled and moreThanOneTicket)
    end

    -- Save the matching portal details to the invite tracker
    inviteData.portal = Utils.getMatchingPortal(destination) -- Set the portal button icon based on the invite data

    -- All action-button mutations stay together: SetAttribute and SetEnabled are protected,
    -- and updating only part of the button in combat can leave its icon and action disagreeing.
    local applied = UI.runWhenOutOfCombat("actionButton", function()
        -- The ticket may have been removed or changed while this update was deferred.
        if not UI.ticketFrame or UI.ticketFrame.currentSender ~= sender or
            Events.pendingInvites[sender] ~= inviteData then
            return
        end

        local actionButton = UI.ticketFrame.actionButton

        if Utils.isTicketComplete(inviteData) then
            if actionButton.icon then
                actionButton.icon:Hide()
            end
            actionButton:SetEnabled(false)
            actionButton:SetScript("PreClick", nil)
        elseif Utils.isTicketPortalAlive(inviteData) then
            -- This ticket's own portal is standing, so the button becomes target/trade. No cast to
            -- arm here.
            actionButton:SetScript("PreClick", nil)
            UI.setTradeIcon({
                actionButton = actionButton,
                name = inviteData.name,
                targetted = inviteData.targetted
            })
            actionButton.icon:Show()
        else
            UI.setIconSpell({
                actionButton = actionButton,
                portal = inviteData.portal
            }, destination)
            actionButton.icon:Show()

            -- Arm the cast against this ticket. PreClick, not PostClick, for the same reason as the
            -- travel button: the secure action fires on click and the cast events follow it.
            actionButton:SetScript("PreClick", function()
                if Events.pendingInvites[sender] == inviteData then
                    InviteTrade.beginPortalCast(sender, inviteData, inviteData.portal.spellName)
                end
            end)
        end
    end)

    if not applied then
        Utils.debugPrint("In combat - deferring ticket button update for " .. sender .. ".")
    end

    -- Remove Button
    local removeButton = UI.ticketFrame.removeButton
    removeButton:SetEnabled(false)
    removeButton:SetScript("OnClick", function()
        UninviteUnit(sender)

        Utils.debugPrint("" .. sender .. " has been removed from the party.")

        Events.pendingInvites[sender] = nil

        UI.updateTicketList()

        if #UI.ticketList == 0 then
            UI.ticketFrame:Hide()
        else
            if UI.currentTicketIndex > #UI.ticketList then
                UI.currentTicketIndex = #UI.ticketList
            end
            UI.updateTicketFrame()
        end
    end)

    local function showRemoveAndClearActionButton()
        -- Show the remove button
        if UI.ticketFrame.removeButton then
            UI.ticketFrame.removeButton:Show()
            UI.ticketFrame.removeButton:SetEnabled(true)
        end

        -- Clear the action button icon and disable it
        if UI.ticketFrame.actionButton.icon then
            UI.ticketFrame.actionButton.icon:Hide()
        end
    end

    -- Show/hide Paid/Complete TICK based on status
    if Utils.isTicketComplete(inviteData) then
        -- Show Complete TICK
        if UI.ticketFrame.completeText then
            UI.ticketFrame.completeText:Show()
        end
        if UI.ticketFrame.tickIcon then
            UI.ticketFrame.tickIcon:Show()
        end
        -- Hide Paid TICK if it was showing
        if UI.ticketFrame.paidText then
            UI.ticketFrame.paidText:Hide()
        end
        if UI.ticketFrame.paidCoinIcon then
            UI.ticketFrame.paidCoinIcon:Hide()
        end

        showRemoveAndClearActionButton()
    elseif Utils.isTicketPaid(inviteData) then
        -- Show Paid TICK if trade is complete but not travelled yet
        if UI.ticketFrame.completeText then
            UI.ticketFrame.completeText:Hide()
        end
        if UI.ticketFrame.tickIcon then
            UI.ticketFrame.tickIcon:Hide()
        end
        if UI.ticketFrame.paidText then
            UI.ticketFrame.paidText:Show()
        end
        if UI.ticketFrame.paidCoinIcon then
            UI.ticketFrame.paidCoinIcon:Show()
        end
    else
        -- Hide Paid/Complete TICK if not paid or travelled
        if UI.ticketFrame.completeText then
            UI.ticketFrame.completeText:Hide()
        end
        if UI.ticketFrame.tickIcon then
            UI.ticketFrame.tickIcon:Hide()
        end
        if UI.ticketFrame.paidText then
            UI.ticketFrame.paidText:Hide()
        end
        if UI.ticketFrame.paidCoinIcon then
            UI.ticketFrame.paidCoinIcon:Hide()
        end

    end

    -- Ticker for dynamic updates (when a user trades gold or travels), only run this if we are not travelled
    if not Utils.isTicketComplete(inviteData) then
        -- Cancel previous ticker if any
        if currentTicker then
            currentTicker:Cancel()
        end

        currentTicker = C_Timer.NewTicker(1, function()
            if Utils.isTicketComplete(Events.pendingInvites[sender]) then
                -- Show Complete TICK
                if UI.ticketFrame.completeText then
                    UI.ticketFrame.completeText:Show()
                end
                if UI.ticketFrame.tickIcon then
                    UI.ticketFrame.tickIcon:Show()
                end
                -- Hide Paid TICK if it was showing
                if UI.ticketFrame.paidText then
                    UI.ticketFrame.paidText:Hide()
                end
                if UI.ticketFrame.paidCoinIcon then
                    UI.ticketFrame.paidCoinIcon:Hide()
                end

                showRemoveAndClearActionButton()

                -- Cancel this tracker before refreshing; the refresh may create a replacement.
                if currentTicker then
                    currentTicker:Cancel()
                    currentTicker = nil
                end

                -- Disable the secure action as soon as combat permits it.
                if UI.ticketFrame.currentSender == sender then
                    UI.updateTicketFrame()
                end
            elseif Utils.isTicketPaid(Events.pendingInvites[sender]) then
                -- Show Paid TICK if trade is complete but not travelled yet
                if UI.ticketFrame.paidText then
                    UI.ticketFrame.paidText:Show()
                end
                if UI.ticketFrame.paidCoinIcon then
                    UI.ticketFrame.paidCoinIcon:Show()
                end
            end
        end, 180)
    end
end

-- The queue overview: every waiting customer at once, grouped by where they are standing.
--
-- The ticket window answers "what does this customer want"; this answers "who should I serve next",
-- which is a different question and the one that gets hard when several people are waiting in
-- different cities.
--
-- Deliberately read-only. It is a pane of FontStrings with no secure children, so none of the
-- protected-frame rules that govern the ticket window apply to it, and nothing here can page the
-- ticket window out from under a click.
local queueOverviewTicker = nil

function UI.createQueueOverview()
    if UI.queueFrame then
        return UI.queueFrame
    end

    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(380, 160)
    frame:SetPoint("CENTER", UIParent, "CENTER", -UIParent:GetWidth() * 0.25, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = {
            left = 11,
            right = 12,
            top = 12,
            bottom = 11
        }
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -16)
    title:SetText("QUEUE")

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 18, -38)
    body:SetWidth(344)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    frame.body = body

    -- Waits count up, so it needs its own heartbeat rather than borrowing the ticket window's,
    -- which only runs while a ticket is on screen.
    frame:SetScript("OnShow", function()
        if queueOverviewTicker then
            queueOverviewTicker:Cancel()
        end

        queueOverviewTicker = C_Timer.NewTicker(1, function()
            UI.refreshQueueOverview()
        end)
    end)

    frame:SetScript("OnHide", function()
        if queueOverviewTicker then
            queueOverviewTicker:Cancel()
            queueOverviewTicker = nil
        end
    end)

    frame:Hide()

    UI.queueFrame = frame

    return frame
end

function UI.refreshQueueOverview()
    local frame = UI.queueFrame

    if not frame or not frame:IsShown() then
        return
    end

    local lines = Utils.formatQueueOverview(Utils.buildQueueOverview(Events.pendingInvites))

    frame.body:SetText(table.concat(lines, "\n"))
    frame:SetHeight(math.max(90, 56 + #lines * 13))
end

function UI.toggleQueueOverview()
    local frame = UI.createQueueOverview()

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        UI.refreshQueueOverview()
    end
end

-- Function to show the paginated ticket window
function UI.showPaginatedTicketWindow()
    UI.updateTicketList()

    if #UI.ticketList == 0 then
        return
    end
    -- Creating a SecureActionButtonTemplate is itself forbidden during combat. If the first
    -- ticket arrives mid-fight, keep tracking it and build the window on leaving combat.
    if not UI.ticketFrame and InCombatLockdown() then
        UI.pendingTicketWindow = true
        Utils.debugPrint("In combat - deferring initial ticket window creation.")
        return
    end
    if not UI.ticketFrame then
        -- Create the main frame (only once)
        local ticketFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ticketFrame:SetSize(220, 340)
        ticketFrame:SetPoint("CENTER", UIParent, "CENTER", UIParent:GetWidth() * 0.3, 0)
        ticketFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = {
                left = 11,
                right = 12,
                top = 12,
                bottom = 11
            }
        })
        ticketFrame:SetBackdropColor(0, 0, 0, 1)
        ticketFrame:EnableMouse(true)
        ticketFrame:SetMovable(true)
        ticketFrame:RegisterForDrag("LeftButton")
        ticketFrame:SetScript("OnDragStart", ticketFrame.StartMoving)
        ticketFrame:SetScript("OnDragStop", ticketFrame.StopMovingOrSizing)

        -- Catches every route to a hidden window - close button, Remove, roster update, /reload -
        -- so the distance ticker can never outlive the frame it writes to.
        ticketFrame:SetScript("OnHide", function()
            Utils.cancelDistanceTicker()
        end)

        -- Close button
        local closeButton = CreateFrame("Button", nil, ticketFrame, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", -5, -5)
        closeButton:SetScript("OnClick", function()
            ticketFrame:Hide()
        end)

        -- Container for labels
        local labelContainer = CreateFrame("Frame", nil, ticketFrame)
        labelContainer:SetSize(200, 100)
        labelContainer:SetPoint("TOP", ticketFrame, "TOP", 0, -10)
        ticketFrame.labelContainer = labelContainer

        local title = labelContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -20)
        title:SetText("TICKET (" .. tostring(UI.currentTicketIndex) .. "/" .. tostring(UI.totalTickets) .. ")")
        ticketFrame.title = title

        local senderLabel = labelContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        senderLabel:SetPoint("TOPLEFT", 20, -50)
        senderLabel:SetText("Player:")
        local senderValue = labelContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        senderValue:SetPoint("LEFT", senderLabel, "RIGHT", 5, 0)
        ticketFrame.senderValue = senderValue

        -- How long they have been waiting, right-aligned on the same row so it needs no space of
        -- its own. Dimmed: it is context for choosing whom to serve, not part of the request.
        local waitValue = labelContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        waitValue:SetPoint("TOPRIGHT", labelContainer, "TOPRIGHT", -4, -50)
        waitValue:SetJustifyH("RIGHT")
        waitValue:SetTextColor(0.6, 0.6, 0.6)
        ticketFrame.waitValue = waitValue

        local destinationLabel = labelContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        destinationLabel:SetPoint("TOPLEFT", senderLabel, "BOTTOMLEFT", 0, -10)
        destinationLabel:SetText("Destination:")
        ticketFrame.destinationLabel = destinationLabel
        local destinationValue = labelContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        destinationValue:SetPoint("LEFT", destinationLabel, "RIGHT", 5, 0)
        ticketFrame.destinationValue = destinationValue

        local distanceLabel = labelContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        -- Leave a row for destination choices. Single-destination tickets simply keep it empty.
        distanceLabel:SetPoint("TOPLEFT", destinationLabel, "BOTTOMLEFT", 0, -28)
        distanceLabel:SetText("Distance: N/A")
        -- Bounded so a long zone name cannot run under the travel button sitting to its right.
        distanceLabel:SetWidth(150)
        distanceLabel:SetWordWrap(false)
        distanceLabel:SetJustifyH("LEFT")
        ticketFrame.distanceLabel = distanceLabel

        -- Small optional shortcut beside the location line: teleport to where the customer is
        -- standing. Deliberately not the main button - that stays the portal, so the ticket always
        -- means the same thing. Protected like the portal button, so it hangs off labelContainer
        -- (a Frame) rather than the FontString it sits beside.
        local travelButton = CreateFrame("Button", nil, labelContainer, "SecureActionButtonTemplate")
        travelButton:SetSize(16, 16)
        travelButton:SetPoint("TOPLEFT", labelContainer, "TOPLEFT", 178, -111)
        travelButton:RegisterForClicks("AnyUp", "AnyDown")
        travelButton:Hide()

        local travelIcon = travelButton:CreateTexture(nil, "BACKGROUND")
        travelIcon:SetAllPoints()
        travelButton.icon = travelIcon

        local travelHighlight = travelButton:CreateTexture(nil, "HIGHLIGHT")
        travelHighlight:SetAllPoints()
        travelHighlight:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        travelHighlight:SetBlendMode("ADD")

        travelButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        ticketFrame.travelButton = travelButton

        -- The customer's own words, shown permanently. The destination guess can be wrong, but
        -- the request never is - so it stays on screen next to the portal button rather than
        -- behind a mode switch.
        local requestText = labelContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        requestText:SetPoint("TOPLEFT", distanceLabel, "BOTTOMLEFT", 0, -12)
        requestText:SetWidth(180)
        requestText:SetHeight(28)
        requestText:SetJustifyH("LEFT")
        requestText:SetJustifyV("TOP")
        requestText:SetWordWrap(true)
        requestText:SetTextColor(0.75, 0.75, 0.75)
        ticketFrame.requestText = requestText

        -- FontStrings cannot take mouse input, so overlay a hit box to serve the untruncated
        -- message on hover.
        local requestHitBox = CreateFrame("Frame", nil, labelContainer)
        requestHitBox:SetAllPoints(requestText)
        requestHitBox:EnableMouse(true)
        requestHitBox:SetScript("OnEnter", function(self)
            if not self.message then
                return
            end

            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Original request")
            GameTooltip:AddLine(self.message, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        requestHitBox:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        ticketFrame.requestHitBox = requestHitBox

        -- Portal Button
        local actionButton = CreateFrame("Button", nil, ticketFrame, "SecureActionButtonTemplate")
        actionButton:SetSize(64, 64)
        -- A SecureActionButtonTemplate is protected, and its entire anchor family must be frames -
        -- anchoring it to requestText, or to anything itself anchored to a FontString, raises
        -- "Cannot anchor protected frames to regions". The text block above is a chain of
        -- FontStrings, so there is no legal route through it. Pin the button to the ticket frame
        -- instead: every offset above it is fixed and requestText has a fixed height, so this lands
        -- in the same place while keeping the chain Button -> ticketFrame -> UIParent.
        actionButton:SetPoint("BOTTOM", ticketFrame, "BOTTOM", 0, 84)
        -- TBC fix: SecureActionButtons need to register for clicks + Set further attributes
        actionButton:RegisterForClicks("AnyUp", "AnyDown")
        actionButton:SetAttribute("type", "action")
        actionButton:SetAttribute("action", 1) -- Default to action 1 (usually the first spell)
        ticketFrame.actionButton = actionButton

        -- Complete TICK
        local completeText = ticketFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        completeText:SetPoint("CENTER", -10, -10)
        completeText:SetText("Complete")
        completeText:Hide()
        ticketFrame.completeText = completeText
        local tickIcon = ticketFrame:CreateTexture(nil, "ARTWORK")
        tickIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
        tickIcon:SetPoint("LEFT", completeText, "RIGHT", 5, 0)
        tickIcon:SetSize(20, 20)
        tickIcon:Hide()
        ticketFrame.tickIcon = tickIcon

        -- Remove Button
        local removeButton = CreateFrame("Button", nil, ticketFrame, "UIPanelButtonTemplate")
        removeButton:SetSize(80, 22)
        removeButton:SetPoint("TOP", actionButton, "BOTTOM", 0, -10) -- Add more space below portal icon
        removeButton:SetText("Remove")
        ticketFrame.removeButton = removeButton

        -- Paid TICK
        local paidText = ticketFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        paidText:SetPoint("BOTTOM", ticketFrame, "BOTTOM", -10, 22)
        paidText:SetText("Paid")
        paidText:Hide()
        ticketFrame.paidText = paidText
        local paidCoinIcon = ticketFrame:CreateTexture(nil, "ARTWORK")
        paidCoinIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_17") -- SOD Gold coin icon
        paidCoinIcon:SetPoint("LEFT", paidText, "RIGHT", 5, 0)
        paidCoinIcon:SetSize(20, 20)
        paidCoinIcon:Hide()
        ticketFrame.paidCoinIcon = paidCoinIcon

        -- Navigation buttons
        local prevButton = CreateFrame("Button", nil, ticketFrame, "UIPanelButtonTemplate")
        prevButton:SetSize(32, 32)
        prevButton:SetPoint("BOTTOMLEFT", 12, 12)
        prevButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
        prevButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
        prevButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
        prevButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        prevButton:SetScript("OnClick", function()
            if UI.currentTicketIndex > 1 then
                UI.currentTicketIndex = UI.currentTicketIndex - 1
                UI.updateTicketFrame()
            end
        end)
        ticketFrame.prevButton = prevButton

        local nextButton = CreateFrame("Button", nil, ticketFrame, "UIPanelButtonTemplate")
        nextButton:SetSize(32, 32)
        nextButton:SetPoint("BOTTOMRIGHT", -12, 12)
        nextButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        nextButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
        nextButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
        nextButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        nextButton:SetScript("OnClick", function()
            if UI.currentTicketIndex < #UI.ticketList then
                UI.currentTicketIndex = UI.currentTicketIndex + 1
                UI.updateTicketFrame()
            end
        end)
        ticketFrame.nextButton = nextButton

        UI.ticketFrame = ticketFrame
        UI.currentTicketIndex = 1 -- Only set to 1 when frame is first created
    end

    UI.ticketFrame:Show()
    UI.updateTicketFrame()
end

-- Function to draw gold statistics to the ticket frame
function UI.drawGoldStatisticsToTicketFrame()
    if UI.totalGoldLabel and UI.dailyGoldLabel and UI.totalTradesLabel then
        -- Update the total gold label
        UI.totalGoldLabel.children[3]:SetText(string.format("%dg %ds %dc",
            math.floor(Config.Settings.totalGold / 10000), math.floor((Config.Settings.totalGold % 10000) / 100),
            Config.Settings.totalGold % 100))

        -- Update the daily gold label
        UI.dailyGoldLabel.children[3]:SetText(string.format("%dg %ds %dc",
            math.floor(Config.Settings.dailyGold / 10000), math.floor((Config.Settings.dailyGold % 10000) / 100),
            Config.Settings.dailyGold % 100))

        -- Update the total trades label
        UI.totalTradesLabel.children[3]:SetText(Config.Settings.totalTradesCompleted)
    end
end

-- Function to create keyword management section
local function createKeywordSection(scroll, titleText, keywordTable, keywordTableType, description)
    local userListGroup = AceGUI:Create("InlineGroup")
    local userListContent = AceGUI:Create("SimpleGroup")
    local keywordsText = AceGUI:Create("Label")

    local function updateKeywordsText()
        local text = ""
        for _, keyword in ipairs(keywordTable) do
            text = text .. keyword .. "\n"
        end
        keywordsText:SetText(text)

        -- Ensure the layout is updated when content changes
        userListContent:DoLayout()
        userListGroup:DoLayout()
        scroll:DoLayout()
    end

    -- Add to Keywords Function
    local function addFunc(keyword)
        if keyword and keyword:trim() ~= "" then
            -- If it doesn't already exist
            if not Utils.keywordInTable(keyword, keywordTable) then
                table.insert(keywordTable, keyword)
                updateKeywordsText()
                Utils.print("" .. keyword .. " has been added.")
            else -- If it already exists
                Utils.print("" .. keyword .. " is already in the list.")
            end
        else
            Utils.print("Cannot add an empty or invalid keyword.")
        end
    end

    -- Remove from Keywords Function
    local function removeFunc(keyword)
        if keyword and keyword:trim() ~= "" then
            for i, k in ipairs(keywordTable) do
                if k == keyword then
                    table.remove(keywordTable, i)
                    updateKeywordsText()
                    Utils.print("" .. keyword .. " has been removed.")
                    break
                end
            end
        else
            Utils.print("Cannot remove an empty or invalid keyword.")
        end
    end

    -- Create and add the title label
    local sectionTitle = AceGUI:Create("Label")
    sectionTitle:SetText(titleText)
    sectionTitle:SetFontObject(GameFontNormalLarge)
    sectionTitle:SetFullWidth(true)
    scroll:AddChild(sectionTitle)

    -- Add optional description if provided
    if description then
        local sectionDescription = AceGUI:Create("Label")
        sectionDescription:SetText(description)
        sectionDescription:SetFontObject(GameFontHighlightSmall)
        sectionDescription:SetFullWidth(true)
        scroll:AddChild(sectionDescription)
    end

    -- Create an InlineGroup for keyword management
    local keywordGroup = AceGUI:Create("InlineGroup")
    keywordGroup:SetFullWidth(true)
    keywordGroup:SetLayout("Flow")
    scroll:AddChild(keywordGroup)

    -- Add/Remove Keyword MultiLineEditBox
    local editBox = AceGUI:Create("EditBox")
    editBox:SetLabel("Add/Remove " .. (keywordTableType or "Keyword")) -- Use the passed keywordTableType or default to "Keyword"
    editBox:SetWidth(200)
    editBox:DisableButton(true)
    editBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if text ~= "" then
            addFunc(text)
            widget:SetText("")
        end
    end)
    keywordGroup:AddChild(editBox)

    -- Add Button
    local addKeywordButton = AceGUI:Create("Button")
    addKeywordButton:SetText("Add")
    addKeywordButton:SetWidth(100)
    addKeywordButton:SetCallback("OnClick", function()
        local keyword = editBox:GetText()
        if keyword ~= "" then
            addFunc(keyword)
            editBox:SetText("")
        end
    end)
    keywordGroup:AddChild(addKeywordButton)

    -- Remove Button
    local removeKeywordButton = AceGUI:Create("Button")
    removeKeywordButton:SetText("Remove")
    removeKeywordButton:SetWidth(100)
    removeKeywordButton:SetCallback("OnClick", function()
        local keyword = editBox:GetText()
        if keyword ~= "" then
            removeFunc(keyword)
            editBox:SetText("")
        end
    end)
    keywordGroup:AddChild(removeKeywordButton)

    -- Internal panel for user list with padding
    userListGroup:SetFullWidth(true)
    userListGroup:SetLayout("Flow")
    userListGroup:SetAutoAdjustHeight(true)
    keywordGroup:AddChild(userListGroup)

    -- Add padding to the internal panel
    userListContent:SetFullWidth(true)
    userListContent:SetLayout("List")
    userListContent:SetAutoAdjustHeight(true) -- Adjust height automatically
    userListGroup:AddChild(userListContent)

    -- Keywords Text Label
    keywordsText:SetFullWidth(true)
    userListContent:AddChild(keywordsText)

    updateKeywordsText()
end

-- Function to create the options panel
function UI.createOptionsPanel()
    optionsPanel = AceGUI:Create("Frame")

    -- Add the frame as a global variable under the name `MyGlobalFrameName`
    _G["ThicPortalsOptionsPanel"] = optionsPanel.frame
    -- Register the global variable `MyGlobalFrameName` as a "special frame"
    -- so that it is closed when the escape key is pressed.
    tinsert(UISpecialFrames, "ThicPortalsOptionsPanel")

    optionsPanel:SetTitle("Thic-Portals Service Configuration")
    optionsPanel:SetCallback("OnClose", function(widget)
        Config.Settings.optionsPanelHidden = true
    end)
    optionsPanel:SetLayout("Fill")
    optionsPanel:SetWidth(480)

    setMinWidth(optionsPanel, 480) -- Ensure the width never goes below the set value

    local largeVerticalGap = AceGUI:Create("Label")
    largeVerticalGap:SetText("\n\n")
    largeVerticalGap:SetFullWidth(true)

    local smallVerticalGap = AceGUI:Create("Label")
    smallVerticalGap:SetText("\n")
    smallVerticalGap:SetFullWidth(true)

    local tinyVerticalGap = AceGUI:Create("Label")
    tinyVerticalGap:SetText("")
    tinyVerticalGap:SetFullWidth(true)

    -- Create a scroll container
    local scrollcontainer = AceGUI:Create("SimpleGroup")
    scrollcontainer:SetFullWidth(true)
    scrollcontainer:SetFullHeight(true)
    scrollcontainer:SetLayout("Fill")
    optionsPanel:AddChild(scrollcontainer)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    scrollcontainer:AddChild(scroll)

    -- Example content
    local generalSettingsTitle = AceGUI:Create("Label")
    generalSettingsTitle:SetText("|cFFFFD700General Settings|r")
    generalSettingsTitle:SetFontObject(GameFontNormalLarge)
    generalSettingsTitle:SetFullWidth(true)
    scroll:AddChild(generalSettingsTitle)
    scroll:AddChild(largeVerticalGap)

    -- Create a group for the checkboxes
    local checkboxGroup = AceGUI:Create("SimpleGroup")
    checkboxGroup:SetFullWidth(true)
    checkboxGroup:SetLayout("Flow")

    -- Addon On/Off Checkbox
    addCheckbox(checkboxGroup, "Enable Addon", UI.addonEnabledCheckbox, Config.Settings.addonEnabled,
        function(_, _, value)
            UI.toggleAddonEnabledState()
        end, "Enables or disables the addon functionality entirely.")

    -- Global Channels On/Off Checkbox
    addCheckbox(checkboxGroup, "Disable Global Channels", UI.disableGlobalChannelsCheckbox,
        Config.Settings.disableGlobalChannels, function(_, _, value)
            Config.Settings.disableGlobalChannels = value
            if Config.Settings.disableGlobalChannels then
                Utils.print("Global channels disabled.")
            else
                Utils.print("Global channels enabled.")
            end
        end, "Enables or disables the addon from listening to global channels for requests.")

    -- Approach Mode Checkbox
    addCheckbox(checkboxGroup, "Approach Mode", UI.approachModeCheckbox, Config.Settings.ApproachMode,
        function(_, _, value)
            Config.Settings.ApproachMode = value
            if Config.Settings.ApproachMode then
                Utils.print("Approach mode enabled.")
            else
                Utils.print("Approach mode disabled.")
            end
        end, "When enabled, the addon will require only a destination value to be provided in either a say/whisper.")

    -- Enable Food and Water Support Checkbox
    addCheckbox(checkboxGroup, "Food and Water Support", UI.enableFoodWaterSupportCheckbox,
        Config.Settings.enableFoodWaterSupport, function(_, _, value)
            Config.Settings.enableFoodWaterSupport = value
            if Config.Settings.enableFoodWaterSupport then
                Utils.print("Food and Water support enabled.")
            else
                Utils.print("Food and Water support disabled.")
            end
        end,
        "Enables or disables the ability to sell food and water items through the portal service. Food and water will be advertised to relevant customers depending on stock levels.")

    -- Disable smart matching and use only common phrase matching
    addCheckbox(checkboxGroup, "Only Use Common Phrase Matching", UI.disableSmartMatchingCheckbox,
        Config.Settings.disableSmartMatching, function(_, _, value)
            Config.Settings.disableSmartMatching = value
            if Config.Settings.disableSmartMatching then
                Utils.print("Smart matching disabled.")
            else
                Utils.print("Smart matching enabled.")
            end
        end,
        "Disables advanced smart matching algorithms and only uses the predefined common phrases to match requests (configurable below).")

    -- Require destination before inviting
    addCheckbox(checkboxGroup, "Require Destination", UI.requireDestinationCheckbox, Config.Settings.requireDestination,
        function(_, _, value)
            Config.Settings.requireDestination = value
            if Config.Settings.requireDestination then
                Utils.print("Require destination enabled.")
            else
                Utils.print("Require destination disabled.")
            end
        end,
        "When enabled, the addon will require a valid destination (one listed in Destination Keywords) in the message before sending out the invite.")

    -- Don't use realm when inviting
    addCheckbox(checkboxGroup, "Remove Realm Affix From Invite Command", UI.removeRealmFromInviteCommandCheckbox,
        Config.Settings.removeRealmFromInviteCommand, function(_, _, value)
            Config.Settings.removeRealmFromInviteCommand = value
            if Config.Settings.removeRealmFromInviteCommand then
                Utils.print("Smart matching disabled.")
            else
                Utils.print("Smart matching enabled.")
            end
        end,
        "When enabled, removes the realm name e.g. '-Ashbringer' from invite commands, making invites suitable for certain single realm servers.")

    -- AFK Protection Checkbox
    addCheckbox(checkboxGroup, "Disable AFK Protection", UI.disableAFKProtectionCheckbox,
        Config.Settings.disableAFKProtection, function(_, _, value)
            Config.Settings.disableAFKProtection = value
            if Config.Settings.disableAFKProtection then
                Utils.print("AFK protection disabled.")
            else
                Utils.print("AFK protection enabled.")
            end
        end,
        "Disables the AFK protection feature which is in place to prevent potentially over-inviting players if the user forgets the addon is running. Two players in a row leaving the party without payment triggers shop close.")

    -- Hide Icon Checkbox
    addCheckbox(checkboxGroup, "Hide Icon", UI.hideIconCheckbox, Config.Settings.hideIcon, function(_, _, value)
        Config.Settings.hideIcon = value
        if Config.Settings.hideIcon then
            Utils.print("Open/Closed icon marked visible.")
            toggleButton:Hide()
        else
            Utils.print("Open/Closed icon marked hidden.")
            toggleButton:Show()
        end
    end, "Hides or shows the toggle button on the screen. You can use '/Tp show' to reveal the hidden icon again.")

    -- Sound On/Off Checkbox
    addCheckbox(checkboxGroup, "Enable Sound", UI.soundEnabledCheckbox, Config.Settings.soundEnabled,
        function(_, _, value)
            Config.Settings.soundEnabled = value
            if Config.Settings.soundEnabled then
                Utils.print("Sound enabled.")
            else
                Utils.print("Sound disabled.")
            end
        end, "Enables or disables sound notifications.")

    -- Debug Mode Checkbox
    addCheckbox(checkboxGroup, "Enable Debug Mode", UI.debugModeCheckbox, Config.Settings.debugMode,
        function(_, _, value)
            Config.Settings.debugMode = value
            if Config.Settings.debugMode then
                Utils.print("Debug mode enabled.")
            else
                Utils.print("Debug mode disabled.")
            end
        end, "Toggles debug mode for additional console logging.")

    -- Create a label for the food and water prices
    scroll:AddChild(checkboxGroup)
    scroll:AddChild(largeVerticalGap)

    -- Max Simultaneous Tickets Setting
    local maxTicketsGroup = AceGUI:Create("SimpleGroup")
    maxTicketsGroup:SetFullWidth(true)
    maxTicketsGroup:SetLayout("Flow")

    local spacer = AceGUI:Create("Label")
    spacer:SetWidth(30)
    maxTicketsGroup:AddChild(spacer)

    maxTicketsEditBox = AceGUI:Create("EditBox")
    maxTicketsEditBox:SetLabel("Max Simultaneous Tickets")
    maxTicketsEditBox:SetText(tostring(Config.Settings.maxSimultaneousTickets))
    maxTicketsEditBox:SetWidth(200)
    maxTicketsEditBox:SetCallback("OnEnterPressed", function(widget, event, text)
        local value = tonumber(text)
        if value and value >= 1 and value <= 15 then
            Config.Settings.maxSimultaneousTickets = math.floor(value)
            Utils.print("Max simultaneous tickets set to: " ..
                      Config.Settings.maxSimultaneousTickets)
        else
            Utils.print("Invalid value. Please enter a number between 1 and 15.")
            widget:SetText(tostring(Config.Settings.maxSimultaneousTickets))
        end
    end)
    maxTicketsGroup:AddChild(maxTicketsEditBox)

    -- How few runes counts as low. Warned about when the shop opens and when stock crosses it.
    local reagentThresholdEditBox = AceGUI:Create("EditBox")
    reagentThresholdEditBox:SetLabel("Warn when runes fall to")
    reagentThresholdEditBox:SetText(tostring(Config.Settings.reagentWarningThreshold))
    reagentThresholdEditBox:SetWidth(200)
    reagentThresholdEditBox:SetCallback("OnEnterPressed", function(widget, event, text)
        local value = tonumber(text)

        if value and value >= 0 then
            Config.Settings.reagentWarningThreshold = math.floor(value)
            Utils.print("Rune warning threshold set to: " .. Config.Settings.reagentWarningThreshold)
        else
            Utils.print("Invalid value. Please enter a number of runes, or 0 to only warn when empty.")
            widget:SetText(tostring(Config.Settings.reagentWarningThreshold))
        end
    end)
    maxTicketsGroup:AddChild(reagentThresholdEditBox)

    scroll:AddChild(maxTicketsGroup)
    scroll:AddChild(largeVerticalGap)

    -- Create a group for food and water prices
    local foodWaterPricesGroup = AceGUI:Create("SimpleGroup")
    foodWaterPricesGroup:SetFullWidth(true)
    foodWaterPricesGroup:SetLayout("Flow")

    -- Create a title for the food and water prices
    local foodWaterPricesTitle = AceGUI:Create("Label")
    foodWaterPricesTitle:SetText("|cFFFFD700Food and Water Prices|r")
    foodWaterPricesTitle:SetFontObject(GameFontNormalLarge)
    foodWaterPricesTitle:SetFullWidth(true)
    scroll:AddChild(foodWaterPricesTitle)
    scroll:AddChild(smallVerticalGap)

    -- Create a description for the food and water prices
    local foodWaterPricesDescription = AceGUI:Create("Label")
    foodWaterPricesDescription:SetText("Set the prices for food and water in copper. Only shows items you can conjure.")
    foodWaterPricesDescription:SetFontObject(GameFontHighlightSmall)
    foodWaterPricesDescription:SetFullWidth(true)
    scroll:AddChild(foodWaterPricesDescription)
    scroll:AddChild(largeVerticalGap)

    -- Add price edit boxes for food and water
    addPriceEditBoxes(foodWaterPricesGroup, "Food", Config.Settings.prices.food)
    addPriceEditBoxes(foodWaterPricesGroup, "Water", Config.Settings.prices.water)

    -- Add the group to the scroll frame
    scroll:AddChild(foodWaterPricesGroup)

    scroll:AddChild(smallVerticalGap)
    scroll:AddChild(largeVerticalGap)

    -- Gold Stats Section
    local goldStatsTitle = AceGUI:Create("Label")
    goldStatsTitle:SetText("|cFFFFD700Gold Statistics|r")
    goldStatsTitle:SetFontObject(GameFontNormalLarge)
    goldStatsTitle:SetFullWidth(true)
    scroll:AddChild(goldStatsTitle)
    scroll:AddChild(largeVerticalGap)

    -- Add label-value pairs to the scroll frame
    UI.totalGoldLabel = addLabelValuePair("Total Gold Earned:", string.format("%dg %ds %dc", 0, 0, 0))
    scroll:AddChild(UI.totalGoldLabel)
    scroll:AddChild(smallVerticalGap)

    UI.dailyGoldLabel = addLabelValuePair("Gold Earned Today:", string.format("%dg %ds %dc", 0, 0, 0))
    scroll:AddChild(UI.dailyGoldLabel)
    scroll:AddChild(smallVerticalGap)

    UI.totalTradesLabel = addLabelValuePair("Total Trades Completed:", Config.Settings.totalTradesCompleted)
    scroll:AddChild(UI.totalTradesLabel)
    scroll:AddChild(largeVerticalGap)
    scroll:AddChild(largeVerticalGap)

    -- Message Configuration Title
    local messageConfigTitle = AceGUI:Create("Label")
    messageConfigTitle:SetText("|cFFFFD700Message Configuration|r")
    messageConfigTitle:SetFontObject(GameFontNormalLarge)
    messageConfigTitle:SetFullWidth(true)
    scroll:AddChild(messageConfigTitle)

    -- Add helper text about placeholders
    local placeholderHelp = AceGUI:Create("Label")
    placeholderHelp:SetText("|cFFADD8E6Tip: Use %destination% in your messages to insert the destination name|r")
    placeholderHelp:SetFullWidth(true)
    scroll:AddChild(placeholderHelp)
    scroll:AddChild(largeVerticalGap)

    -- Create a parent group for the message configuration
    local messageConfigGroup = AceGUI:Create("SimpleGroup")
    messageConfigGroup:SetFullWidth(true)
    messageConfigGroup:SetLayout("Flow")
    scroll:AddChild(messageConfigGroup)

    -- Invite Message
    local inviteMessageGroup = addMessageMultiLineEditBox("Invite Message:", Config.Settings.inviteMessage,
        function(text)
            Config.Settings.inviteMessage = text
            Utils.print("Invite message updated.")
        end)
    messageConfigGroup:AddChild(inviteMessageGroup)
    messageConfigGroup:AddChild(smallVerticalGap)

    -- Invite Message Without Destination
    local inviteMessageWithoutDestinationGroup = addMessageMultiLineEditBox("Invite Message (No Destination):",
        Config.Settings.inviteMessageWithoutDestination, function(text)
            Config.Settings.inviteMessageWithoutDestination = text
            Utils.print("Invite message without destination updated.")
        end)
    messageConfigGroup:AddChild(inviteMessageWithoutDestinationGroup)
    messageConfigGroup:AddChild(smallVerticalGap)

    -- Tip Message
    local tipMessageGroup = addMessageMultiLineEditBox("Tip Message:", Config.Settings.tipMessage, function(text)
        Config.Settings.tipMessage = text
        Utils.print("Tip message updated.")
    end)
    messageConfigGroup:AddChild(tipMessageGroup)
    messageConfigGroup:AddChild(smallVerticalGap)

    -- No Tip Message
    local noTipMessageGroup = addMessageMultiLineEditBox("No Tip Message:", Config.Settings.noTipMessage, function(text)
        Config.Settings.noTipMessage = text
        Utils.print("No tip message updated.")
    end)
    messageConfigGroup:AddChild(noTipMessageGroup)
    messageConfigGroup:AddChild(smallVerticalGap)

    -- Travel Message: whispered when the teleport to the customer's city starts casting, so they
    -- hear it at the top of the cast rather than ten seconds later. %location% is where we are
    -- heading, %destination% is still where they are going.
    local travelMessageGroup = addMessageMultiLineEditBox("Travel Message (%location%):", Config.Settings.travelMessage,
        function(text)
            Config.Settings.travelMessage = text
            Utils.print("Travel message updated.")
        end)
    messageConfigGroup:AddChild(travelMessageGroup)
    messageConfigGroup:AddChild(largeVerticalGap)

    -- Creating Keyword Sections
    createKeywordSection(scroll, "|cFFFFD700Any Keyword Ban List Management|r", Config.Settings.KeywordBanList,
        "Keyword",
        "If the addon matches one of these keywords or phrases in any evaluated message, it will ignore it. This is an exact match by default, to use a partial match where the keyword exists within another word, wrap the keyword in '%' (e.g. %keyword%).")
    scroll:AddChild(largeVerticalGap)
    createKeywordSection(scroll, "|cFFFFD700Common Phrases Management|r", Config.Settings.commonPhrases,
        "Common Phrase",
        "Common Phrases are the first compared list of terms before any other keyword matching occurs. The only way to send an automated invite in this scenario is to match one of the below phrases. This is an exact match by default, but it may be contained in a sentence.")
    scroll:AddChild(largeVerticalGap)
    createKeywordSection(scroll, "|cFFFFD700Intent Keywords Management|r", Config.Settings.IntentKeywords, "Intent",
        "Intent is used to match the player's intent to trade or request a service (e.g. wtb, need). Exact match only.")
    scroll:AddChild(largeVerticalGap)
    createKeywordSection(scroll, "|cFFFFD700Destination Keywords Management|r", Config.Settings.DestinationKeywords,
        "Destination",
        "Destination is used to match the player's intended destination (e.g. darna, if). Exact match only.")
    scroll:AddChild(largeVerticalGap)
    createKeywordSection(scroll, "|cFFFFD700Service Keywords Management|r", Config.Settings.ServiceKeywords, "Service",
        "Service is used to match the player's intended service (e.g. portal, tp). Exact match only.")
    scroll:AddChild(largeVerticalGap)
    createKeywordSection(scroll, "|cFFFFD700Player Ban List Management|r", Config.Settings.BanList, "Player",
        "The addon will scan each message and discard any message from a player in this list. Enter values in the format 'Player-Realm'. Exact match only.")
    scroll:AddChild(largeVerticalGap)

    -- Save the options panel reference in the config for other modules to use
    UI.optionsPanel = optionsPanel
end

-- Show the options panel
function UI.showOptionsPanel()
    -- If debug mode is enabled, print a message
    Utils.debugPrint("Showing options panel.")

    if not optionsPanel then
        UI.createOptionsPanel()
    else
        UI.drawGoldStatisticsToTicketFrame()
    end

    optionsPanel:Show()

    Config.Settings.optionsPanelHidden = false
end

-- Hide the options panel
function UI.hideOptionsPanel()
    -- If debug mode is enabled, print a message
    Utils.debugPrint("Hiding options panel.")

    if optionsPanel then
        optionsPanel:Hide()

        Config.Settings.optionsPanelHidden = true
    end
end

-- Function to show a food and water request in the UI
function UI.showFoodWaterRequest(sender, foodRequested, waterRequested)
    local message = ""
    local iconPath = ""

    if foodRequested and waterRequested then
        message = "Food and Water requested by " .. sender
        iconPath = "Interface\\Icons\\INV_Misc_Food_15" -- Example icon path
    elseif foodRequested then
        message = "Food requested by " .. sender
        iconPath = "Interface\\Icons\\INV_Misc_Food_14"
    elseif waterRequested then
        message = "Water requested by " .. sender
        iconPath = "Interface\\Icons\\INV_Drink_04"
    end

    -- Display the message and icon
    print(message)
    -- Code to display the icon in the UI (e.g., create a frame and set the icon texture)
end

-- Function to show the toggle button
function UI.showToggleButton()
    toggleButton:Show()
    Config.Settings.optionsPanelHidden = true

    Config.Settings.hideIcon = false
    UI.hideIconCheckbox:SetValue(false)
end

-- Function to reset the position of the toggle button back to default
function UI.resetToggleButtonPosition()
    Config.Settings.toggleButtonPosition = {
        point = "CENTER",
        x = 0,
        y = 200
    }

    toggleButton:ClearAllPoints()
    toggleButton:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
end

-- Function to create the global interface options panel
function UI.createInterfaceOptionsPanel()
    -- Create the main panel frame
    local panel = CreateFrame("Frame", "ThicPortalsInterfaceOptions", UIParent)
    panel.name = "Thic-Portals"

    -- Create title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Thic-Portals Icon Management")

    -- Create subtitle
    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Manage the addon's toggle icon visibility and position")

    -- Show Icon Button
    local showIconButton = CreateFrame("Button", "ThicPortalsShowIconButton", panel, "UIPanelButtonTemplate")
    showIconButton:SetSize(150, 25)
    showIconButton:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -20)
    showIconButton:SetText("Show Icon Button")
    showIconButton:SetScript("OnClick", function()
        UI.showToggleButton()
        Utils.print("Addon management icon displayed.")
    end)

    -- Reset Icon Position Button
    local resetIconButton = CreateFrame("Button", "ThicPortalsResetIconButton", panel, "UIPanelButtonTemplate")
    resetIconButton:SetSize(150, 25)
    resetIconButton:SetPoint("LEFT", showIconButton, "RIGHT", 20, 0)
    resetIconButton:SetText("Reset Icon Position")
    resetIconButton:SetScript("OnClick", function()
        UI.resetToggleButtonPosition()
        Utils.print("Addon management icon position reset.")
    end)

    -- Add descriptions for the buttons
    local showIconDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    showIconDesc:SetPoint("TOPLEFT", showIconButton, "BOTTOMLEFT", 0, -8)
    showIconDesc:SetText("Makes the addon toggle icon visible if it's hidden")
    showIconDesc:SetWidth(150)
    showIconDesc:SetJustifyH("LEFT")
    showIconDesc:SetWordWrap(true)

    local resetIconDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    resetIconDesc:SetPoint("TOPLEFT", resetIconButton, "BOTTOMLEFT", 0, -8)
    resetIconDesc:SetText("Resets the icon position to the center of the screen")
    resetIconDesc:SetWidth(150)
    resetIconDesc:SetJustifyH("LEFT")
    resetIconDesc:SetWordWrap(true)

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    else
        local category, layout = _G.Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        _G.Settings.RegisterAddOnCategory(category)
    end

    return panel
end

return UI
