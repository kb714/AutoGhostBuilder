-- src/tests/mod-compatibility.lua
-- Tests for compatibility with other mods via script_raised_revive event

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
    run_test("CONTROL: revive with raise_revive=false does NOT raise event", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{-5, -5}, {0, 0}}
        clear_area(surface, area)

        local event_raised = false

        script.on_event(defines.events.script_raised_revive, function(event)
            event_raised = true
        end)

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {-2, -2},
            force = player.force
        }

        -- Manually call revive with raise_revive = false (like the bug)
        ghost.revive({ raise_revive = false })

        script.on_event(defines.events.script_raised_revive, nil)

        assert.is_false(event_raised, "Event should NOT be raised when raise_revive=false")

        clear_area(surface, area)
    end)

    reset()
    run_test("CONTROL: revive with raise_revive=true DOES raise event", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{-5, -5}, {0, 0}}
        clear_area(surface, area)

        local event_raised = false

        script.on_event(defines.events.script_raised_revive, function(event)
            event_raised = true
        end)

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {-2, -2},
            force = player.force
        }

        -- Manually call revive with raise_revive = true (the fix)
        ghost.revive({ raise_revive = true })

        script.on_event(defines.events.script_raised_revive, nil)

        assert.is_true(event_raised, "Event SHOULD be raised when raise_revive=true")

        clear_area(surface, area)
    end)

    reset()
    run_test("script_raised_revive event is raised when ghost is built", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{0, 0}, {5, 5}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()
        player.insert{name = "iron-chest", count = 1}

        -- Track if event was raised
        local event_raised = false
        local revived_entity = nil
        local event_data = nil

        local handler_id = script.on_event(defines.events.script_raised_revive, function(event)
            event_raised = true
            revived_entity = event.entity
            event_data = event
        end)

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {2, 2},
            force = player.force
        }

        player.selected = ghost
        GhostBuilder.on_selected_entity_changed(player)

        -- Clean up handler
        script.on_event(defines.events.script_raised_revive, nil)

        assert.is_true(event_raised, "script_raised_revive event should be raised")
        assert.is_true(revived_entity ~= nil and revived_entity.valid, "Revived entity should be valid")
        assert.equals("iron-chest", revived_entity.name, "Revived entity should be iron-chest")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)

    reset()
    run_test("script_raised_revive includes correct entity data", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{10, 10}, {15, 15}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()
        player.insert{name = "assembling-machine-1", count = 1}

        local event_entity = nil
        local event_position = nil

        script.on_event(defines.events.script_raised_revive, function(event)
            event_entity = event.entity
            if event.entity and event.entity.valid then
                event_position = event.entity.position
            end
        end)

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "assembling-machine-1",
            position = {12, 12},
            force = player.force
        }

        player.selected = ghost
        GhostBuilder.on_selected_entity_changed(player)

        script.on_event(defines.events.script_raised_revive, nil)

        assert.is_true(event_entity ~= nil, "Event should include entity")
        assert.equals("assembling-machine-1", event_entity.name, "Event entity should be correct type")
        assert.is_true(event_position ~= nil, "Event entity should have position")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)

    reset()
    run_test("Event simulation: external mod can track built entities", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{20, 20}, {25, 25}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()
        player.insert{name = "electric-mining-drill", count = 1}

        -- Simulate an external mod tracking entities (like Project Cybersyn)
        local tracked_entities = {}

        script.on_event(defines.events.script_raised_revive, function(event)
            if event.entity and event.entity.valid then
                table.insert(tracked_entities, {
                    name = event.entity.name,
                    position = event.entity.position,
                    unit_number = event.entity.unit_number
                })
            end
        end)

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "electric-mining-drill",
            position = {22, 22},
            force = player.force
        }

        player.selected = ghost
        GhostBuilder.on_selected_entity_changed(player)

        script.on_event(defines.events.script_raised_revive, nil)

        assert.equals(1, #tracked_entities, "External mod should have tracked the built entity")
        assert.equals("electric-mining-drill", tracked_entities[1].name, "Tracked entity should be the mining drill")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)
end
