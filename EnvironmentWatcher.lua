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

local icons = {
	"kA"
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
	o.settings = {
		notificationsX = 10,
		notificationsY = 10
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
 

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher OnLoad
-----------------------------------------------------------------------------------------------
function EnvironmentWatcher:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("EnvironmentWatcher.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher OnDocLoaded
-----------------------------------------------------------------------------------------------
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
		
		-- item list
		self.wndItemList = self.wndMain:FindChild("ItemList")
	    self.wndMain:Show(false, true)
		self.wndNotification:Show(false, true)
		self.wndNotification:Invoke()

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		Apollo.RegisterEventHandler("UnitEnteredCombat", "OnEnteredCombat", self)
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("ew", "OnEnvironmentWatcherOn", self)

		self.timer = ApolloTimer.Create(0.100, true, "OnTimer", self)

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
		end
	end
end

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/ew"
function EnvironmentWatcher:OnEnvironmentWatcherOn()
	self.wndMain:Invoke() -- show the window
	--self.wndItemList:ArrangeChildrenVert()
end

-- on timer
function EnvironmentWatcher:OnTimer()
	for id1, unit in pairs(self.watched) do
		local unitName = unit:GetName()
		local buffs = unit:GetBuffs()
		if buffs then
			-- Buffs
			for kB, buff in pairs(buffs.arBeneficial) do
				local trackTable = self.trackedBuffs[buff.splEffect:GetName()]
				if trackTable then
					for k, v in pairs(trackTable) do
						if v.showNotificationItem then
							if not v.notificationItem[unitName] then
								v.notificationItem[unitName] = Apollo.LoadForm(self.xmlDoc, "NotificationItem", self.wndNotification, self)
								v.notificationItem[unitName]:FindChild("Icon"):FindChild("ProgressBar"):SetMax(buff.fTimeRemaining)
								v.notificationItem[unitName]:FindChild("Icon"):SetSprite(buff.splEffect:GetIcon())
								v.notificationItem[unitName]:FindChild("Text"):SetText(unitName)
								self.wndNotification:ArrangeChildrenVert()
							end
							v.notificationItem[unitName]:FindChild("Icon"):FindChild("ProgressBar"):SetProgress(buff.fTimeRemaining)
							v.notificationItem[unitName]:FindChild("Icon"):FindChild("IconText"):SetText(tonumber(string.format("%.2f", buff.fTimeRemaining)))
						end
						if not v.nextNotification[unitName] or os.difftime(v.nextNotification[unitName] , os.clock()) <= 0 then
							if v.toChat then
								self:SendChatMessage(v, unitName .. " has buff " .. v.name)
							end
							if v.sound and v.sound ~= "none" then
								Sound.Play(v.sound)
							end
							v.nextNotification[unitName] = os.clock() + buff.fTimeRemaining + 1.0
						end
					end
				end
			end
			-- Debuffs
			for kB, debuff in pairs(buffs.arHarmful) do
				local trackTable = self.trackedDebuffs[debuff.splEffect:GetName()]
				if trackTable then
					for k, v in pairs(trackTable) do
						if v.showNotificationItem then
							if not v.notificationItem[unitName] then
								v.notificationItem[unitName] = Apollo.LoadForm(self.xmlDoc, "NotificationItem", self.wndNotification, self)
								v.notificationItem[unitName]:FindChild("Icon"):FindChild("ProgressBar"):SetMax(debuff.fTimeRemaining)
								v.notificationItem[unitName]:FindChild("Icon"):SetSprite(debuff.splEffect:GetIcon())
								v.notificationItem[unitName]:FindChild("Text"):SetText(unitName)
								self.wndNotification:ArrangeChildrenVert()
							end
							v.notificationItem[unitName]:FindChild("Icon"):FindChild("ProgressBar"):SetProgress(debuff.fTimeRemaining)
							v.notificationItem[unitName]:FindChild("Icon"):FindChild("IconText"):SetText(tonumber(string.format("%.2f", debuff.fTimeRemaining)))
						end
						if not v.nextNotification[unitName] or os.difftime(v.nextNotification[unitName] , os.clock()) <= 0 then
							if v.toChat then
								self:SendChatMessage(v, unitName .. " has debuff " .. v.name)
							end
							if v.sound and v.sound ~= "none" then
								Sound.Play(v.sound)
							end
							v.nextNotification[unitName] = os.clock() + debuff.fTimeRemaining + 1.0
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
					if v.showNotificationItem then
						if not v.notificationItem[unitName] then
							v.notificationItem[unitName] = Apollo.LoadForm(self.xmlDoc, "NotificationItem", self.wndNotification, self)
							v.notificationItem[unitName]:FindChild("Icon"):FindChild("ProgressBar"):SetMax(castPercentage)
							--v.notificationItem[unitName]:FindChild("Icon"):SetSprite(buff.splEffect:GetIcon())
							v.notificationItem[unitName]:FindChild("Text"):SetText(unitName)
							self.wndNotification:ArrangeChildrenVert()
						end
						v.notificationItem[unitName]:FindChild("Icon"):FindChild("ProgressBar"):SetProgress(unit:GetCastElapsed())
						v.notificationItem[unitName]:FindChild("Icon"):FindChild("IconText"):SetText(tonumber(string.format("%.2f", unit:GetCastElapsed()/1000.0)))
					end
					if not v.nextNotification[unitName] or os.difftime(v.nextNotification[unitName] , os.clock()) <= 0 then
						if v.toChat then
							self:SendChatMessage(v, unitName .. " is casting " .. v.name)
						end
						if v.sound and v.sound ~= "none" then
							Sound.Play(v.sound)
						end
						v.nextNotification[unitName] = os.clock() + (unit:GetCastDuration())/1000.0 + 1.0
					end
				end
			end
		end
	end
	-- clear workaround
	self:ClearWatcher()
end

function EnvironmentWatcher:ClearWatcher()
	for _,v in pairs(self.trackedBuffs) do
		for _,trackable in pairs(v) do
			for k,noti in pairs(trackable.nextNotification) do
				if trackable.notificationItem[k] and os.difftime(noti , os.clock()) <= 0 then
					trackable.notificationItem[k]:Destroy()
					trackable.notificationItem[k] = nil
				end
			end
		end
	end
	for _,v in pairs(self.trackedDebuffs) do
		for _,trackable in pairs(v) do
			for k,noti in pairs(trackable.nextNotification) do
				if trackable.notificationItem[k] and os.difftime(noti , os.clock()) <= 0 then
					trackable.notificationItem[k]:Destroy()
					trackable.notificationItem[k] = nil
				end
			end
		end
	end
	for _,v in pairs(self.trackedCasts) do
		for _,trackable in pairs(v) do
			for k,noti in pairs(trackable.nextNotification) do
				if trackable.notificationItem[k] and os.difftime(noti , os.clock()) <= 0 then
					trackable.notificationItem[k]:Destroy()
					trackable.notificationItem[k] = nil
				end
			end
		end
	end
	self.wndNotification:ArrangeChildrenVert()
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

function EnvironmentWatcher:OnEnteredCombat(unitChanged,bInCombat)
	if bInCombat then
		--Print("OnEnteredCombat(".. unitChanged:GetName() ..", true)")
		self.watched[unitChanged:GetId()] = unitChanged
	else
		--Print("OnEnteredCombat(".. unitChanged:GetName() ..", false)")
		self.watched[unitChanged:GetId()] = nil
	end
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

-----------------------------------------------------------------------------------------------
-- EnvironmentWatcherForm Functions
-----------------------------------------------------------------------------------------------
function EnvironmentWatcher:LoadTrackable(t)
	local optionForm = self.wndMain:FindChild("OptionForm")
	optionForm:FindChild("TrackableName"):SetText(t.printName or "##ERROR##")
	
	optionForm:FindChild("BuffCheckButton"):SetCheck(t.type == trackableType["Buff"])
	optionForm:FindChild("DebuffCheckButton"):SetCheck(t.type == trackableType["Debuff"])
	optionForm:FindChild("CastCheckButton"):SetCheck(t.type == trackableType["Cast"])
	
	optionForm:FindChild("TypeName"):SetText(t.name or "##ERROR##")
	
	optionForm:FindChild("ChatNameContainer"):FindChild("ChatName"):SetText(t.toChat or "")
	
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
		toChat = "",
		timeShow = false,
		-- Sound
		sound = "none",
		soundPlay = false,
		-- Icon
		icon = icons[1],
		iconSize = 1.0,
		iconShow = false,
		iconX = 100,
		iconY = 100,
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

function EnvironmentWatcher:OnSoundChooserPressed( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY )
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
	self.wndSelectedListItem:FindChild("Text"):SetText(strText)
	self.wndSelectedListItem:GetData().printName = strText
end

function EnvironmentWatcher:OnNameChanged( wndHandler, wndControl, strText )
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
	if strText == "" then
		self.wndSelectedListItem:GetData().toChat = nil
	else
		self.wndSelectedListItem:GetData().toChat = strText
	end
end

function EnvironmentWatcher:OnBuffChecked( wndHandler, wndControl, eMouseButton )
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
	
	trackable.type = trackableType["Buff"]
	if strText == "" then
		Print("Trackable not added due to empty name.")
		return
	end
	self:AddTracked(self.trackedBuffs, trackable)
end

function EnvironmentWatcher:OnDebuffChecked( wndHandler, wndControl, eMouseButton )
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
	
	trackable.type = trackableType["Debuff"]
	if strText == "" then
		Print("Trackable not added due to empty name.")
		return
	end
	self:AddTracked(self.trackedDebuffs, trackable)
end

function EnvironmentWatcher:OnCastChecked( wndHandler, wndControl, eMouseButton )
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
	
	trackable.type = trackableType["Cast"]
	if strText == "" then
		Print("Trackable not added due to empty name.")
		return
	end
	self:AddTracked(self.trackedCasts, trackable)
end

-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------

-- when a list item is selected
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
    
	Print( "item " ..  self.wndSelectedListItem:GetData().printName .. " is selected.")
	self:LoadTrackable(self.wndSelectedListItem:GetData())
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


-----------------------------------------------------------------------------------------------
-- EnvironmentWatcher Instance
-----------------------------------------------------------------------------------------------
local EnvironmentWatcherInst = EnvironmentWatcher:new()
EnvironmentWatcherInst:Init()
