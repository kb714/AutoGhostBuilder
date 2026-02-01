-- src/tests/core.lua
-- Core logic tests

local GhostBuilder = require("src.core.ghost-builder")

return function(run_test)
    local function reset()
        GhostBuilder.reset_state()
    end

    -- State management
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
        local mode1 = GhostBuilder.toggle(1)
        assert.equals(mode1, "hover")
        local mode2 = GhostBuilder.toggle(1)
        assert.equals(mode2, "click")
        local mode3 = GhostBuilder.toggle(1)
        assert.equals(mode3, "disabled")
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
    run_test("set_enabled backward compatibility - true sets hover", function(assert)
        GhostBuilder.set_enabled(1, true)
        assert.equals(GhostBuilder.get_mode(1), "hover")
    end)

    reset()
    run_test("set_enabled backward compatibility - false sets disabled", function(assert)
        GhostBuilder.set_enabled(1, false)
        assert.equals(GhostBuilder.get_mode(1), "disabled")
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
