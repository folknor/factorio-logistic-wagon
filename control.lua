-- http://lua-users.org/wiki/StringInterpolation

-----------------------------------------------------------
-- CONFIG
--

local stackSizeOverride = {
	["gun-turret"] = 5,
	["laser-turret"] = 5,
	["flamethrower-turret"] = 5,
	["logistic-robot"] = 5,
	["construction-robot"] = 5,
	["repair-pack"] = 15,
}

-----------------------------------------------------------
-- CACHE
--

local itemStackCache
do
	local cache = {}
	itemStackCache = setmetatable({}, {
		__index = cache,
		__newindex = function(_, key, value)
			if cache[key] then
				cache[key].count = value
			else
				cache[key] = { name = key, count = value }
			end
		end
	})
end
local getStackSize
local temporaryStackSizes = {}
do
	local type = type
	local stackSizeCache = setmetatable({}, {
		__index = function(self, item)
			local ret = nil
			if type(item) ~= "string" then
				return 10
			elseif stackSizeOverride[item] then
				ret = stackSizeOverride[item]
			elseif type(game.item_prototypes[item]) == "table" and game.item_prototypes[item].stack_size then
				ret = game.item_prototypes[item].stack_size
			end
			if type(ret) ~= "number" then return 10 end
			rawset(self, item, ret)
			return ret
		end
	})

	getStackSize = function(wagon, item)
		if temporaryStackSizes[wagon.unit_number] and temporaryStackSizes[wagon.unit_number][item] then
			return temporaryStackSizes[wagon.unit_number][item]
		end
		return stackSizeCache[item]
	end
end
local function wipe(tbl) for k in pairs(tbl) do tbl[k] = nil end end

-----------------------------------------------------------
-- LOCAL VARIABLES
--

-- Items are added to this table when we want to process them.
-- key: wagon entity, value: chest entity
-- upvalue of global.wagons
local _wagons -- = {}

-----------------------------------------------------------
-- UTILITY
--

local function moveAll(from, to, ignore)
	local contents = from.get_contents()
	for item, count in pairs(contents) do
		if not ignore or not ignore[item] then
			itemStackCache[item] = count
			local inserted = to.insert(itemStackCache[item])
			if inserted == count then
				from.remove(itemStackCache[item])
			elseif type(inserted) == "number" and inserted > 0 then
				itemStackCache[item] = inserted
				from.remove(itemStackCache[item])
			end
		end
	end
end

-----------------------------------------------------------
-- STOP HANDLER FUNCTIONS
-- These handler functions are invoked when a wagon stops at a station, per chest type.
--

