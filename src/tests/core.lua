-- src/tests/core.lua

local GhostBuilder = require("src.core.ghost-builder")

return function(run_test)
    local function reset()
        GhostBuilder.reset_state()
    end

    local function clear_area(surface, area)
        for _, entity in pairs(surface.find_entities_filtered{area = area}) do
            if entity.valid and entity.name ~= "character" then
                pcall(function() entity.destroy() end)
            end
        end
    end

    local function get_player()
        local player = game.get_player(1)
        if not player then
            error("Player 1 not found in save")
        end
        return player
    end

    reset()
    run_test("get_mode returns disabled for unknown player", function(assert)
        assert.equals(GhostBuilder.get_mode(999), "disabled")
    end)

    reset()
    run_test("is_enabled returns false for disabled mode", function(assert)
        GhostBuilder.set_mode(1, "disabled")
        assert.is_false(GhostBuilder.is_enabled(1))
    end)

    reset()
    run_test("is_enabled returns true for hover mode", function(assert)
        GhostBuilder.set_mode(1, "hover")
        assert.is_true(GhostBuilder.is_enabled(1))
    end)

    reset()
    run_test("is_enabled returns true for click mode", function(assert)
        GhostBuilder.set_mode(1, "click")
        assert.is_true(GhostBuilder.is_enabled(1))
    end)

    reset()
    run_test("toggle cycles through modes correctly", function(assert)
        GhostBuilder.set_mode(1, "disabled")
        assert.equals(GhostBuilder.toggle(1), "hover")
        assert.equals(GhostBuilder.toggle(1), "click")
        assert.equals(GhostBuilder.toggle(1), "disabled")
    end)

    reset()
    run_test("tracks state per player independently", function(assert)
        GhostBuilder.set_mode(1, "hover")
        GhostBuilder.set_mode(2, "click")
        GhostBuilder.set_mode(3, "disabled")
        assert.equals(GhostBuilder.get_mode(1), "hover")
        assert.equals(GhostBuilder.get_mode(2), "click")
        assert.equals(GhostBuilder.get_mode(3), "disabled")
    end)

    reset()
    run_test("Hover mode builds ghost when selected", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{0, 0}, {5, 5}}
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
            position = {2, 2},
            force = player.force
        }

        player.selected = ghost
        GhostBuilder.on_selected_entity_changed(player)

        assert.is_false(ghost.valid, "Ghost should be built and removed")
        assert.is_true(surface.find_entity("iron-chest", {2.5, 2.5}) ~= nil, "Iron chest should exist")

        local count_after = player.get_main_inventory().get_item_count("iron-chest")
        assert.equals(0, count_after, "Item should be consumed from inventory")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)

    reset()
    run_test("Disabled mode does not build ghost", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{10, 10}, {15, 15}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "disabled")
        player.clear_cursor()
        player.get_main_inventory().clear()
        player.insert{name = "iron-chest", count = 1}

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {12, 12},
            force = player.force
        }

        player.selected = ghost
        GhostBuilder.on_selected_entity_changed(player)

        assert.is_true(ghost.valid, "Ghost should not be built in disabled mode")

        local count_after = player.get_main_inventory().get_item_count("iron-chest")
        assert.equals(1, count_after, "Item should NOT be consumed in disabled mode")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)

    reset()
    run_test("Click mode does not build on hover", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{20, 20}, {25, 25}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "click")
        player.clear_cursor()
        player.get_main_inventory().clear()
        player.insert{name = "iron-chest", count = 1}

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {22, 22},
            force = player.force
        }

        player.selected = ghost
        GhostBuilder.on_selected_entity_changed(player)

        assert.is_true(ghost.valid, "Ghost should not be built on hover in click mode")

        local count_after = player.get_main_inventory().get_item_count("iron-chest")
        assert.equals(1, count_after, "Item should NOT be consumed in click mode on hover")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)

    reset()
    run_test("Prioritizes cursor over inventory", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{30, 30}, {35, 35}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()
        player.get_main_inventory().insert{name = "iron-chest", count = 5}
        player.cursor_stack.set_stack{name = "iron-chest", count = 1}

        assert.equals(5, player.get_main_inventory().get_item_count("iron-chest"), "Should have 5 in inventory")
        assert.is_true(player.cursor_stack.valid_for_read, "Should have item in cursor")
        assert.equals(1, player.cursor_stack.count, "Should have 1 in cursor")

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {32, 32},
            force = player.force
        }

        player.selected = ghost
        GhostBuilder.on_selected_entity_changed(player)

        assert.is_false(ghost.valid, "Ghost should be built")
        assert.is_false(player.cursor_stack.valid_for_read, "Cursor item should be consumed first")
        assert.equals(5, player.get_main_inventory().get_item_count("iron-chest"), "Inventory should be untouched")

        clear_area(surface, area)
        player.clear_cursor()
        player.get_main_inventory().clear()
    end)

    reset()
    run_test("Does not build without required items", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{40, 40}, {45, 45}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()

        assert.equals(0, player.get_main_inventory().get_item_count("iron-chest"), "Should have no items")

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {42, 42},
            force = player.force
        }

        player.selected = ghost
        GhostBuilder.on_selected_entity_changed(player)

        assert.is_true(ghost.valid, "Ghost should not be built without items")
        assert.is_nil(surface.find_entity("iron-chest", {42.5, 42.5}), "No entity should be built")

        clear_area(surface, area)
    end)
end
