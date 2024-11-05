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
				cache[key] = { name = key, count = value, }
			end
		end,
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
			elseif type(prototypes.item[item]) == "userdata" and prototypes.item[item].stack_size then
				ret = prototypes.item[item].stack_size
			end
			if type(ret) ~= "number" then return 10 end
			rawset(self, item, ret)
			return ret
		end,
	})

	getStackSize = function(wagon, item)
		if temporaryStackSizes[wagon.unit_number] and temporaryStackSizes[wagon.unit_number][item] then
			return temporaryStackSizes[wagon.unit_number][item]
		end
		return stackSizeCache[item]
	end
end

-----------------------------------------------------------
-- LOCAL VARIABLES
--

-- Items are added to this table when we want to process them.
-- key: wagon entity, value: chest entity
-- upvalue of storage.wagons
local _wagons -- = {}

-----------------------------------------------------------
-- UTILITY
--

local function moveAll(from, to, ignore)
	local contents = from.get_contents()
	for _, item in next, contents do
		if not ignore or not ignore[item.name] then
			itemStackCache[item.name] = item.count
			local inserted = to.insert(itemStackCache[item.name])
			if type(inserted) == "number" then
				if inserted == item.count then
					from.remove(itemStackCache[item.name])
				elseif inserted > 0 then
					itemStackCache[item.name] = inserted
					from.remove(itemStackCache[item.name])
				end
			end
		end
	end
end

local function getFilters(inv)
	if not inv.is_filtered() then return false end
	local any = false
	local ret = {}

	for i = 1, #inv do
		local filter = inv.get_filter(i)
		if filter and type(filter) == "table" then
			filter = filter.name
		end

		if filter then
			ret[filter] = (ret[filter] and ret[filter] + 1) or 1
			any = true
		end
	end

	return any, ret
end

local function isValidItemSignal(signal)
	return type(signal) == "table" and type(signal.value) == "table" and type(signal.value.name) == "string" and
		type(signal.min) == "number" and signal.value.type == "item"
end

-----------------------------------------------------------
-- MOVE HANDLER FUNCTIONS
-- These handlers are invoked after we start moving from a spot where we previously handled a
-- chest of some sort. They are only invoked for the chests we actually touched.
--

local moveHandlers = {}
do
	function moveHandlers.resetTempStackSizes(wagon)
		temporaryStackSizes[wagon.unit_number] = nil
	end

	function moveHandlers.grabAll(wagon, chest)
		local chestInv = chest.get_inventory(defines.inventory.chest)
		if not chestInv or not chestInv.valid or chestInv.is_empty() then return end

		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		if not wagonInv or not wagonInv.valid then return end

		moveAll(chestInv, wagonInv)
	end

	function moveHandlers.grabSignalsAndZero(wagon, chest)
		local chestInv = chest.get_inventory(defines.inventory.chest)
		if not chestInv or not chestInv.valid then return end
		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		if not wagonInv or not wagonInv.valid then return end

		local useFilters, filters = getFilters(wagonInv)

		if useFilters and filters then
			local llp = chest.get_requester_point()
			if not llp then return false end

			for _, section in next, llp.sections do
				if section.valid and section.active and section.is_manual then
					for i, signal in next, section.filters do
						if isValidItemSignal(signal) then
							if signal.min > 0 then
								-- Set signal to zero
								local item = signal.value.name
								if filters[item] then
									section.set_slot(i, {
										value = item,
										min = 0,
										max = 0,
									})
								end
							end
						end
					end
				end
			end

			-- Transfer to wagon
			for item, stacks in pairs(filters) do
				local available = chestInv.get_item_count(item)
				if available and available > 0 then
					local missing = (getStackSize(wagon, item) * stacks) - wagonInv.get_item_count(item)
					if missing > 0 then
						if available >= missing then
							itemStackCache[item] = missing
						else
							itemStackCache[item] = available
						end
						local inserted = wagonInv.insert(itemStackCache[item])
						if type(inserted) == "number" and inserted > 0 then
							itemStackCache[item] = inserted
							chestInv.remove(itemStackCache[item])
						end
					end
				end
			end
		end
	end

	function moveHandlers.grabAllApplyBar(wagon, chest)
		local chestInv = chest.get_inventory(defines.inventory.chest)
		if not chestInv or not chestInv.valid then return end
		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		if not wagonInv or not wagonInv.valid then return end

		-- There was no zero-filter set, which means this is a requester chest
		-- placed somewhere that we should bring with us
		-- Re-apply a red bar on the whole chest
		chestInv.set_bar(1)
		-- Transfer everything
		moveAll(chestInv, wagonInv)
	end
end