local handleStop = {}
do
	local ignore = {}
	local filters = {}

	do
		local function readSignals(wagon, parameters)
			local any = false
			for _, signal in next, parameters do
				-- It's slightly problematic because when the player places down a new, empty CC
				-- without setting any parameters on it, .parameters contains one entry with all
				-- keys (.index, .signal, .count) set to 'nil'.
				-- As opposed to - you know - being empty, like it should be.
				--
				-- Also, a CC with 1 item signal is filled with item signals with no .name
				-- and count=!.
				-- wtf
				--
				if type(signal) == "table" and type(signal.signal.name) == "string" and type(signal.count) == "number" then
					-- Seems we're getting stack size overrides
					if not temporaryStackSizes[wagon.unit_number] then temporaryStackSizes[wagon.unit_number] = {} end
					temporaryStackSizes[wagon.unit_number][signal.signal.name] = signal.count
					any = true
				end
			end
			return any
		end

		handleStop["constant-combinator"] = function(wagon, cc)
			if not cc or not cc.valid then return false end
			local behavior = cc.get_control_behavior()
			if not behavior or not behavior.parameters then return false end
			local anyParameters = false
			for _, parameters in next, behavior.parameters do

				if parameters then
					anyParameters = readSignals(wagon, parameters)
				end
			end
			return anyParameters
		end
	end

	-- For passive provider chests, we insert a stack of every item type we carry
	-- that is filtered, and grab the filtered items from the chest again when we leave
	handleStop["logistic-chest-passive-provider"] = function(wagon, chest)
		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		if not wagonInv or not wagonInv.valid then return false end

		local chestInv = chest.get_inventory(defines.inventory.chest)
		if not chestInv or not chestInv.valid then return false end

		if not wagonInv.is_empty() and wagonInv.is_filtered() then
			wipe(filters)
			for i = 1, #wagonInv do
				local filter = wagonInv.get_filter(i)
				if filter then
					filters[filter] = true
				end
			end

			local contents = wagonInv.get_contents()
			for item, count in pairs(contents) do
				if filters[item] then
					local stack = getStackSize(wagon, item)
					local alreadyIn = chestInv.get_item_count(item)
					if alreadyIn < stack then
						local toInsert = (stack - alreadyIn)
						-- Make sure we dont insert more than we have
						if toInsert > count then toInsert = count end
						itemStackCache[item] = toInsert
						local inserted = chestInv.insert(itemStackCache[item])
						if inserted == toInsert then
							wagonInv.remove(itemStackCache[item])
						elseif type(inserted) == "number" and inserted > 0 then
							itemStackCache[item] = inserted
							wagonInv.remove(itemStackCache[item])
						end
					end
				end
			end
		end
		-- We always handle passive providers, because we grab their contents when we move again
		return true
	end

	-- For active provider chests, we dump a stack of every filtered item type
	handleStop["logistic-chest-active-provider"] = function(wagon, chest)
		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		-- If the wagon inventory is empty, we dont do anything
		if not wagonInv or not wagonInv.valid or wagonInv.is_empty() then return false end
		local chestInv = chest.get_inventory(defines.inventory.chest)
		if not chestInv or not chestInv.valid then return false end

		-- If the active provider chest has a full red bar, we dump everything
		-- that is not filtered into it and reapply the red bar
		if chestInv.getbar() == 0 then
			chestInv.setbar() -- Remove the red bars
			handleStop["logistic-chest-storage"](wagon, chest)
			chestInv.setbar(0)
		else
			local chestNut = chest.logistic_network
			if not chestNut or not chestNut.valid then return false end

			local useFilters = wagonInv.is_filtered()
			if useFilters then
				wipe(filters)
				for i = 1, #wagonInv do
					local filter = wagonInv.get_filter(i)
					if filter then
						filters[filter] = true
					end
				end
			end

			local contents = wagonInv.get_contents()
			for item, count in pairs(contents) do
				if not useFilters or filters[item] then
					local stack = getStackSize(wagon, item)
					local alreadyIn = chestNut.get_item_count(item)
					if alreadyIn < stack then
						local toInsert = (stack - alreadyIn)
						if toInsert > count then toInsert = count end
						itemStackCache[item] = toInsert
						local inserted = chestInv.insert(itemStackCache[item])
						if inserted == toInsert then
							wagonInv.remove(itemStackCache[item])
						elseif type(inserted) == "number" and inserted > 0 then
							itemStackCache[item] = inserted
							wagonInv.remove(itemStackCache[item])
						end
					end
				end
			end
		end
		return false
	end

	-- For storage chests, we just dump everything and we dont process
	-- the chest when we start moving away from this station.
	-- Dump-and-forget
	handleStop["logistic-chest-storage"] = function(wagon, chest)
		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		-- If the wagon inventory is empty, we dont do anything
		if not wagonInv or not wagonInv.valid or wagonInv.is_empty() then return false end

		local chestInv = chest.get_inventory(defines.inventory.chest)
		if not chestInv or not chestInv.valid then return false end

		if wagonInv.is_filtered() then
			wipe(filters)
			for i = 1, #wagonInv do
				local filter = wagonInv.get_filter(i)
				if filter then filters[filter] = true end
			end
			moveAll(wagonInv, chestInv, filters)
		else
			moveAll(wagonInv, chestInv)
		end
		return false
	end

	handleStop["logistic-chest-requester"] = function(wagon, chest)
		local chestInv = chest.get_inventory(defines.inventory.chest)
		if not chestInv or not chestInv.valid then return false end
		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		if not wagonInv or not wagonInv.valid then return false end

		-- If the requester chest has a red bar filling the entire chest, we remove the restrictions
		-- and let whatever is there fill it up for us
		if chestInv.getbar() == 0 then
			chestInv.setbar() -- Remove the red bars
		elseif wagonInv.is_filtered() then
			-- if there are any request slots already set
			-- with a count higher than 0, we dont touch it
			wipe(ignore)
			local zeroFound = false
			for i = 1, 10 do
				local req = chest.get_request_slot(i)
				if req then
					if req.count > 0 then
						return false -- we dont handle this chest
					elseif req.count == 0 then
						ignore[req.name] = true
						zeroFound = true
					end
				end
			end
			if not zeroFound then return false end

			wipe(filters)
			for i = 1, #wagonInv do
				local filter = wagonInv.get_filter(i)
				if filter and not ignore[filter] then
					filters[filter] = (filters[filter] and filters[filter] + 1) or 1
				end
			end

			local requestedAnything = false
			for i = 1, 10 do
				local req = chest.get_request_slot(i)
				if not req then
					local item, count = next(filters) -- pop queue
					if item and count then
						local stack = getStackSize(wagon, item)
						local total = (count * stack) - (wagonInv.get_item_count(item) or 0)
						if total > 0 then
							itemStackCache[item] = total
							requestedAnything = true
							chest.set_request_slot(itemStackCache[item], i)
						end
						filters[item] = nil
					end
				end
			end
			return requestedAnything
		end
		return true
	end
