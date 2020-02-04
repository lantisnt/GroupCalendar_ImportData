-- This file is part of Group Calendar Import Data WoW Classic AddOn.

-- Group Calendar Import Data WoW Classic AddOn is free software: 
-- you can redistribute it and/or modify it
-- under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- Group Calendar Import Data WoW Classic AddOn is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with Group Calendar Import Data WoW Classic AddOn.
-- If not, see <https://www.gnu.org/licenses/>.

local InternalState = { imported = false }
local ImportedData = {input = nil, rows = nil}
local ColumnToEventDataMapping = {}
local ColumnToClassMapping = {}
local ColumnToSpecMapping = {}

local Event = {} 
local Events = {}

local GuildRaiderCache = { CREATED = false, DATA = {}}

local MIN_RAID_LEVEL = 1;

------------------------ SECTION -------------------------
-- Addon General Functions and UI functions
----------------------------------------------------------
----------------------------------------------------------
-- OnLoad
-- Set slash command /gcid
-- Set toggle UI to it as the handler
-- PUBLIC
----------------------------------------------------------
function GroupCalendarImportData_OnLoad(frame)	  	  
	SLASH_GCIMPORTDATA1 = "/gcid";
	tinsert(UISpecialFrames, "GroupCalendarImportDataFrame");
	
	UIPanelWindows["GroupCalendarImportDataFrame"] = {area = "left", pushable = 5, whileDead = 1};
	SlashCmdList.GCIMPORTDATA = GroupCalendarImportData_ToggleFrame
end

----------------------------------------------------------
-- ToggleFrame
-- Toggle Import Frame visiblity
-- PUBLIC
----------------------------------------------------------
function GroupCalendarImportData_ToggleFrame()
  if GroupCalendarImportDataFrame:IsVisible() then
    HideUIPanel(GroupCalendarImportDataFrame);
  else
    ShowUIPanel(GroupCalendarImportDataFrame);
  end
end

------------------------ SECTION -------------------------
-- Helpers
----------------------------------------------------------
----------------------------------------------------------
-- ArrayToString
-- Stringify Array. Includes nil values as "NIL" string.
-- PRIVATE
----------------------------------------------------------
local function ArrayToString(arr, indentLevel)
  -- https://stackoverflow.com/questions/7274380/how-do-i-display-array-elements-in-lua
  local str = ""
  local indentStr = ""

  if arr == nil then
    return "NIL"
  end

  if indentLevel == nil then
    indentLevel = 2
  end

  for i = 0, indentLevel do
    indentStr = indentStr.." "
  end

  for index, value in pairs(arr) do
    if type(value) == "table" then
      str = str..indentStr..index..": \n"..ArrayToString(value, (indentLevel + 1))
    else 
      str = str..indentStr..index..": "..value.."\n"
    end
  end
  
  return str
end

----------------------------------------------------------
-- GetHMFromTimeRounded
-- Return Hours and Minutes from time string.
-- Minutes is rounded to 0/5.
-- For now supports only 24h date format
-- PRIVATE
----------------------------------------------------------
local function GetHMFromTimeRounded(string)
  local hour, minute = strsplit(":", string)
  local nHour = tonumber(hour); nMinute = tonumber(minute)
  
  if nHour then
    if nHour > 23 then
      nHour = 23
    end
  else
    nHour = 0
  end
  
  if nMinute then
    -- Minute = 10*Tens + Ones
    local minuteTens = tonumber(strsub(minute, 1, 1))
    local minuteOnes = tonumber(strsub(minute, 2, 2))
    
    -- e.g. 12:5 insted of 12:05
    if not minuteOnes then
      minuteOnes = minuteTens
      minuteTens = 0
    end
    
    if minuteOnes >= 5 then
      minuteOnes = 5
    else
      minuteOnes = 0
    end
    
    nMinute = 10*minuteTens + minuteOnes
    
  else
    nMinute = 0
  end
  
  return nHour, nMinute
end

