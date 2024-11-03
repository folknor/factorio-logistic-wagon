---@meta

---@class game
---@field players table
---@field set_game_state function
game = {}

---@alias TargetType
---| "entity"
---| "position"
---| "direction"

---@class AmmoType
---@field target_type TargetType

---@class itemPrototype
---@field stack_size? number
---@field fuel_category? string
---@field fuel_value? number
---@field get_ammo_type? function
---@field order? string

itemPrototype = {}

---@return AmmoType
function itemPrototype.get_ammo_type() end

---@class prototypes
---@field item table<string, itemPrototype>

---@class script
script = {}
function script.on_event(event, fn) end
