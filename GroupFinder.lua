﻿GF_RELEASEVERSION 				= "R12";
GF_SavedVariables = {
	joinworld					= true,
	lastlogout					= 0,
	disablechatfiltering		= false;
	translate					= true;
	showoriginal				= false;
	automatictranslate			= false;
	blockpolitics				= false;
	blockmessagebelowlevel		= 1;
	grouplistingduration		= 15,
	showgroupsinchat			= true,
	showgroupsinminimap			= false,
	showgroupsnewonly			= false,
	showgroupsnewonlytime		= 3,
	showchattexts				= true,
	showtradestexts				= true,
	errorfilter					= false,
	spamfilter					= true,
	spamfilterduration			= 5,
	autoblacklist				= true,
	autoblacklistminlevel		= 12,
	playsounds					= false,
	autofilter					= false,
	autofilterlevelvar			= 6,
	showtranslate				= true,
	showdungeons				= true,
	showraids					= true,
	showquests					= true,
	showother					= true,
	showlfm						= true,
	showlfg						= true,
	searchtext					= "",
	searchbuttonstext			= "",
	searchlfgtext				= "",
	searchlfgwhispertext		= "",
	lfgwhisperclass				= GF_WARRIOR,
	announcetimer				= 120,
	lfgauto						= false,
	lfgsize						= 5,
	FilterLevel					= 4,
	MinimapArcOffset			= 18,
	MinimapRadiusOffset			= 84,
	MinimapMsgArcOffset			= 345,
	MinimapMsgRadiusOffset		= 90,
	MainFrameTransparency		= 0.85,
};

local GF_WorldFound				= nil;
GF_BlackList 					= {};
GF_MessageList 					= {};
GF_FilteredResultsList 			= {};
GF_ResultsListOffset 			= 0;
GF_BlackListOffset 			= 0;
local GF_SelectedResultListItem = 0;

local GF_OnStartupRunOnce 		= 1;
local GF_SendAddonWhoBuffer		= {};
local GF_SendAddonWhoNames		= {};
local GF_SendAddonRequestNames	= {};
local GF_SendAddonRequestWho	= nil;

local GF_SendAddonMessageNames	= {};
local GF_SendAddonMessageBuffer	= {};
local GF_SendAddonRequestGroup	= nil;

local GF_AutoAnnounceTimer 		= nil;

GF_NumSearchButtons				= 0;
GF_PlayersCurrentlyInGroup 		= {};
local GF_FriendsAndGuildies		= {};
local GF_GetWhoLevel 			= 0;

local GF_UpdateTicker 			= 0;
local GF_TimeSinceLastBroadcast	= 25;
local GF_RequestTimer			= 0;

local GF_PlayerMessages 		= {}
local GF_IncomingMessagePrune 	= 0;
local GF_PreviousMessage		= {};
local GF_SentMessage			= "";
local GF_TranslatedMessage		= nil;

local GF_Classes	= {};

local GF_ClassColors = {};
GF_ClassColors[GF_PRIEST]  	= "ffffff";
GF_ClassColors[GF_MAGE] 	= "68ccef";
GF_ClassColors[GF_WARLOCK] 	= "9382c9";
GF_ClassColors[GF_DRUID] 	= "ff7c0a";
GF_ClassColors[GF_HUNTER]	= "aad372";
GF_ClassColors[GF_ROGUE]	= "fff468";
GF_ClassColors[GF_WARRIOR] 	= "c69b6d";
GF_ClassColors[GF_PALADIN] 	= "f48cba";
GF_ClassColors[GF_SHAMAN]  	= "f48cba";

function GF_OnLoad()
	SlashCmdList["GroupFinderCOMMAND"] = GF_SlashHandler; --Register Slash Command
	SLASH_GroupFinderCOMMAND1 = "/gf";
	
	this:RegisterEvent("CHAT_MSG_CHANNEL"); --Register Event Listeners
	--this:RegisterEvent("CHAT_MSG_ADDON");
	--this:RegisterEvent("PARTY_LEADER_CHANGED");
	--this:RegisterEvent("PARTY_MEMBERS_CHANGED");
	this:RegisterEvent("PLAYER_ENTERING_WORLD");
	--this:RegisterEvent("RAID_ROSTER_UPDATE");
	--this:RegisterEvent("WHO_LIST_UPDATE");
	--this:RegisterEvent("ZONE_CHANGED");
	this:RegisterEvent("PLAYER_LEAVING_WORLD");
	
	local old_ChatFrame_OnEvent = ChatFrame_OnEvent;
	function ChatFrame_OnEvent(event)
		if arg4 and (string.find(string.lower(arg4), "ttrp")
			or string.find(string.lower(arg4), "lft")) then
			-- addon channels
		elseif not arg1 or arg1 == GF_SentMessage or not arg2 or arg2 == "" or arg2 == UnitName("player") or not arg9 then
			if GF_SavedVariables.showoriginal and arg1 and arg1 ~= "" and arg1 == GF_SentMessage and string.find(arg1, "([\227\228\229\230\231\232\233\234\235\236\237])") then
				SELECTED_CHAT_FRAME:AddMessage("Translated text: "..GF_TranslateMessage(arg1), 1, 1, 1)
			end 
			GF_SentMessage = nil;
			if GF_SavedVariables.errorfilter and arg1 then 
				for i=1, getn(GF_ErrorFilters) do
					if string.find(arg1, GF_ErrorFilters[i]) then
						return
					end
				end
			end
		else
			if not GF_PreviousMessage[arg2] or GF_PreviousMessage[arg2][1] ~= arg1 or GF_PreviousMessage[arg2][2] + 30 < GetTime() then
				GF_PreviousMessage[arg2] = {arg1,GetTime(), nil, arg1} -- Old message, time of last message, whether to block message, translated message
				GF_TranslatedMessage = nil
				local tempwhodata = GF_GetWhoData(arg2)
				if not GF_PlayersCurrentlyInGroup[arg2] and not GF_FriendsAndGuildies[arg2] then									-- Block blacklist, website spam, and politics.
					if GF_BlackList[arg2] then
						GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLACKLIST_MESSAGE..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);	
						GF_PreviousMessage[arg2][3] = true;
						return;
					end
					if GF_SavedVariables.autoblacklist then
						for i=1, getn(GF_TRIGGER_LIST.SPAM) do
							if string.find(string.lower(arg1), GF_TRIGGER_LIST.SPAM[i]) then
								GF_BlackList[arg2] = string.sub(arg1,1,80);
								GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLACKLIST_ADDED..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
								GF_PreviousMessage[arg2][3] = true;
								return
							end
						end
					end
					if GF_SavedVariables.blockpolitics and arg9 ~= "" then
						for i=1, getn(GF_TRIGGER_LIST.POLITICS) do
							if string.find(string.lower(arg1), GF_TRIGGER_LIST.POLITICS[i]) then
								GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLOCKED_POLITICS..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
								GF_PreviousMessage[arg2][3] = true;
								return
							end
						end
					end
				end
				if not Questie and string.find(arg1, "|c%w+|Hquest[0-9a-fA-F:]+|h%[.-%]%|h|r") then								-- Block broken questie links
					arg1 = string.gsub(arg1, "|c%w+|Hquest[0-9a-fA-F:]+|h%[(.-)%]%|h|r", "%1")
				end
				if GF_SavedVariables.translate then 																			-- Translate Chinese to English
					arg1 = GF_TranslateMessage(arg1)
				end
				GF_PreviousMessage[arg2][4] = arg1
				local foundgroup, data;
				if arg9 ~= "" then foundgroup, data = GF_CheckForGroups(arg1,arg2,arg8,GF_PreviousMessage[arg2][1]); end
				if not GF_PlayersCurrentlyInGroup[arg2] and not GF_FriendsAndGuildies[arg2] then								-- Block if below level
					if (tempwhodata and tonumber(tempwhodata.level) < GF_SavedVariables.blockmessagebelowlevel) then
						GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLOCKED_BELOWLEVEL..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
						GF_PreviousMessage[arg2][3] = true;
						return
					end
					if GF_SavedVariables.spamfilter and (not foundgroup or string.len(arg1) > 50) then							-- Block chat spam
						if GF_IncomingMessagePrune < GetTime() then
							local tempplayermessages = {}
							for name,data in GF_PlayerMessages do
								if GF_PlayerMessages[name].time then
									tempplayermessages[name] = GF_PlayerMessages[name]
								end
							end
							GF_PlayerMessages = tempplayermessages;
							GF_IncomingMessagePrune = GetTime()+60*60;
						end
						local sniprandom = math.random(string.len(arg1) or 4)
						if not GF_PlayerMessages[arg2] then
							GF_PlayerMessages[arg2] = { [1] = string.sub(arg1,math.floor(sniprandom/4),math.floor(sniprandom/4) + 50), [2] = "ZXYXZ123" }
						elseif GF_PlayerMessages[arg2].time then
							if GF_PlayerMessages[arg2].time > time() and (string.find(arg1,GF_PlayerMessages[arg2][1],1,true) or string.find(arg1,GF_PlayerMessages[arg2][2],1,true)) then
								GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLOCKED_SPAM..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
								GF_PreviousMessage[arg2][3] = true;
								return;
							else
								GF_PlayerMessages[arg2] = nil;
							end
						else
							if string.find(arg1,GF_PlayerMessages[arg2][1],1,true) or string.find(arg1,GF_PlayerMessages[arg2][2],1,true) then
								if GF_SavedVariables.autoblacklist and not GF_BlackList[arg2] and tempwhodata
								and tonumber(tempwhodata.level) <= GF_SavedVariables.autoblacklistminlevel and string.len(arg1) > 120 then 
									if tempwhodata.recordedTime + 60*60*6 < time() then
										GF_WhoTable[arg2] = nil;
										GFAWM.addNameToWhoQueue(arg2)
									else
										GF_BlackList[arg2] = string.sub(arg1,1,80);
									end
								end
								GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLOCKED_SPAM..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
								GF_PreviousMessage[arg2][3] = true;
								GF_PlayerMessages[arg2].time = time() + GF_SavedVariables.spamfilterduration*60;
								return;
							end
							table.insert(GF_PlayerMessages[arg2],1, string.sub(arg1,math.floor(sniprandom/4),math.floor(sniprandom/4) + 50))
							table.remove(GF_PlayerMessages[arg2],3)
						end
						if string.find(arg1,string.sub(arg1,1,20),21, true) then
							GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLOCKED_SPAM..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
							GF_PreviousMessage[arg2][3] = true;
							return
						end
					end
				end
				if arg9 ~= "" then
					if foundgroup then
						if GF_SelectedResultListItem > 0 then getglobal("GF_NewItem"..GF_SelectedResultListItem.."TextureSelected"):Hide(); GF_SelectedResultListItem = 0; end
						table.insert(GF_MessageList, 1, data);
						GF_ApplyFiltersToGroupList()
						if not GF_SavedVariables.showgroupsnewonly or foundgroup == 2 then
							if data and ((GF_SavedVariables.searchtext ~= "" and GF_EntryMatchesGroupFilterCriteria(data, true) and (GF_Util.search(data.message, GF_SavedVariables.searchtext) > 0 or GF_Util.search(data.message, GF_SavedVariables.searchbuttonstext) > 0))
							or (GF_SavedVariables.searchtext == "" and GF_EntryMatchesGroupFilterCriteria(data) and (GF_SavedVariables.searchbuttonstext == "" or GF_Util.search(data.message, GF_SavedVariables.searchbuttonstext) > 0))) then
								if GF_SavedVariables.showgroupsinminimap then
									if tempwhodata then 
										GF_MinimapMessageFrame:AddMessage("|cff"..(GF_ClassColors[tempwhodata.class] or "ffffff").."|Hplayer:"..arg2.."|h "..arg2..", "..tempwhodata.level.." "..tempwhodata.class.."|h|r", 1, 0.8, 0);
									else
										GF_MinimapMessageFrame:AddMessage("|cff".."ffffff".."|Hplayer:"..arg2.."|h "..arg2.."|h|r", 1, 0.8, 0);
									end
									GF_MinimapMessageFrame2:AddMessage("|cff".."bbffbb"..arg1.. "|r", 1, 0.8, 0);
								end
								if GF_SavedVariables.playsounds then PlaySoundFile( "Sound\\Interface\\PickUp\\PutDownRing.wav" ); end
								if GF_SavedVariables.showgroupsinchat then
									if tempwhodata and not GF_SavedVariables.disablechatfiltering then
										GF_AddMessage(arg1, arg2, arg8, arg9, tempwhodata)
										GF_PreviousMessage[arg2][3] = true;
										return
									end
								else
									GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLOCKED_GROUPS..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
									GF_PreviousMessage[arg2][3] = true;
									return
								end
							else
								GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLOCKED_GROUPS..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
								GF_PreviousMessage[arg2][3] = true;
								return
							end
						else
							GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLOCKED_NEW..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
							GF_PreviousMessage[arg2][3] = true;
							return
						end
					else
						local foundtrades;
						for i=1, getn(GF_TRIGGER_LIST.TRADE) do	if string.find(string.lower(arg1), GF_TRIGGER_LIST.TRADE[i]) then foundtrades = true; end end
						if (GF_SavedVariables.showtradestexts and foundtrades) or (GF_SavedVariables.showchattexts and not foundtrades) then
							if tempwhodata and not GF_SavedVariables.disablechatfiltering then
								GF_AddMessage(arg1, arg2, arg8, arg9, tempwhodata)
								GF_PreviousMessage[arg2][3] = true;
								return
							end
						else
							GF_Log:AddMessage("["..GF_GetTime(true).."] "..GF_BLOCKED_CHAT..arg2..": "..string.sub(arg1,1,80), 1.0, 1.0, 0.5);
							GF_PreviousMessage[arg2][3] = true;
							return
						end
					end
				end
			else
				if GF_PreviousMessage[arg2][3] or (GF_PreviousMessage[arg2][1] == arg1 and GF_PreviousMessage[arg2][2] + 30 > GetTime() and GF_PreviousMessage[arg2][2] + .25 < GetTime()) then
						return
				else
					arg1 = GF_PreviousMessage[arg2][4]
				end
			end
		end
		old_ChatFrame_OnEvent(event);
	end
	--local old_SendChatMessage = SendChatMessage;
	--function SendChatMessage(arg1, arg2, arg3, arg4)
	--	local channelname;
	--	local istesting = string.find(string.sub(arg1,1,6), "testt ");
	--	if arg4 then _,channelname = GetChannelName(arg4) end
	--	if (GF_SavedVariables.automatictranslate and channelname and string.lower(channelname) == "china") or string.lower(string.sub(arg1,1,2)) == "t " or istesting then
	--		arg1 = GF_TranslateSentMessage(arg1)
	--	end
	--	GF_SentMessage = arg1;
	--	if not istesting then
	--		old_SendChatMessage(arg1, arg2, arg3, arg4)
	--	else
	--		arg1 = string.sub(arg1,7)
	--		SELECTED_CHAT_FRAME:AddMessage("Translated text: "..arg1, 1, 1, 1)
	--		SELECTED_CHAT_FRAME:AddMessage("Post-translated text: "..GF_TranslateMessage(arg1), 1, 1, 1)
	--	end
	--end
	--local old_AddIgnore = AddIgnore;
	--function AddIgnore(name)
	--	name = string.lower(name);
	--	name = string.gsub(name, "^%l", string.upper);
	--	GF_BlackList[name] = GF_DEFAULT_PLAYER_NOTE;
	--	old_AddIgnore(name);
	--end