----------------------------------------------------------
-- GetDMYToday
-- Return day, month, year for current date
-- Attention: Uses GroupCalendar current date info
-- PRIVATE
----------------------------------------------------------
local function GetDMYToday()
  local	m, d, y = Calendar_ConvertDateToMDY(gCalendarActualDate);
  return d, m, y
end

----------------------------------------------------------
-- GetDMYFromDateString
-- Return day, month, year from date string
-- Supports only D/M/Y date format
-- Supports \/-. separators
-- PRIVATE
----------------------------------------------------------
local function GetDMYFromDateString(string)
  local separator = nil
  if strfind(string, "/") then
    separator = "/"
  elseif strfind(string, "\\") then
    separator = "\\"
  elseif strfind(string, "-") then
    separator = "-"
  elseif strfind(string, ".") then
    separator = "."
  end
  
  -- Return current date from in case of error
  if not separator then
    return GetDMYToday();
  end
  
  local day, month, year = strsplit(separator, string)
  
  if not day or (day == 0) then
    day = 1
  end
  
  if not month or (month == 0) then
    month = 1
  end
  
  if not year or (year == 0) then
    year = 2020
  end
  
  return day, month, year
end
------------------------ SECTION -------------------------
-- Input data handling
----------------------------------------------------------
----------------------------------------------------------
-- ReformatData
-- Reformat data to csv
-- Supports tab, space and comma separated formats 
-- PRIVATE
----------------------------------------------------------
local function ReformatData()
  -- Copying to WoW puts 4 spaces instead of tab. Reformat all 4 spaced to ,
  local csv = gsub(ImportedData.input, "    ", ",")
  -- Reformat all tabs to ,
  csv = gsub(csv, "\t", ",")
  -- Remove multiple newlines
  csv = gsub(csv, "\n+", "\n")
  -- Split to rows
  ImportedData.rows = { strsplit("\n", csv) }
end

----------------------------------------------------------
-- IsRaidColumn
-- Check if column contains raid indicator
-- PRIVATE
----------------------------------------------------------
local function IsRaidColumn(column)
  return (strlower(strtrim(column)) == GCID.EVENT_INFO_COLUMN.RAID)
end

----------------------------------------------------------
-- IsNameColumn
-- Check if column contains event name
-- PRIVATE
----------------------------------------------------------
local function IsNameColumn(column)
  return (strlower(strtrim(column)) == GCID.EVENT_INFO_COLUMN.NAME)
end

----------------------------------------------------------
-- IsDateColumn
-- Check if column contains event date
-- PRIVATE
----------------------------------------------------------
local function IsDateColumn(column)
  return (strlower(strtrim(column)) == GCID.EVENT_INFO_COLUMN.DATE)
end

----------------------------------------------------------
-- IsTimeColumn
-- Check if column contains event time
-- PRIVATE
----------------------------------------------------------
local function IsTimeColumn(column)
  return (strlower(strtrim(column)) == GCID.EVENT_INFO_COLUMN.TIME)
end

----------------------------------------------------------
-- IsTitleRow
-- Check if row this row is the title row
-- PRIVATE
----------------------------------------------------------
local function IsTitleRow(column)
  return IsRaidColumn(column)
end

----------------------------------------------------------
-- IsEmptyColumn
-- Check column is empty
-- PRIVATE
----------------------------------------------------------
local function IsEmptyColumn(column)
  if column == nil then return true end
  if not column then return true end
  if column:len() == 0 then return true end
  return false
end

