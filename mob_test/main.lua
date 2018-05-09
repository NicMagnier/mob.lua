mob = require "libs/mob"

-- NPC --
npc = {
	x = 0,
	y = 0,
	size = 30
}
function new_npc()
	local type_list = {"square", "circle"}
	mob.new(npc, "type_npc @idle"):add_class(type_list[math.ceil(love.math.random() * #type_list)])
end

function npc:update(dt)
	-- calculate distance from the mouse
	local mx, my = love.mouse.getPosition()
	local dx = mx - self.x
	local dy = my - self.y
	self.mouse_distance = (dx*dx+dy*dy)

	-- in idle, we are checking if there is another npc ready to explode nearby
	if self:get_state()=="idle" then
		local interesting_entity = mob.get("type_npc @about_to_explode")
			:filter(function(e)
					local dx = e.x - self.x
					local dy = e.y - self.y
					return (dx*dx+dy*dy)<150*150
				end)
			:get_random()

		if interesting_entity then
			shape = "circle"
			if self:has_class("square") then
				shape = "square"
			end

			-- we get the id of the entity
			self.entity_ref = interesting_entity:get_id()

			-- depending if the entity had the same shape as us, we mights try to look up for them or run away
			if interesting_entity:has_class(shape) then
				self:set_state("look_closer")
			else
				self:set_state("run_away")
			end
		end
	elseif self:is("@look_closer") then
		local e = mob.get_entity(self.entity_ref)
		local dx = e.x - self.x
		local dy = e.y - self.y
		local length = (dx*dx+dy*dy)^.5
		if length>30 then
			local vx, vy = dx/length, dy/length
			self.x = self.x + vx*25*dt
			self.y = self.y + vy*25*dt
		end
	elseif self:is("@run_away") then
		local e = mob.get_entity(self.entity_ref)
		local dx = self.x - e.x
		local dy = self.y - e.y
		local length = (dx*dx+dy*dy)^.5
		if length<400 then
			local vx, vy = dx/length, dy/length
			self.x = self.x + vx*50*dt
			self.y = self.y + vy*50*dt
		else
			self:set_state("idle")
		end
	end
end

function npc:draw()
	-- set color
	if self:is("@about_to_explode") then
		love.graphics.setColor(about_to_explode_color)
	elseif self:is("square") then
		love.graphics.setColor(0,0,255)
	else
		love.graphics.setColor(255,0,0)
	end

	-- draw shape
	if self:is("square") then
		love.graphics.rectangle("fill", self.x - (self.size/2), self.y - self.size, self.size, self.size)
		love.graphics.setColor(0,0,0)
		love.graphics.rectangle("line", self.x - (self.size/2), self.y - self.size, self.size, self.size)
	elseif self:has_class("circle") then
		love.graphics.circle("fill", self.x , self.y - self.size/2, self.size/2)
		love.graphics.setColor(0,0,0)
		love.graphics.circle("line", self.x , self.y - self.size/2, self.size/2)
	end
end

function npc:draw_outline()
	if self:has_class("square") then
		love.graphics.rectangle("line", self.x - (self.size/2), self.y - self.size, self.size, self.size)
	elseif self:has_class("circle") then
		love.graphics.circle("line", self.x , self.y - self.size/2, self.size/2)
	end
end



-- CLOUD --

cloud = {
	x = 0,
	y = 0
}
function new_cloud()
	local e = mob.new(cloud, "type_cloud")
	e.x = -50
	e.y = love.graphics.getHeight() * love.math.random()
	e.vx = 50 + 50 * love.math.random()
end
function cloud:update(dt)
	-- clouds move with the wind
	self.x = self.x + self.vx*dt

	-- we delete them if they go too much on the right side
	if self.x > love.graphics.getWidth() + 50 then
		self:delete()
	end
end
function cloud:draw()
	love.graphics.ellipse("fill", self.x, self.y, 50, 30)
end




-- LOVE --

function love.load()
	cloud_cooldown = 0
	about_to_explode_color = {255,128,0}

	for i=1, 100 do
		new_npc()
	end

	-- go through all npc and assign a random position
	for i, e in mob.pairs("type_npc") do
		e.x = love.graphics.getWidth() * love.math.random()
		e.y = love.graphics.getHeight() * love.math.random()
	end
end

function love.update(dt)
	-- create a new cloud from time to time
	cloud_cooldown = cloud_cooldown - dt
	if cloud_cooldown<0 then
		new_cloud()
		cloud_cooldown = 0.8
	end

	-- update everything
	mob.get():update(dt)

	local by_distance = function(a,b)
		return a.mouse_distance < b.mouse_distance
	end

	-- when the user click, find the closest npc and set is to explode
	if love.mouse.isDown(1) then
		mob.get("type_npc")
			:get_smallest("mouse_distance")
			:set_state("about_to_explode")
	end
end

function love.draw()
	love.graphics.clear(64,64,64)

	-- draw all NPC, the order depends on the y axis
	love.graphics.setLineWidth(1)
	mob.get("type_npc")
		:sort(function(a,b) return a.y<b.y end)
		:draw()

	-- draw the circle of selection
	local mx, my = love.mouse.getPosition()
	local selection_radius = 100
	love.graphics.setColor(0,255,0, 64)
	love.graphics.circle("fill", mx, my, selection_radius)

	local near_mouse = function(npc)
		local dx = mx - npc.x
		local dy = my - npc.y
		local length = dx*dx+dy*dy
		return length<selection_radius*selection_radius
	end

	-- highlight NPC that are in the circle of selection
	love.graphics.setColor(255,255,255)
	love.graphics.setLineWidth(5)
	mob.get("type_npc")
		:filter(near_mouse)
		:draw_outline()

	-- draw all the cloud and output how many cloud are drawn
	love.graphics.setColor(255,255,255,100)
	print("cloud drawn:", mob.get("type_cloud"):draw():size())
end