-----------------------------------------------------------
-- STOP HANDLER FUNCTIONS
-- These handler functions are invoked when a wagon stops at a station, per chest type.
--

local readFromConstantCombinator
do
	local function readSignals(un, parameters)
		local any = false
		for _, signal in next, parameters do
			if isValidItemSignal(signal) then
				if not temporaryStackSizes[un] then temporaryStackSizes[un] = {} end
				temporaryStackSizes[un][signal.value.name] = signal.min
				any = true
			end
		end
		return any
	end

	readFromConstantCombinator = function(wagon, cc)
		if not cc or not cc.valid then return false end
		local behave = cc.get_control_behavior()
		if not behave.enabled then return false end

		local anyParameters = false
		local un = wagon.unit_number

		for _, section in next, behave.sections do
			if section.valid and section.active and section.is_manual then
				if readSignals(un, section.filters) then
					anyParameters = true
				end
			end
		end

		return anyParameters
	end
end

local handleStop = {}
do
	-- For passive provider chests, we insert a stack of every item type we carry
	-- that is filtered, and grab the filtered items from the chest again when we leave
	handleStop["passive-provider-chest"] = function(wagon, chest, wagonInv, chestInv, useFilters, filters)
		-- We still need to process when we leave
		if wagonInv.is_empty() then return "grabAll" end
		if not wagonInv.is_filtered() then return "grabAll" end

		local contents = wagonInv.get_contents()
		for _, it in next, contents do
			local item = it.name
			local count = it.count

			if filters[item] then
				local stack = getStackSize(wagon, item)
				local alreadyIn = chestInv.get_item_count(item) or 0
				if alreadyIn < stack then
					local toInsert = (stack - alreadyIn)
					-- Make sure we dont insert more than we have
					if toInsert > count then toInsert = count end
					itemStackCache[item] = toInsert
					local inserted = chestInv.insert(itemStackCache[item])
					if type(inserted) == "number" then
						if inserted == toInsert then
							wagonInv.remove(itemStackCache[item])
						elseif inserted > 0 then
							itemStackCache[item] = inserted
							wagonInv.remove(itemStackCache[item])
						end
					end
				end
			end
		end
		-- We always handle passive providers, because we grab their contents when we move again
		return "grabAll"
	end

	-- For active provider chests, we dump a stack of every filtered item type
	handleStop["active-provider-chest"] = function(wagon, chest, wagonInv, chestInv, useFilters, filters)
		-- If the wagon inventory is empty, we dont do anything
		if wagonInv.is_empty() then return false end

		-- If the active provider chest has a full red bar, we dump everything
		-- that is not filtered into it and reapply the red bar
		if chestInv.get_bar() == 1 then
			chestInv.set_bar() -- Remove the red bars
			handleStop["storage-chest"](wagon, chest)
			chestInv.set_bar(1)
			return false
		end

		if not wagonInv.is_filtered() then return false end

		local chestNut = chest.logistic_network
		if not chestNut or not chestNut.valid then return false end

		local contents = wagonInv.get_contents()
		for _, it in next, contents do
			local item = it.name
			local count = it.count

			if filters[item] then
				local stack = getStackSize(wagon, item)
				local alreadyIn = chestNut.get_item_count(item) or 0

				if alreadyIn < stack then
					local toInsert = (stack - alreadyIn)
					if toInsert > count then toInsert = count end

					itemStackCache[item] = toInsert
					local inserted = chestInv.insert(itemStackCache[item])
					if type(inserted) == "number" then
						if inserted == toInsert then
							wagonInv.remove(itemStackCache[item])
						elseif inserted > 0 then
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
	handleStop["storage-chest"] = function(wagon, chest, wagonInv, chestInv, useFilters, filters)
		-- If the wagon inventory is empty, we dont do anything
		if wagonInv.is_empty() then return false end

		if useFilters then
			moveAll(wagonInv, chestInv, filters)
		else
			moveAll(wagonInv, chestInv)
		end
		return false
	end

	handleStop["requester-chest"] = function(wagon, chest, wagonInv, chestInv, useFilters, filters)
		-- If the requester chest has a red bar filling the entire chest, we remove the restrictions
		-- and let whatever is there fill it up for us
		if chestInv.get_bar() == 1 then
			chestInv.set_bar()
			-- Wait for it to be filled up and then grab everything when we move
			return "grabAllApplyBar"
		end

		if not wagonInv.is_filtered() then return false end

		local llp = chest.get_requester_point()
		if not llp then return false end

		local requestedAnything = false

		for _, section in next, llp.sections do
			if section.valid and section.active and section.is_manual then
				for i, signal in next, section.filters do
					if isValidItemSignal(signal) and signal.min == 0 then
						-- Request enough of this item to fill all filtered slots in the wagon
						local item = signal.value.name

						-- Is this item filtered in the wagon?
						if filters[item] then
							-- filters[item]'s value is how many slots in the wagon is filtered to this item
							local stack = getStackSize(wagon, item)
							local missing = (filters[item] * stack) - (wagonInv.get_item_count(item) or 0)

							if missing > 0 then
								local inChest = chestInv.get_item_count(item)

								-- First just check if there's any in the chest
								if inChest and inChest > 0 then
									-- There might be more in the chest than we need
									if inChest > missing then inChest = missing end
									itemStackCache[item] = inChest

									local inserted = wagonInv.insert(itemStackCache[item])
									if type(inserted) == "number" and inserted > 0 then
										itemStackCache[item] = inserted
										chestInv.remove(itemStackCache[item])

										missing = missing - inserted
									end
								end

								if missing > 0 then
									requestedAnything = true
									section.set_slot(i, {
										value = item,
										min = missing,
										max = missing,
									})
								end
							end
						end
					end
				end
			end
		end
		if requestedAnything then return "grabSignalsAndZero" end
		return false
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
			local ent, fn = unpack((select(i, ...)))
			if ent and ent.valid and type(fn) == "string" then
				moveHandlers[fn](wagon, ent)
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
		if not storage.wagons then storage.wagons = {} end
		if not _wagons then _wagons = storage.wagons end
	end)

	script.on_load(function()
		if not _wagons then _wagons = storage.wagons end
		if #_wagons ~= 0 then
			script.on_event(def, tick)
		end
	end)
