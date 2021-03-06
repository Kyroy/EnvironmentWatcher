-----------------------------------------------------------------------------------------------
-- Client Lua Script for EnvironmentWatcher
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "Sound"
require "ChatSystemLib"
 
-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher Module Definition
-----------------------------------------------------------------------------------------------
local EnvironmentWatcher = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
local kcrSelectedText = ApolloColor.new("UI_BtnTextHoloPressedFlyby")
local kcrNormalText = ApolloColor.new("UI_BtnTextHoloNormal")

local trackableType = {
	["Buff"] = 1,
	["Debuff"] = 2,
	["Cast"] = 3
}
local chats = {
	["d"] = ChatSystemLib.ChatChannel_Debug,
	["s"] = ChatSystemLib.ChatChannel_Say,
	["p"] = ChatSystemLib.ChatChannel_Party,
	["g"] = ChatSystemLib.ChatChannel_Guild,
	["i"] = ChatSystemLib.ChatChannel_Instance,
	["z"] = ChatSystemLib.ChatChannel_Zone,
	["t"] = ChatSystemLib.ChatChannel_Trade
}

local sounds = {
	["PlayUIWindowAuctionHouseOpen"] = Sound.PlayUIWindowAuctionHouseOpen,
	--["PlayUIStoryPaneUrgent"] = Sound.PlayUIStoryPaneUrgent,
	["PlayUICraftingSuccess"] = Sound.PlayUICraftingSuccess,
	["PlayUICraftingOverchargeWarning"] = Sound.PlayUICraftingOverchargeWarning,
	["PlayUIWindowPublicEventVoteOpen"] = Sound.PlayUIWindowPublicEventVoteOpen,
	--["PlayUIMissionUnlockSoldier"] = Sound.PlayUIMissionUnlockSoldier,
	["PlayUIQueuePopsPvP"] = Sound.PlayUIQueuePopsPvP,
	["PlayUIQueuePopsDungeon"] = Sound.PlayUIQueuePopsDungeon,
	["PlayUIWindowPublicEventVoteVotingEnd"] = Sound.PlayUIWindowPublicEventVoteVotingEnd
}
local soundsLookup = {
	[Sound.PlayUIWindowAuctionHouseOpen] = "PlayUIWindowAuctionHouseOpen",
	--[Sound.PlayUIStoryPaneUrgent] = "PlayUIStoryPaneUrgent",
	[Sound.PlayUICraftingSuccess] = "PlayUICraftingSuccess",
	[Sound.PlayUICraftingOverchargeWarning] = "PlayUICraftingOverchargeWarning",
	[Sound.PlayUIWindowPublicEventVoteOpen] = "PlayUIWindowPublicEventVoteOpen",
	--[Sound.PlayUIMissionUnlockSoldier] = "PlayUIMissionUnlockSoldier",
	[Sound.PlayUIQueuePopsPvP] = "PlayUIQueuePopsPvP",
	[Sound.PlayUIQueuePopsDungeon] = "PlayUIQueuePopsDungeon",
	[Sound.PlayUIWindowPublicEventVoteVotingEnd] = "PlayUIWindowPublicEventVoteVotingEnd"
}
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function EnvironmentWatcher:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	o.wndSelectedListItem = nil -- keep track of which list item is currently selected
	o.trackedBuffs = {}
	o.trackedDebuffs = {}
	o.trackedCasts = {}
	o.watched = {}
	o.watchedCombat = {}
	o.settings = {
		anchorOffsets = nil
	}
	o.saveData = nil

    return o
end