end

function GF_SlashHandler()
	if GF_MainFrame:IsVisible() then GF_MainFrame:Hide(); else GF_MainFrame:Show(); end
	return;
end

function GF_OnUpdate()
	GFAWM.onUpdate();
	if GF_UpdateTicker < GetTime() then -- Triggers everything below every second.
		GF_UpdateTicker = GetTime() + 1

		if GF_AutoAnnounceTimer then -- Auto Announce routine
			GF_AutoAnnounceTimer = GF_AutoAnnounceTimer + 1;
			if GF_AutoAnnounceTimer > GF_SavedVariables.announcetimer then
				GF_AutoAnnounceTimer = 0;
				if GF_LFGDescriptionEditBox:GetText() ~= "" and string.len(GF_LFGDescriptionEditBox:GetText()) >= 6 then
					if GF_SavedVariables.lfgauto and string.sub(GF_LFGDescriptionEditBox:GetText(), 1, 2) == "lf" and string.sub(GF_LFGDescriptionEditBox:GetText(), 1, 3) ~= "lfg" then 
						local lfgmessage = string.gsub(GF_LFGDescriptionEditBox:GetText(), "%w+%s(.+)", "%1") or ""
						GF_SendChatMessage("LF"..GF_SavedVariables.lfgsize-GF_GetNumGroupMembers().."M "..lfgmessage, "CHANNEL", GF_CHANNEL_NAME);
						GF_Println(GF_SENT.."LF"..GF_SavedVariables.lfgsize-GF_GetNumGroupMembers().."M "..lfgmessage);
					else
						GF_SendChatMessage(GF_LFGDescriptionEditBox:GetText(), "CHANNEL", GF_CHANNEL_NAME);
						GF_Println(GF_SENT..GF_LFGDescriptionEditBox:GetText());
					end
					PlaySound("TellMessage");
					GF_MinimapMessageFrame:AddMessage(GF_ANNOUNCED_LFG_EXT, 1.0, 1.0, 0.5, 1.0, UIERRORS_HOLD_TIME);
				else
					GF_ToggleAnnounce()
					GF_Println(GF_NOTHING_TO_ANNOUNCE);
				end
			else
				GF_AnnounceToLFGButton:SetText(GF_ANNOUNCE_LFG_BTN.."-"..GF_SavedVariables.announcetimer-GF_AutoAnnounceTimer);
			end
		end
		
		GF_TimeSinceLastBroadcast = GF_TimeSinceLastBroadcast + 1;
		if GF_TimeSinceLastBroadcast > 4 then 
			GF_TimeSinceLastBroadcast = 0;
			GF_ApplyFiltersToGroupList()
			local counter = 0;
			for n,m in pairs(GF_SendAddonMessageBuffer) do
				local timedifference = (tonumber(string.sub(GF_GetTime(),1,2))*60 + tonumber(string.sub(GF_GetTime(),3,4))) - (tonumber(string.sub(m.time,1,2))*60 + tonumber(string.sub(m.time,3,4)))
				if m.who and not m.translated and (m.type == "D" or m.type == "R") and timedifference < 15 then
					local t = m.time
					local c = GF_Classes[m.who.class] or 7
					local d = m.type
					local h = m.channel or "4"
					local v = m.ilevel or 0
					local l = m.who.level or 60
					local g = m.who.guild or "<>"
					local n = m.op
					local s = string.gsub(string.gsub(m.message, "|c(%w+)|H(.+):(.+)|h(.+)|h|r", "%4"),":","")
					SendAddonMessage("GF", t..c..d..h..v..":"..l..":"..g..":"..n..":"..s, "GUILD");
					counter = counter + 1
					if counter == 10 then break end
				end
				GF_SendAddonMessageBuffer[n] = nil;
			end
			if GF_SendAddonRequestWho then
				local addonsendstring = "W"
				for n,w in pairs(GF_SendAddonWhoNames) do
					if w then addonsendstring = addonsendstring..":"..n end
					if string.len(addonsendstring) > 240 then SendAddonMessage("GF", addonsendstring, "GUILD"); addonsendstring = "W" break end
				end
				if string.len(addonsendstring) > 1 then SendAddonMessage("GF", addonsendstring, "GUILD"); end
				GF_SendAddonRequestWho = nil;
			end
			local addonsendstring = "R"
			for n,w in pairs(GF_SendAddonRequestNames) do
				if w then addonsendstring = addonsendstring..":"..n end
				if GF_SendAddonRequestNames then GF_SendAddonRequestNames[n] = nil; end
				if string.len(addonsendstring) > 240 then SendAddonMessage("GF", addonsendstring, "GUILD"); addonsendstring = "R" break end
			end
			if string.len(addonsendstring) > 1 then SendAddonMessage("GF", addonsendstring, "GUILD"); end
			
			local addonsendstring = ""
			for n,w in pairs(GF_SendAddonWhoBuffer) do
				if w[4] == "" then w[4] = "<>" end
				if w then addonsendstring = addonsendstring..":"..GF_Classes[w[3]]..n..w[2]..w[4] end
				if GF_SendAddonWhoBuffer[n] then GF_SendAddonWhoBuffer[n] = nil; end
				if string.len(addonsendstring) > 212 then SendAddonMessage("GF", addonsendstring, "GUILD"); addonsendstring = "" break end
			end
			if string.len(addonsendstring) > 1 then SendAddonMessage("GF", addonsendstring, "GUILD"); end
		end
	
		GF_RequestTimer = GF_RequestTimer + 1;
		if GF_RequestTimer == 2 then
			GF_RequestTimer = 0;
			for i=1, getn(GF_MessageList) do
				if GF_MessageList[i] and not GF_MessageList[i].who then
					local name = GF_MessageList[i].op or GF_MessageList[i].author;
					GF_MessageList[i].whoAttempts = GF_MessageList[i].whoAttempts or 0;
					GF_MessageList[i].who = GFAWM.toOldFormat(name);
					if GF_MessageList[i].who then
						GF_MessageList[i].whoAttempts = 0;
						GF_ApplyFiltersToGroupList()
					else
						if GF_MessageList[i].whoAttempts < 5 then
							if GFAWM.getPositionInQueue(name) == 0 then
								GF_MessageList[i].whoAttempts = GF_MessageList[i].whoAttempts + 1;
								GFAWM.addNameToWhoQueue(name);
							end
						else
							table.remove(GF_MessageList, i);
						end
					end
				end
				if GF_SendAddonRequestGroup and not GF_SendAddonMessageNames[GF_MessageList[i].op] then GF_SendAddonMessageBuffer[GF_MessageList[i].op] = GF_MessageList[i] end
			end
			GF_SendAddonRequestGroup = nil;
			GF_SendAddonMessageNames = {}
		end
	end
end

