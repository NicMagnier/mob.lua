--[[
	Simple Entity System

	* Add/remove entities to the mob
	mob.new()
	mob.register()
	mob.delete()

	* Get group of entities
	You can query to get a pool of entities with get() with a single string "#player @dead item_resurection -level_hell"
	#<id_name> is an id. An entity has a unique id that cannot be changed.
	<flag_name> is a flag. An entity can have multiple flags
	@<state_name> is a state. An entity has only one state and can be changed
	-<stuff> means that the query should include the element. "-level_hell" means that the entity shouldn't have the flag 'level_hell'. works also for is and state

	You can also use a function to get a group of entities where you can filter based on any properties of the entity
	The function is called for each entity (with the entity as an argument) and should return true if the entity should be in the group

	* Chain group of entities functions
	The get() function return a special object that is a group of entities. The object have functions that can be chained to manipulate the group
	example: mob.get("npc"):combine("bullets"):remove()

	You can also chain functions your functions specific to the entities
	mob.get("npc"):check_collision_with_bullets()


	* use entity and pool of entities only locally
	if you need to keep a reference of an entity (for example if an entity need to use another entity)
	use and save their id instead with get_id() and get the entity with get_entity()
	This way you avoid risk of referencing an entity that might get removed from the mob.
	The memory manager can also clean up unused entities as soon as it is removed from the mob

	* TODO
	Precomputed queries (query is cached, modifying entities update all cached list)
	Queries with regular expressions
]]--

local mob = {
	list = {},
	current_uid = 0,
	count = 0
}

-- create a new entity for the mob based on another object
-- return the new entity and its id
function mob.new(type, query)
	if not type then type = {} end
	local result = {}

	-- init metatables
	setmetatable(result,type)
	type.__index = type

	-- regsiter object
	mob.register(result, query)

	return result, result.__mob_id
end

-- add the object to the mob without creating it with mob.new()
-- return entity id
function mob.register(entity, query)
	-- parse definiton
	qo = mob.parse(query)

	local get_uid = function()
		mob.current_uid = mob.current_uid + 1
		-- we keep iterating until we find a free slot
		-- shouldn't happen unless programmer start adding entity with custom is format id_XXX
		while (mob.list["id_"..mob.current_uid]) do
			mob.current_uid = mob.current_uid + 1
		end
		return "id_"..mob.current_uid
	end

	-- init object
	entity.__mob = {}
	entity.__mob.id = qo.id or get_uid()
	entity.__mob.state = ""
	entity.__mob.flags = {}

	-- setup the entity based on the query
	mob.set(entity, qo)

	-- set easy access functions on entity in metatable
	-- looks kind of hackey, find a cleaner way?
	local mt = getmetatable(entity)
	if not mt then
		mt = {}
		setmetatable(entity,mt)
	end
	if not mt.__index then mt.__index = {} end

	if not mt.__mob_registered and type(mt.__index)~="function" then
		mt.__mob_registered = true

		-- list of function to install
		local fn_list = {"delete", "set", "set_state", "add_flag", "remove_flag", "get_flags", "has_flag", "has_not_flag", "is", "get_id", "get_state", "get_string"}
		for _, fn in pairs(fn_list) do
			if not mt.__index[fn] then
				mt.__index[fn] = function(...) return mob[fn](unpack({...})) end
			end
		end
	end

	-- add object to the mob
	mob.list[entity.__mob.id] = entity
	mob.count = mob.count + 1

	return entity.__mob.id
end

-- delete an entity from the mob
function mob.delete(entity)
	if not entity or not entity.__mob then return end

	if mob.list[entity.__mob.id] then
		mob.count = mob.count - 1
	end

	mob.list[entity.__mob.id] = nil
	entity.__mob = nil
end

-- parse a string (or multiple strings) which can contain #id, flag, @state
function mob.parse(...)
	local result = {
		flags = {},
		without = {flags={}}
	}

	for i,v in ipairs({...}) do
		if type(v)=="string" then
			local query_list = mob._query_split(v, ' ')

			-- sort each query element in the query object
			for j, query in pairs(query_list) do
				local add_to = result

				-- '-'
				if query:byte(1)==45 then
					add_to = result.without
					query = query:sub(2)
				end

				-- '#'
				if query:byte(1)==35 then
					add_to.id = query:sub(2)

				-- '@'
				elseif query:byte(1)==64 then
					add_to.state = query:sub(2)

				else
					table.insert(add_to.flags, query)
				end
			end
		end
	end

	return result
