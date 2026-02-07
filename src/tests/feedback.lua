-- src/tests/feedback.lua
-- Tests for feedback message behavior (spam prevention)

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

    local function create_belt_ghosts(surface, force, start_x, y, count)
        local ghosts = {}
        for i = 0, count - 1 do
            local ghost = surface.create_entity{
                name = "entity-ghost",
                inner_name = "transport-belt",
                position = {start_x + (i * 2), y},
                force = force
            }
            table.insert(ghosts, ghost)
        end
        return ghosts
    end

    -- These tests use player.selected assignment which triggers the real
    -- on_selected_entity_changed event handler, testing the actual code path.

    reset()
    run_test("Shows feedback once when hovering ghost without items", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{50, 50}, {55, 55}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "transport-belt",
            position = {52, 52},
            force = player.force
        }

        GhostBuilder.state.feedback_count[1] = 0
        player.selected = ghost

        assert.is_true(ghost.valid, "Ghost should remain (no items)")
        assert.equals(1, GhostBuilder.state.feedback_count[1], "Should show feedback once")

        clear_area(surface, area)
    end)

    reset()
    run_test("Duplicate feedback is suppressed when hovering multiple ghosts with same missing items", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{60, 60}, {80, 65}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()

        local ghosts = create_belt_ghosts(surface, player.force, 62, 62, 5)

        GhostBuilder.state.feedback_count[1] = 0
        for _, ghost in ipairs(ghosts) do
            player.selected = ghost
        end

        -- Desired behavior: only 1 feedback for identical missing items
        assert.equals(1, GhostBuilder.state.feedback_count[1],
            "Should suppress duplicate feedback for same missing items")

        for _, ghost in ipairs(ghosts) do
            assert.is_true(ghost.valid, "Ghost should remain")
        end

        clear_area(surface, area)
    end)

    reset()
    run_test("Feedback resets when missing item type changes", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{60, 70}, {80, 80}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()

        local belt_ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "transport-belt",
            position = {62, 72},
            force = player.force
        }
        local chest_ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {66, 72},
            force = player.force
        }

        GhostBuilder.state.feedback_count[1] = 0

        player.selected = belt_ghost
        assert.equals(1, GhostBuilder.state.feedback_count[1],
            "First item type shows feedback")

        player.selected = chest_ghost
        assert.equals(2, GhostBuilder.state.feedback_count[1],
            "Different item type resets suppression and shows feedback")

        clear_area(surface, area)
    end)

    reset()
    run_test("No feedback when items are available and ghosts are built", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{80, 80}, {100, 85}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()
        player.insert{name = "transport-belt", count = 5}

        local ghosts = create_belt_ghosts(surface, player.force, 82, 82, 5)

        GhostBuilder.state.feedback_count[1] = 0
        for _, ghost in ipairs(ghosts) do
            player.selected = ghost
        end

        assert.equals(0, GhostBuilder.state.feedback_count[1],
            "No feedback when building succeeds")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)

    reset()
    run_test("Only one feedback when items run out mid-hover", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{100, 100}, {120, 105}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()
        player.insert{name = "transport-belt", count = 2}

        local ghosts = create_belt_ghosts(surface, player.force, 102, 102, 5)

        GhostBuilder.state.feedback_count[1] = 0
        for _, ghost in ipairs(ghosts) do
            player.selected = ghost
        end

        -- First 2 build ok, then 3 ghosts missing same item → only 1 feedback
        assert.equals(1, GhostBuilder.state.feedback_count[1],
            "Should suppress duplicate feedback after items run out")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)

    reset()
    run_test("Feedback muted setting suppresses all missing item messages", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{120, 120}, {130, 125}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        GhostBuilder.set_feedback_mode(1, "muted")
        player.clear_cursor()
        player.get_main_inventory().clear()

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "transport-belt",
            position = {122, 122},
            force = player.force
        }

        GhostBuilder.state.feedback_count[1] = 0
        player.selected = ghost

        assert.is_true(ghost.valid, "Ghost should remain")
        assert.equals(0, GhostBuilder.state.feedback_count[1],
            "Muted setting should suppress all feedback")

        clear_area(surface, area)
    end)

    reset()
    run_test("Feedback active setting allows messages normally", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{130, 130}, {135, 135}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        GhostBuilder.set_feedback_mode(1, "active")
        player.clear_cursor()
        player.get_main_inventory().clear()

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "transport-belt",
            position = {132, 132},
            force = player.force
        }

        GhostBuilder.state.feedback_count[1] = 0
        player.selected = ghost

        assert.is_true(ghost.valid, "Ghost should remain")
        assert.equals(1, GhostBuilder.state.feedback_count[1],
            "Active setting should show feedback")

        clear_area(surface, area)
    end)
end