local function GF_LoadSettings()
	GF_Classes[1] = GF_PRIEST;
	GF_Classes[2] = GF_MAGE;
	GF_Classes[3] = GF_WARLOCK;
	GF_Classes[4] = GF_DRUID;
	GF_Classes[5] = GF_HUNTER;
	GF_Classes[6] = GF_ROGUE;
	GF_Classes[7] = GF_WARRIOR;
	if UnitFactionGroup("player") == "Alliance" then GF_Classes[8] = GF_PALADIN; else	GF_Classes[8] = GF_SHAMAN; end			
	GF_Classes[GF_PRIEST] 	= 1;
	GF_Classes[GF_MAGE] 	= 2;
	GF_Classes[GF_WARLOCK] 	= 3;
	GF_Classes[GF_DRUID] 	= 4;
	GF_Classes[GF_HUNTER] 	= 5;
	GF_Classes[GF_ROGUE] 	= 6;
	GF_Classes[GF_WARRIOR] 	= 7;
	GF_Classes[GF_PALADIN] 	= 8;
	GF_Classes[GF_SHAMAN] 	= 8;
	GF_Classes["PRIEST"] 	= GF_PRIEST;
	GF_Classes["MAGE"] 		= GF_MAGE;
	GF_Classes["WARLOCK"] 	= GF_WARLOCK;
	GF_Classes["DRUID"] 	= GF_DRUID;
	GF_Classes["HUNTER"] 	= GF_HUNTER;
	GF_Classes["ROGUE"] 	= GF_ROGUE;
	GF_Classes["WARRIOR"] 	= GF_WARRIOR;
	GF_Classes["PALADIN"] 	= GF_PALADIN;
	GF_Classes["SHAMAN"] 	= GF_SHAMAN;
	
	GF_BUTTONS_LIST["LFGLFM"][2] = { GF_TRIGGER_LIST.CLASSES[UnitClass("player")][1].." "..UnitClass("player").." LFG", 1, 60, }
	GF_BUTTONS_LIST["LFGLFM"][3] = { GF_TRIGGER_LIST.CLASSES[UnitClass("player")][2].." "..UnitClass("player").." LFG", 1, 60, }
	GF_BUTTONS_LIST["LFGLFM"][4] = { GF_TRIGGER_LIST.CLASSES[UnitClass("player")][3].." "..UnitClass("player").." LFG", 1, 60, }
	GF_BUTTONS_LIST["LFGLFM"][5] = { UnitClass("player").." LFG", 1, 60, }

	GF_MinimapArcSlider:SetValue(GF_SavedVariables.MinimapArcOffset);
	GF_MinimapRadiusSlider:SetValue(GF_SavedVariables.MinimapRadiusOffset);
	GF_MinimapMsgArcSlider:SetValue(GF_SavedVariables.MinimapMsgArcOffset);
	GF_MinimapMsgRadiusSlider:SetValue(GF_SavedVariables.MinimapMsgRadiusOffset);
	GF_UpdateMinimapIcon();

	GF_FilterLevelSlider:SetValue(GF_SavedVariables.FilterLevel);
	GF_FilterLevelSliderNote:SetText(GF_FilterLevelNotes[GF_SavedVariables.FilterLevel]);
	GF_FrameTransparencySlider:SetValue((GF_SavedVariables.MainFrameTransparency or 0.85));
	GF_MainFrame:SetAlpha(GF_FrameTransparencySlider:GetValue());

	GF_GroupsInChatCheckButton:SetChecked(GF_SavedVariables.showgroupsinchat);
	GF_GroupsInMinimapCheckButton:SetChecked(GF_SavedVariables.showgroupsinminimap);
	GF_GroupsNewOnlyCheckButton:SetChecked(GF_SavedVariables.showgroupsnewonly);

	GF_ShowChatCheckButton:SetChecked(GF_SavedVariables.showchattexts);
	GF_ShowTradesCheckButton:SetChecked(GF_SavedVariables.showtradestexts);
	GF_TranslateCheckButton:SetChecked(GF_SavedVariables.translate);

	GF_AutoFilterCheckButton:SetChecked(GF_SavedVariables.autofilter);
	GF_SearchFrameShowTranslateCheckButton:SetChecked(GF_SavedVariables.showtranslate);
	GF_SearchFrameShowDungeonCheckButton:SetChecked(GF_SavedVariables.showdungeons);
	GF_SearchFrameShowRaidCheckButton:SetChecked(GF_SavedVariables.showraids);
	GF_SearchFrameShowQuestCheckButton:SetChecked(GF_SavedVariables.showquests);
	GF_SearchFrameShowOtherCheckButton:SetChecked(GF_SavedVariables.showother);
	GF_SearchFrameShowLFMCheckButton:SetChecked(GF_SavedVariables.showlfm);
	GF_SearchFrameShowLFGCheckButton:SetChecked(GF_SavedVariables.showlfg);

	GF_FrameJoinWorldCheckButton:SetChecked(GF_SavedVariables.joinworld);
	GF_FrameDisableChatFilteringCheckButton:SetChecked(GF_SavedVariables.disablechatfiltering);
	GF_FrameAutomaticTranslateCheckButton:SetChecked(GF_SavedVariables.automatictranslate);
	GF_FrameShowOriginalTextCheckButton:SetChecked(GF_SavedVariables.showoriginal);
	
	GF_FrameErrorFilterCheckButton:SetChecked(GF_SavedVariables.errorfilter);
	GF_FrameBlockPoliticsCheckButton:SetChecked(GF_SavedVariables.blockpolitics);
	GF_FrameSpamFilterCheckButton:SetChecked(GF_SavedVariables.spamfilter);
	GF_FrameAutoBlacklistCheckButton:SetChecked(GF_SavedVariables.autoblacklist);
	GF_PlaySoundOnResultsCheckButton:SetChecked(GF_SavedVariables.playsounds);

	GF_FrameSpamFilterDurationSlider:SetValue((GF_SavedVariables.spamfilterduration or 5));
	GF_FrameSpamBlacklistMinLevelSlider:SetValue((GF_SavedVariables.autoblacklistminlevel or 12));
	GF_FrameBlockMessagesBelowLevelSlider:SetValue((GF_SavedVariables.blockmessagebelowlevel or 1));
	GF_GroupListingDurationSlider:SetValue((GF_SavedVariables.grouplistingduration or 15));
	GF_AutoFilterLevelSlider:SetValue((GF_SavedVariables.autofilterlevelvar or 6));
	GF_GroupNewTimeoutSlider:SetValue((GF_SavedVariables.showgroupsnewonlytime or 3));

	--GF_LFGAutoCheckButton:SetChecked(GF_SavedVariables.lfgauto);
	--getglobal(GF_SearchFrameDescriptionEditBox:GetName()):SetText(GF_SavedVariables.searchtext or "");
	getglobal(GF_LFGDescriptionEditBox:GetName()):SetText(GF_SavedVariables.searchlfgtext or "");
	--getglobal(GF_LFGExtraEditBox:GetName()):SetText(GF_SavedVariables.searchlfgwhispertext or "");
	--GF_FrameLFGSizeSlider:SetValue((GF_SavedVariables.lfgsize or 5));
	--GF_FrameAnnounceTimerSlider:SetValue((GF_SavedVariables.announcetimer/60 or 2));
	--getglobal(GF_LFGWhoClassDropdown:GetName().."TextLabel"):SetText(GF_SavedVariables.lfgwhisperclass or "");
	--getglobal(GF_LFGWhoClassDropdown:GetName().."TextLabel"):SetPoint("LEFT", "GF_LFGWhoClassDropdown", "LEFT", 22, 3);
end

function GF_OnEvent(event)
	if event == "PLAYER_ENTERING_WORLD" and GF_OnStartupRunOnce then
		GF_OnStartupRunOnce = nil;
		GF_LoadSettings()
		GFAWM.onEventVariablesLoaded(event);	
		GF_UpdateBlackListItems(); 
		GF_ApplyFiltersToGroupList()	
		GF_UpdatePlayersInGroupList()
		for i=1, GetNumFriends() do
			local name = GetFriendInfo(i)
			if name and not GF_FriendsAndGuildies[name] then GF_FriendsAndGuildies[name] = true; end
		end
		for i=1, GetNumGuildMembers() do
			local name = GetGuildRosterInfo(i)
			if name and not GF_FriendsAndGuildies[name] then GF_FriendsAndGuildies[name] = true; end
		end
		if GF_SavedVariables.lastlogout + 600 < GetTime() then
			local addonsendstring = "U";
			local counter = 0;
			for j=1, getn(GF_MessageList) do
				if not GF_MessageList[j].translated and (GF_MessageList[j].type == "D" or GF_MessageList[j].type == "R") then
					counter = counter + 1;
					addonsendstring = addonsendstring..":"..GF_MessageList[j].op
					if string.len(addonsendstring) > 240 then SendAddonMessage("GF", addonsendstring, "GUILD"); addonsendstring = "U" end
				end
			end
			if string.len(addonsendstring) > 1 or counter == 0 then SendAddonMessage("GF", addonsendstring, "GUILD"); end
		end
	elseif event == "CHAT_MSG_SYSTEM" and GF_AutoAnnounceTimer and string.find(arg1, GF_NOW_AFK) then
		GF_ToggleAnnounce();
		GF_Println(GF_AFK_ANNOUNCE_OFF);
	--elseif event == "CHAT_MSG_ADDON" and arg1 == "GF" and arg4 ~= UnitName("player") then
	--	if string.sub(arg2,1,1) == "U" then
	--		for w in string.gfind(arg2, "(%w+)") do
	--			GF_SendAddonMessageNames[w] = true;
	--		end
	--		GF_SendAddonWhoNames = {}
	--		for n,w in pairs(GF_WhoTable) do
	--			if not GF_SendAddonWhoBuffer[w] and w[1] + 900 > time() then GF_SendAddonWhoNames[n] = true; end
	--		end
	--		GF_RequestTimer = 0;
	--		GF_TimeSinceLastBroadcast = math.random(27);
	--		GF_SendAddonRequestGroup = true;
	--		GF_SendAddonRequestWho = true;
	--	elseif string.sub(arg2,1,1) == "W" then
	--		for sentname in gfind(arg2, ":(%w+)") do
	--			if not GF_WhoTable[sentname] then GF_SendAddonRequestNames[sentname] = true end
	--			GF_SendAddonWhoNames[sentname] = nil
	--		end
	--	elseif string.sub(arg2,1,1) == "R" then
	--		for sentname in gfind(arg2, ":(%w+)") do
	--			if GF_WhoTable[sentname] then GF_SendAddonWhoBuffer[sentname] = GF_WhoTable[sentname]; end
	--			GF_SendAddonRequestNames[sentname] = nil
	--		end
	--	elseif string.sub(arg2,1,1) == ":" then
	--		for sentclass,sentname,sentlevel,sentguild in gfind(arg2, ":(%d)([a-zA-Z]+)(%d+)([a-zA-Z%s<>]+)") do
	--			if not GF_WhoTable[sentname] then
	--				GF_WhoTable[sentname] = { time(), tonumber(sentlevel), GF_Classes[tonumber(sentclass)], string.gsub(sentguild,"[<>]", "") };
	--			end
	--			GF_SendAddonWhoNames[sentname] = nil;
	--			GF_SendAddonRequestNames[sentname] = nil;
	--			GF_SendAddonWhoBuffer[sentname] = nil;
	--		end
	--	elseif string.len(arg2) > 2 then
	--		for code, sentlevel, sentguild, sentname, com in string.gfind(arg2, "(.+):(.+):(.+):(.+):(.+)") do
	--			local tim = string.sub(code,1,4);
	--			local cla = tonumber(string.sub(code,5,5));
	--			local senttype = string.sub(code,6,6);
	--			local sentchannel = tonumber(string.sub(code,7,7));
	--			local sentilevel = tonumber(string.sub(code,8,9)) or 0;
	--
	--			if not tim or not cla or not sentlevel or not sentguild or not sentname or not senttype or not sentchannel or not sentilevel or not com then break end
	--
	--			if not GF_WhoTable[sentname] then GF_WhoTable[sentname] = { time(), tonumber(sentlevel), GF_Classes[cla], string.gsub(sentguild,"[<>]", "")}; end
	--			local whodata = {class=GF_Classes[cla], level=tonumber(sentlevel), guild=sentguild };
	--			for i = 1, getn(GF_MessageList) do
	--				if GF_MessageList[i].op and GF_MessageList[i].op == sentname then
	--					whodata = GF_MessageList[i].who;
	--					table.remove(GF_MessageList, i);
	--					break;
	--				end
	--			end
	--			local entry = {};
	--			entry.author = "";
	--			entry.message = com;
	--			entry.time = tim;
	--			entry.op = sentname;
	--			entry.who = whodata;
	--			entry.type = senttype;
	--			entry.ilevel = sentilevel
	--			entry.channel = sentchannel;
	--			if getn(GF_MessageList) > 0 then
	--				for i = 1, getn(GF_MessageList) do
	--					if entry.time > GF_MessageList[i].time then
	--						table.insert(GF_MessageList, i, entry);
	--						break;
	--					end
	--					if i == getn(GF_MessageList) then table.insert(GF_MessageList, i + 1, entry); end
	--				end
	--			else
	--				table.insert(GF_MessageList, 1, entry);
	--			end
	--			GF_SendAddonMessageBuffer[sentname] = nil;
	--		end
	--	end
	elseif event == "WHO_LIST_UPDATE" then
		GFAWM.onEventWhoListUpdated();
	elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "PARTY_MEMBERS_CHANGED" then
		if GF_AutoAnnounceTimer then
			if not UnitIsPartyLeader("player") and GF_GetNumGroupMembers() > 1 then
				GF_Println(GF_JOIN_ANNOUNCE_OFF);
				GF_ToggleAnnounce()
				GF_AutoAnnounceTimer = nil;
			elseif GF_GetNumGroupMembers() >= GF_SavedVariables.lfgsize then
				GF_Println(GF_NO_MORE_PLAYERS_NEEDED);
				GF_ToggleAnnounce()
				GF_AutoAnnounceTimer = nil;
			end
			GF_UpdatePlayersInGroupList()
		end
	elseif event == "ZONE_CHANGED" and not GF_WorldFound then
		GF_JoinWorld()
	elseif event == "PLAYER_LEAVING_WORLD" then
		GF_SavedVariables.lastlogout = GetTime();
	end