end

-- add and remove flag and change state with a single query or query object
-- id cannot be set after registration
function mob.set(entity, query)
	if not entity or not query then return end

	-- get query object
	if type(query)=="string" then
		query = mob.parse(query)
	end

	-- set state
	mob.set_state(entity, query.state)

	-- remove flags
	for key, flag in pairs(query.without.flags) do
		entity.__mob.flags[flag] = nil
	end

	-- add flags
	for key, flag in pairs(query.flags) do
		entity.__mob.flags[flag] = true
	end
end

-- set the state of an entity (only one state per entity)
function mob.set_state(entity, state)
	if not entity or not entity.__mob then return end
	entity.__mob.state = state
end

-- add a list of flag to an entity (entities can have multiple flags)
function mob.add_flag(entity, flags)
	if not entity or not entity.__mob or not flags then return end

	for key, flag in pairs(mob._query_split(flags, ' ')) do
		entity.__mob.flags[flag] = true
	end
end

-- remove a list of flag to an entity
function mob.remove_flag(entity, flags)
	if not entity or not entity.__mob or not flags then return end

	for key, flag in pairs(mob._query_split(flags, ' ')) do
		entity.__mob.flags[flag] = nil
	end
end

-- get the flags as a single string
function mob.get_flags(entity)
	if not entity or not entity.__mob then return end

	local result = ""
	for key, value in pairs(entity.__mob.flags) do
		result = result.." "..key
	end

	return result:sub(2)
end

-- check if the entity has a list of flag
function mob.has_flag(entity, query)
	if not entity or not entity.__mob then return end

	local qo = mob.parse(query)
	if #qo.flags==0 then
		return false
	end

	for i, flag in pairs(qo.flags) do
		if not entity.__mob.flags[flag] then
			return false
		end
	end

	return true
end

-- check if the entity has not a list of flag
function mob.has_not_flag(entity, query)
	if not entity or not entity.__mob then return end

	local qo = mob.parse(query)
	for i, flag in pairs(qo.flags) do
		if entity.__mob.flag[flag] then
			return false
		end
	end

	return true
end

-- check if the entity comply with the query
function mob.is(entity, query)
	if not entity or not entity.__mob or not query then return false end

	-- get query object
	if type(query)=="string" then
		query = mob.parse(query)
	end

	-- check id
	if query.id and query.id~=entity.__mob.id then return false end
	if query.without.id and query.without.id==entity.__mob.id then return false end

	-- check state
	if query.state and query.state~=entity.__mob.state then return false end
	if query.without.state and query.without.state==entity.__mob.state then return false end

	-- check flags
	for i, flag in pairs(query.flags) do
		if not entity.__mob.flags[flag] then
			return false
		end
	end
	for i, flag in pairs(query.without.flags) do
		if entity.__mob.flags[flag] then
			return false
		end
	end

	return true
end

-- get the id of an entity
function mob.get_id(entity)
	if not entity or not entity.__mob then return end
	return entity.__mob.id
end

-- get the state of an entity
function mob.get_state(entity)
	if not entity or not entity.__mob then return end
	return entity.__mob.state
end

-- get in a single screen the id, flags and state of an entity
function mob.get_string(entity)
	if not entity or not entity.__mob then return "#UnregisteredObject" end

	local id = mob.get_id(entity)
	local state = mob.get_state(entity)
	local flags = mob.get_flags(entity)

	local result = "#"..id
	if state then result = result.." @"..state end
	if flags then result = result.." "..flags end

	return result
end

-- query the mob to get a pool of entities
function mob.get(query_or_fn)
	-- create an empty pool
	local result = mob.new_pool()

	-- of the function is called without arguments we create a pool with all entities
	if not query_or_fn then
		for key, entity in pairs(mob.list) do
			table.insert(result.list, entity)
		end
		return result
	end

	-- get function that check an entity
	local check_fn
	if type(query_or_fn)=="function" then
		check_fn = query_or_fn
	else
		local query_object = query_or_fn
		if type(query_object)=="string" then
			query_object = mob.parse(query_object)
		end

		check_fn = function(entity)
			return mob.is(entity, query_object)
		end
	end

	for key, entity in pairs(mob.list) do
		if check_fn(entity) then
			table.insert(result.list, entity)
		end
	end

	return result
end

