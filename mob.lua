--[[
	Simple Entity System

	* Add/remove entities to the mob
	mob.new()
	mob.register()
	mob.delete()

	* Get group of entities
	You can query to get a list of entities with get() with a single string "#player @dead item_resurection -level_hell"
	#<id_name> is an id. An entity has a unique id that cannot be changed.
	<class_name> is a class. An entity can have multiple classes
	@<state_name> is a state. An entity has only one state and can be changed
	-<stuff> means that the query should include the element. "-level_hell" means that the entity shouldn't have the class 'level_hell'. works also for is and state

	You can also use a function to get a group of entities where you can filter based on any properties of the entity
	The function is called for each entity (with the entity as an argument) and should return true if the entity should be in the group

	* Chain group of entities functions
	The get() function return a special object that is a group of entities. The object have functions that can be chained to manipulate the group
	example: mob.get("npc"):combine("bullets"):remove()

	You can also chain functions your functions specific to the entities
	mob.get("npc"):check_collision_with_bullets()


	* use entity and list of entities only locally
	if you need to keep a reference of an entity (for example if an entity need to use another entity)
	use and save their id instead with get_id() and get the entity with get_entity()
	This way you avoid risk of referencing an entity that might get removed from the mob.
	The memory manager can also clean up unused entities as soon as it is removed from the mob

	* TODO
	Cached list (query is cached, modifying entities update all cached list)
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
	entity.__mob.classes = {}

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
		local fn_list = {"delete", "set", "set_state", "add_class", "remove_class", "get_class", "has_class", "has_not_class", "is", "get_id", "get_state", "get_string"}
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

-- parse a string (or multiple strings) which can contain #id, class, @state
function mob.parse(...)
	local result = {
		classes = {},
		without = {classes={}}
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
					table.insert(add_to.classes, query)
				end
			end
		end
	end

	return result
end

-- add and remove class and change state with a single query or query object
-- id cannot be set after registration
function mob.set(entity, query)
	if not entity or not query then return end

	-- get query object
	if type(query)=="string" then
		query = mob.parse(query)
	end

	-- set state
	mob.set_state(entity, query.state)

	-- remove classes
	for key, class in pairs(query.without.classes) do
		entity.__mob.classes[class] = nil
	end

	-- add classes
	for key, class in pairs(query.classes) do
		entity.__mob.classes[class] = true
	end
end

-- set the state of an entity (only one state per entity)
function mob.set_state(entity, state)
	if not entity or not entity.__mob then return end
	entity.__mob.state = state
end

-- add a list of class to an entity (entities can have multiple classe)
function mob.add_class(entity, classes)
	if not entity or not entity.__mob or not classes then return end

	for key, class in pairs(mob._query_split(classes, ' ')) do
		entity.__mob.classes[class] = true
	end
end

-- remove a list of class to an entity
function mob.remove_class(entity, classes)
	if not entity or not entity.__mob or not classes then return end

	for key, class in pairs(mob._query_split(classes, ' ')) do
		entity.__mob.classes[class] = nil
	end
end

-- get the list of class as a single string
function mob.get_class(entity)
	if not entity or not entity.__mob then return end

	local result = ""
	for key, value in pairs(entity.__mob.classes) do
		result = result.." "..key
	end

	return result:sub(2)
end

-- check if the entity has a list of class
function mob.has_class(entity, query)
	if not entity or not entity.__mob then return end

	local qo = mob.parse(query)
	if #qo.classes==0 then
		return false
	end

	for i, class in pairs(qo.classes) do
		if not entity.__mob.classes[class] then
			return false
		end
	end

	return true
end

-- check if the entity has not a list of class
function mob.has_not_class(entity, query)
	if not entity or not entity.__mob then return end

	local qo = mob.parse(query)
	for i, class in pairs(qo.classes) do
		if entity.__mob.classes[class] then
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

	-- check classes
	for i, class in pairs(query.classes) do
		if not entity.__mob.classes[class] then
			return false
		end
	end
	for i, class in pairs(query.without.classes) do
		if entity.__mob.classes[class] then
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

-- get in a single screen the id, classes and state of an entity
function mob.get_string(entity)
	if not entity or not entity.__mob then return "#UnregisteredObject" end

	local id = mob.get_id(entity)
	local state = mob.get_state(entity)
	local classes = mob.get_class(entity)

	local result = "#"..id
	if state then result = result.." @"..state end
	if classes then result = result.." "..classes end

	return result
end

-- query the mob to get a list of entities
function mob.get(query_or_fn)
	-- create an empty mob list
	local result = mob_list.new()

	-- of the function is called without arguments we create a list with all entities
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
-- MOB LIST --
-- Group of entities return by mob_get, can chain functions
--------------

-- mob_list object with custom metatable
mob_list = {
	meta = {
		__index = function(table, key)
			-- if this is a mob_list function we just send it
			if mob_list[key] then
				return mob_list[key]
			end

			-- if the key is not a mob_list function, we call the function for all the entities in the list
			return function(...)
				local args = {...}

				-- first argument should be the mob_list object
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
function mob_list.new()
	local list = {}
	list.list = {}

	setmetatable(list, mob_list.meta)

	return list
end

-- function to iterate though the list of entities
function mob_list:pairs()
	return function(mob_list, index)
		index = index + 1
		entity = mob_list.list[index]
		if entity then
			return index, entity
		end
	end, self, 0
end


-- add entities to a mob list
-- can be a mob list, function, query, entities of array of entities
function mob_list:add(a)
	if not self or not a then return self end

	-- get the new list
	local entities_to_add
	if a.mt.__index==mob_list then
		entities_to_add = a.list
	elseif type(a)=="string" or type(a)=="function" then
		local new_list = mob.get(a)
		entities_to_add = new_list.list
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

-- remove entities from a mob list
-- can be a mob list, function, query, entities of array of entities
function mob_list:remove(a)
	if not self or not a then return self end

	-- get the new list
	local entities_to_remove
	-- standard query
	if type(a)=="string" or type(a)=="function" then
		local new_list = mob.get(a)
		entities_to_remove = new_list.list
	-- if it's a mob_list
	elseif a.mt and a.mt.__index==mob_list then
		entities_to_remove = a.list
	-- or just a list of entities
	elseif type(a)=="table" then
		entities_to_remove = a
	else
		entities_to_remove = {a}
	end

	-- remove from the list the entities
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
function mob_list:filter(query_or_fn)
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

	-- filter the list, remove entities that doesn't comply with the query
	for index=#self.list, 1, -1 do
		if not check_fn(self.list[index]) then
			table.remove(self.list, index)
		end
	end

	return self
end

-- delete all elements in the list from the game
function mob_list:delete()
	if not self then return end

	for i, entity in pairs(self.list) do
		mob.delete(entity)
	end

	self.list = {}

	return self
end

-- create a new list with the exact same list of element
-- useful to filter a list, while keeping the original list intact
-- local cache_list = mob.get("npc")
-- cache_list:copy():filter("@idle"):update()
-- cache_list:copy():remove("alive"):delete()
function mob_list:copy()
	local copy = mob_list.new()
	if not self then return copy end

	for i=1, #self.list do
		table.insert(copy.list,self.list[i])
	end

	return copy
end

-- sort the list of entities based on a function (argument fn)
-- the argument function has 2 arguments, and return true if the first entity has to come before the second
function mob_list:sort(fn)
	if not self then return self end
	table.sort(self.list, fn)
	return self
end

-- call a function on each entities of the list
-- the argument function as 1 argument, the entity
function mob_list:call(fn)
	if not self or not fn then return self end
	for i, entity in pairs(self.list) do
		fn(entity)
	end

	return self
end

-- return the size of the list
function mob_list:get_size()
	if not self then return 0 end
	return #self.list
end

-- return the first entity in the list
function mob_list:get_first()
	if not self then return end
	return self.list[1]
end

-- return the last entity in the list
function mob_list:get_last()
	if not self then return end
	return self.list[#self.list]
end

-- return a random entity in the list
function mob_list:get_random()
	if not self then return end
	return self.list[math.ceil(love.math.random() * #self.list)]
end

-- get the entity with the smallest value
-- argument can be a string of the name of a property or a function that take an entity as a argument and return a value
function mob_list:get_smallest(prop_or_fn)
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
function mob_list:get_biggest(prop_or_fn)
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
function mob_list:get_closest(prop_or_fn, reference)
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