function EnvironmentWatcher:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 
function EnvironmentWatcher:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("EnvironmentWatcher.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

function EnvironmentWatcher:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "EnvironmentWatcherForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
		self.wndNotification = Apollo.LoadForm(self.xmlDoc, "NotificationForm", nil, self)
		if self.wndNotification == nil then
			Apollo.AddAddonErrorText(self, "Could not load the notification window for some reason.")
			return
		end
		
		self.wndMoveWatchers = Apollo.LoadForm(self.xmlDoc, "NotificationMoveForm", nil, self)
		if self.wndMoveWatchers == nil then
			Apollo.AddAddonErrorText(self, "Could not load the move-watchers window for some reason.")
			return
		end
		
		-- item list
		self.wndItemList = self.wndMain:FindChild("ItemList")
	    self.wndMain:Show(false, true)
		self.wndNotification:Show(true, true)
		self.wndMoveWatchers:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		Apollo.RegisterEventHandler("UnitEnteredCombat", "OnEnteredCombat", self)
		Apollo.RegisterEventHandler("UnitCreated", "OnUnitCreated", self)
		Apollo.RegisterEventHandler("UnitDestroyed", "OnUnitDestroyed", self)
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("ew", "OnEnvironmentWatcherOn", self)

		self.timer = {
				ApolloTimer.Create(0.100, true, "OnTimer", self),
				ApolloTimer.Create(0.200, true, "ClearWatcher", self),
				ApolloTimer.Create(10.00, true, "ClearInvalidUnits", self)
			}

		-- Do additional Addon initialization here
		if self.saveData then
			for _,v in pairs(self.saveData.trackedBuffs) do
				for _,trackable in pairs(v) do
					self:ItemListAddWatcher(trackable)
					self:AddTracked(self.trackedBuffs, trackable)
				end
			end
			for _,v in pairs(self.saveData.trackedDebuffs) do
				for _,trackable in pairs(v) do
					self:ItemListAddWatcher(trackable)
					self:AddTracked(self.trackedDebuffs, trackable)
				end
			end
			for _,v in pairs(self.saveData.trackedCasts) do
				for _,trackable in pairs(v) do
					self:ItemListAddWatcher(trackable)
					self:AddTracked(self.trackedCasts, trackable)
				end
			end
	
			self.settings = self.saveData.settings
			if self.settings.anchorOffsets then
				self.wndMoveWatchers:SetAnchorOffsets(unpack(self.settings.anchorOffsets))
				self.wndNotification:SetAnchorOffsets(unpack(self.settings.anchorOffsets))
			end
		end
		
		-- Watch yourself (not tracked via UnitCreated)
		self:OnUnitCreated(GameLib.GetPlayerUnit())
	end
end

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/ew"
function EnvironmentWatcher:OnEnvironmentWatcherOn(cmd, args)
	if args:lower() == "debug" then
		self:OnEnvironmentWatcherDebug()
	elseif args:lower() == "" then
		self.wndMain:Invoke() -- show the window
	else
		local num = tonumber(args:lower())
		if num then
			local unit
			if self.watched[num] then
				unit = self.watched[num]
			else
				unit = self.watchedCombat[num]
			end
			
			if unit then
				Print("UnitInformation: " .. unit:GetName() ..
						--" -- unit:GetMouseOverType(): " .. unit:GetMouseOverType() ..
						" -- unit:IsValid(): " .. tostring(unit:IsValid()) ..
						" -- unit:GetType(): " .. unit:GetType()
					)
			end
		end
	end
end

function EnvironmentWatcher:OnEnvironmentWatcherDebug()
	Print("Printing watched units:")
	local i = 0
	for k,v in pairs(self.watched) do
		i = i+1
		Print(i .. ": " .. k .. " -- " .. v:GetName())
	end
	Print("Printing watchedCombat units:")
	for k,v in pairs(self.watchedCombat) do
		i = i+1
		Print(i .. ": " .. k .. " -- " .. v:GetName())
	end
end

-----------------------------------------------------------------------------------------------
-- Watcher Functionality
-----------------------------------------------------------------------------------------------
function EnvironmentWatcher:OnTimer()
	local watchedUnits = self:TableMergeUniqueId(self.watched, self.watchedCombat)
	for unitId, unit in pairs(watchedUnits) do
		local unitName = unit:GetName()
		local isPlayer = unit:IsACharacter()
		local buffs = unit:GetBuffs()
		if buffs then
			-- Buffs
			for kB, buff in pairs(buffs.arBeneficial) do
				local trackTable = self.trackedBuffs[buff.splEffect:GetName()]
				if trackTable then
					for k, v in pairs(trackTable) do
						if (v.trackPlayer == isPlayer or v.trackNPC == not isPlayer) and (not v.trackId or v.trackId == buff.splEffect:GetBaseSpellId()) then
							if v.showNotificationItem then
								self:ShowWatcher(v,buff.splEffect:GetIcon(),unitName,buff.fTimeRemaining,buff.nCount)
							end
							if not v.nextNotification[unitId] or os.difftime(v.nextNotification[unitId] , os.clock()) <= 0 then
								if v.targetMark then
									unit:ClearTargetMarker()
									unit:SetTargetMarker(v.targetMark)
								end
								if v.toChat then
									local addMsg = ""
									if v.chatShowId then
										addMsg = " (id=" .. buff.splEffect:GetBaseSpellId() .. ")"
									end
									if v.chatOptionalText then
										addMsg = unitName .. " " .. v.chatOptionalText .. addMsg
									else
										addMsg = unitName .. " has buff " .. v.name .. addMsg
									end
									self:SendChatMessage(v, addMsg)
								end
								if v.sound and v.sound ~= "none" then
									Sound.Play(v.sound)
								end
								v.nextNotification[unitId] = os.clock() + buff.fTimeRemaining + 1.0
							end
						end
					end
				end
			end
			-- Debuffs
			for kB, debuff in pairs(buffs.arHarmful) do
				local trackTable = self.trackedDebuffs[debuff.splEffect:GetName()]
				if trackTable then
					for k, v in pairs(trackTable) do
						if (v.trackPlayer == isPlayer or v.trackNPC == not isPlayer) and (not v.trackId or v.trackId == debuff.splEffect:GetBaseSpellId()) then
							if v.showNotificationItem then
								self:ShowWatcher(v,debuff.splEffect:GetIcon(),unitName,debuff.fTimeRemaining,debuff.nCount)
							end
							if not v.nextNotification[unitId] or os.difftime(v.nextNotification[unitId] , os.clock()) <= 0 then
								if v.targetMark then
									unit:ClearTargetMarker()
									unit:SetTargetMarker(v.targetMark)
								end
								if v.toChat then
									local addMsg = ""
									if v.chatShowId then
										addMsg = " (id=" .. debuff.splEffect:GetBaseSpellId() .. ")"
									end
									if v.chatOptionalText then
										addMsg = unitName .. " " .. v.chatOptionalText .. addMsg
									else
										addMsg = unitName .. " has debuff " .. v.name .. addMsg
									end
									self:SendChatMessage(v, addMsg)
								end
								if v.sound and v.sound ~= "none" then
									Sound.Play(v.sound)
								end
								v.nextNotification[unitId] = os.clock() + debuff.fTimeRemaining + 1.0
							end
						end
					end
				end
			end
		end
		-- Casts
		local castPercentage = unit:GetCastTotalPercent()
		if castPercentage and 0 < castPercentage and castPercentage < 100 then
			--Print(unit:GetName() .. " is Casting " .. unit:GetCastName())
			local trackTable = self.trackedCasts[unit:GetCastName()]
			if trackTable then
				for k, v in pairs(trackTable) do
					if (v.trackPlayer == isPlayer or v.trackNPC == not isPlayer) then
						if v.showNotificationItem then
							self:ShowWatcher(v,nil,unitName,unit:GetCastElapsed(),nil)
						end
						if not v.nextNotification[unitId] or os.difftime(v.nextNotification[unitId] , os.clock()) <= 0 then
							if v.targetMark then
									unit:ClearTargetMarker()
									unit:SetTargetMarker(v.targetMark)
								end
							if v.toChat then
								local addMsg = ""
								if v.chatOptionalText then
									addMsg = unitName .. " " .. v.chatOptionalText .. addMsg
								else
									addMsg = unitName .. " is casting " .. v.name .. addMsg
								end
								self:SendChatMessage(v, addMsg)
							end
							if v.sound and v.sound ~= "none" then
								Sound.Play(v.sound)
							end
							v.nextNotification[unitId] = os.clock() + (unit:GetCastDuration())/1000.0 + 1.0
						end
					end
				end
			end
		end
	end
end

function EnvironmentWatcher:SendChatMessage(trackable, message)
	if chats[trackable.toChat] == ChatSystemLib.ChatChannel_Debug then
		ChatSystemLib.PostOnChannel(chats[trackable.toChat], message, "")
	else
		for idx, channel in pairs(ChatSystemLib.GetChannels()) do
			if channel:GetType() == chats[trackable.toChat] then
				channel:Send(message)
				break
			end
		end
	end
end

function EnvironmentWatcher:OnUnitCreated(unit)
	if unit and unit:GetMouseOverType() == "Normal" and unit:IsValid() then
		local type = unit:GetType()
		if type == "Player" or type == "NonPlayer" then 
			self.watched[unit:GetId()] = unit
		end
	end
end

function EnvironmentWatcher:OnUnitDestroyed(unit)
	self.watched[unit:GetId()] = nil
end

function EnvironmentWatcher:OnEnteredCombat(unitChanged,bInCombat)
	if bInCombat then
		--Print("OnEnteredCombat(".. unitChanged:GetName() ..", true)")
		self.watchedCombat[unitChanged:GetId()] = unitChanged
	else
		--Print("OnEnteredCombat(".. unitChanged:GetName() ..", false)")
		self.watchedCombat[unitChanged:GetId()] = nil
	end
end

function EnvironmentWatcher:ClearInvalidUnits()
	for _, t in pairs({self.watched, self.watchedCombat}) do
		for unitId, unit in pairs(t) do
			if not unit:IsValid() then
				t[unitId] = nil
			end
		end
	end
end

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher GUI
-----------------------------------------------------------------------------------------------
function EnvironmentWatcher:ShowWatcher(trackable, icon, unitName, timeRemaining, stacks)
	local guiIcon
	if not trackable.notificationItem[unitName] then
		trackable.notificationItem[unitName] = Apollo.LoadForm(self.xmlDoc, "NotificationItem", self.wndNotification, self)
		guiIcon = trackable.notificationItem[unitName]:FindChild("Icon")
		guiIcon:FindChild("ProgressBar"):SetMax(timeRemaining)
		if icon then
			guiIcon:SetSprite(icon)
		end
		trackable.notificationItem[unitName]:FindChild("Text"):SetText(unitName)
		if trackable.textShowWatcherName then
			trackable.notificationItem[unitName]:FindChild("WatcherName"):SetText(trackable.printName)
		end
		self.wndNotification:ArrangeChildrenVert()
	end
	guiIcon = trackable.notificationItem[unitName]:FindChild("Icon")
	trackable.notificationItem[unitName]:Invoke()
	guiIcon:FindChild("ProgressBar"):SetProgress(timeRemaining)
	guiIcon:FindChild("IconText"):SetText(tonumber(string.format("%.0f", timeRemaining)))
	if stacks then
		if stacks > 1 then
			guiIcon:FindChild("IconStacks"):SetText(stacks)
		else
			guiIcon:FindChild("IconStacks"):SetText("")
		end
	end
	trackable.notificationItem[unitName]:SetData(os.clock())
end

function EnvironmentWatcher:ClearWatcher()
	local time = os.clock()
	--Print("Checking Closing for #items: " .. #self.wndNotification:GetChildren())
	for k,v in pairs(self.wndNotification:GetChildren()) do
		local lastUpdated = v:GetData()
		if os.difftime(time, lastUpdated) > 0.5 then
			v:Close()
		end
	end
	self.wndNotification:ArrangeChildrenVert()
end

function EnvironmentWatcher:AddTracked(table, trackable)
	local buffTable = table[trackable.name]
	if not buffTable then
		table[trackable.name] = {}
		buffTable = table[trackable.name]
	end
	local i = 1
	while buffTable[i] do
		i = i + 1
	end
	buffTable[i] = trackable
end

function EnvironmentWatcher:RemoveTracked(table, trackable)
	local buffTable = table[trackable.name]
	if not buffTable then return end
	for k,v in pairs(buffTable) do
		if v == trackable then
			buffTable[k] = nil
		end
	end
end

function EnvironmentWatcher:OnListItemSelected(wndHandler, wndControl)
    -- make sure the wndControl is valid
    if wndHandler ~= wndControl then
        return
    end
    
    -- change the old item's text color back to normal color
    local wndItemText
    if self.wndSelectedListItem ~= nil then
        wndItemText = self.wndSelectedListItem:FindChild("Text")
        wndItemText:SetTextColor(kcrNormalText)
    end
    
	-- wndControl is the item selected - change its color to selected
	self.wndSelectedListItem = wndControl
	wndItemText = self.wndSelectedListItem:FindChild("Text")
    wndItemText:SetTextColor(kcrSelectedText)
    
	--Print( "item " ..  self.wndSelectedListItem:GetData().printName .. " is selected.")
	self:LoadTrackable(self.wndSelectedListItem:GetData())
end

function EnvironmentWatcher:LoadTrackable(t)
	local optionForm = self.wndMain:FindChild("OptionForm")
	optionForm:FindChild("TrackableName"):SetText(t.printName or "##ERROR##")
	
	optionForm:FindChild("BuffCheckButton"):SetCheck(t.type == trackableType["Buff"])
	optionForm:FindChild("DebuffCheckButton"):SetCheck(t.type == trackableType["Debuff"])
	optionForm:FindChild("CastCheckButton"):SetCheck(t.type == trackableType["Cast"])
	
	optionForm:FindChild("TypeName"):SetText(t.name or "##ERROR##")
	optionForm:FindChild("IdContainer"):FindChild("IdName"):SetText(t.trackId or "")
	
	optionForm:FindChild("UnitTypeContainer"):FindChild("TypePlayerCheckButton"):SetCheck(t.trackPlayer)
	optionForm:FindChild("UnitTypeContainer"):FindChild("TypeNPCCheckButton"):SetCheck(t.trackNPC)
	
	optionForm:FindChild("WatcherNameCheckButton"):SetCheck(t.textShowWatcherName)
	
	optionForm:FindChild("ChatNameContainer"):FindChild("ChatName"):SetText(t.toChat or "")
	optionForm:FindChild("ChatNameContainer"):FindChild("OptionalChatText"):SetText(t.chatOptionalText or "")
	optionForm:FindChild("ChatNameContainer"):FindChild("IdCheckButton"):SetCheck(t.chatShowId)
	
	for k,v in pairs(optionForm:FindChild("TargetMarkContainer"):GetChildren()) do
		v:SetCheck(tonumber(v:GetText()) == t.targetMark)
	end
	
	for k,v in pairs(optionForm:FindChild("SoundContainer"):FindChild("SoundChooser"):GetChildren()) do
		if v:GetText() == (soundsLookup[t.sound] or "none" )then
			v:SetTextColor(kcrSelectedText)
		else
			v:SetTextColor(kcrNormalText)
		end
	end
end

function EnvironmentWatcher:OnCloseButton()
	self.wndMain:Close() -- hide the window
end

function EnvironmentWatcher:OnAddWatcherButton( wndHandler, wndControl, eMouseButton )
	local newTrackable = {
		printName = "",
		type = trackableType["Buff"],
		name = "",
		trackId = nil,
		trackPlayer = true,
		trackNPC = false,
		-- Chat
		toChat = "",
		chatOptionalText = nil,
		chatShowId = false,
		-- More
		targetMark = 0,
		--timeShow = false,
		-- Sound
		sound = "none",
		-- Icon
		--[[
		icon = icons[1],
		iconSize = 1.0,
		iconShow = false,
		iconX = 100,
		iconY = 100,
		--]]
		-- Text
		textShowWatcherName = false,
		--
		nextNotification = {},
		showNotificationItem = true,
		notificationItem = {}
	}
	
	-- selected to normal
	self:ItemListAddWatcher(newTrackable)
end

function EnvironmentWatcher:ItemListAddWatcher(trackable)
	if self.wndSelectedListItem then
		self.wndSelectedListItem:FindChild("Text"):SetTextColor(kcrNormalText)
	end
	
	local wnd = Apollo.LoadForm(self.xmlDoc, "ListItem", self.wndItemList, self)
	wnd:FindChild("Text"):SetText(trackable.printName)
	wnd:FindChild("Text"):SetTextColor(kcrSelectedText)
	self.wndSelectedListItem = wnd
	wnd:SetData(trackable)
	self.wndItemList:ArrangeChildrenVert()
	self:LoadTrackable(trackable)
end

function EnvironmentWatcher:OnRemoveWatcherButton( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	-- 
	local delWnd = self.wndSelectedListItem:GetData()
	if delWnd.type == trackableType["Buff"] then
		self:RemoveTracked(self.trackedBuffs, delWnd)
	elseif delWnd.type == trackableType["Debuff"] then
		self:RemoveTracked(self.trackedDebuffs, delWnd)
	elseif delWnd.type == trackableType["Cast"] then
		self:RemoveTracked(self.trackedCasts, delWnd)
	else
		Print("Error 1 in OnRemoveWatcherButton: This shoud not happen.")
	end
	
	self.wndSelectedListItem:Destroy()
	self.wndItemList:ArrangeChildrenVert()
	
	local wnd = self.wndItemList:GetChildren()[1]
	if wnd then
		wnd:FindChild("Text"):SetTextColor(kcrSelectedText)
		self.wndSelectedListItem = wnd
		self:LoadTrackable(self.wndSelectedListItem:GetData())
	else
		self.wndSelectedListItem = nil
	end
end

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcherOptions
-----------------------------------------------------------------------------------------------
function EnvironmentWatcher:OnSoundChooserPressed( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY )
	if not self.wndSelectedListItem then return end
	-- make sure the wndControl is valid
    if wndHandler ~= wndControl then
        return
    end

	wndHandler:GetParent():FindChild(soundsLookup[self.wndSelectedListItem:GetData().sound] or "none"):SetTextColor(kcrNormalText)
	wndHandler:SetTextColor(kcrSelectedText)
	if wndHandler:GetText() == "none" then
		self.wndSelectedListItem:GetData().sound = nil
	else
		self.wndSelectedListItem:GetData().sound = sounds[wndHandler:GetText()]
		Sound.Play(self.wndSelectedListItem:GetData().sound)
	end
end

function EnvironmentWatcher:OnPrintNameChanged( wndHandler, wndControl, strText )
	if not self.wndSelectedListItem then return end
	self.wndSelectedListItem:FindChild("Text"):SetText(strText)
	self.wndSelectedListItem:GetData().printName = strText
	
	for k,v in pairs(self.wndSelectedListItem:GetData().notificationItem) do
		v:FindChild("WatcherName"):SetText(strText)
	end
end

function EnvironmentWatcher:OnNameChanged( wndHandler, wndControl, strText )
	if not self.wndSelectedListItem then return end
	local trackable = self.wndSelectedListItem:GetData()
	local relTable
	if trackable .type == trackableType["Buff"] then
		relTable = self.trackedBuffs
	elseif trackable .type == trackableType["Debuff"] then
		relTable = self.trackedDebuffs
	elseif trackable .type == trackableType["Cast"] then
		relTable = self.trackedCasts
	else
		Print("Error 1 in OnNameChanged: This shoud not happen.")
	end
	
	self:RemoveTracked(relTable, trackable)
	if strText == "" then
		Print("Trackable not added due to empty name.")
		return
	end
	trackable.name = strText
	self:AddTracked(relTable, trackable)
end

function EnvironmentWatcher:OnChatNameChanged( wndHandler, wndControl, strText )
	if not self.wndSelectedListItem then return end
	if strText == "" then
		self.wndSelectedListItem:GetData().toChat = nil
	else
		self.wndSelectedListItem:GetData().toChat = strText
	end
end

function EnvironmentWatcher:OnBuffChecked( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	local trackable = self.wndSelectedListItem:GetData()
	local relTable
	if trackable.type == trackableType["Buff"] then
		relTable = self.trackedBuffs
	elseif trackable.type == trackableType["Debuff"] then
		relTable = self.trackedDebuffs
	elseif trackable.type == trackableType["Cast"] then
		relTable = self.trackedCasts
	else
		Print("Error 1 in OnNameChanged: This shoud not happen.")
	end
	
	self:RemoveTracked(relTable, trackable)
	
	trackable.type = trackableType["Buff"]
	if strText == "" then
		Print("Trackable not added due to empty name.")
		return
	end
	self:AddTracked(self.trackedBuffs, trackable)
end

function EnvironmentWatcher:OnDebuffChecked( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	local trackable = self.wndSelectedListItem:GetData()
	local relTable
	if trackable.type == trackableType["Buff"] then
		relTable = self.trackedBuffs
	elseif trackable.type == trackableType["Debuff"] then
		relTable = self.trackedDebuffs
	elseif trackable.type == trackableType["Cast"] then
		relTable = self.trackedCasts
	else
		Print("Error 1 in OnNameChanged: This shoud not happen.")
	end
	
	self:RemoveTracked(relTable, trackable)
	
	trackable.type = trackableType["Debuff"]
	if strText == "" then
		Print("Trackable not added due to empty name.")
		return
	end
	self:AddTracked(self.trackedDebuffs, trackable)
end

function EnvironmentWatcher:OnCastChecked( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	local trackable = self.wndSelectedListItem:GetData()
	local relTable
	if trackable.type == trackableType["Buff"] then
		relTable = self.trackedBuffs
	elseif trackable.type == trackableType["Debuff"] then
		relTable = self.trackedDebuffs
	elseif trackable.type == trackableType["Cast"] then
		relTable = self.trackedCasts
	else
		Print("Error 1 in OnNameChanged: This shoud not happen.")
	end
	
	self:RemoveTracked(relTable, trackable)
	
	trackable.type = trackableType["Cast"]
	if strText == "" then
		Print("Trackable not added due to empty name.")
		return
	end
	self:AddTracked(self.trackedCasts, trackable)
end

function EnvironmentWatcher:OnMoveWatchersCheck( wndHandler, wndControl, eMouseButton )
	self.wndMoveWatchers:Invoke()
end

function EnvironmentWatcher:OnMoveWatchersUncheck( wndHandler, wndControl, eMouseButton )
	self.wndMoveWatchers:Close()
end

function EnvironmentWatcher:OnIdCheckButtonCheck( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	self.wndSelectedListItem:GetData().chatShowId = true
end

function EnvironmentWatcher:OnIdCheckButtonUncheck( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	self.wndSelectedListItem:GetData().chatShowId = false
end

function EnvironmentWatcher:OnIdChanged( wndHandler, wndControl, strText )
	if not self.wndSelectedListItem then return end
	if strText == "" then
		self.wndSelectedListItem:GetData().trackId = nil
	else
		local nText = tonumber(strText)
		if nText then
			self.wndSelectedListItem:GetData().trackId = nText
		else
			self.wndMain:FindChild("OptionForm"):FindChild("IdContainer"):FindChild("IdName"):SetText(self.wndSelectedListItem:GetData().trackId or "")
		end
	end

end

function EnvironmentWatcher:WatcherNameCheckButtonCheck( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	self.wndSelectedListItem:GetData().textShowWatcherName = true
end

function EnvironmentWatcher:WatcherNameCheckButtonUncheck( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	self.wndSelectedListItem:GetData().textShowWatcherName = false
end

function EnvironmentWatcher:OnTypePlayerCheck( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	self.wndSelectedListItem:GetData().trackPlayer = true
end

function EnvironmentWatcher:OnTypePlayerUncheck( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	self.wndSelectedListItem:GetData().trackPlayer = false
end

function EnvironmentWatcher:OnTypeNPCCheck( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	self.wndSelectedListItem:GetData().trackNPC = true
end

function EnvironmentWatcher:OnTypeNPCUncheck( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	self.wndSelectedListItem:GetData().trackNPC = false
end

function EnvironmentWatcher:OnOptionalChatTextChanged( wndHandler, wndControl, strText )
	if not self.wndSelectedListItem then return end
	if strText and strText ~= "" then
		self.wndSelectedListItem:GetData().chatOptionalText = strText
	else
		self.wndSelectedListItem:GetData().chatOptionalText = nil
	end
end

function EnvironmentWatcher:OnTargetMarkCheck( wndHandler, wndControl, eMouseButton )
	if not self.wndSelectedListItem then return end
	local num = tonumber(wndHandler:GetText())
	if num then
		self.wndSelectedListItem:GetData().targetMark = num
	end
end

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher Save/Restore
-----------------------------------------------------------------------------------------------
function EnvironmentWatcher:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
        return nil
    end
	local tData = {
		trackedBuffs = self.trackedBuffs,
		trackedDebuffs = self.trackedDebuffs,
		trackedCasts = self.trackedCasts,
		settings = self.settings
	}

	return tData
end

function EnvironmentWatcher:OnRestore(eLevel, tData)
	if tData then
		self.saveData = tData
	end
end


---------------------------------------------------------------------------------------------------
-- NotificationMoveForm Functions
---------------------------------------------------------------------------------------------------

function EnvironmentWatcher:OnMoveWatchers( wndHandler, wndControl, nOldLeft, nOldTop, nOldRight, nOldBottom )
	self.settings.anchorOffsets = {self.wndMoveWatchers:GetAnchorOffsets()}
	self.wndNotification:SetAnchorOffsets(unpack(self.settings.anchorOffsets))
end

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher Helpers
-----------------------------------------------------------------------------------------------
function EnvironmentWatcher:TableMerge(t1,t2)
	local t = {}
	for k,v in pairs(t1) do
		table.insert(t,v)
	end
	for k,v in pairs(t2) do
		table.insert(t,v)
	end
	
	return t
end

function EnvironmentWatcher:TableMergeUniqueId(t1,t2)
	local t = {}
	for k,v in pairs(t1) do
		t[k] = v
	end
	for k,v in pairs(t2) do
		if not t[k] then
			t[k] = v
		end
	end
	
	return t
end

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher Instance
-----------------------------------------------------------------------------------------------
local EnvironmentWatcherInst = EnvironmentWatcher:new()
EnvironmentWatcherInst:Init()
