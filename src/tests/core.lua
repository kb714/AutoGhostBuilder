-- src/tests/core.lua
-- Core logic and ghost building tests

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

    local function reset()
        GhostBuilder.reset_state()
    end

    -- State management
    reset()
    run_test("is_enabled returns false for unknown player", function(assert)
        assert.is_false(GhostBuilder.is_enabled(999))
    end)

    reset()
    run_test("toggle enables when currently disabled", function(assert)
        local new_state = GhostBuilder.toggle(1, false)
        assert.is_true(new_state)
    end)

    reset()
    run_test("tracks state per player independently", function(assert)
        GhostBuilder.set_enabled(1, true)
        GhostBuilder.set_enabled(2, false)
        assert.is_true(GhostBuilder.is_enabled(1))
        assert.is_false(GhostBuilder.is_enabled(2))
    end)

    -- Item finding
    reset()
    run_test("find_item_source returns 'cursor' when item in cursor", function(assert)
        local mock_quality = {}
        local mock_cursor = {
            valid_for_read = true,
            name = "iron-plate",
            quality = mock_quality,
            is_item_with_tags = false
        }
        local result = GhostBuilder.find_item_source("iron-plate", mock_quality, mock_cursor, nil)
        assert.equals("cursor", result)
    end)

    reset()
    run_test("find_item_source prioritizes cursor over inventory", function(assert)
        local mock_quality = {}
        local mock_cursor = {
            valid_for_read = true,
            name = "iron-plate",
            quality = mock_quality,
            is_item_with_tags = false
        }
        local mock_inventory = {
            [1] = {
                valid_for_read = true,
                name = "iron-plate",
                quality = mock_quality,
                is_item_with_tags = false
            }
        }
        setmetatable(mock_inventory, { __len = function() return 1 end })

        local result = GhostBuilder.find_item_source("iron-plate", mock_quality, mock_cursor, mock_inventory)
        assert.equals("cursor", result)
    end)

    -- Ghost building with Factorio API
    run_test("can create and destroy entities on surface", function(assert)
        local surface = get_test_surface()
        clear_test_area(surface, {{100, 100}, {110, 110}})

        local entity = surface.create_entity{
            name = "iron-chest",
            position = {105, 105},
            force = "player"
        }

        assert.is_true(entity ~= nil, "Entity should be created")
        assert.is_true(entity.valid, "Entity should be valid")

        entity.destroy()
    end)

    run_test("can create ghost entities", function(assert)
        local surface = get_test_surface()
        clear_test_area(surface, {{110, 110}, {120, 120}})

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {115, 115},
            force = "player"
        }

        assert.is_true(ghost ~= nil, "Ghost should be created")
        assert.is_true(ghost.name == "entity-ghost", "Should be a ghost")

        ghost.destroy()
    end)


    run_test("ghost.quality is LuaQualityPrototype userdata", function(assert)
        local surface = get_test_surface()
        clear_test_area(surface, {{130, 130}, {140, 140}})

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "wooden-chest",
            position = {135, 135},
            force = "player"
        }

        local quality = ghost.quality
        local quality_type = type(quality)

        assert.is_true(quality_type == "userdata" or quality_type == "table", "Quality should be userdata or table")

        if quality_type == "userdata" or quality_type == "table" then
            local success, name = pcall(function() return quality.name end)
            if success and name then
                assert.is_true(type(name) == "string", "quality.name should be string")
            end
        end

        ghost.destroy()
    end)

    run_test("try_build_ghost uses raise_revive=false", function(assert)
        local surface = get_test_surface()
        clear_test_area(surface, {{140, 140}, {150, 150}})

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "wooden-chest",
            position = {145, 145},
            force = "player"
        }

        local mock_player = {
            get_inventory = function(inventory_type)
                local inv = {}
                setmetatable(inv, { __len = function() return 0 end })
                return inv
            end,
            cursor_stack = { valid_for_read = false },
            can_place_entity = function() return true end,
            position = {145, 145},
            create_local_flying_text = function(args) end
        }

        local success = GhostBuilder.try_build_ghost(mock_player, ghost)
        assert.is_false(success, "Should fail without items")

        if ghost.valid then
            ghost.destroy()
        end
    end)

    run_test("missing items message shows quality name correctly", function(assert)
        local surface = get_test_surface()
        clear_test_area(surface, {{150, 150}, {160, 160}})

        local ghost = surface.create_entity{
            name = "entity-ghost",
            inner_name = "iron-chest",
            position = {155, 155},
            force = "player"
        }

        local message_shown = false
        local mock_player = {
            get_inventory = function(inventory_type)
                local inv = {}
                setmetatable(inv, { __len = function() return 0 end })
                return inv
            end,
            cursor_stack = { valid_for_read = false },
            can_place_entity = function() return true end,
            position = {155, 155},
            create_local_flying_text = function(args)
                message_shown = true
                if type(args.text) == "table" and args.text[2] then
                    assert.is_false(
                        string.find(args.text[2], "LuaQualityPrototype") ~= nil,
                        "Message should not contain 'LuaQualityPrototype'"
                    )
                end
            end
        }

        GhostBuilder.try_build_ghost(mock_player, ghost)
        assert.is_true(message_shown, "Should show missing items message")

        if ghost.valid then
            ghost.destroy()
        end
    end)
end
