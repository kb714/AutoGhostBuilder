-- src/tests/item-requests.lua
-- Tests for item_requests and module handling

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

    run_test("handle empty item_requests without crashing", function(assert)
        local surface = get_test_surface()
        clear_test_area(surface, {{180, 180}, {190, 190}})

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "wooden-chest",
            position = {185, 185},
            force = "player"
        }

        local mock_player = {
            get_inventory = function(inventory_type)
                local inv = {}
                setmetatable(inv, { __len = function() return 0 end })
                return inv
            end,
            cursor_stack = { valid_for_read = false },
            can_place_entity = function() return true end
        }

        local success, error_msg = pcall(function()
            GhostBuilder.check_all_items_available(ghost, mock_player)
        end)

        assert.is_true(success, "Should handle empty item_requests: " .. tostring(error_msg))
        ghost.destroy()
    end)

    run_test("quality string vs LuaQualityPrototype comparison", function(assert)
        local surface = get_test_surface()
        clear_test_area(surface, {{190, 190}, {200, 200}})

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "assembling-machine-1",
            position = {195, 195},
            force = "player"
        }

        -- Simulate item_requests with quality as STRING (real API behavior)
        local mock_item_requests = {
            {
                name = "speed-module",
                quality = "normal",
                count = 3
            }
        }

        local mock_player = {
            get_inventory = function(inventory_type)
                local inv = {}
                setmetatable(inv, {
                    __len = function() return 1 end,
                    __index = function(t, i)
                        if i == 1 then
                            return {
                                valid_for_read = true,
                                is_item_with_tags = false,
                                name = "speed-module",
                                quality = prototypes.quality["normal"],  -- LuaQualityPrototype
                                count = 3
                            }
                        end
                        return nil
                    end
                })
                return inv
            end,
            cursor_stack = { valid_for_read = false }
        }

        local item_request = mock_item_requests[1]
        local item_quality = item_request.quality

        -- Normalize string to LuaQualityPrototype
        if type(item_quality) == "string" then
            item_quality = prototypes.quality[item_quality]
        end

        local inventory = mock_player.get_inventory(defines.inventory.character_main)
        local stack = inventory[1]

        local matches = (stack.quality == item_quality)
        assert.is_true(matches, "Quality should match after normalization")

        ghost.destroy()
    end)
end