----------------------------------------------------------
-- IsTitleRowMappingValid
-- Check if title row mapping is valid
-- PRIVATE
----------------------------------------------------------
local function IsTitleRowMappingValid()
  local hasIndicator = false
  local hasName = false
  local hasDate = false
  local hasTime = false
  
  for _, column in pairs(ColumnToEventDataMapping) do
    if column == GCID.EVENT_INFO_COLUMN.RAID then
      hasIndicator = true;
    elseif column == GCID.EVENT_INFO_COLUMN.NAME then
      hasName = true;
    elseif column == GCID.EVENT_INFO_COLUMN.DATE then
      hasDate = true;
    elseif column == GCID.EVENT_INFO_COLUMN.TIME then
      hasTime = true;
    end
  end
  
  if not hasIndicator then
    GroupCalendarImportData_Error("Missing Raid indiator");
  end
  
  if not hasName then
    GroupCalendarImportData_Error("Missing raid Name");
  end
  
  if not hasDate then
    GroupCalendarImportData_Error("Missing raid Date");
  end
  
  if not hasTime then
    GroupCalendarImportData_Error("Missing raid Time");
  end
  
  return (hasIndicator and hasName and hasDate and hasTime)
end

----------------------------------------------------------
-- MapColumnsFromTitleRow
-- Map column number from 1 to n to its related specifc type
-- This allows for unordered columns
-- Resolves also which class / spec is in which column for further filling
-- PRIVATE
----------------------------------------------------------
local function MapColumnsFromTitleRow(_column, id)
  if IsEmptyColumn(_column) then return end
  -- This function is called after Raid indicator is found. No need to check for it.
  if IsNameColumn(_column) then
    ColumnToEventDataMapping[id] = GCID.EVENT_INFO_COLUMN.NAME
  elseif IsDateColumn(_column) then
    ColumnToEventDataMapping[id] = GCID.EVENT_INFO_COLUMN.DATE
  elseif IsTimeColumn(_column) then
    ColumnToEventDataMapping[id] = GCID.EVENT_INFO_COLUMN.TIME
  else
    -- Expected column format is "Class Spec" where spec can be empty and by default set to DPS
    local class, spec = strsplit(" ", strlower(strtrim(_column)))
    if not spec then
      spec = "dps"
    end
    -- Map Class
    if GCID.VALID_CLASS[class] then
      ColumnToClassMapping[id] = class
    else
      ColumnToClassMapping[id] = "unknown"
    end
    -- Map Spec
    if GCID.SPEC.NAME_MAP.DPS[spec] then
      ColumnToSpecMapping[id] = "DPS"
    elseif GCID.SPEC.NAME_MAP.HEALER[spec] then
      ColumnToSpecMapping[id] = "Healer"
    elseif GCID.SPEC.NAME_MAP.TANK[spec] then
      ColumnToSpecMapping[id] = "Tank"
    else
      ColumnToSpecMapping[id] = "Unknown"
    end
  end
end

----------------------------------------------------------
-- GetRaidId
-- Get Raid Id (defined by Group Calendar) from Raid column 
-- PRIVATE
----------------------------------------------------------
local function GetRaidId(_column)
  local column = strlower(strtrim(_column))

  local raidId = GCID.RAID.DEFAULT
  if GCID.RAID.MOLTEN_CORE.NAME_MAP[column] then
    raidId = GCID.RAID.MOLTEN_CORE.ID
  elseif GCID.RAID.ONYXIA.NAME_MAP[column] then
    raidId = GCID.RAID.ONYXIA.ID
  elseif GCID.RAID.BLACKWING_LAIR.NAME_MAP[column] then
    raidId = GCID.RAID.BLACKWING_LAIR.ID
  end

  return raidId
end

----------------------------------------------------------
-- FillEventData
-- Fill information about event and attendees based on the mapping
-- This function is called on each column of each row
-- PRIVATE
----------------------------------------------------------
local function FillEventData(_column, id)
  if IsEmptyColumn(_column) then return end
  
  -- Cleanup value. Trim spaces, remove all invalid characters
  local column = strtrim(_column)
  if ColumnToEventDataMapping[id] then
    -- Event Info
    Event[ColumnToEventDataMapping[id]] = column
  else
    -- PLAYERS
    if not Event[PLAYERS] then
      Event[PLAYERS] = {}
    end
    
    local player = { NAME = column, CLASS = ColumnToClassMapping[id], ROLE = ColumnToSpecMapping[id] }
    table.insert(Event[PLAYERS], player)
  end
end