-- get an entity based on its id
function mob.get_entity(id)
	return mob.list[id]
end

-- function to iterate through a selection of entities
-- e.g. for i, entitiy in mob.pairs("npc") do
function mob.pairs(query_or_fn)
	return mob.get(query_or_fn):pairs()
end

-- internal function to parse a query
function mob._query_split(str, delimiter)
	if not delimiter then delimiter = ' ' end
    local result = {}
    local string_index = 1

    local found_start, found_end = string.find( str, delimiter, string_index)
    while found_start do
        table.insert(result, string.sub( str, string_index , found_start-1 ) )
        string_index = found_end + 1
        found_start, found_end = string.find( str, delimiter, string_index)
    end

    table.insert( result, string.sub( str, string_index) )

    return result
end

-- get how many element are in the mob
function mob.get_size()
	return mob.count
end



--------------
-- POOLS OF ENTITIES --
-- Group of entities return by mob.get, can chain functions
--------------

-- entity_pool object with custom metatable
mob.entity_pool = {
	meta = {
		__index = function(table, key)
			-- if this is a function from the mon.entity_pool object we just send it
			if mob.entity_pool[key] then
				return mob.entity_pool[key]
			end

			-- if the key is not a mob.entity_pool function, we call the function for all the entities in the list
			return function(...)
				local args = {...}

				-- first argument should be the mob.entity_pool object
				-- mob.get():test()
				local this = args[1]

				if not this then return end

				-- we go through all the entities and check if they have the function
				for i, entity in pairs(this.list) do
					if entity[key] and type(entity[key])=="function" then
						args[1] = entity
						entity[key](unpack(args))
					end
				end

				return this
			end
		end
	}
}

-- create a new empty list
function mob.new_pool()
	local pool = {}
	pool.list = {}

	setmetatable(pool, mob.entity_pool.meta)

	return pool
end

-- function to iterate though the pool of entities
function mob.entity_pool:pairs()
	return function(pool, index)
		index = index + 1
		entity = pool.list[index]
		if entity then
			return index, entity
		end
	end, self, 0
end


-- add entities to a pool of entities
-- can be a pool, function, query, entities of array of entities
function mob.entity_pool:add(a)
	if not self or not a then return self end

	-- get the new list
	local entities_to_add
	if a.mt.__index==mob.entity_pool then
		entities_to_add = a.list
	elseif type(a)=="string" or type(a)=="function" then
		local new_pool = mob.get(a)
		entities_to_add = new_pool.list
	elseif type(a)=="table" then
		entities_to_add = a
	else
		entities_to_add = {a}
	end

	-- add to the list the entities that are not duplicates
	for i, new_entity in pairs(entities_to_add) do
		local is_new = true
		for j, entity in paisr(self.list) do
			if entity==new_entity then
				is_new = false
				break
			end
		end

		if is_new then
			table.insert(self.list, new_entity)
		end
	end

	return self
end

-- remove entities from a pool
-- can be a pool, function, query, entities of array of entities
function mob.entity_pool:remove(a)
	if not self or not a then return self end

	-- get the new list
	local entities_to_remove
	-- standard query
	if type(a)=="string" or type(a)=="function" then
		local new_pool = mob.get(a)
		entities_to_remove = new_pool.list
	-- if it's a mob.entity_pool
	elseif a.mt and a.mt.__index==mob.entity_pool then
		entities_to_remove = a.list
	-- or just a list of entities
	elseif type(a)=="table" then
		entities_to_remove = a
	else
		entities_to_remove = {a}
	end

	-- remove from the entities from the pool
	for i, entity_to_remove in pairs(entities_to_remove) do
		local is_new = true
		for j, entity in pairs(self.list) do
			if entity==entity_to_remove then
				table.remove(self.list, j)
				break
			end
		end
	end

	return self
end


-- keep only entities that comply with the query
function mob.entity_pool:filter(query_or_fn)
	if not self or not query_or_fn then return self end

	-- get function that check an entity
	local check_fn
	if type(query_or_fn)=="function" then
		check_fn = query_or_fn
	else
		local query_object = query_or_fn
		if type(query_object)=="string" then
			query_object = mob.parse(query_object)
		end

		check_fn = function(entity)
			return mob.is(entity, query_object)
		end
	end

	-- filter the pool, remove entities that doesn't comply with the query
	for index=#self.list, 1, -1 do
		if not check_fn(self.list[index]) then
			table.remove(self.list, index)
		end
	end

	return self
