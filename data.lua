
do
	local data = _G.data

	local wagon = table.deepcopy(data.raw["cargo-wagon"]["cargo-wagon"])
	wagon.name = "folk-logistic-wagon"
	wagon.minable.result = "folk-logistic-wagon"
	wagon.inventory_size = data.raw["logistic-container"]["logistic-chest-storage"].inventory_size
	wagon.pictures.layers[1].filenames = {
		"__folk-logistic-wagon__/cargo-wagon-1.png",
		"__folk-logistic-wagon__/cargo-wagon-2.png",
		"__folk-logistic-wagon__/cargo-wagon-3.png",
		"__folk-logistic-wagon__/cargo-wagon-4.png"
	}
	wagon.horizontal_doors.layers[1].filename = "__folk-logistic-wagon__/cargo-wagon-door-horizontal-end.png"
	wagon.horizontal_doors.layers[2].filename = "__folk-logistic-wagon__/cargo-wagon-door-horizontal-side.png"
	wagon.horizontal_doors.layers[4].filename = "__folk-logistic-wagon__/cargo-wagon-door-horizontal-top.png"
	wagon.vertical_doors.layers[1].filename = "__folk-logistic-wagon__/cargo-wagon-door-vertical-end.png"
	wagon.vertical_doors.layers[2].filename = "__folk-logistic-wagon__/cargo-wagon-door-vertical-side.png"
	wagon.vertical_doors.layers[4].filename = "__folk-logistic-wagon__/cargo-wagon-door-vertical-top.png"

	data:extend({
		wagon,
		{
			type = "item-with-entity-data",
			name = "folk-logistic-wagon",
			icon = "__folk-logistic-wagon__/item-icon.png",
			icon_size = 32,
			flags = {"goes-to-quickbar"},
			subgroup = "transport",
			order = "a[train-system]-g[cargo-wagon]",
			place_result = "folk-logistic-wagon",
			stack_size = 5
		},
		{
			type = "recipe",
			name = "folk-logistic-wagon",
			enabled = false,
			ingredients =
			{
				{"cargo-wagon", 1},
				{"electronic-circuit", 8},
				{"advanced-circuit", 3},
			},
			result = "folk-logistic-wagon"
		},
		{
			type = "technology",
			name = "folk-logistic-wagon",
			icon = "__folk-logistic-wagon__/tech.png",
			effects = {
				{
					type = "unlock-recipe",
					recipe = "folk-logistic-wagon"
				}
			},
			icon_size = 128,
			prerequisites = { "automated-rail-transportation", "logistic-system" },
			unit = {
				count = 150,
				ingredients = {
					{"science-pack-1", 1},
					{"science-pack-2", 1},
					{"science-pack-3", 1},
				},
				time = 30
			},
			order = "c-k-d",
		},
	})
end