----------------------------------------------------------
-- CreateEventsFromData
-- Parse input data to fill event info, and attendees
-- Supports multiple events
-- Requires one empty line between each event
-- First filled column must be the one with title row indication
-- PRIVATE
----------------------------------------------------------
local function CreateEventsFromData()
  local parsingRaid = false;
  
  for _rowId, row in pairs(ImportedData.rows) do
    
    local columns = { strsplit(",", row) }
    
    local foundColumnWithDataInRow = false;
    local isTitleRow = false;
    
    for _columndId, column in pairs(columns) do
      foundColumnWithDataInRow = foundColumnWithDataInRow or (column:len() > 0);
      if parsingRaid then
        -- Parse Raid Info
        FillEventData(column, _columndId)
      elseif isTitleRow then
        -- Parse title row
        MapColumnsFromTitleRow(column, _columndId)
      elseif not parsingRaid and not isTitleRow then
        -- Start searching for title row
        isTitleRow = IsTitleRow(column);
        
        if foundColumnWithDataInRow and not isTitleRow then
          -- Erroneus condition
          -- Requirement: first filled column must be the one with title row indication. 
          GroupCalendarImportData_Error("First filled column must be Raid indicator")
          return false
        end
        
        if isTitleRow then
          ColumnToEventDataMapping[_columndId] = GCID.EVENT_INFO_COLUMN.RAID
        end
        
      end
    end
    
    if not foundColumnWithDataInRow then
      -- If we got empty row we either not started parsing the events
      -- Or already completed one
      if parsingRaid then
        -- finalize parsing and create event
        parsingRaid = false;
        table.insert(Events, Event)
        ColumnToEventDataMapping = {}; ColumnToClassMapping = {}; ColumnToSpecMapping = {}
        GroupCalendarImportData_Message("Event parsed successfully.")
      end
    end
    
    if isTitleRow then
      GroupCalendarImportData_Message("Event found");
      if not IsTitleRowMappingValid() then
        return false
      end
      -- Start parting as raid input after title row
      isTitleRow = false; 
      parsingRaid = true;
      Event = {}
    end
  end
  
  -- Handle missing empty row at the end
  if parsingRaid then
    parsingRaid = false;
    table.insert(Events, Event)
    ColumnToEventDataMapping = {}; ColumnToClassMapping = {}; ColumnToSpecMapping = {}
    GroupCalendarImportData_Message("Event parsed successfully")
  end

  return true
end

----------------------------------------------------------
-- ParseDataToEvents
-- Reformat and parse import data
-- returns true on success, false otherwise
-- PRIVATE
----------------------------------------------------------
local function ParseDataToEvents()
  ReformatData();
  success = CreateEventsFromData();
  return success
end

------------------------ SECTION -------------------------
-- Guild / player info handling
----------------------------------------------------------
----------------------------------------------------------
-- GuildCachePlayersAllowedToRaid
-- Read and cache players allowed to raid
-- This data is persisted until UI reload
-- PRIVATE
----------------------------------------------------------
local function GuildCachePlayersAllowedToRaid()
  if not GuildRaiderCache.CREATED then
    -- Get Guild data
    GuildRoster();
    
    -- Cache Players that are allowed to raid
    local numTotal = GetNumGuildMembers();
    
    local cachedCount = 0;
    for i = 1, numTotal do
      local fullName, _, rankIndex, level, class = GetGuildRosterInfo(i)
      -- Classic: Remove server from name
      local name = strlower(strsplit("-", fullName))
      if level >= MIN_RAID_LEVEL then
        GuildRaiderCache.DATA[name] = { RANKINDEX = rankIndex, LEVEL = level, CLASS = class }
        cachedCount = cachedCount + 1
      end
    end
    GroupCalendarImportData_Warning("Found "..cachedCount.." players with min "..MIN_RAID_LEVEL.." lvl");
    GuildRaiderCache.CREATED = true
  end
end