end

function GF_UpdatePlayersInGroupList()
		GF_PlayersCurrentlyInGroup = {}
		GF_PlayersCurrentlyInGroup[UnitName("player")] = true;
		for i=1, GetNumPartyMembers() do
			GF_PlayersCurrentlyInGroup[UnitName("party"..i)] = true;
		end
		for i=1, GetNumRaidMembers() do
			GF_PlayersCurrentlyInGroup[GetRaidRosterInfo(i)] = true;
		end	
end

function GF_JoinWorld(show)
	GF_WorldFound = nil;
	for i=1, 10 do
		local _,cName = GetChannelName(i)
		if cName and string.lower(cName) == string.lower(GF_CHANNEL_NAME) then
			GF_WorldFound = true;
			return
		end
	end
	if not GF_WorldFound then
		JoinChannelByName(GF_CHANNEL_NAME);
		GF_WorldFound = true;
	end
	if show then ChatFrame_AddChannel(ChatFrame1, GF_CHANNEL_NAME) end
end

function GF_LeaveWorld()
	for i=1, 10 do
		local _,cName = GetChannelName(i)
		if cName and string.lower(cName) == string.lower(GF_CHANNEL_NAME) then
			ChatFrame_RemoveChannel(1, cName);
			return
		end
	end
end

function GF_SendChatMessage(message, messageType, channel)
	if messageType == "CHANNEL" and type(channel)=="string" then
		local index = GetChannelName(channel)
		if index~=0 then channel = index end
	end
	SendChatMessage(string.gsub(message, "|c(%w+)|H(%w+):(.+)|h(.+)|h|r", "%4"), messageType, nil, channel);
end

function GF_EntryMatchesGroupFilterCriteria(entry, nolevelcheck)
	if (GF_SavedVariables.showtranslate or not entry.translated)
	and ((GF_SavedVariables.showdungeons and entry.type == "D") or (GF_SavedVariables.showraids and entry.type == "R")
	or (GF_SavedVariables.showquests and entry.type == "Q") or (GF_SavedVariables.showother and entry.type == "N"))
	and ((GF_SavedVariables.showlfg and string.find(string.lower(entry.message), "lfg"))
	or (GF_SavedVariables.showlfm and not string.find(string.lower(entry.message), "lfg")))
	and (nolevelcheck or (not GF_SavedVariables.autofilter or (entry.who and entry.who.level and entry.who.level ~= 0
	and (entry.who.level >= UnitLevel("player")-GF_SavedVariables.autofilterlevelvar and entry.who.level <= UnitLevel("player")+GF_SavedVariables.autofilterlevelvar))
	or (entry.ilevel and entry.ilevel >= UnitLevel("player")-5 and entry.ilevel <= UnitLevel("player")+5)))
	then return true; end
end

function GF_ApplyFiltersToGroupList()
	GF_SavedVariables.searchtext = GF_SearchFrameDescriptionEditBox:GetText()
	GF_SavedVariables.searchlfgtext = GF_LFGDescriptionEditBox:GetText()
	GF_FilteredResultsList = {};
	for i=1, getn(GF_MessageList) do
		local data = GF_MessageList[i];
		if data then
			local timedifference = (tonumber(string.sub(GF_GetTime(),1,2))*60 + tonumber(string.sub(GF_GetTime(),3,4))) - (tonumber(string.sub(data.time,1,2))*60 + tonumber(string.sub(data.time,3,4))) + 1
			if timedifference >= 0 and (timedifference < GF_SavedVariables.grouplistingduration or timedifference+720<GF_SavedVariables.grouplistingduration) then
				if (GF_SavedVariables.searchtext ~= "" and GF_EntryMatchesGroupFilterCriteria(data, true) and (GF_Util.search(data.message, GF_SavedVariables.searchtext) > 0 or GF_Util.search(data.message, GF_SavedVariables.searchbuttonstext) > 0))
				or (GF_SavedVariables.searchtext == "" and GF_EntryMatchesGroupFilterCriteria(data) and (GF_SavedVariables.searchbuttonstext == "" or GF_Util.search(data.message, GF_SavedVariables.searchbuttonstext) > 0)) then
					data.elapsed = timedifference;
					table.insert(GF_FilteredResultsList, data);
				elseif data.type ~= "N" and data.type ~= "D" and data.type ~= "R" and data.type ~= "Q" then
					table.remove(GF_MessageList , i);
					i = i - 1;
				end
			else
				table.remove(GF_MessageList , i);
				i = i - 1;
			end
		end
	end	
	if floor(GF_ResultsListOffset/20) > floor(getn(GF_FilteredResultsList)/20) then GF_ResultsListOffset = GF_ResultsListOffset - 20 end
	GF_UpdateResults();
end

function GF_UpdateResults()
	local index = 1;
	local groupListLength = getn(GF_FilteredResultsList);
	GF_MinimapIconTextLabel:SetText(groupListLength);
	GF_MinimapIconTextLabel:Show();
	GF_ResultsLabel:SetText(GF_RESULTS_FOUND.." "..groupListLength.." / "..getn(GF_MessageList));
	GF_PageLabel:Show();

	local cpage = floor(GF_ResultsListOffset / 20);
	local tpage = floor(groupListLength / 20);
	if cpage == 0 or cpage <= GF_ResultsListOffset / 20 then cpage = cpage + 1; end
	if tpage == 0 or tpage < groupListLength / 20 then tpage = tpage + 1; end
	GF_PageLabel:SetText(GF_PAGE.." "..cpage.." / "..tpage);

	while index < 20+1 do
		local c = "GF_NewItem"..index;
		if getglobal(c) then
			if index+GF_ResultsListOffset <= groupListLength then 
				local entry = GF_FilteredResultsList[index+GF_ResultsListOffset];
				getglobal(c.."NameLabel"):SetTextColor( 0.75, 0.75, 1, 1);

				local rightText = "";
				if entry.elapsed then
					if entry.elapsed > 1 then rightText = GF_TIME_LEFT..entry.elapsed..GF_MINUTES..GF_TIME_AGO;
					else rightText = GF_TIME_LEFT..entry.elapsed..GF_MINUTE..GF_TIME_AGO; end
				else
					rightText = entry.time;
				end
				getglobal(c.."MoreRightLabel"):SetText(rightText);
				
				local mainText = GF_GetIOPScore(entry.op) or "";
				local moreText = "";
				if entry.who and entry.who.class and entry.who.level and entry.who.level ~= 0 then
					if entry.who.guild == "<>" then
						moreText = "Level "..entry.who.level.." "..entry.who.class;
					else
						moreText = "Level "..entry.who.level.." "..entry.who.class..", "..entry.who.guild;
					end
					mainText = mainText.."|cff"..(GF_ClassColors[entry.who.class] or "ffffff")..entry.op.."|r: "..entry.message;
				else
					mainText = mainText..entry.op..": "..entry.message;
				end
				getglobal(c.."NameLabel"):SetText(mainText);
				getglobal(c.."MoreLabel"):SetText(moreText);
				getglobal(c):Show();	
			else	
				getglobal(c):Hide();
			end
		end
		index = index + 1;
	end
end

function GF_GetWhoData(arg2)
	if string.find(arg2," ") then return end
	local whodata = GFAWM.toOldFormat(arg2)
	if not whodata and IsAddOnLoaded("InventoryOnPar") then whodata = IOP.Data[GetRealmName()][arg2] end
	if not whodata and IsAddOnLoaded("pfUI") then
		whodata = pfUI_playerDB[arg2] 
		if whodata then
			whodata.class = string.sub(whodata.class,1,1)..string.lower(string.sub(whodata.class,2))
			whodata.recordedTime = time()
			whodata.guild = "<>"
		end 
	end
	if whodata then
		if not GF_WhoTable[arg2] then
			if whodata.level <= GF_SavedVariables.autoblacklistminlevel  then
				GFAWM.addNameToWhoQueue(arg2)
				return
			else
				GF_WhoTable[arg2] = { time(), whodata.level, whodata.class, whodata.guild };
			end
		end
		if whodata.recordedTime + 259200 < time() then GF_WhoTable[arg2] = nil; GFAWM.addNameToWhoQueue(arg2) end
	else
		GFAWM.addNameToWhoQueue(arg2)
	end
	return whodata
end

function GF_AddMessage(arg1, arg2, arg8, arg9, whodata)
	arg9 = string.gsub(arg9, " - .*", "")
	for i=1,NUM_CHAT_WINDOWS do
		local channellist = { GetChatWindowChannels(i) };
		for j=1, getn(channellist) do
			if string.find(arg9,channellist[j]) then
				getglobal("ChatFrame"..i):AddMessage("["..arg8..". "..string.upper(string.sub(arg9,1,1))..string.lower(string.sub(arg9,2)).."] ".."|cff"..(GF_ClassColors[whodata.class] or "ffffff").."[|Hplayer:"..arg2.."|h"..arg2..", "..whodata.level.."|h|r]: "..arg1, 1, 192/255, 192/255) 
			end
			j=j+1
		end
	end
end

