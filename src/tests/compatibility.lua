-- src/tests/compatibility.lua
-- Tests for item-with-tags protection (Factorissimo, Packing Tape)

local GhostBuilder = require("src.core.ghost-builder")

return function(run_test)
    local function get_test_surface()
        return game.surfaces[1]
    end

    local function clear_test_area(surface, area)
        for _, entity in pairs(surface.find_entities_filtered{area = area}) do
            if entity.valid and entity.name ~= "character" then
                pcall(function() entity.destroy() end)
            end
        end
    end

    run_test("ignores items with tags in cursor", function(assert)
        local mock_quality = {}
        local mock_cursor_with_tags = {
            valid_for_read = true,
            name = "iron-chest",
            quality = mock_quality,
            is_item_with_tags = true
        }

        local result = GhostBuilder.find_item_source("iron-chest", mock_quality, mock_cursor_with_tags, nil)
        assert.is_nil(result, "Should not use items with tags")
    end)

    run_test("uses normal items without tags", function(assert)
        local mock_quality = {}
        local mock_cursor_normal = {
            valid_for_read = true,
            name = "iron-chest",
            quality = mock_quality,
            is_item_with_tags = false
        }

        local result = GhostBuilder.find_item_source("iron-chest", mock_quality, mock_cursor_normal, nil)
        assert.equals("cursor", result)
    end)

    run_test("skips items with tags in mixed inventory", function(assert)
        local mock_quality = {}
        local mock_inventory = {
            [1] = {
                valid_for_read = true,
                name = "iron-chest",
                quality = mock_quality,
                is_item_with_tags = true
            },
            [2] = {
                valid_for_read = true,
                name = "iron-chest",
                quality = mock_quality,
                is_item_with_tags = false
            }
        }
        setmetatable(mock_inventory, { __len = function() return 2 end })

        local result = GhostBuilder.find_item_source("iron-chest", mock_quality, nil, mock_inventory)
        assert.equals("inventory", result, "Should find non-tagged item")
    end)

    run_test("cannot build with only tagged items", function(assert)
        local surface = get_test_surface()
        clear_test_area(surface, {{220, 220}, {230, 230}})

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {225, 225},
            force = "player"
        }

        local mock_player = {
            get_inventory = function(inventory_type)
                local inv = {
                    [1] = {
                        valid_for_read = true,
                        name = "iron-chest",
                        quality = prototypes.quality["normal"],
                        is_item_with_tags = true
                    }
                }
                setmetatable(inv, { __len = function() return 1 end })
                return inv
            end,
            cursor_stack = { valid_for_read = false },
            can_place_entity = function() return true end
        }

        local can_build, item_info = GhostBuilder.can_build_ghost(ghost, mock_player)
        assert.is_false(can_build, "Should not build with tagged items only")

        ghost.destroy()
    end)
end