----------------------------------------------------------
-- GetPlayerInfo
-- Get information about player
-- Returns false, nil, nil, nil when user is not in cache database
-- PRIVATE
----------------------------------------------------------
local function GetPlayerInfo(playerData)
  -- Check cached raiders data
  local info = GuildRaiderCache.DATA[strlower(playerData.NAME)]
  if not info then
    return false, nil, nil, nil
  else
    return true, info.CLASS, info.LEVEL, info.RANKINDEX
  end
  
  -- TODO: Blacklist
  -- TODO: Guild Rank for specific events (BWL?)
end

------------------------ SECTION -------------------------
-- Main addon modified functions
-- Those functions are modified so this addon can work
-- In an independent matter
-- Those changes are expected to be incorporated in the 
-- GroupCalendar addon further on
----------------------------------------------------------

----------------------------------------------------------
-- CalendarEventEditor_SaveEvent
-- Save Group Calendar Event
-- Data is taken from parameter instead of UI
-- PRIVATE
----------------------------------------------------------
local function _CalendarEventEditor_SaveEvent(rChangedFieldsExternal)
	-- Update the event
	local	vChangedFields = {};
	if rChangedFieldsExternal then
    vChangedFields = rChangedFieldsExternal
  else
    CalendarEventEditor_UpdateEventFromControls(gCalendarEventEditor_Event, vChangedFields);	
  end

	if not gCalendarEventEditor_IsNewEvent then
		CalendarEventEditor_SaveRSVP(gCalendarEventEditor_Event);
	end
  
	if Calendar_ArrayIsEmpty(vChangedFields) and not gCalendarEventEditor_IsNewEvent then		
		return;
	end
	
	local	vDate, vTime60 = EventDatabase_GetServerDateTime60Stamp();	
	gCalendarEventEditor_Event.mChangedDate = vDate;
	gCalendarEventEditor_Event.mChangedTime = vTime60;

	-- Save the event if it's new
	
	if gCalendarEventEditor_IsNewEvent then
		if (gCalendarEventEditor_Event.mTitle ~= nil and gCalendarEventEditor_Event.mTitle ~= "")
		or gCalendarEventEditor_Event.mType ~= nil then
			EventDatabase_AddEvent(gCalendarEventEditor_Database, gCalendarEventEditor_Event);			
		end
	else
		EventDatabase_EventChanged(gCalendarEventEditor_Database, gCalendarEventEditor_Event, vChangedFields);
	end
	
	-- Save a template for the event
	
	if gCalendarEventEditor_Event.mType
	and gCalendarEventEditor_Event.mType ~= "Birth" then
		if not gGroupCalendar_PlayerSettings.EventTemplates then
			gGroupCalendar_PlayerSettings.EventTemplates = {};
		end
		
		local	vEventTemplate = {};
		
		CalendarEventEditor_CopyTemplateFields(gCalendarEventEditor_Event, vEventTemplate);
		vEventTemplate.mSelfAttend = CalendarEventEditor_GetSelfAttend();
		
		gGroupCalendar_PlayerSettings.EventTemplates[gCalendarEventEditor_Event.mType] = vEventTemplate;
	end

	CalendarNetwork_SendEventUpdate(gCalendarEventEditor_Event, "ALERT");

	if gCalendarEventEditor_IsNewEvent then
		CalendarEventEditor_SaveRSVP(gCalendarEventEditor_Event);
	end
end


