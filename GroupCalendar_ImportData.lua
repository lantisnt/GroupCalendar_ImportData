local InternalState = { parsed = false, imported = false }
local ImportedData = {input = nil, rows = nil}
local ColumnToEventDataMapping = {}
local ColumnToClassMapping = {}
local ColumnToSpecMapping = {}
local SpecToColumnMapping = { DPS = {}, HEALER = {}, TANK = {} }

-- Event = { NAME = "", DATE = "", TIME = "", PLAYERS = {} }
-- PlayerData = { {NAME = "", CLASS = "", ROLE = ""}}
local Event = {} 
local Events = {}

local GuildRaiderCache = { CREATED = false, DATA = {}}

local MIN_RAID_LEVEL = 1;

-- DEFAULT_CHAT_FRAME:AddMessage(, 0.8, 0.8, 0.2);

local LAST_MEMORY_IN_USE = 0
local DEBUG = false;

MIN_RAID_LEVEL = 0;

-- Functions

local function DiffMemoryUsage()
  if not DEBUG then return end
  local currentMemoryInUse = gcinfo()
  local diff = currentMemoryInUse - LAST_MEMORY_IN_USE
  DEFAULT_CHAT_FRAME:AddMessage("Memory diff: "..diff.." KB", 0.15, 0.15, 0.80);
  LAST_MEMORY_IN_USE = currentMemoryInUse
end

function GroupCalendarImportData_OnLoad(frame)	  	  
  DiffMemoryUsage()
  
	SLASH_GCIMPORTDATA1 = "/gcid";
	--SLASH_GCIMPORTDATADEBUG1 = "/gcidd";
	tinsert(UISpecialFrames, "GroupCalendarImportDataFrame");
	
	UIPanelWindows["GroupCalendarImportDataFrame"] = {area = "left", pushable = 5, whileDead = 1};
	SlashCmdList.GCIMPORTDATA = GroupCalendarImportData_ToggleFrame
  --SlashCmdList.GCIMPORTDATADEBUG = CreateEventAtDate
end

function GroupCalendarImportData_ToggleFrame()
  if GroupCalendarImportDataFrame:IsVisible() then
    HideUIPanel(GroupCalendarImportDataFrame);
  else
    ShowUIPanel(GroupCalendarImportDataFrame);
  end
end



function ArrayToString(arr, indentLevel)
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

-- Column / row decoding functions

local function IsRaidColumn(column)
  return (strlower(strtrim(column)) == GCID.EVENT_INFO_COLUMN.RAID)
end

local function IsNameColumn(column)
  return (strlower(strtrim(column)) == GCID.EVENT_INFO_COLUMN.NAME)
end

local function IsDateColumn(column)
  return (strlower(strtrim(column)) == GCID.EVENT_INFO_COLUMN.DATE)
end

local function IsTimeColumn(column)
  return (strlower(strtrim(column)) == GCID.EVENT_INFO_COLUMN.TIME)
end

local function IsTitleRow(column)
  return IsRaidColumn(column)
end

local function IsEmptyColumn(column)
  if column == nil then return true end
  if not column then return true end
  if column:len() == 0 then return true end
  return false
end

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
      ColumnToClassMapping[id] = GCID.CLASS.UNKNOWN.NAME
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

 -- Parsing

local function ParseDataToEvents()
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
          GroupCalendarImportData_Error("First filled column must be [Raid] indicator")
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
      end
    end
    
    if isTitleRow then
      -- Start parting as raid input after title row
      isTitleRow = false;
      parsingRaid = true;
      Event = {}
    end
  
  end

  return true
end

local function ParseData()
  ReformatData();
  success = ParseDataToEvents();
  if success then
    DEFAULT_CHAT_FRAME:AddMessage("Parse Successful", 0.15, 0.9, 0.15);
  else
    DEFAULT_CHAT_FRAME:AddMessage("Parse Failed", 0.9, 0.15, 0.15);
  end
  DiffMemoryUsage();
end

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
    DEFAULT_CHAT_FRAME:AddMessage("Found "..cachedCount.." players with min "..MIN_RAID_LEVEL.." lvl", 0.15, 0.15, 0.80);
    GuildRaiderCache.CREATED = true
  end
  DiffMemoryUsage();
end

local function GetCachedPlayerInfo(playerData)
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

---------------------------------------------------------
--------------------------------------
-------------------

function InternalSaveEvent(rChangedFieldsExternal) -- Master addon edited function
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

