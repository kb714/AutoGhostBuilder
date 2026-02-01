-- src/tests/core.lua
-- Core logic tests

local GhostBuilder = require("src.core.ghost-builder")

return function(run_test)
    local function reset()
        GhostBuilder.reset_state()
    end

    -- State management
    reset()
    run_test("is_enabled returns false for unknown player", function(assert)
        assert.is_false(GhostBuilder.is_enabled(999))
    end)

    reset()
    run_test("toggle cycles enabled state", function(assert)
        local state1 = GhostBuilder.toggle(1, false)
        assert.is_true(state1)
        local state2 = GhostBuilder.toggle(1, state1)
        assert.is_false(state2)
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

    reset()
    run_test("find_item_source ignores items with tags", function(assert)
        local mock_quality = {}
        local mock_cursor = {
            valid_for_read = true,
            name = "iron-chest",
            quality = mock_quality,
            is_item_with_tags = true
        }

        local result = GhostBuilder.find_item_source("iron-chest", mock_quality, mock_cursor, nil)
        assert.is_nil(result)
    end)
end