----------------------------------------------------------
-- CalendarAddPlayer_Save
-- Save Attendee to an event
-- Data is taken from parameter instead of UI
-- PRIVATE
----------------------------------------------------------
local function _CalendarAddPlayer_Save(playerInfo) -- Master addon edited function
	local vName,	vStatusCode,	vClassCode,	vRaceCode,	vLevel,	vComment,	vGuild,	vGuildRank,	vRole,	vRoleCode
  
  if playerInfo then
    vName = playerInfo.name
  else
    vName = CalendarAddPlayerFrameName:GetText();
  end
  
	if vName == "" then
		return;
	end
	if playerInfo then
    vStatusCode = playerInfo.statusCode
    vClassCode = playerInfo.classCode
    vRaceCode = playerInfo.raceCode
    vLevel = playerInfo.level
    vComment = playerInfo.comment
    vGuild = playerInfo.guild
    vGuildRank = playerInfo.guildRank
    vRole = playerInfo.role
    vRoleCode = playerInfo.roleCode
  else
    vStatusCode = UIDropDownMenu_GetSelectedValue(CalendarAddPlayerFrameStatusMenu);
    vClassCode = UIDropDownMenu_GetSelectedValue(CalendarAddPlayerFrameClassMenu);
    vRaceCode = UIDropDownMenu_GetSelectedValue(CalendarAddPlayerFrameRaceMenu);
    vLevel = tonumber(CalendarAddPlayerFrameLevel:GetText());
    vComment = Calendar_EscapeString(CalendarAddPlayerFrameComment:GetText());
    vGuild = CalendarAddPlayerFrame.Guild;
    vGuildRank = UIDropDownMenu_GetSelectedValue(CalendarAddPlayerFrameGuildRankMenu);
    vRole = UIDropDownMenu_GetSelectedValue(CalendarAddPlayerFrameRoleMenu);
    vRoleCode = EventDatabase_GetRoleCodeByRole(vRole)    
  end

	if not vGuild then
		vGuild = gGroupCalendar_PlayerGuild;
	end

	if not vGuildRank then
		vGuild = nil;
	end
	
	local vRSVP = EventDatabase_CreatePlayerRSVP(
							gCalendarEventEditor_Database,
							gCalendarEventEditor_Event,
							vName,
							vRaceCode,
							vClassCode,
							vLevel,
							vStatusCode,
							vComment,
							vGuild,
							vGuildRank,
							vRoleCode);
	
	
	gCalendarEventEditor_Event.mAttendance[vName] = vRSVP;
	
	CalendarNetwork_SendRSVPUpdate(gCalendarEventEditor_Event, vRSVP, "ALERT");

	if CalendarAddPlayerFrame.IsWhisper then
		CalendarWhisperLog_RemovePlayer(CalendarAddPlayerFrame.Name);
	end
	
	-- Send the reply /w if there is one
	
	if CalendarAddPlayerFrameWhisper:IsVisible() then
		local	vReplyWhisper = CalendarAddPlayerFrameWhisperReply:GetText();
		
		if vReplyWhisper and vReplyWhisper ~= "" then
			gGroupCalendar_PlayerSettings.LastWhisperConfirmMessage = vReplyWhisper;
			SendChatMessage(vReplyWhisper, "WHISPER", nil, CalendarAddPlayerFrame.Name);
		end
		
		-- Remember what status was used
		
		gGroupCalendar_PlayerSettings.LastWhisperStatus = UIDropDownMenu_GetSelectedValue(CalendarAddPlayerFrameStatusMenu);
	end

	
	CalendarAttendanceList_EventChanged(CalendarEventEditorAttendance, gCalendarEventEditor_Database, gCalendarEventEditor_Event);

	if EventDatabase_IsPlayer(vName) then
		CalendarEventEditor_UpdateControlsFromEvent(gCalendarEventEditor_Event, true);	
	end
end