function GF_GetIOPScore(name)
	if IsAddOnLoaded("InventoryOnPar") then
		local playerInfo = IOP_GetPlayerRecord(name);
		if not GearScoreCached[name] then
			if playerInfo then
				GearScoreCached[name] = IOP_GetGearScore(playerInfo.itemstring,playerInfo.class,playerInfo.level,playerInfo.set,true)
				if GearScoreCached[name] then
					if playerInfo.level >= 10 then
						return "|c"..ITEM_RARITY[math.min(math.max(math.ceil(GearScoreCached[name] / (playerInfo.level*2) - 4),0),7)].."["..GearScoreCached[name].."] ";
					else
						return "|c"..colorGold.."["..GearScoreCached[name].."] ";
					end
				end
			end
		else
			if playerInfo and GearScoreCached[name] then
				if playerInfo.level >= 10 then
					return "|c"..ITEM_RARITY[math.min(math.max(math.ceil(GearScoreCached[name] / (playerInfo.level*2) - 4),0),7)].."["..GearScoreCached[name].."] ";
				else
					return "|c"..colorGold.."["..GearScoreCached[name].."] ";
				end
			end
		end
	end	
end

function GF_ListItem_OnMouseUp() -- When you click a name in the list.
	local value = string.gsub(this:GetName(), "GF_NewItem(%d+)", "%1"); 
	if GF_SelectedResultListItem == GF_ResultsListOffset + value then
		GF_SelectedResultListItem = 0;
		getglobal(this:GetName().."TextureSelected"):Hide();
	else
		if GF_SelectedResultListItem > 0 then getglobal("GF_NewItem"..GF_SelectedResultListItem.."TextureSelected"):Hide(); end
		GF_SelectedResultListItem = GF_ResultsListOffset + value;
		getglobal(this:GetName().."TextureSelected"):Show();
		local raid = GF_FilteredResultsList[GF_ResultsListOffset + value];
		
	   	if (arg1 == "RightButton") then
	   		local name = raid.op or raid.author;
			HideDropDownMenu(1);
			if name ~= UnitName("player") then
				FriendsDropDown.initialize = FriendsFrameDropDown_Initialize;
				FriendsDropDown.displayMode = "MENU";
				FriendsDropDown.name = name;
				ToggleDropDownMenu(1, nil, FriendsDropDown, this:GetName());
			end
			return;
		end

		-- Handle LeftButton click with Ctrl pressed
		if (arg1 == "LeftButton" and IsControlKeyDown()) then
			local name = raid.op or raid.author;
			if name and name ~= UnitName("player") then
				SendChatMessage("++", "WHISPER", nil, name); -- Send "++" to the player
			end
			return;
		end
	end
	GF_UpdateResults();
end

function GF_ListItemAuxLeft_ShowTooltip()
	GetMouseFocus():GetName()
	GameTooltip:ClearLines();
	local parent = this:GetParent();
	local value = GF_ResultsListOffset + string.gsub(parent:GetName(), "GF_NewItem(%d+)", "%1");
	
	local entry = GF_FilteredResultsList[value];
	GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT");
	GameTooltip:ClearAllPoints();
	GameTooltip:SetPoint("BOTTOMLEFT", parent:GetName(), "TOPLEFT", 0, 8);
	
	if entry == nil then return; end
	
	GameTooltip:AddLine(entry.op or entry.author);
	GameTooltip:AddLine(entry.message, 0.9, 0.9, 1.0, 1, 1);
	GameTooltip:Show();
end

function GF_ListItemAuxRight_ShowTooltip()
	local parent = this:GetParent();
	GameTooltip:ClearLines();
	local value = GF_ResultsListOffset + string.gsub(parent:GetName(), "GF_NewItem(%d+)", "%1");
	
	local raid = GF_FilteredResultsList[value];
	GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT");
	GameTooltip:ClearAllPoints();
	GameTooltip:SetPoint("BOTTOMRIGHT", parent:GetName(), "TOPRIGHT", 0, 8);
	
	if raid == nil then return; end

	GameTooltip:AddLine(raid.op, 0.9, 0.9, 0.9, 1, 1)
	GameTooltip:AddLine(raid.message, 0.3, 0.9, 0.3, 1, 1)
	GameTooltip:Show();	
end

function GF_ResultItem_Hover_On(parent) -- Displays tooltip when hovering over a group in main list.
	local value = GF_ResultsListOffset + string.gsub(parent:GetName(), "GF_NewItem(%d+)", "%1");
	local entry = GF_FilteredResultsList[value];
	if entry == nil then return; end

	parent:SetHeight(32);
	getglobal(parent:GetName().."MoreLabel"):Show();
	getglobal(parent:GetName().."MoreRightLabel"):Show();
	getglobal(parent:GetName().."TextureBlue"):Show();
	getglobal(parent:GetName().."TextureSelectedIcon"):SetTexture("Interface\\Icons\\Spell_Holy_SealOfFury");	
	getglobal(parent:GetName().."NameLabel"):SetPoint("TOPLEFT", parent:GetName(), "TOPLEFT", 37, 0);
	getglobal(parent:GetName().."MoreLabel"):SetPoint("LEFT", parent:GetName(), "LEFT", 37, -6);
	getglobal(parent:GetName().."TextureSelectedBg"):Show();
	getglobal(parent:GetName().."TextureSelectedIcon"):Show();

end

function GF_ResultItem_Hover_Off(parent) -- Displays tooltip when hovering over a group in main list.
	parent:SetHeight(18);
	getglobal(parent:GetName().."MoreLabel"):Hide();
	getglobal(parent:GetName().."MoreRightLabel"):Hide();
	getglobal(parent:GetName().."TextureBlue"):Hide();

	getglobal(parent:GetName().."NameLabel"):SetPoint("TOPLEFT", parent:GetName(), "TOPLEFT", 5, 0);
	getglobal(parent:GetName().."MoreLabel"):SetPoint("LEFT", parent:GetName(), "LEFT", 5, -6);
		
	getglobal(parent:GetName().."TextureSelectedBg"):Hide();
	getglobal(parent:GetName().."TextureSelectedIcon"):Hide();

end

function GF_GetNumGroupMembers()
	if GetNumRaidMembers() > 0 then
		return GetNumRaidMembers();
	elseif GetNumPartyMembers() > 0 then
		return GetNumPartyMembers() + 1;
	else
		return 1;
	end
end

function GF_ConvertToParty()
	local numRaidMembers = GetNumRaidMembers();
	if numRaidMembers > 5 then
		GF_Println(GF_CANNOT_CONVERT_TO_PARTY);
		return;
	end
	local memberList = {};
	local name;
	while num <= numRaidMembers do	
		name = GetRaidRosterInfo(num);
		if name ~= UnitName("player") then
			memberList[num] = name;
			UninviteByName(name);
		end
		num = num + 1;
	end	
	for i = 1, numRaidMembers-1 do
		InviteByName(memberList[i]);
	end
	GF_Println(GF_CONVERTING_TO_PARTY);
end

function GF_UpdateBlackListItems()
	GF_BlackListItem0NameLabel:SetText(GF_NAME);
	GF_BlackListItem0NoteLabel:SetText(GF_PLAYER_NOTE);
	GF_BlackListItem0StatusLabel:SetText("");
	GF_BlackListItem0:Show();

	local counter = 0;
	local index = 0;
	for i=1, 15 do 
		getglobal("GF_BlackListItem"..i):Hide();
	end
	for name, note in pairs(GF_BlackList) do
		counter = counter + 1;
		if counter > GF_BlackListOffset and counter <= GF_BlackListOffset + 15 then
			index = index + 1;
			local item = getglobal("GF_BlackListItem"..index);
			getglobal("GF_BlackListItem"..index.."NameLabel"):SetText(name);
			getglobal("GF_BlackListItem"..index.."NoteLabel"):SetTextColor(1, 1, 1);
			getglobal("GF_BlackListItem"..index.."NoteLabel"):SetText(note);
			getglobal("GF_BlackListItem"..index):Show();
		end
	end
	GF_BlackListFramePageLabel:Show();

	local cpage = floor(GF_BlackListOffset / 15);
	if cpage == 0 or cpage <= GF_BlackListOffset / 15 then cpage = cpage + 1; end

	local tpage = floor(counter / 15);
	if tpage == 0 or tpage < counter / 15 then tpage = tpage + 1; end
	GF_BlackListFramePageLabel:SetText(GF_PAGE.." "..cpage.." / "..tpage);
end

function GF_ShowBlackListFrame()
	GF_SettingsFrame:Hide();
	GF_LogFrame:Hide();
	GF_BlackListFrame:Show();
	GF_UpdateBlackListItems();	
end
		
function GF_EditBlackListItem()
	GF_BlackListItemEditFrame.name = (getglobal(this:GetName().."NameLabel"):GetText() or "?");
	if not GF_BlackList[GF_BlackListItemEditFrame.name] then
		GF_BlackList[GF_BlackListItemEditFrame.name] = GF_DEFAULT_PLAYER_NOTE;
	end
	GF_BlackListItemEditFrameEditBox:SetText(GF_BlackList[GF_BlackListItemEditFrame.name]);
	GF_BlackListItemEditFrameTitleLabel:SetText(GF_EDIT_PLAYER..": "..GF_BlackListItemEditFrame.name);
	GF_BlackListItemEditFrame:Show();
end

function GF_DialogOKButton_OnCLick()
	local name = GF_AddPlayerFrameEditBox:GetText();
	if name and name ~= ""  then
		GF_BlackList[name] = GF_DEFAULT_PLAYER_NOTE;
	end
	GF_AddPlayerFrame:Hide();
	GF_ShowBlackListFrame()
end
		
function GF_BlackListItemSaveChanges()
	GF_BlackList[GF_BlackListItemEditFrame.name] = GF_BlackListItemEditFrameEditBox:GetText();
	GF_BlackList[GF_BlackListItemEditFrame.name] = GF_BlackListItemEditFrameEditBox:GetText();
	
	GF_BlackListItemEditFrame:Hide();
	GF_ShowBlackListFrame();
end
		
function GF_DeletePlayer()
	GF_BlackList[GF_BlackListItemEditFrame.name] = nil;
	GF_BlackListItemEditFrame:Hide();
	GF_ShowBlackListFrame();
end

function GF_ToggleMainFrame()
	PlaySound("igCharacterInfoTab");
	if GF_MainFrame:IsVisible() then
		GF_MainFrame:Hide();
		GF_SearchList:Hide();
	else
		GF_MainFrame:Show();
	end
end

function GF_Tab_OnCLick() -- When clicking tabs
	PlaySound("igCharacterInfoTab");
	GF_SearchFrame:Hide();
	GF_MoreFeaturesFrame:Hide();

	GF_ShowSearchButton:SetFrameLevel(GF_MainFrame:GetFrameLevel() - 1);	
	GF_ShowMFFButton:SetFrameLevel(GF_MainFrame:GetFrameLevel() - 1);	
	
	this:SetFrameLevel(GF_MainFrame:GetFrameLevel() + 1);	
	
	if this:GetName() == "GF_ShowSearchButton" then
		GF_SearchFrame:Show();	
	elseif this:GetName() == "GF_ShowPlayerListButton" then
		GF_ShowBlackListFrame();
	elseif this:GetName() == "GF_ShowSettingsButton" then
		GF_SettingsFrame:Show();
	elseif this:GetName() == "GF_ShowLogButton" then
		GF_LogFrame:Show();
	elseif this:GetName() == "GF_ShowMFFButton" then
		GF_MoreFeaturesFrame:Show();
	end
end