end

do
	local migrate = {
		["0.1.0"] = function()
			if storage.wagons then
				-- 0.1.0-0.1.5 just nuke everything
				storage.wagons = {}
			end
			return "0.1.5"
		end,
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
		name = { "constant-combinator", "passive-provider-chest", "active-provider-chest", "storage-chest", "requester-chest", },
	}

	local function handleWagon(wagon)
		local area
		if wagon.orientation == 0.25 or wagon.orientation == 0.75 then
			area = { { wagon.position.x - 0.5, wagon.position.y - 1.5, }, { wagon.position.x + 0.5, wagon.position.y + 1.5, }, }
		elseif wagon.orientation == 0 or wagon.orientation == 0.5 then
			area = { { wagon.position.x - 1.5, wagon.position.y - 0.5, }, { wagon.position.x + 1.5, wagon.position.y + 0.5, }, }
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
		for i = #res, 1, -1 do
			local entity = res[i]
			if entity.type == "constant-combinator" then
				cc = table.remove(res, i)
				-- Don't break, we remove all combinators and only use the last
				-- one we find.
			end
		end

		if cc and cc.valid then
			readFromConstantCombinator(wagon, cc)
		else
			cc = nil
		end

		local ticktable = nil

		local wagonInv = wagon.get_inventory(defines.inventory.cargo_wagon)
		if wagonInv and wagonInv.valid then
			local useFilters, filters = getFilters(wagonInv)
			for _, chest in next, res do
				if handleStop[chest.name] then
					local chestInv = chest.get_inventory(defines.inventory.chest)
					if chestInv and chestInv.valid then
						local process = handleStop[chest.name](wagon, chest, wagonInv, chestInv, useFilters, filters)
						if process then
							if not ticktable then
								ticktable = { wagon, { chest, process, }, }
							else
								ticktable[#ticktable + 1] = { chest, process, }
							end
						end
					end
				end
			end
		end

		if ticktable then
			-- ZZZ We make sure the combinator is the last entry in the ticktable data,
			-- ZZZ so that we handleStop[] it last, clearing the stack size data after
			-- ZZZ we are done processing the chests - and not randomly inbetween chests.
			if cc then
				ticktable[#ticktable + 1] = { cc, "resetTempStackSizes", }
			end

			if not storage.wagons then storage.wagons = {} end
			if not _wagons then _wagons = storage.wagons end
			if #_wagons == 0 then
				script.on_event(defines.events.on_tick, tick)
			end
			_wagons[#_wagons + 1] = ticktable
		end
	end

	local ignore = {
		[defines.train_state.on_the_path] = true,
		[defines.train_state.no_schedule] = true,
		[defines.train_state.no_path] = true,
		[defines.train_state.arrive_signal] = true,
		[defines.train_state.wait_signal] = true,
		[defines.train_state.arrive_station] = true,
		--[defines.train_state.wait_station] = false,
		[defines.train_state.manual_control_stop] = true,
		[defines.train_state.manual_control] = true,
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