------------------------ SECTION -------------------------
-- Data formating for GroupCalendar
----------------------------------------------------------
----------------------------------------------------------
-- PrepareEventDataForGroupCalendar
-- Prepare event data in group calendar understandable form
-- returns formated array
-- PRIVATE
----------------------------------------------------------
local function PrepareEventDataForGroupCalendar(groupCalendarEvent, eventData)
  local changedFields = {}
  
  -- Type
  local eventType = GetRaidId(eventData[GCID.EVENT_INFO_COLUMN.RAID]);
  groupCalendarEvent.mType = eventType
  changedFields.mType = {op = "UPD", val = eventType};
	
	-- Title
  groupCalendarEvent.mTitle = Calendar_EscapeString(eventData[GCID.EVENT_INFO_COLUMN.NAME]);
  changedFields.mTitle = "UPD";
  vChanged = true;
	
	-- Date and Time
  local hour, minute = GetHMFromTimeRounded(eventData[GCID.EVENT_INFO_COLUMN.TIME])
  local time = Calendar_ConvertHMToTime(hour, minute)

  -- Don't touch date
  -- local vDate = gCalendarEventEditor_EventDate
  -- groupCalendarEvent.mDate = vDate;
  -- changedFields.mDate = "UPD";
	
  groupCalendarEvent.mTime = time;
  changedFields.mTime = "UPD";
	
	-- Duration
  -- Don't touch default duration
  --	if not EventDatabase_EventTypeUsesTime(groupCalendarEvent.mType) then
  --		vValue = nil;
  --	end
    
  --	if vValue == 0 then
  --		vValue = nil;
  --	end
  
  --  groupCalendarEvent.mDuration = vValue;
  --	changedFields.mDuration = "UPD";
	
	-- Description
  groupCalendarEvent.mDescription = Calendar_EscapeString("Event imported using GroupCalendar ImportData");
  changedFields.mDescription = "UPD";
	
	-- MinLevel
  groupCalendarEvent.mMinLevel = MIN_RAID_LEVEL;
  changedFields.mMinLevel = "UPD";
	
  -- MaxLevel
  groupCalendarEvent.mMaxLevel = 60
  changedFields.mMaxLevel = "UPD";

  return changedFields
end

----------------------------------------------------------
-- CreateAttendanceListForGroupCalendar
-- Create list of attendees in format acceptable by GroupCalendar
-- returns formated array
-- PRIVATE
----------------------------------------------------------
local function CreateAttendanceListForGroupCalendar(eventData)
  GuildCachePlayersAllowedToRaid()

  local playerList = {}
  if not eventData[PLAYERS] then return playerList end
  for playerId, playerData in pairs(eventData[PLAYERS]) do

    local playerInfo = {
      name = "",
      statusCode = "Y", -- Always accepted
      classCode = nil,
      raceCode = "N", -- Don't care, set all to Night Elf
      level = nil,
      comment = "",
      guild = nil,
      guildRank = nil,
      role = nil,
      roleCode = nil
    }
    
    local allowedToRaid, _class, level, rankIndex = GetPlayerInfo(playerData)
    local class = nil
    
    if allowedToRaid then
      class = strlower(_class)
    end
    
    if not allowedToRaid then
      GroupCalendarImportData_Warning("Unknown player: ["..playerData.NAME.."]");
    elseif class ~= playerData.CLASS then
      GroupCalendarImportData_Warning("Player ["..playerData.NAME.."] has class mixed up: ["..class.." or "..playerData.CLASS.."]?");
    else
      playerInfo.name = playerData.NAME
      playerInfo.classCode = GCID.CLASS[class]
      playerInfo.level = level
      playerInfo.guildRank = rankIndex
      playerInfo.role = playerData.ROLE
      playerInfo.roleCode = GCID.SPEC[playerData.ROLE]
      table.insert(playerList, playerInfo)
    end
  end

  return playerList
end

------------------------ SECTION -------------------------
-- Main functions
----------------------------------------------------------
----------------------------------------------------------
-- CreateAndFillEvents
-- Handles the creation of events in Group Calendar
-- Requires parsed data
-- PRIVATE
----------------------------------------------------------
local function CreateAndFillEvents()
  -- Date
  -- TODO handle date properly, maybe multiple formats
  for _, eventData in pairs(Events) do
    GroupCalendarImportData_Message("Creating event: "..eventData[GCID.EVENT_INFO_COLUMN.NAME]);
    -- Select date for the event date
    local day, month, year = GetDMYFromDateString(eventData[GCID.EVENT_INFO_COLUMN.DATE])
    GroupCalendar_SelectDate(Calendar_ConvertMDYToDate(month, 1, year) + day - 1);
    -- Create event. This opens event editing window. Due to WoW API requirements its ok.
    CalendarEditor_NewEvent()
    -- Save and update event
    local eventInfo = PrepareEventDataForGroupCalendar(gCalendarEventEditor_Event, eventData)
    _CalendarEventEditor_SaveEvent(eventInfo)
    -- Add Attendees
    local playerList = CreateAttendanceListForGroupCalendar(eventData)
    for _, playerInfo in pairs(playerList) do
      _CalendarAddPlayer_Save(playerInfo)
    end
    -- Hide the event editiing window. This should happen fast enough and behind the import UI
    -- So user should not notice it. But if he does - known issue :)
    HideUIPanel(CalendarEventEditorFrame);
  end
  return true
