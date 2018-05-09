# mob.lua

mob.lua is an entity manager for Löve2d inspired by jQuery. The code manages the entities created by a game and makes it easy to retrieve elements and manipulate them. The goal is to make the game code cleaner and more readable.

## Introduction

To use the library simply load it

```lua
mob = require('mob')
```

you can add entities with `mob.new()`or `mob.register()`

```lua
mob.register(my_player, "#player @idle invincible has_collider")
```

you can get entities with `mob.get()`

```lua
mob.get("grunt @dead")
```


## Attributes

Every entity added to the mob gets special attributes
- **id**: Every entity has their own unique id that cannot be changed
- **state**: An entity can have one state (and only one) that can be change at anytime
- **classes**: An entity can have multiple classes which can be change

When an entity is registered, a list of function are automatically added to it to easily change or check attributes:
`delete(), set(), set_state(), add_class(), remove_class(), get_class(), has_class(), has_not_class(), is(), get_id(), get_state(), get_string()`

```lua
empty_entity = {}
new_entity = mob.new(empty_entity, "class_1 class_2")
new_entity:remove_class("class_2")
new_entity:get_id()
```

## Query

The library makes it easy to retrieve a list of entities with simply queries. A query is a simple string with properties separated by spaces.

```lua
mob.get("#player -@dead magic_wand")
```

- *#<id_name>* is an id.
- *<class_name>* is a class.
- *@<state_name>* is a state.
- *-<stuff>* means that the query should not include the element (can be used on class, id or state)

A query can also be a custom function that take an entity as its only argument and that return true if the entity id complient. Custom function are useful to do queries on other properties of the entitiy

```lua
mob.get(function(a) return a.velocity>100 end)
```

## Chains

The result of a query is an object that contain the list of entities. The object also includes a selection of functions that can be chained to manipulate even more the list of entities


```lua
-- delete all the bullets that was spawn more than 10 seconds ago
mob.get("bullets"):filter(function(a) return a.lifetime>10 end):delete()

for i,particle in mob.get("particles"):pairs() do
  -- update particles
end
```

### Group manipulation

The following functions, manipulate the group of entities and return itself.

`add(), remove(), filter(), copy(), sort(), call()`

### Access entities

The following functions allow you to retrieve specific entities stores in a group

`pairs(), get_first(), get_last(), get_random(), get_smallest(), get_biggest(), get_closest()`

### Entities custom function

It is possible to also call in a chain functions that are defined by entities themselves. Alternatively the function `call()` can also execute a function on each entities of the group.

```lua
enemy = {}
function enemy:per_frame_update()
end

bullet = {}
function bullet:update(dt)
end

-- create one enemy and two bullets
mob.new(enemy)
mob.new(bullet)
mob.new(bullet)

-- call on all entities update() and per_frame_update()
mob.get()
  :update(dt)
  :per_frame_update()
```

## Performance

While the code is created to perform well, the main goal is to improve convenience and code readability. Making queries can have a cost, especially if the entity count is high, since the library has to check every entity against a query. Be mindful.
