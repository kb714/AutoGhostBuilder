-- src/tests/item-requests.lua

local GhostBuilder = require("src.core.ghost-builder")

return function(run_test)
    local function get_player()
        local player = game.get_player(1)
        if not player then
            error("Player 1 not found in save")
        end
        return player
    end

    local function clear_area(surface, area)
        for _, entity in pairs(surface.find_entities_filtered{area = area}) do
            if entity.valid and entity.name ~= "character" then
                pcall(function() entity.destroy() end)
            end
        end
    end

    run_test("Handles ghost without item_requests", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{90, 90}, {95, 95}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()
        player.insert{name = "iron-chest", count = 1}

        local count_before = player.get_main_inventory().get_item_count("iron-chest")
        assert.equals(1, count_before, "Should have 1 iron-chest before building")

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {92, 92},
            force = player.force
        }

        player.selected = ghost
        GhostBuilder.on_selected_entity_changed(player)

        assert.is_false(ghost.valid, "Ghost should be built normally")
        assert.is_true(surface.find_entity("iron-chest", {92.5, 92.5}) ~= nil, "Chest should exist")

        local count_after = player.get_main_inventory().get_item_count("iron-chest")
        assert.equals(0, count_after, "Item should be consumed")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)
end