end

-----------------------------------------------------------
-- MOVE HANDLER FUNCTIONS
-- These handlers are invoked after we start moving from a spot where we previously handled a
-- chest of some sort. They are only invoked for the chests we actually touched.
--

local handleMove = {}
do
	local ignore = {}
	local filters = {}

	handleMove["constant-combinator"] = function(wagon, _)
		if temporaryStackSizes[wagon.unit_number] then
			temporaryStackSizes[wagon.unit_number] = nil
		end
	end

	handleMove["logistic-chest-passive-provider"] = function(wagon, chest)
		local chestInv = chest.get_inventory(defines.inventory.chest)
		if not chestInv or not chestInv.valid or chestInv.is_empty() then return end

		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		if not wagonInv or not wagonInv.valid then return end

		moveAll(chestInv, wagonInv)
	end
	--handleMove["logistic-chest-active-provider"] = handleMove["logistic-chest-passive-provider"]
	--handleMove["logistic-chest-storage"] = handleMove["logistic-chest-passive-provider"]

	handleMove["logistic-chest-requester"] = function(wagon, chest)
		local chestInv = chest.get_inventory(defines.inventory.chest)
		if not chestInv or not chestInv.valid then return end
		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		if not wagonInv or not wagonInv.valid then return end

		-- First check if any requests in the chest are set to zero
		local zero = nil
		local nonZero = nil
		for i = 1, 10 do
			local req = chest.get_request_slot(i)
			if req then
				if req.count == 0 then
					zero = true
				else
					nonZero = true
				end
			end
		end

		if zero then
			wipe(filters)
			for i = 1, #wagonInv do
				local filter = wagonInv.get_filter(i)
				if filter and not ignore[filter] then
					filters[filter] = (filters[filter] and filters[filter] + 1) or 1
				end
			end
			for item, count in pairs(filters) do
				local stack = getStackSize(wagon, item)
				filters[item] = stack * count
			end

			-- Clear the requests for all non-zero slots
			for i = 1, 10 do
				local req = chest.get_request_slot(i)
				if req and req.count > 0 then
					chest.clear_request_slot(i)
				end
			end

			-- Transfer filtered contents to wagon
			for item, total in pairs(filters) do
				local current = wagonInv.get_item_count(item)
				local missing = total - current
				if missing > 0 then
					local available = chestInv.get_item_count(item)
					if available and available > 0 then
						if available >= missing then
							itemStackCache[item] = missing
						else
							itemStackCache[item] = available
						end
						local inserted = wagonInv.insert(itemStackCache[item])
						if inserted > 0 then
							itemStackCache[item] = inserted
							chestInv.remove(itemStackCache[item])
						end
					end
				end
			end
		elseif nonZero then
			-- There was no zero-filter set, which means this is a requester chest
			-- placed somewhere that we should bring with us
			-- Re-apply a red bar on the whole chest
			chestInv.setbar(0)
			-- Transfer everything
			moveAll(chestInv, wagonInv)
		end
	end
end

-----------------------------------------------------------
-- TICK HANDLER
-- Only registered for when there are logistic wagons at train
-- stops with one or more chests that we actually did something
-- with in one of the stop handlers.
--
-- If there was nothing to do when we stopped, we dont tick.
--

local tick
do
	local unpack = table.unpack
	local remove = table.remove
	local select = select
	local def = defines.events.on_tick

	local function handleWagon(wagon, ...)
		for i = 1, select("#", ...) do
			local ent = select(i, ...)
			if ent and ent.valid and handleMove[ent.name] then
				handleMove[ent.name](wagon, ent)
			end
		end
	end

	tick = function(event)
		if event.tick % 20 == 0 then
			for i = #_wagons, 1, -1 do
				local data = _wagons[i]
				local wagon = data and data[1]
				if not data or not wagon or not wagon.valid or not wagon.train or not wagon.train.valid then
					remove(_wagons, i)
				elseif wagon.train.speed ~= 0 then
					handleWagon(unpack(remove(_wagons, i)))
				end
			end

			if #_wagons == 0 then
				script.on_event(def, nil)
			end
		end
	end

	script.on_init(function()
		if not global.wagons then global.wagons = {} end
		if not _wagons then _wagons = global.wagons end
	end)

	script.on_load(function()
		if not _wagons then _wagons = global.wagons end
		if #_wagons ~= 0 then
			script.on_event(def, tick)
		end
	end)
end