function GF_UpdateMinimapIcon()
	local xpos = Minimap:GetRight()
	local ypos = Minimap:GetTop()
	local xradadjust = 180 - (180*xpos/GetScreenWidth())
	local yradadjust = 180 - (180*ypos/GetScreenHeight())
	local relativepos;
	if Minimap:GetLeft() > GetScreenWidth()/2 then
		if Minimap:GetTop() > GetScreenHeight()/2 then relativepos = "TOPRIGHT"	else relativepos = "BOTTOMRIGHT" end
	else
		if Minimap:GetTop() > GetScreenHeight()/2 then relativepos = "TOPLEFT" else	relativepos = "BOTTOMLEFT" end
	end
	GF_MinimapIcon:SetPoint("TOPLEFT", "Minimap", "TOPLEFT",
		55 - ((GF_SavedVariables.MinimapRadiusOffset) * cos(GF_SavedVariables.MinimapArcOffset)),
		((GF_SavedVariables.MinimapRadiusOffset) * sin(GF_SavedVariables.MinimapArcOffset)) - 55);
	GF_MinimapMessageFrame:SetPoint(relativepos, "Minimap", relativepos,
		(0 - ((GF_SavedVariables.MinimapMsgRadiusOffset) * cos(GF_SavedVariables.MinimapMsgArcOffset + xradadjust))) - 55,
		((GF_SavedVariables.MinimapMsgRadiusOffset) * sin(GF_SavedVariables.MinimapMsgArcOffset + yradadjust)) - 55);
end

function GF_GetTime(colon)
	local hour, minute = GetGameTime();
	if hour < 10 then hour = "0"..hour; end
	if minute < 10 then minute = "0"..minute; end
	if colon then return hour..":"..minute else return hour..minute; end
end

function GF_ShowTooltip() -- Generic Tooltip. Called by XML
	if GF_GenTooltips[this:GetName()] then
		GameTooltip:SetOwner(getglobal(this:GetName()), "ANCHOR_TOP");
		GameTooltip:ClearLines();
		GameTooltip:ClearAllPoints();
		GameTooltip:SetPoint("TOPLEFT", this:GetName(), "BOTTOMLEFT", 0, -2);		
		GameTooltip:AddLine(GF_GenTooltips[this:GetName()].tooltip1);
		GameTooltip:AddLine(GF_GenTooltips[this:GetName()].tooltip2, 1, 1, 1, 1, 1);
		GameTooltip:Show();
	end
end
		
function GF_Println(m)
	if m and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("GF: "..m, 1, 1, 0.5); end		
end

function GF_ToggleAnnounce()
	if GF_AutoAnnounceTimer then
		GF_AutoAnnounceTimer = nil;
		GF_AnnounceToLFGButton:SetText(GF_ANNOUNCE_LFG_BTN);
		DEFAULT_CHAT_FRAME:AddMessage(GF_AUTO_ANNOUNCE_TURNED_OFF)
	else
		if string.len(GF_LFGDescriptionEditBox:GetText()) >= 6 then
			GF_AutoAnnounceTimer = GF_SavedVariables.announcetimer;
			GF_AnnounceToLFGButton:SetText(GF_ANNOUNCE_LFG_BTN.."-"..GF_SavedVariables.announcetimer);
			DEFAULT_CHAT_FRAME:AddMessage(GF_AUTO_ANNOUNCE_TURNED_ON)
		else
			GF_Println(GF_NOTHING_TO_ANNOUNCE);
		end
	end
end

function GF_ToggleGetWho()
	if not GF_ClassWhoRequest then
		GF_GetWhoLevel = GF_FindDungeonLevel()
		if GF_GetWhoLevel then
			GFAWM.getClassWholist(GF_SavedVariables.lfgwhisperclass, GF_GetWhoLevel, true)
		else
			GF_Println(GF_NO_WHISPER_DUNGEON);
		end
	else
		GF_ClassWhoRequest = nil;
		GF_LFGGetWhoButton:SetText(GF_GET_WHO.." - "..GFAWM.ClassWhoMatchingResults);
	end
end

function GF_LFGWhisperButton()
	local whispermessage = GF_LFGExtraEditBox:GetText()
	if whispermessage == "" then whispermessage = GF_LFGDescriptionEditBox:GetText() end
	if string.len(whispermessage) > 5 then
		GF_GetWhoLevel = GF_FindDungeonLevel()
		for k,v in pairs(GF_ClassWhoTable) do
			if GF_ClassWhoTable[k][1] < time()-GFAWM_GETWHO_RESET_TIMER then
				if GF_ClassWhoTable[k][2] >= GF_GetWhoLevel-GFAWM_GETWHO_LEVEL_RANGE and GF_ClassWhoTable[k][2] <= GF_GetWhoLevel+GFAWM_GETWHO_LEVEL_RANGE and GF_ClassWhoTable[k][3] == GF_SavedVariables.lfgwhisperclass then
					GF_ClassWhoTable[k][1] = time()
					GFAWM.ClassWhoMatchingResults = GFAWM.ClassWhoMatchingResults - 1;
					GF_LFGGetWhoButton:SetText(GF_GET_WHO.." - "..GFAWM.ClassWhoMatchingResults);
					GF_ClassWhoRequest = nil;
					ClassWhoQueue = {}
					SendChatMessage(whispermessage,"WHISPER",nil,k)
					return
				end
			end
		end
		GF_Println(GF_NO_PLAYERS_TO_WHISPER);
	else
		GF_Println(GF_NO_WHISPER_TEXT);
	end
end

function GF_FindDungeonLevel()
	for _,dtable in pairs(GF_BUTTONS_LIST["LFGDungeon"]) do
		for w in string.gfind(string.lower(GF_SavedVariables.searchlfgtext), string.lower(dtable[1])) do
			return dtable[6]
		end
    end
	for _,dtable in pairs(GF_BUTTONS_LIST["LFGRaid"]) do
		for w in string.gfind(string.lower(GF_SavedVariables.searchlfgtext), string.lower(dtable[1])) do
			return dtable[6]
		end
    end
end

local function GF_CreateSearchButton(id, parent)
	local button = CreateFrame("CheckButton", parent:GetName() .. id, parent, "GF_AbstractLabelCheckButtonClick")
	if id == 1 then
		button:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -4)
	else
		button:SetPoint("TOP", getglobal(parent:GetName() .. (id - 1) ), "BOTTOM", 0, 6)
	end
	return button
end

function GF_FixLFGStrings()
	local lfglfmtext = ""
	for _,dtable in pairs(GF_BUTTONS_LIST["LFGLFM"]) do
		for w in string.gfind(string.lower(GF_SavedVariables.searchlfgtext), string.lower(dtable[1])) do
			if lfglfmtext == "" then lfglfmtext = dtable[1] end
			local lfgstart,lfgend = string.find(string.lower(GF_SavedVariables.searchlfgtext), w)
			local prelfg = string.sub(GF_SavedVariables.searchlfgtext, 1, lfgstart-1) or ""
			local postlfg = string.sub(GF_SavedVariables.searchlfgtext, lfgend+1) or ""
			if string.sub(postlfg, 1, 1) == " " then postlfg = string.sub(postlfg, 2) end
			GF_SavedVariables.searchlfgtext = prelfg..postlfg
		end
    end
	local lfgroletext = ""
	for _,dtable in pairs(GF_BUTTONS_LIST["LFGRole"]) do
		for w in string.gfind(string.lower(GF_SavedVariables.searchlfgtext), string.lower(dtable[1])) do
			if lfgroletext == "" and lfglfmtext == "LFM" then lfgroletext = "need "..dtable[1] elseif lfgroletext == "" then lfgroletext = dtable[1] elseif not string.find(lfgroletext, dtable[1]) then lfgroletext = lfgroletext.."/"..dtable[1] end
			local lfgstart,lfgend = string.find(string.lower(GF_SavedVariables.searchlfgtext), w)
			local prelfg = string.sub(GF_SavedVariables.searchlfgtext, 1, lfgstart-1) or ""
			local postlfg = string.sub(GF_SavedVariables.searchlfgtext, lfgend+1) or ""
			if string.sub(postlfg, 1, 1) == " " or string.sub(postlfg, 1, 1) == "/" then postlfg = string.sub(postlfg, 2) end
			if string.sub(prelfg, string.len(prelfg)-4, string.len(prelfg)) == "need " then prelfg = string.sub(prelfg, 1, string.len(prelfg)-5) end
			GF_SavedVariables.searchlfgtext = prelfg..postlfg
		end
    end
	if lfgroletext == "" then GF_SavedVariables.searchlfgtext = string.gsub(GF_SavedVariables.searchlfgtext, "need ", "") end
	local lfgdungeonraidtext = ""
	for _,dtable in pairs(GF_BUTTONS_LIST["LFGDungeon"]) do
		for w in string.gfind(string.lower(GF_SavedVariables.searchlfgtext), string.lower(dtable[1])) do
			if lfgdungeonraidtext == "" then lfgdungeonraidtext = dtable[1] elseif not string.find(lfgdungeonraidtext, dtable[1]) then lfgdungeonraidtext = lfgdungeonraidtext.."/"..dtable[1] end
			local lfgstart,lfgend = string.find(string.lower(GF_SavedVariables.searchlfgtext), w)
			local prelfg = string.sub(GF_SavedVariables.searchlfgtext, 1, lfgstart-1) or ""
			local postlfg = string.sub(GF_SavedVariables.searchlfgtext, lfgend+1) or ""
			if string.sub(postlfg, 1, 1) == " " or string.sub(postlfg, 1, 1) == "/" then postlfg = string.sub(postlfg, 2) end
			GF_SavedVariables.searchlfgtext = prelfg..postlfg
		end
		for w in string.gfind(string.lower(GF_SavedVariables.searchlfgtext), string.lower(dtable[4])) do
			if lfgdungeonraidtext == "" then lfgdungeonraidtext = dtable[1] elseif not string.find(lfgdungeonraidtext, dtable[1]) then lfgdungeonraidtext = lfgdungeonraidtext.."/"..dtable[1] end
			local lfgstart,lfgend = string.find(string.lower(GF_SavedVariables.searchlfgtext), w)
			local prelfg = string.sub(GF_SavedVariables.searchlfgtext, 1, lfgstart-1) or ""
			local postlfg = string.sub(GF_SavedVariables.searchlfgtext, lfgend+1) or ""
			if string.sub(postlfg, 1, 1) == " " or string.sub(postlfg, 1, 1) == "/" then postlfg = string.sub(postlfg, 2) end
			GF_SavedVariables.searchlfgtext = prelfg..postlfg
		end
    end
	for _,dtable in pairs(GF_BUTTONS_LIST["LFGRaid"]) do
		for w in string.gfind(string.lower(GF_SavedVariables.searchlfgtext), string.lower(dtable[1])) do
			if lfgdungeonraidtext == "" then lfgdungeonraidtext = dtable[1] elseif not string.find(lfgdungeonraidtext, dtable[1]) then lfgdungeonraidtext = lfgdungeonraidtext.."/"..dtable[1] end
			local lfgstart,lfgend = string.find(string.lower(GF_SavedVariables.searchlfgtext), w)
			local prelfg = string.sub(GF_SavedVariables.searchlfgtext, 1, lfgstart-1) or ""
			local postlfg = string.sub(GF_SavedVariables.searchlfgtext, lfgend+1) or ""
			if string.sub(postlfg, 1, 1) == " " or string.sub(postlfg, 1, 1) == "/" then postlfg = string.sub(postlfg, 2) end
			GF_SavedVariables.searchlfgtext = prelfg..postlfg
		end
		for w in string.gfind(string.lower(GF_SavedVariables.searchlfgtext), string.lower(dtable[4])) do
			if lfgdungeonraidtext == "" then lfgdungeonraidtext = dtable[1] elseif not string.find(lfgdungeonraidtext, dtable[1]) then lfgdungeonraidtext = lfgdungeonraidtext.."/"..dtable[1] end
			local lfgstart,lfgend = string.find(string.lower(GF_SavedVariables.searchlfgtext), w)
			local prelfg = string.sub(GF_SavedVariables.searchlfgtext, 1, lfgstart-1) or ""
			local postlfg = string.sub(GF_SavedVariables.searchlfgtext, lfgend+1) or ""
			if string.sub(postlfg, 1, 1) == " " or string.sub(postlfg, 1, 1) == "/" then postlfg = string.sub(postlfg, 2) end
			GF_SavedVariables.searchlfgtext = prelfg..postlfg
		end
    end
	if lfglfmtext ~= "" and lfgdungeonraidtext ~= "" then
		lfglfmtext = lfglfmtext.." "..lfgdungeonraidtext
	else 
		lfglfmtext = lfglfmtext..lfgdungeonraidtext 
	end
	if lfglfmtext ~= "" and lfgroletext ~= "" then
		lfglfmtext = lfglfmtext.." "..lfgroletext
	else 
		lfglfmtext = lfglfmtext..lfgroletext
	end
	if lfglfmtext ~= "" and GF_SavedVariables.searchlfgtext ~= "" then
		lfglfmtext = lfglfmtext.." "..GF_SavedVariables.searchlfgtext
	else 
		lfglfmtext = lfglfmtext..GF_SavedVariables.searchlfgtext
	end
	GF_SavedVariables.searchlfgtext = lfglfmtext
	getglobal(GF_LFGDescriptionEditBox:GetName()):SetText(GF_SavedVariables.searchlfgtext);