-------------------
-------------------
-------------------
function InternalAddPlayer(playerInfo) -- Master addon edited function
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
-------------------
-------------------
-------------------
function UpdateEventFromParsedData(rEvent, rChangedFields, eventData)
  
  -- Type
  local eventType = GetRaidId(eventData[GCID.EVENT_INFO_COLUMN.RAID]);
  rEvent.mType = eventType
  rChangedFields.mType = {op = "UPD", val = eventType};
	
	-- Title
  rEvent.mTitle = Calendar_EscapeString(eventData[GCID.EVENT_INFO_COLUMN.NAME]);
  rChangedFields.mTitle = "UPD";
  vChanged = true;
	
	-- Date and Time
  local vTime = Calendar_ConvertHMToTime(20, 30)

  -- Dont touch date
  -- local vDate = gCalendarEventEditor_EventDate
  -- rEvent.mDate = vDate;
  -- rChangedFields.mDate = "UPD";
	
  rEvent.mTime = vTime;
  rChangedFields.mTime = "UPD";
	
	-- Duration
  -- Don't touch default duration
  --	if not EventDatabase_EventTypeUsesTime(rEvent.mType) then
  --		vValue = nil;
  --	end
    
  --	if vValue == 0 then
  --		vValue = nil;
  --	end
  
  --  rEvent.mDuration = vValue;
  --	rChangedFields.mDuration = "UPD";
	
	-- Description
  rEvent.mDescription = Calendar_EscapeString("Event imported using GroupCalendar ImportData");
  rChangedFields.mDescription = "UPD";
	
	-- MinLevel
	
	if EventDatabase_EventTypeUsesLevelLimits(rEvent.mType) then
		vValue = MIN_RAID_LEVEL
	else
		vValue = nil;
	end
	
  if vValue == 0 then
    vValue = nil;
	end
	
  rEvent.mMinLevel = vValue;
  rChangedFields.mMinLevel = "UPD";
	
  -- MaxLevel
	
	if EventDatabase_EventTypeUsesTime(rEvent.mType) then
		vValue = 60
	else
		vValue = nil;
	end

  if vValue == 0 then
    vValue = nil;
	end
	
  rEvent.mMaxLevel = vValue;
  rChangedFields.mMaxLevel = "UPD";

end
-------------------
-------------------
-------------------
function CreateAttendanceListFromParsedData(playerList, eventData)
  GuildCachePlayersAllowedToRaid()

  for playerId, playerData in pairs(eventData[PLAYERS]) do

    local playerInfo = {
      name = "",
      statusCode = "Y", -- Always accepted
      classCode = nil,
      raceCode = "N", -- Don't care, set all to Night Elf
      level = nil,
      comment = "Attendee imported using GroupCalendar ImportData",
      guild = nil,
      guildRank = nil,
      role = nil,
      roleCode = nil
    }
    
    local allowedToRaid, _class, level, rankIndex = GetCachedPlayerInfo(playerData)
    local class = nil
    
    if allowedToRaid then
      class = strlower(_class)
    end
    
    if not allowedToRaid then
      DEFAULT_CHAT_FRAME:AddMessage("Raid <"..eventData[GCID.EVENT_INFO_COLUMN.NAME].."> unknown player: ["..playerData.NAME.."]", 0.8, 0.8, 0.2);
    elseif class ~= playerData.CLASS then
      DEFAULT_CHAT_FRAME:AddMessage("Player ["..playerData.NAME.."] has class mixed up: ["..class.." or "..playerData.CLASS.."]?", 0.8, 0.8, 0.2);
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

end
-------------------
-------------------
-------------------
function CreateAndFillEvents()
  -- Date
  -- TODO handle date properly, maybe multiple formats
  for _, eventData in pairs(Events) do
    local day, month, year = strsplit("-", eventData[GCID.EVENT_INFO_COLUMN.DATE])
    local	vMonthStartDate = Calendar_ConvertMDYToDate(month, 1, year);
    -- ---
    local eventInfo = {}
    local playerList = {}
    -- ---
    GroupCalendar_SelectDate(vMonthStartDate + day - 1);
    -- Create event
    CalendarEditor_NewEvent()
    UpdateEventFromParsedData(gCalendarEventEditor_Event, eventInfo, eventData)
    -- Save and upate event
    InternalSaveEvent(eventInfo)
    -- Attendees
    CreateAttendanceListFromParsedData(playerList, eventData)
    for _, playerInfo in pairs(playerList) do
      InternalAddPlayer(playerInfo)
    end
    -- Hide
    HideUIPanel(CalendarEventEditorFrame); -- hide the edit window, as everything is done atuomatically
  end
end

-------------------
--------------------------------------
---------------------------------------------------------

-- Other Functions

function GroupCalendarImportData_Error(message)
  if message then
    DEFAULT_CHAT_FRAME:AddMessage("GroupCalendar ImportData Error: "..message, 0.9, 0.15, 0.15);
  end
end

function GroupCalendarImportData_ButtonImportOnClick()
  DiffMemoryUsage();
  if InternalState.parsed then return end
  -- 1) Get Data
  ImportedData.input = GroupCalendarImportDataFrame_ScrollFrameImportData.EditBox:GetText();
  -- 2) Parse data to get Events array
  ParseData();
  -- 3) Display parsed data (raw format) -- TODO make it good looking
  GroupCalendarImportDataFrame_ScrollFrameImportData.EditBox:SetText(ArrayToString(Events));
  -- 4)
  CreateAndFillEvents();
  -- 
  InternalState.parsed = true
end

function GroupCalendarImportData_ButtonClearOnClick()
  DiffMemoryUsage();
  -- Reset all
  InternalState.parsed = false
  Events = {}
  Event = {}
  ImportedData.input = nil
  ImportedData.rows = nil
  ColumnToEventDataMapping = {}
  ColumnToClassMapping = {}
  ColumnToSpecMapping = {}
  SpecToColumnMapping.DPS = {}
  SpecToColumnMapping.HEALER = {}
  SpecToColumnMapping.TANK = {}
  -- Do NOT clear Raider  cache
  GroupCalendarImportDataFrame_ScrollFrameImportData.EditBox:SetText("");
  collectgarbage()
  DiffMemoryUsage();
end