end

-- delete all elements in the pool from the game
function mob.entity_pool:delete()
	if not self then return end

	for i, entity in pairs(self.list) do
		mob.delete(entity)
	end

	self.list = {}

	return self
end

-- create a new pool with the exact same list of entities
-- useful to filter a pool, while keeping the original one intact
-- local cache_pool = mob.get("npc")
-- cache_pool:copy():filter("@idle"):update()
-- cache_pool:copy():remove("alive"):delete()
function mob.entity_pool:copy()
	local copy = mob.new_pool()
	if not self then return copy end

	for i=1, #self.list do
		table.insert(copy.list,self.list[i])
	end

	return copy
end

-- sort the pool of entities based on a function (argument fn)
-- the argument function has 2 arguments, and return true if the first entity has to come before the second
function mob.entity_pool:sort(fn)
	if not self then return self end
	table.sort(self.list, fn)
	return self
end

-- call a function on each entities in the pool
-- the argument function as 1 argument, the entity
function mob.entity_pool:call(fn)
	if not self or not fn then return self end
	for i, entity in pairs(self.list) do
		fn(entity)
	end

	return self
end

-- return the size of the pool
function mob.entity_pool:get_size()
	if not self then return 0 end
	return #self.list
end

-- return the first entity in the pool
function mob.entity_pool:get_first()
	if not self then return end
	return self.list[1]
end

-- return the last entity in the pool
function mob.entity_pool:get_last()
	if not self then return end
	return self.list[#self.list]
end

-- return a random entity in the pool
function mob.entity_pool:get_random()
	if not self then return end
	return self.list[math.ceil(love.math.random() * #self.list)]
end

-- return an entitiy at a special index
-- you shouldn't need this function in theory
function mob.entity_pool:get_index(index)
	if not self then return end
	return self.list[index]
end

-- get the entity with the smallest value
-- argument can be a string of the name of a property or a function that take an entity as a argument and return a value
function mob.entity_pool:get_smallest(prop_or_fn)
	if not self or not prop_or_fn then return end
	if #self.list==0 then return end

	-- get function that return a value
	local get_value_fn
	if type(prop_or_fn)=="string" then
		get_value_fn = function(a) return a[prop_or_fn] end
	elseif type(prop_or_fn)=="function" then
		get_value_fn = prop_or_fn
	else
		return
	end

	local result = self.list[1]
	local smallest_value = get_value_fn(result)

	for i = 2, #self.list do
		local entity = self.list[i]
		if entity then
			local val = get_value_fn(entity)
			if val and val<smallest_value then
				result = entity
				smallest_value = val
			end
		end
	end

	return result
end

-- get the entity with the biggest value
-- argument can be a string of the name of a property or a function that take an entity as a argument and return a value
function mob.entity_pool:get_biggest(prop_or_fn)
	if not self or not prop_or_fn then return end
	if #self.list==0 then return end

	-- get function that return a value
	local get_value_fn
	if type(prop_or_fn)=="string" then
		get_value_fn = function(a) return a[prop_or_fn] end
	elseif type(prop_or_fn)=="function" then
		get_value_fn = prop_or_fn
	else
		return
	end

	local result = self.list[1]
	local biggest_value = get_value_fn(result)

	for i = 2, #self.list do
		local entity = self.list[i]
		if entity then
			local val = get_value_fn(entity)
			if val and val>biggest_value then
				result = entity
				biggest_value = val
			end
		end
	end

	return result
end

-- get the entity that is the closest from the reference
-- argument can be a string of the name of a property or a function that take an entity as a argument and return a single value
-- value is compared with argument "reference"
function mob.entity_pool:get_closest(prop_or_fn, reference)
	if not self or not prop_or_fn then return end
	if #self.list==0 then return end

	if not reference then reference = 0 end

	-- get function that return a value
	local get_value_fn
	if type(prop_or_fn)=="string" then
		get_value_fn = function(a) return a[prop_or_fn] end
	elseif type(prop_or_fn)=="function" then
		get_value_fn = prop_or_fn
	else
		return
	end

	local result = self.list[1]
	local diff_value = math.abs(get_value_fn(result)-reference)

	for i = 2, #self.list do
		local entity = self.list[i]
		if entity then
			local val = math.abs(get_value_fn(entity)-reference)
			if val and val<diff_value then
				result = entity
				diff_value = val
			end
		end
	end

	return result
end

return mob
