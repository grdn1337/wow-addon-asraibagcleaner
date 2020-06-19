-----------------------------------
-- Setting up scope and libs
-----------------------------------

local AddonName, ABC = ...;
LibStub("AceEvent-3.0"):Embed(ABC);
LibStub("AceTimer-3.0"):Embed(ABC);
LibStub("AceComm-3.0"):Embed(ABC);
LibStub("AceConsole-3.0"):Embed(ABC);
LibStub("AceSerializer-3.0"):Embed(ABC);

setmetatable(ABC, {__tostring = function() return AddonName end});

local _G = _G;
local profiles = {};

local Dialog = LibStub("LibDialog-1.0");

local DialogTable_SyncRequest = {
	text = "",
	buttons = {
		{text = _G.ACCEPT, on_click = function(self)
			if( not(type(self.data) == "table" and self.data.sender and type(self.data.data) == "table") ) then
				self:Print("Data on data sync request is corrupt. Aborted. Try again.");
			else
				ABC:SendCommMessage("abcok", ABC:Serialize(self.data.data), "WHISPER", self.data.sender);
			end
		end},
		{text = _G.CANCEL},
	},
};
Dialog:Register("ABC_SyncRequest", DialogTable_SyncRequest);

_G.AsraiBagCleaner = ABC;

-------------------------------
-- Registering with iLib
-------------------------------

LibStub("iLib"):Register(AddonName, nil, ABC);

-----------------------------------------
-- Variables, functions and colors
-----------------------------------------

function ABC:CleanBags(dungeon, profile) 
	self:RebuildSecureIndex();

	local insecurities = 0;
	local qualities = 0;
	local list = self.db.profiles[dungeon] and self.db.profiles[dungeon][profile] or {};

	self:Print("Start cleaning your bags.");
	
	for b = 0, 4 do
		for s = 1, 32 do
			local _, _, _, quality, _, _, itemlink, _, _, itemid = _G.GetContainerItemInfo(b, s);

			if( list[itemid] ) then
				if( quality >= 3 ) then -- rare
					qualities = qualities + 1;
				elseif( not self.db.secure[itemid] ) then
					insecurities = insecurities + 1;
					self:Printf("%s |cffff0000was not deleted due to its insecure state|r. Approve it using: |c0000ffff/abc approve %s|r", itemlink, itemid);
				else
					_G.PickupContainerItem(b, s)
					_G.DeleteCursorItem()
				end
			end
		end
	end

	self:Print("Report =============================================");
	
	if( insecurities > 1 ) then
		self:Printf("|cffff0000There where %s slots of unapproved items.|r", insecurities);
		self:Print("Approve them all by once using: |c0000ffff/abc approve all|r");
	end
	if( qualities >= 1 ) then
		self:Printf("%s items were not deleted due to their higher quality.", qualities);
	end

	self:Print("Bags cleaned.");
end

-----------------------------------------
-- Boot
-----------------------------------------

function ABC:Boot()
	self.db = LibStub("AceDB-3.0"):New("AsraiBagCleanerDB", {global = {profiles = {}, stage = {}, secure = {}}}, "Default").global;

	for dungeon, v in pairs(profiles) do
		if( not self.db.profiles[dungeon] ) then
			self.db.profiles[dungeon] = {};
		end

		for profile, t in pairs(v) do
			if( not self.db.profiles[dungeon][profile] ) then
				self.db.profiles[dungeon][profile] = {};
			end

			for i, itemid in ipairs(t) do
				self.db.profiles[dungeon][profile][itemid] = 3; -- 1: auto
			end
		end
	end

	self:RebuildSecureIndex();

	self:RegisterComm("abcreq", "OnComm");
	self:RegisterComm("abcok", "OnComm");
	self:RegisterComm("abcdata", "OnComm");
	self:RegisterChatCommand("abc", "HandleChatCommand");
end
ABC:RegisterEvent("PLAYER_ENTERING_WORLD", "Boot");