end

function GF_ShowDropdownList(bframe)
	local width = 0
	GF_NumSearchButtons = 0;
	GF_SavedVariables.searchlfgtext = GF_LFGDescriptionEditBox:GetText();
	local LFGLFMFound = nil;
	for _,dtable in pairs(GF_BUTTONS_LIST[bframe]) do
		if UnitLevel("player") >= dtable[2] and UnitLevel("player") <= dtable[3] then
			GF_NumSearchButtons = GF_NumSearchButtons + 1
			local button = getglobal("GF_"..bframe..GF_NumSearchButtons) or GF_CreateSearchButton(GF_NumSearchButtons, getglobal("GF_"..bframe))
			getglobal(button:GetName().."TextLabel"):SetText(dtable[1]);
			if getglobal(button:GetName().."TextLabel"):GetStringWidth() > width then width = getglobal(button:GetName().."TextLabel"):GetStringWidth() end
			getglobal(button:GetName().."TextLabel"):SetWidth(width);
			button:Show()
			if bframe == "SearchList" then
				if string.find(GF_SavedVariables.searchbuttonstext, dtable[4]) then
					button:SetChecked(true)
				else
					button:SetChecked(false)
				end
			elseif bframe == "LFGWhoClass" then
				if string.find(GF_SavedVariables.lfgwhisperclass, dtable[1]) then
					button:SetChecked(true)
				else
					button:SetChecked(false)
				end
			else
				GF_FixLFGStrings()
				if dtable[1] == GF_CLEAR then
					button:SetChecked(true)
				else
					if string.find(GF_SavedVariables.searchlfgtext, dtable[1]) then
						if bframe== "LFGLFM" and LFGLFMFound then button:SetChecked(false) else button:SetChecked(true) LFGLFMFound = true; end
					else
						button:SetChecked(false)
					end
				end
			end
		end
	end
	getglobal("GF_"..bframe):SetHeight(12 + GF_NumSearchButtons * 18)
	getglobal("GF_"..bframe):SetWidth(width + 45)
	getglobal("GF_"..bframe):ClearAllPoints()
	getglobal("GF_"..bframe):SetPoint("TOPLEFT", getglobal("GF_"..bframe.."Dropdown"), "BOTTOMLEFT", 0, 4)
	getglobal("GF_"..bframe):Show()
end

function GF_AddRemoveSearch(bframe, entryname, add)
	if bframe == "SearchList" then
		if entryname == "Clear" then
			GF_SavedVariables.searchbuttonstext = ""
		else
			for _,dtable in pairs(GF_BUTTONS_LIST[bframe]) do
				if dtable[1] == entryname then
					for i in dtable do
						if i > 3 then 
							if add then
								GF_SavedVariables.searchbuttonstext = GF_SavedVariables.searchbuttonstext..dtable[i].."/"
							else
								for w in string.gfind(dtable[i], "%w+") do
									GF_SavedVariables.searchbuttonstext = string.gsub(GF_SavedVariables.searchbuttonstext, w.."[/%+%-]+", "")
								end
							end
						end
					end
				end
			end
		end
		GF_ApplyFiltersToGroupList();
	else
		for _,dtable in pairs(GF_BUTTONS_LIST[bframe]) do
			if dtable[1] == entryname then
				if add then
					if bframe == "LFGWhoClass" then
						GF_SavedVariables.lfgwhisperclass = entryname;
						getglobal(GF_LFGWhoClassDropdown:GetName().."TextLabel"):SetText(GF_SavedVariables.lfgwhisperclass);
						getglobal(GF_LFGWhoClassDropdown:GetName().."TextLabel"):SetPoint("LEFT", "GF_LFGWhoClassDropdown", "LEFT", 22, 3);
						GF_LFGWhoClass:Hide()
					else
						if bframe == "LFGLFM" then
							for _,dentry in pairs(GF_BUTTONS_LIST["LFGLFM"]) do
								for w in string.gfind(GF_SavedVariables.searchlfgtext, dentry[1]) do
									local lfgstart,lfgend = string.find(GF_SavedVariables.searchlfgtext, w)
									if lfgstart then 
										local prelfg = string.sub(GF_SavedVariables.searchlfgtext, 1, lfgstart-1) or ""
										local postlfg = string.sub(GF_SavedVariables.searchlfgtext, lfgend+1) or ""
										GF_SavedVariables.searchlfgtext = prelfg..postlfg
									end
								end
							end
							GF_LFGLFM:Hide()
						end
						GF_SavedVariables.searchlfgtext = dtable[1]..GF_SavedVariables.searchlfgtext
					end
				else
					local lfgstart,lfgend = string.find(GF_SavedVariables.searchlfgtext, dtable[1])
					if lfgstart then 
						local prelfg = string.sub(GF_SavedVariables.searchlfgtext, 1, lfgstart-1) or ""
						local postlfg = string.sub(GF_SavedVariables.searchlfgtext, lfgend+1) or ""
						if string.sub(postlfg, 1, 1) == "/" or string.sub(postlfg, 1, 1) == " " then postlfg = string.sub(postlfg, 2) end
						GF_SavedVariables.searchlfgtext = prelfg..postlfg
					end
					GF_LFGLFM:Hide()
				end
				getglobal(GF_LFGDescriptionEditBox:GetName()):SetText(GF_SavedVariables.searchlfgtext);
			end
		end
		GF_FixLFGStrings()
	end
end

function GF_CheckForGroups(arg1, arg2, arg8, untranslated)
	local score, gtype, glevel = GF_Util.rateResults(arg1, GF_SavedVariables.FilterLevel);
	if score == 0 then return end

	local whoData = nil;
	local savedmessage = "";
	local savedtime = string.sub(tonumber(GF_GetTime())-(GF_SavedVariables.showgroupsnewonlytime+1)+10000, 2,5)
	for i = 1, getn(GF_MessageList) do
		if arg2 == GF_MessageList[i].op then
			whoData = GF_MessageList[i].who;
			savedmessage = GF_MessageList[i].message;
			savedtime = GF_MessageList[i].time;
			table.remove(GF_MessageList, i);
			break;
		end
	end
	local entry = {};
	entry.author = "";
	entry.message = arg1;
	entry.untranslated = untranslated;
	local timedifference = (tonumber(string.sub(GF_GetTime(),1,2))*60 + tonumber(string.sub(GF_GetTime(),3,4))) - (tonumber(string.sub(savedtime,1,2))*60 + tonumber(string.sub(savedtime,3,4)))
	if savedmessage == arg1 then
		if timedifference <= GF_SavedVariables.showgroupsnewonlytime or timedifference+720 <= GF_SavedVariables.showgroupsnewonlytime then
			score = 1;
			entry.time = savedtime;
		else
			score = 2;
			entry.time = GF_GetTime();
		end
	else 
		score = 2;
		entry.time = GF_GetTime();
	end
	entry.who = GFAWM.toOldFormat(arg2) or whoData;
	entry.op = arg2;
	entry.type = gtype;
	entry.translated = GF_TranslatedMessage;
	entry.ilevel = glevel;
	entry.channel = arg8;
	return score, entry
end

function GF_TranslateMessage(arg1)
	local untranslatedsnips = {}
	local translatedsnips = {}
	local st,et,su,se;
-- Remove spam and non-punctuation characters
	local checkchars = { {"(AA+)", "AA"}, {"(%++)", "+"}, {"(=+)", "="}, {"(MM+)", "MM"}, {"(NN+)", "N"}, {"(TT+)", "T"}, {"(~+)", "~"}, {"(\\+)", "\\"}, {"(%-+)", "-"},
	{"(：+)", ""}, {"(ω+)", ""}, {"(·+)", ""}, {"(？+)", "?"}, {"(?+)", "?"}, {"(;+)", ","}, {"(》+)", ","}, {"(《+)", ","}, {"(（+)", ","}, {"(）+)", ","},
	{"(，+)", ","}, {"(、+)", ","}, {"(,+)", ","}, {"(！+)", "!"}, {"(! )", "!"}, {"(!+)", "!"}, {"(。+)", " "}, }
	for i=1, getn(checkchars) do
		arg1 = string.gsub(arg1, checkchars[i][1], checkchars[i][2])
	end
-- Translate all links
	local startingposition = 1;
	untranslatedsnips = { [1] = { arg1, 1, string.len(arg1) } }
	for linkcolor, linktype, linkstring, linkname in string.gfind(arg1, "|c(.-)|H([a-tA-T]*):(.-)|h%[(.-)%]|h|r") do
		st,et = string.find(arg1, "|c.-|H[a-tA-T]*:.-|h%[.-%]|h|r", startingposition)
		for i=1, getn(untranslatedsnips) do
			su,eu = string.find(untranslatedsnips[i][1], "|c.-|H[a-tA-T]*:.-|h%[.-%]|h|r")
			if st and su then
				local _,_,itemid = string.find(linkstring, "(%d+)(:[:%d]+)")
				local name;
				if itemid then name = GetItemInfo(itemid); end
				if (not name and linktype == "item") or linktype == "enchant" then
					table.insert(translatedsnips, { "|c"..linkcolor.."|H"..linktype..":"..linkstring.."|h[", st})
					table.insert(translatedsnips, { "]|h|r", et})
					table.insert(untranslatedsnips, { linkname, et-string.len(linkname)-4, string.len(linkname)})
					table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], eu+1), et+1, string.len(string.sub(untranslatedsnips[i][1], eu+1))})
					untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], 1, su-1), st-1, string.len(string.sub(untranslatedsnips[i][1], 1, su-1))}
					local replaceitemlinkwithchars = ""
					for j=st, et-string.len(linkname)-5 do
						replaceitemlinkwithchars = replaceitemlinkwithchars.."="
					end
					arg1 = string.sub(arg1, 1, st-1)..replaceitemlinkwithchars..linkname.."====="..string.sub(arg1, et+1)
					break
				end
				if not name then name = linkname; end
				table.insert(translatedsnips, { "|c"..linkcolor.."|H"..linktype..":"..linkstring.."|h["..name.."]|h|r", st})
				table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], eu+1), et+1, string.len(string.sub(untranslatedsnips[i][1], eu+1))})
				untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], 1, su-1), st-1, string.len(string.sub(untranslatedsnips[i][1], 1, su-1))}
				local replaceitemlinkwithchars = ""
				for j=st,et do
					replaceitemlinkwithchars = replaceitemlinkwithchars.."="
				end
				arg1 = string.sub(arg1, 1, st-1)..replaceitemlinkwithchars..string.sub(arg1, et+1)
				break
			end
			startingposition = et+1
		end
	end
	table.sort(untranslatedsnips, function(a,b) return a[2] < b[2] end)