end

----------------------------------------------------------
-- ImportAndParse
-- Main executed function
-- Handles the import of the data and creation of events.
-- PRIVATE
----------------------------------------------------------
local function ImportAndParse()
  -- 1) Get Data
  ImportedData.input = GroupCalendarImportDataFrame_ScrollFrameImportData.EditBox:GetText();

  -- 2) Parse data and get fill events info
  if ParseDataToEvents() then
    GroupCalendarImportData_Success("Parse successful");
  else
    GroupCalendarImportData_Error("Parse failed");
    return
  end

  -- 3) Display parsed data (raw format) -- TODO make it good looking
  GroupCalendarImportDataFrame_ScrollFrameImportData.EditBox:SetText(ArrayToString(Events));

  -- 4) Create GroupCalendar events, fill it with info and add attendees
  if CreateAndFillEvents() then
    GroupCalendarImportData_Success("Import complete");
  else
    GroupCalendarImportData_Error("Import error");
    return
  end

end

------------------------ SECTION -------------------------
-- Messages
----------------------------------------------------------
----------------------------------------------------------
-- GroupCalendarImportData_Success
-- Send SUCCESS message
-- PUBLIC
----------------------------------------------------------
function GroupCalendarImportData_Success(message)
  if message then
    DEFAULT_CHAT_FRAME:AddMessage(message, 0.15, 0.9, 0.15);
  end
end

----------------------------------------------------------
-- GroupCalendarImportData_Error
-- Send SUCCESS message
-- PUBLIC
----------------------------------------------------------
function GroupCalendarImportData_Error(message)
  if message then
    DEFAULT_CHAT_FRAME:AddMessage(message, 0.9, 0.15, 0.15);
  end
end

----------------------------------------------------------
-- GroupCalendarImportData_Warning
-- Send SUCCESS message
-- PUBLIC
----------------------------------------------------------
function GroupCalendarImportData_Warning(message)
  if message then
    DEFAULT_CHAT_FRAME:AddMessage(message, 0.9, 0.9, 0.15);
  end
end

----------------------------------------------------------
-- GroupCalendarImportData_Message
-- Send SUCCESS message
-- PUBLIC
----------------------------------------------------------
function GroupCalendarImportData_Message(message)
  if message then
    DEFAULT_CHAT_FRAME:AddMessage(message, 0.15, 0.15, 0.9);
  end
end

------------------------ SECTION -------------------------
-- Event Handlers
----------------------------------------------------------
----------------------------------------------------------
-- GroupCalendarImportData_ButtonImportOnClick
-- Handle Import button click
-- PUBLIC
----------------------------------------------------------
function GroupCalendarImportData_ButtonImportOnClick()
  if InternalState.imported then return end
  ImportAndParse()
  InternalState.imported = true
end

----------------------------------------------------------
-- GroupCalendarImportData_ButtonClearOnClick
-- Handle Clear button click
-- PUBLIC
----------------------------------------------------------
function GroupCalendarImportData_ButtonClearOnClick()
  -- Reset all
  InternalState.imported = false
  Events = {}; Event = {} ImportedData.input = nil; ImportedData.rows = nil;
  ColumnToEventDataMapping = {}; ColumnToClassMapping = {}; ColumnToSpecMapping = {}
  -- Do NOT clear Raider cache
  GroupCalendarImportDataFrame_ScrollFrameImportData.EditBox:SetText("");
  collectgarbage()
end