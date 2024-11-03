do
	local data = _G.data

	local wagon = table.deepcopy(data.raw["cargo-wagon"]["cargo-wagon"])
	wagon.name = "folk-logistic-wagon"
	wagon.minable.result = "folk-logistic-wagon"
	wagon.inventory_size = data.raw["logistic-container"]["storage-chest"].inventory_size
	wagon.pictures.rotated.layers[1].filenames = {
		"__folk-logistic-wagon__/cargo-wagon-1.png",
		"__folk-logistic-wagon__/cargo-wagon-2.png",
		"__folk-logistic-wagon__/cargo-wagon-3.png",
		"__folk-logistic-wagon__/cargo-wagon-4.png",
	}
	wagon.horizontal_doors.layers[1].filename = "__folk-logistic-wagon__/cargo-wagon-door-horizontal.png"
	wagon.vertical_doors.layers[1].filename = "__folk-logistic-wagon__/cargo-wagon-door-vertical.png"

	local item = table.deepcopy(data.raw["item-with-entity-data"]["cargo-wagon"])
	item.name = "folk-logistic-wagon"
	item.icon = "__folk-logistic-wagon__/item-icon.png"
	item.icon_size = 32
	item.place_result = "folk-logistic-wagon"

	data:extend({
		item,
		wagon,
		{
			type = "recipe",
			name = "folk-logistic-wagon",
			enabled = false,
			energy_required = 1,
			ingredients =
			{
				{ type = "item", name = "cargo-wagon",        amount = 1, },
				{ type = "item", name = "electronic-circuit", amount = 8, },
				{ type = "item", name = "advanced-circuit",   amount = 3, },
			},
			results = { { type = "item", name = "folk-logistic-wagon", amount = 1, }, },
		},
		{
			type = "technology",
			name = "folk-logistic-wagon",
			icon = "__folk-logistic-wagon__/tech.png",
			effects = {
				{
					type = "unlock-recipe",
					recipe = "folk-logistic-wagon",
				},
			},
			icon_size = 128,
			prerequisites = { "automated-rail-transportation", "logistic-system", },
			unit = {
				count = 150,
				ingredients = {
					{ "automation-science-pack", 2, },
					{ "logistic-science-pack",   1, },
					{ "chemical-science-pack",   1, },
					{ "utility-science-pack",    1, },
				},
				time = 30,
			},
			order = "c-k-d",
		},
	})
end