function ABC:OnComm(command, data, distribution, sender)
	if( distribution ~= "WHISPER" ) then return end

	if( command == "abcreq" ) then
		local success, t = self:Deserialize(data);
		if( not(success and type(t) == "table" and t.dungeon and t.profile) ) then return end

		DialogTable_SyncRequest.text = ("%s wants to sync data to you!\nDungeon: %s\nProfile: %s"):format(sender, t.dungeon, t.profile);
		Dialog:Spawn("ABC_SyncRequest", {sender = sender, data = t});
	elseif( command == "abcok" ) then
		local success, t = self:Deserialize(data);
		if( not(success and type(t) == "table" and t.dungeon and t.profile) ) then return end
		if( not(self:hasDungeon(t.dungeon) and self:hasDungeonProfile(t.dungeon, t.profile)) ) then return end

		self:SendCommMessage("abcdata", self:Serialize({dungeon = t.dungeon, profile = t.profile, data = self.db.profiles[t.dungeon][t.profile]}), "WHISPER", sender);
	elseif( command == "abcdata" ) then
		local success, t = self:Deserialize(data);
		if( not(success and type(t) == "table" and t.dungeon and t.profile and type(t.data) == "table") ) then return end

		local dungeon = self.db.profiles[t.dungeon] or {};
		local profile = dungeon[t.profile] or {};

		local inserted, confirmed, deleted = 0, 0, 0;

		for itemid, _ in pairs(t.data) do
			if( profile[itemid] ) then
				confirmed = confirmed + 1;
			else
				profile[itemid] = 3; -- 3: external
				inserted = inserted + 1;
			end
		end

		for itemid, _ in pairs(profile) do
			if( not t.data[itemid] ) then
				profile[itemid] = nil;
				deleted = deleted + 1;
			end
		end

		self.db.profiles[t.dungeon][t.profile] = profile;
		self:RebuildSecureIndex();

		self:Printf("Sync from %s finished. %s inserted, %s confirmed, %s deleted.", sender, inserted, confirmed, deleted);
	else

	end
end

function ABC:RebuildSecureIndex()
	local secure = {};

	for _, d in pairs(self.db.profiles) do
		for _, p in pairs(d) do
			for i, s in pairs(p) do
				secure[i] = not(s == 3);
			end
		end
	end

	self.db.secure = secure;
end