do
	local migrate = {
		["0.1.0"] = function()
			if global.wagons then
				-- 0.1.0-0.1.5 just nuke everything
				global.wagons = {}
			end
			return "0.1.5"
		end
	}
	migrate["0.1.1"] = migrate["0.1.0"]
	migrate["0.1.2"] = migrate["0.1.0"]
	migrate["0.1.3"] = migrate["0.1.0"]
	migrate["0.1.4"] = migrate["0.1.0"]

	local mod = "folk-logistic-wagon"

	local function conf(data)
		if not data or not data.mod_changes then return end
		if data.mod_changes[mod] then
			local new = data.mod_changes[mod].new_version
			local old = data.mod_changes[mod].old_version
			if migrate[old] then
				local current = old
				while true do
					local step = migrate[current](old, new, current)
					if migrate[step] then
						current = step
					else
						break
					end
				end

			end
		end
	end
	script.on_configuration_changed(conf)
end

-----------------------------------------------------------
-- TRAIN STATE CHANGED HANDLING
-- When a train changes state, we check to see if there are any
-- logistic wagons connected to it, and if there is we look around the
-- wagon for logistic chests and handle them appropriately.
--
-- If we find anything to handle, we register the tick updater.
--

do
	local find = {
		--type = "logistic-container",
	}

	local function handleWagon(wagon)
		local area
		if wagon.orientation == 0.25 or wagon.orientation == 0.75 then
			area = { { wagon.position.x - 0.5, wagon.position.y - 1.5 }, { wagon.position.x + 0.5, wagon.position.y + 1.5 } }
		elseif wagon.orientation == 0 or wagon.orientation == 0.5 then
			area = { { wagon.position.x - 1.5, wagon.position.y - 0.5 }, { wagon.position.x + 1.5, wagon.position.y + 0.5 } }
		end
		-- XXX If area is not defined we really should display a warning
		-- XXX that they should file a bug report on the addon page.
		if not area then return end
		find.area = area
		find.force = wagon.force

		local res = wagon.surface.find_entities_filtered(find)

		if type(res) ~= "table" or #res == 0 then return end

		-- See if we find a CC
		local cc = nil
		for i, entity in next, res do
			if entity.type == "constant-combinator" then
				cc = table.remove(res, i)
				-- Don't break, we remove all combinators and only use the last
				-- one we find.
			end
		end

		if type(cc) == "table" and cc.valid and handleStop[cc.name] then
			handleStop[cc.name](wagon, cc)
		end

		local ticktable = nil
		for _, entity in next, res do
			if handleStop[entity.name] then
				local process = handleStop[entity.name](wagon, entity)
				if process then
					if not ticktable then
						ticktable = { wagon, entity }
					else
						ticktable[#ticktable + 1] = entity
					end
				end
			end
		end
		if ticktable then
			-- ZZZ We make sure the combinator is the last entry in the ticktable data,
			-- ZZZ so that we handleStop[] it last, clearing the stack size data after
			-- ZZZ we are done processing the chests - and not randomly inbetween chests.
			if type(cc) == "table" and cc.valid and handleStop[cc.name] then
				ticktable[#ticktable + 1] = cc
			end

			if not global.wagons then global.wagons = {} end
			if not _wagons then _wagons = global.wagons end
			if #_wagons == 0 then
				script.on_event(defines.events.on_tick, tick)
			end
			_wagons[#_wagons + 1] = ticktable
		end
	end

	-- We only act on this define:
	-- defines.train_state.wait_station  Waiting at a station.
	--
	-- Or if they add more defines in the future, we would act on those as well.
	-- I'd rather do it this way (explicit exclude) because you never know what
	-- states they might add, remove, or rename. So this way we scan for chests
	-- on all unknown states.

	local ignore = {
		[defines.train_state.on_the_path] = true,
		[defines.train_state.path_lost] = true,
		[defines.train_state.arrive_signal] = true,
		[defines.train_state.arrive_station] = true,
		[defines.train_state.manual_control_stop] = true,
		[defines.train_state.manual_control] = true,
		[defines.train_state.stop_for_auto_control] = true,
		[defines.train_state.no_path] = true,
		[defines.train_state.no_schedule] = true,
		[defines.train_state.wait_signal] = true,
	}

	local function onStateChanged(event)
		local train = event.train
		if not train or not train.valid or train.speed ~= 0 or ignore[train.state] or not train.cargo_wagons or #train.cargo_wagons == 0 then return end

		for _, wagon in next, train.cargo_wagons do
			if wagon and wagon.valid and wagon.name == "folk-logistic-wagon" then
				handleWagon(wagon)
			end
		end
	end
	script.on_event(defines.events.on_train_changed_state, onStateChanged)
end