-- Find all Chinese character sequences to compare to.
	startingposition = 1																																
	while true do
		st,et,checkchars = string.find(arg1, "([%w%s%p]+)", startingposition)
		for i=1, getn(untranslatedsnips) do
			su,eu = string.find(untranslatedsnips[i][1], "([%w%s%p]+)", 1)
			if st and su and not string.find(checkchars, "==") then
				table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], 1, su-1), st-1, string.len(string.sub(untranslatedsnips[i][1], 1, su-1))})
				table.insert(untranslatedsnips, { checkchars, st,string.len(checkchars)})
				untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], eu+1), et+1, string.len(string.sub(untranslatedsnips[i][1], eu+1))}
				break
			end
		end
		if not st or not su then break else startingposition = et+1 end
	end
-- Compare the Chinese sequences against our database
	st = {}
	local r = 0;
	local counter;
	local w;
	local charstring;
	while getn(untranslatedsnips) > r do
		r = getn(untranslatedsnips)
		table.sort(untranslatedsnips, function(a,b) return a[3] > b[3] end)
		for i=1, r do
			if untranslatedsnips[i][1] ~= "" and string.find(untranslatedsnips[i][1], "([\227\228\229\230\231\232\233\234\235\236\237])") then
				untranslatedsnips[i][1] = string.gsub(untranslatedsnips[i][1], "[%w%s%p]+", "")
				checkchars = string.len(untranslatedsnips[i][1])
				counter = math.floor(checkchars/3)
				while counter > 0 and checkchars >= 3 do
					su = 1
					eu = counter * 3
					while eu <= checkchars do
						charstring = string.sub(untranslatedsnips[i][1],su,eu)
						w = GF_Translate[counter][charstring]
						if w then
							if not st[charstring] then st[charstring] = 1 end
							st[charstring], et = string.find(arg1, charstring, st[charstring])
							table.insert(translatedsnips, { w[1], st[charstring] })
							table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], 1, su-1), st[charstring]-1,string.len(string.sub(untranslatedsnips[i][1], 1, su-1))})
							untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], eu+1), et+1,string.len(string.sub(untranslatedsnips[i][1], eu+1))}
							st[charstring] = et+1
							counter = counter + 1
							break
						end
						su = su + 3
						eu = eu + 3
					end
					counter = counter - 1
				end
			end
		end
	end
-- Translate abbreviations into English
	table.sort(untranslatedsnips, function(a,b) return a[3] > b[3] end)
	if string.find(arg1, "([\227\228\229\230\231\232\233\234\235\236\237])") then GF_TranslatedMessage = true; end
	startingposition = 1;
	while true do
		st,et,checkchars = string.find(string.upper(arg1),"([%a']+)",startingposition)
		if st then
			for k,v in pairs(GF_Translate["ENGLISH"]) do
				if checkchars == k and (string.len(checkchars) > 2 or GF_TranslatedMessage) then -- and not string.find(checkchars, "[ABCDEGHIJKLMOPRUVWXYZ]")) then
					for i=1, getn(untranslatedsnips) do
						su = string.find(string.upper(untranslatedsnips[i][1]),checkchars,1,true)
						c,eu = string.find(checkchars,k,1,true)
						if su and c then
							table.insert(translatedsnips, { v[1], st+c-1})
							table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], su+eu), st+eu,})
							untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], 1, su-1), st+c-2}
							GF_TranslatedMessage = true;
							break
						end
					end
				end
			end
			startingposition = et+1
		else
			break
		end
	end
-- Translate the 4=1-type messages into LFM messages
	startingposition = 1;
	while true do
		st,et,checkchars,w = string.find(arg1,"(%d)%=+(%d)",startingposition)
		if not st then st,et,w = string.find(arg1,"%=+(%d)",startingposition) end
		for i=1, getn(untranslatedsnips) do
			su,eu = string.find(untranslatedsnips[i][1],"%d%=+(%d)",1)
			if not su then su,eu = string.find(untranslatedsnips[i][1],"%=+(%d)",1) end
			if st and su then
				if tonumber(w) > 0 then
					if checkchars then table.insert(translatedsnips, { "LF"..w.."M", st}) else table.insert(translatedsnips, { "need "..w, st}) end
					table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], eu+1), et+1,string.len(string.sub(untranslatedsnips[i][1], eu+1))})
					untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], 1, su-1), st-1,string.len(string.sub(untranslatedsnips[i][1], 1, su-1))}
				end
				break
			end
		end
		if not st or not su then break else startingposition = et+1 end
	end
-- Place the remaining untranslated snips into the translated database
	for i=1, getn(untranslatedsnips) do
		if untranslatedsnips[i][1] ~= "" then 
			table.insert(translatedsnips, untranslatedsnips[i])
		end
	end
-- Sort the translated snips by original position so that I can create the final string to be returned
	table.sort(translatedsnips, function(a,b) return a[2] < b[2] end)
	arg1 = ""
	for i=1, getn(translatedsnips) do
		if arg1 ~= "" and not string.find(translatedsnips[i][1],"^[ ,=%+]") then arg1 = arg1.." " end
		arg1 = arg1..translatedsnips[i][1]
	end
	arg1 = string.gsub(arg1,"( +)", " ")
	return arg1
end

function GF_TranslateSentMessage(arg1)
	if string.sub(arg1,1,2) == "t " then arg1 = string.sub(arg1,3) end
	local untranslatedsnips = {}
	local translatedsnips = {}
	local st,et,su,se
-- Remove punctuation characters
	local checkchars = { {"(')", ""}, }
	for i=1, getn(checkchars) do
		arg1 = string.gsub(arg1, checkchars[i][1], checkchars[i][2])
	end
-- Translate all links
	local startingposition = 1;
	untranslatedsnips = { [1] = { arg1, 1, string.len(arg1) } }
	for linkcolor, linktype, linkstring, linkname in string.gfind(arg1, "|c(.-)|H([a-tA-T]*):(.-)|h%[(.-)%]|h|r") do
		st,et = string.find(arg1, "|c.-|H[a-tA-T]*:.-|h%[.-%]|h|r", startingposition)
		for i=1, getn(untranslatedsnips) do
			su,eu = string.find(untranslatedsnips[i][1], "|c.-|H[a-tA-T]*:.-|h%[.-%]|h|r")
			if st and su then
				--[[if linktype == "item" or linktype == "enchant" then
					table.insert(translatedsnips, { "|c"..linkcolor.."|H"..linktype..":"..linkstring.."|h[", st})
					table.insert(translatedsnips, { "]|h|r", et})
					table.insert(untranslatedsnips, { linkname, et-string.len(linkname)-4, string.len(linkname)})
					table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], eu+1), et+1, string.len(string.sub(untranslatedsnips[i][1], eu+1))})
					untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], 1, su-1), st-1, string.len(string.sub(untranslatedsnips[i][1], 1, su-1))}
					local replaceitemlinkwithchars = ""
					for j=st, et-string.len(linkname)-5 do
						replaceitemlinkwithchars = replaceitemlinkwithchars.."="
					end
					arg1 = string.sub(arg1, 1, st-1)..replaceitemlinkwithchars..linkname.."====="..string.sub(arg1, et+1)
					break
				end--]]
				table.insert(translatedsnips, { "|c"..linkcolor.."|H"..linktype..":"..linkstring.."|h["..linkname.."]|h|r", st})
				table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], eu+1), et+1, string.len(string.sub(untranslatedsnips[i][1], eu+1))})
				untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], 1, su-1), st-1, string.len(string.sub(untranslatedsnips[i][1], 1, su-1))}
				local replaceitemlinkwithchars = ""
				for j=st,et do
					replaceitemlinkwithchars = replaceitemlinkwithchars.."="
				end
				arg1 = string.sub(arg1, 1, st-1)..replaceitemlinkwithchars..string.sub(arg1, et+1)
				break
			end
			startingposition = et+1
		end
	end
-- Convert everything to lowercase
	for i=1, getn(untranslatedsnips) do
		untranslatedsnips[i][1] = string.lower(untranslatedsnips[i][1])
	end
	arg1 = string.lower(arg1)
-- Translate from LF??M to =??
	startingposition = 1;
	local w;
	while true do
		st,et,w = string.find(arg1,"lf(%d+)m",startingposition)
		for i=1, getn(untranslatedsnips) do
			su,eu = string.find(untranslatedsnips[i][1],"lf(%d+)m",1)
			if st and su then
				if tonumber(w) > 0 then
					table.insert(translatedsnips, { "="..num, st})
					table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], eu+1), et+1,string.len(string.sub(untranslatedsnips[i][1], eu+1))})
					untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], 1, su-1), st-1,string.len(string.sub(untranslatedsnips[i][1], 1, su-1))}
				end
				break
			end
		end
		if not st or not su then break else startingposition = et+1 end
	end
-- Translate to Chinese
	local counter;
	counter = getn(GF_Translate)
	while counter > 0 do
		for k,v in pairs(GF_Translate[counter]) do
			for j=1, getn(v) do
				startingposition = 1;
				while true do
					st,et = string.find(arg1,v[j],startingposition,true)
					for i=1, getn(untranslatedsnips) do
						su,eu = string.find(untranslatedsnips[i][1],v[j],1,true)
						if st and su and not string.find(string.sub(arg1,st-1,st-1),"[a-z]") and not string.find(string.sub(arg1,et+1,et+1),"[a-z]") then
							table.insert(translatedsnips, { k, st})
							table.insert(untranslatedsnips, { string.sub(untranslatedsnips[i][1], eu+1), et+1,string.len(string.sub(untranslatedsnips[i][1], eu+1))})
							untranslatedsnips[i] = { string.sub(untranslatedsnips[i][1], 1, su-1), st-1,string.len(string.sub(untranslatedsnips[i][1], 1, su-1))}
							break
						end
					end
					if not st then break else startingposition = et+1 end
				end
			end
		end
		counter = counter - 1
	end
	for i=1, getn(untranslatedsnips) do
		if untranslatedsnips[i][1] ~= "" then 
			table.insert(translatedsnips, untranslatedsnips[i])
		end
	end
	table.sort(translatedsnips, function(a,b) return a[2] < b[2] end)
	arg1 = ""
	for i=1, getn(translatedsnips) do
		--if arg1 ~= "" and string.sub(arg1, string.len(arg1)) ~= " " then arg1 = arg1.." " end
		arg1 = arg1..translatedsnips[i][1]
	end
	arg1 = string.gsub(arg1,"( +)", " ")
	return arg1
end
