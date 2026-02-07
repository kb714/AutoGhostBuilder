-- src/tests/feedback.lua
-- Tests for feedback message behavior (spam prevention)

local GhostBuilder = require("src.core.ghost-builder")

return function(run_test)
    local function reset()
        GhostBuilder.reset_state()
        GhostBuilder._tick_override = nil
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

    -- Integration: basic feedback with real ghosts

    reset()
    run_test("Shows feedback when missing items, suppresses duplicates, none on success", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{50, 50}, {80, 55}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()

        local ghosts = create_belt_ghosts(surface, player.force, 52, 52, 5)

        GhostBuilder.state.feedback_count[1] = 0
        for _, ghost in ipairs(ghosts) do
            player.selected = ghost
        end
        assert.equals(1, GhostBuilder.state.feedback_count[1],
            "Should show feedback once, suppress duplicates in same tick")

        clear_area(surface, area)
        player.insert{name = "transport-belt", count = 3}
        local ghosts2 = create_belt_ghosts(surface, player.force, 52, 52, 3)

        GhostBuilder.state.feedback_count[1] = 0
        GhostBuilder.state.last_feedback = {}
        for _, ghost in ipairs(ghosts2) do
            player.selected = ghost
        end
        assert.equals(0, GhostBuilder.state.feedback_count[1],
            "No feedback when building succeeds")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)

    reset()
    run_test("Feedback muted setting suppresses all messages", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{80, 80}, {85, 85}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        GhostBuilder.set_feedback_mode(1, "muted")
        player.clear_cursor()
        player.get_main_inventory().clear()

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "transport-belt",
            position = {82, 82},
            force = player.force
        }

        GhostBuilder.state.feedback_count[1] = 0
        player.selected = ghost

        assert.equals(0, GhostBuilder.state.feedback_count[1],
            "Muted setting should suppress all feedback")

        clear_area(surface, area)
    end)

    -- Time simulation tests using _tick_override

    reset()
    run_test("Continuous hover on same item: suppressed even after 10 seconds total", function(assert)
        GhostBuilder._tick_override = 1000

        -- First hover at tick 1000: shows
        assert.is_true(GhostBuilder.should_show_feedback(1, "belt"), "First hover shows")

        -- Hover every ~1 second for 10 seconds
        -- Each hover is within 3s of the PREVIOUS hover, so must stay suppressed
        for i = 1, 10 do
            GhostBuilder._tick_override = 1000 + (i * 60)
            assert.is_false(GhostBuilder.should_show_feedback(1, "belt"),
                "Hover at +" .. i .. "s should be suppressed")
        end

        -- Total time: 10 seconds since first hover, but last hover was 1s ago
        -- Must still be suppressed
        GhostBuilder._tick_override = 1000 + (10 * 60) + 30
        assert.is_false(GhostBuilder.should_show_feedback(1, "belt"),
            "Must stay suppressed with continuous hover even after 10+ seconds")
    end)

    reset()
    run_test("Feedback reappears after 3 seconds of no hover", function(assert)
        GhostBuilder._tick_override = 1000
        assert.is_true(GhostBuilder.should_show_feedback(1, "belt"), "First hover shows")

        -- 2 seconds later: still suppressed
        GhostBuilder._tick_override = 1120
        assert.is_false(GhostBuilder.should_show_feedback(1, "belt"), "2s later suppressed")

        -- 3+ seconds with NO hover in between: shows again
        GhostBuilder._tick_override = 1120 + 181
        assert.is_true(GhostBuilder.should_show_feedback(1, "belt"),
            "Shows again after 3s of inactivity")
    end)

    reset()
    run_test("Alternating items: each shows once, then both stay suppressed", function(assert)
        GhostBuilder._tick_override = 1000
        assert.is_true(GhostBuilder.should_show_feedback(1, "belt"), "First belt shows")

        GhostBuilder._tick_override = 1030
        assert.is_true(GhostBuilder.should_show_feedback(1, "chest"), "First chest shows")

        -- Go back to belt: should be suppressed (independent timer, 60 ticks < 180)
        GhostBuilder._tick_override = 1060
        assert.is_false(GhostBuilder.should_show_feedback(1, "belt"),
            "Belt suppressed on return")

        -- Go back to chest: should be suppressed (independent timer, 60 ticks < 180)
        GhostBuilder._tick_override = 1090
        assert.is_false(GhostBuilder.should_show_feedback(1, "chest"),
            "Chest suppressed on return")

        -- Keep alternating for 10 seconds
        for i = 1, 10 do
            GhostBuilder._tick_override = 1090 + (i * 60)
            assert.is_false(GhostBuilder.should_show_feedback(1, "belt"),
                "Belt still suppressed at +" .. i .. "s")
            GhostBuilder._tick_override = 1090 + (i * 60) + 30
            assert.is_false(GhostBuilder.should_show_feedback(1, "chest"),
                "Chest still suppressed at +" .. i .. "s")
        end
    end)

    reset()
    run_test("One item expires while other stays suppressed", function(assert)
        GhostBuilder._tick_override = 1000
        assert.is_true(GhostBuilder.should_show_feedback(1, "belt"), "Belt shows")

        GhostBuilder._tick_override = 1030
        assert.is_true(GhostBuilder.should_show_feedback(1, "chest"), "Chest shows")

        -- Keep hovering only chest for 3+ seconds
        GhostBuilder._tick_override = 1090
        assert.is_false(GhostBuilder.should_show_feedback(1, "chest"), "Chest suppressed")
        GhostBuilder._tick_override = 1150
        assert.is_false(GhostBuilder.should_show_feedback(1, "chest"), "Chest suppressed")

        -- Belt hasn't been hovered since tick 1000, now 200 ticks later → expired
        GhostBuilder._tick_override = 1200
        assert.is_true(GhostBuilder.should_show_feedback(1, "belt"),
            "Belt expired after 3s without hover")
        assert.is_false(GhostBuilder.should_show_feedback(1, "chest"),
            "Chest still suppressed (was recently hovered)")
    end)

    reset()
    run_test("Belt -> Splitter -> Belt (different positions): each different item shows once", function(assert)
        local player = get_player()
        local surface = player.surface
        local area = {{100, 50}, {130, 55}}
        clear_area(surface, area)

        GhostBuilder.set_mode(1, "hover")
        player.clear_cursor()
        player.get_main_inventory().clear()

        -- Create belt ghosts at different positions
        local belt1 = surface.create_entity{
            name = "entity-ghost",
            inner_name = "transport-belt",
            position = {102, 52},
            force = player.force
        }
        local splitter = surface.create_entity{
            name = "entity-ghost",
            inner_name = "splitter",
            position = {106, 52},
            force = player.force
        }
        local belt2 = surface.create_entity{
            name = "entity-ghost",
            inner_name = "transport-belt",
            position = {110, 52},
            force = player.force
        }

        GhostBuilder.state.feedback_count[1] = 0

        -- Hover belt1: should show
        player.selected = belt1
        assert.equals(1, GhostBuilder.state.feedback_count[1], "Belt1: feedback shows")

        -- Hover splitter: should show (different item)
        player.selected = splitter
        assert.equals(2, GhostBuilder.state.feedback_count[1], "Splitter: feedback shows")

        -- Hover belt2 (same as belt1 but different position): should be suppressed (same message_key)
        player.selected = belt2
        assert.equals(2, GhostBuilder.state.feedback_count[1], "Belt2: feedback suppressed (same item as belt1)")

        clear_area(surface, area)
        player.get_main_inventory().clear()
    end)
end