local function getTableKeys(tab)
	local keyset = {};
	for k, v in pairs(tab) do
		keyset[#keyset + 1] = k;
	end
	return table.concat(keyset, ", ");
end

function ABC:hasDungeon(dungeon)
	return type(self.db.profiles[dungeon]) == "table";
end

function ABC:hasDungeonProfile(dungeon, profile)
	return self:hasDungeon(dungeon) and type(self.db.profiles[dungeon][profile]) == "table";
end

function ABC:HandleChatCommand(line)
	local command, arg1, arg2, arg3 = self:GetArgs(line, 4, 1);

	command = command and command:lower() or command;
	arg1 = arg1 and arg1:lower() or arg1;
	arg2 = arg2 and arg2:lower() or arg2;
	arg3 = arg3 and arg3:lower() or arg3;

	if( command == "dungeons") then
		self:Printf("Registered dungeons: %s", getTableKeys(self.db.profiles));
	elseif( command == "profiles" ) then
		if( self:hasDungeon(arg1) ) then
			self:Printf("Registered profiles for [%s]: %s", arg1, getTableKeys(self.db[arg1]));
		else
			self:Printf("Dungeon [%s] does not exist.", arg1);
		end
	elseif( command == "create" ) then
		if( arg1 == "dungeon" ) then
			if( not arg2 ) then
				self:Print("Usage: |c0000ffff/abc create dungeon DUNGEONNAME|r");
			elseif( self:hasDungeon(arg2) ) then
				self:Printf("Dungeon [%s] already exists.", arg2);
			else
				self.db.profiles[arg2] = {};
				self:Printf("Dungeon [%s] created. You should create a profile using: |c0000ffff/abc create profile DUNGEONNAME PROFILENAME|r", arg2);
			end
		elseif( arg1 == "profile" ) then
			if( not(arg2 and arg3) ) then
				self:Print("Usage: |c0000ffff/abc create profile DUNGEONNAME PROFILENAME|r");
			elseif( not self:hasDungeon(arg2) ) then
				self:Printf("Dungeon [%s] does not exist.", arg2);
			elseif( self:hasDungeonProfile(arg2, arg3) ) then
				self:Printf("Profile [%s] for dungeon [%s] already exists.", arg3, arg2);
			else
				self.db.profile[arg2][arg3] = {};
				self:Printf("Profile [%s] for dungeon [%s] created. You may now add items to it using: |c0000ffff/abc add DUNGEONNAME PROFILENAME ITEMID|r", arg3, arg2);
			end
		else
			self:Print("Usage: |c0000ffff/abc create dungeon DUNGEONNAME|r  or  |c0000ffff/abc create profile DUNGEONNAME PROFILENAME|r");
		end
	elseif( command == "delete" ) then
		if( arg1 == "dungeon" ) then
			if( not arg2 ) then
				self:Print("Usage: |c0000ffff/abc delete dungeon DUNGEONNAME|r");
			elseif( not self:hasDungeon(arg2) ) then
				self:Printf("Dungeon [%s] does not exist.", arg2);
			else
				self.db.profiles[arg2] = nil;
				self:Printf("Dungeon [%s] deleted.", arg2);
			end
		elseif( arg1 == "profile" ) then
			if( not(arg2 and arg3) ) then
				self:Print("Usage: |c0000ffff/abc delete profile DUNGEONNAME PROFILENAME|r");
			elseif( not self:hasDungeon(arg2) ) then
				self:Printf("Dungeon [%s] does not exist.", arg2);
			elseif( not self:hasDungeonProfile(arg2, arg3) ) then
				self:Printf("Profile [%s] for dungeon [%s] does not exist.", arg3, arg2);
			else
				self.db.profiles[arg2][arg3] = nil;
				self:Printf("Profile [%s] for dungeon [%s] deleted.", arg3, arg2);
			end
		else
			self:Print("Usage: |c0000ffff/abc delete dungeon DUNGEONNAME|r  or  |c0000ffff/abc delete profile DUNGEONNAME PROFILENAME|r");
		end
	elseif( command == "add" or command == "remove" ) then
		if( not(arg1 and arg2 and arg3) ) then
			self:Printf("Usage: |c0000ffff/abc %s DUNGEONNAME PROFILENAME ITEMID|r", command);
		elseif( not self:hasDungeon(arg1) ) then
			self:Printf("Dungeon [%s] does not exist.", arg1);
		elseif( not self:hasDungeonProfile(arg1, arg2) ) then
			self:Printf("Profile [%s] for dungeon [%s] does not exist.", arg2, arg1);
		elseif( not(arg3 and tonumber(arg3)) ) then
			self:Print("The item id must be a number value. Example: 1234");
		else
			if( command == "add" ) then
				self.db.profiles[arg1][arg2][tonumber(arg3)] = 2; -- 2: manual
				self:RebuildSecureIndex();

				self:Printf("Item [%d] added to profile [%s] of dungeon [%s].", tonumber(arg3), arg2, arg1);
			else
				self.db.profiles[arg1][arg2][tonumber(arg3)] = nil;
				self:RebuildSecureIndex();

				self:Printf("Item [%d] removed from profile [%s] of dungeon [%s].", tonumber(arg3), arg2, arg1);
			end
		end
	elseif( command == "sync" ) then
		if( not arg1 and arg2 and arg3 ) then
			self:Printf("Usage: |c0000ffff/abc sync PLAYER DUNGEONNAME PROFILENAME|r", command);
		elseif( not self:hasDungeon(arg2) ) then
			self:Printf("Dungeon [%s] does not exist.", arg2);
		elseif( not self:hasDungeonProfile(arg2, arg3) ) then
			self:Printf("Profile [%s] for dungeon [%s] does not exist.", arg3, arg2);
		else 
			self:SendCommMessage("abcreq", self:Serialize({dungeon = arg2, profile = arg3}), "WHISPER", arg1);
		end
	elseif( command == "approve" ) then
		if( not arg1 or not(arg1 == "all" or tonumber(arg1) ) ) then
			self:Print("Usage: |c0000ffff/abc approve [ITEMID -or- all]|r");
		else
			if( arg1 == "all" ) then
				for dungeon, d in pairs(self.db.profiles) do
					for profile, p in pairs(d) do
						for i, s in pairs(p) do
							if( s == 3 ) then
								self.db.profiles[dungeon][profile][i] = 2; -- 2: manual
							end
						end
					end
				end
				
				self:Print("Approved all insecure items.");
			else
				local id = tonumber(arg1);
				local occurance = 0;

				for dungeon, d in pairs(self.db.profiles) do
					for profile, p in pairs(d) do
						for i, s in pairs(p) do
							if( i == id and s == 3 ) then
								self.db.profiles[dungeon][profile][i] = 2; -- 2: manual
								occurance = occurance + 1;
							end
						end
					end
				end

				if( occurance > 0 ) then
					self:Printf("Item %s approvved.", arg1);
				else
					self:Printf("No item of %s found and approved.", arg1);
				end
			end

			self:RebuildSecureIndex();
		end
	end
end

-----------------------------------------
-- Default Data
-----------------------------------------

do
	-- RageFire Farm Profiles
	profiles["rf"] = {
		["linencloth"] = {
			3375, 14102, 2455, 2287, 1504, 1516, 1734, 1507, 4569, 1179, 15306, 1506, 1731, 1210, 4577, 818, 2214, 14097, 3288, 1730, 14147,
			4680, 858, 1515, 14150, 2078, 2778, 2075, 3309, 15012, 14149, 2079, 1509, 3308, 1514, 2632, 1502, 1510, 4687, 15490, 15491, 15303,
			2763, 4570, 14113, 1501, 15300, 955, 774, 15298, 4567, 1495, 2215, 1813, 1505, 2073, 15015, 15945, 14115, 1513, 15016, 3304, 4693,
			1737, 1733, 3290, 1498, 1770, 3312, 3283, 14114, 15210, 1511, 14109, 5069, 2777, 14123, 14148, 14099, 1180, 4566, 1768, 14096, 14151,
			1732, 3313, 3303, 3282, 2407, 1181, 1735, 4564, 14724, 3307, 15305, 14145, 14110, 3013, 6347, 15486, 15495, 3302, 15308, 3036, 3287,
			14563, 14116, 3653, 1499, 3374, 15011, 15268, 15485, 1512, 15484, 3279
		},
	};
end