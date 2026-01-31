-- tests/ghost-builder_test.lua
-- Tests for GhostBuilder module

local GhostBuilder = require("scripts.ghost-builder")

-- Helper to reset state between tests
local function setup()
    GhostBuilder.reset_state()
end

-- ============================================================================
-- Tests for toggle() and is_enabled()
-- ============================================================================

describe("GhostBuilder.is_enabled", function()
    before_each(setup)

    it("returns false for unknown player", function()
        assert.is_false(GhostBuilder.is_enabled(1))
    end)

    it("returns true when player is enabled", function()
        GhostBuilder.set_enabled(1, true)
        assert.is_true(GhostBuilder.is_enabled(1))
    end)

    it("returns false when player is disabled", function()
        GhostBuilder.set_enabled(1, false)
        assert.is_false(GhostBuilder.is_enabled(1))
    end)

    it("tracks state per player independently", function()
        GhostBuilder.set_enabled(1, true)
        GhostBuilder.set_enabled(2, false)

        assert.is_true(GhostBuilder.is_enabled(1))
        assert.is_false(GhostBuilder.is_enabled(2))
    end)
end)

describe("GhostBuilder.toggle", function()
    before_each(setup)

    it("enables when currently disabled", function()
        GhostBuilder.set_enabled(1, false)
        local result = GhostBuilder.toggle(1)

        assert.is_true(result)
        assert.is_true(GhostBuilder.is_enabled(1))
    end)

    it("disables when currently enabled", function()
        GhostBuilder.set_enabled(1, true)
        local result = GhostBuilder.toggle(1)

        assert.is_false(result)
        assert.is_false(GhostBuilder.is_enabled(1))
    end)

    it("enables when state is nil (first toggle)", function()
        local result = GhostBuilder.toggle(1)

        assert.is_true(result)
        assert.is_true(GhostBuilder.is_enabled(1))
    end)

    it("uses provided current_value when given", function()
        GhostBuilder.set_enabled(1, false)
        -- Override with explicit value
        local result = GhostBuilder.toggle(1, true)

        assert.is_false(result)
        assert.is_false(GhostBuilder.is_enabled(1))
    end)
end)

describe("GhostBuilder.set_enabled", function()
    before_each(setup)

    it("sets enabled state to true", function()
        GhostBuilder.set_enabled(1, true)
        assert.is_true(GhostBuilder.is_enabled(1))
    end)

    it("sets enabled state to false", function()
        GhostBuilder.set_enabled(1, true)
        GhostBuilder.set_enabled(1, false)
        assert.is_false(GhostBuilder.is_enabled(1))
    end)
end)

-- ============================================================================
-- Tests for find_item_source()
-- ============================================================================

describe("GhostBuilder.find_item_source", function()
    before_each(setup)

    it("returns nil when both cursor and inventory are nil", function()
        local result = GhostBuilder.find_item_source("iron-plate", "normal", nil, nil)
        assert.is_nil(result)
    end)

    it("returns 'cursor' when item is in cursor", function()
        local mock_cursor = {
            valid_for_read = true,
            name = "iron-plate",
            quality = "normal"
        }

        local result = GhostBuilder.find_item_source("iron-plate", "normal", mock_cursor, nil)
        assert.equals("cursor", result)
    end)

    it("returns nil when cursor has different item", function()
        local mock_cursor = {
            valid_for_read = true,
            name = "copper-plate",
            quality = "normal"
        }

        local result = GhostBuilder.find_item_source("iron-plate", "normal", mock_cursor, nil)
        assert.is_nil(result)
    end)

    it("returns nil when cursor has different quality", function()
        local mock_cursor = {
            valid_for_read = true,
            name = "iron-plate",
            quality = "uncommon"
        }

        local result = GhostBuilder.find_item_source("iron-plate", "normal", mock_cursor, nil)
        assert.is_nil(result)
    end)

    it("returns nil when cursor is not valid_for_read", function()
        local mock_cursor = {
            valid_for_read = false,
            name = "iron-plate",
            quality = "normal"
        }

        local result = GhostBuilder.find_item_source("iron-plate", "normal", mock_cursor, nil)
        assert.is_nil(result)
    end)

    it("returns 'inventory' when item is in inventory", function()
        local mock_inventory = {
            get_item_count = function(_, filter)
                if filter.name == "iron-plate" and filter.quality == "normal" then
                    return 5
                end
                return 0
            end
        }

        local result = GhostBuilder.find_item_source("iron-plate", "normal", nil, mock_inventory)
        assert.equals("inventory", result)
    end)

    it("returns nil when inventory has zero count", function()
        local mock_inventory = {
            get_item_count = function()
                return 0
            end
        }

        local result = GhostBuilder.find_item_source("iron-plate", "normal", nil, mock_inventory)
        assert.is_nil(result)
    end)

    it("prioritizes cursor over inventory", function()
        local mock_cursor = {
            valid_for_read = true,
            name = "iron-plate",
            quality = "normal"
        }

        local mock_inventory = {
            get_item_count = function()
                return 10
            end
        }

        local result = GhostBuilder.find_item_source("iron-plate", "normal", mock_cursor, mock_inventory)
        assert.equals("cursor", result)
    end)

    it("falls back to inventory when cursor has wrong item", function()
        local mock_cursor = {
            valid_for_read = true,
            name = "copper-plate",
            quality = "normal"
        }

        local mock_inventory = {
            get_item_count = function(_, filter)
                if filter.name == "iron-plate" then
                    return 5
                end
                return 0
            end
        }

        local result = GhostBuilder.find_item_source("iron-plate", "normal", mock_cursor, mock_inventory)
        assert.equals("inventory", result)
    end)
end)

-- ============================================================================
-- Tests for reset_state()
-- ============================================================================

describe("GhostBuilder.reset_state", function()
    it("clears all enabled states", function()
        GhostBuilder.set_enabled(1, true)
        GhostBuilder.set_enabled(2, true)
        GhostBuilder.set_enabled(3, false)

        GhostBuilder.reset_state()

        assert.is_false(GhostBuilder.is_enabled(1))
        assert.is_false(GhostBuilder.is_enabled(2))
        assert.is_false(GhostBuilder.is_enabled(3))
    end)
end)

-- ============================================================================
-- Integration tests (require Factorio runtime)
-- These tests use real Factorio entities and should be run with factorio-test
-- ============================================================================

describe("GhostBuilder integration", function()
    before_each(setup)

    -- Note: These tests require factorio-test runtime environment
    -- They will be skipped if run outside of Factorio

    it("can_build_ghost returns false for non-ghost entity", function()
        -- This test uses a mock since we can't create real entities easily
        local mock_entity = {
            name = "iron-chest",
            ghost_prototype = nil
        }
        local mock_player = {}

        local can_build, item_info = GhostBuilder.can_build_ghost(mock_entity, mock_player)

        assert.is_false(can_build)
        assert.is_nil(item_info)
    end)

    it("can_build_ghost returns false for nil entity", function()
        local mock_player = {}

        local can_build, item_info = GhostBuilder.can_build_ghost(nil, mock_player)

        assert.is_false(can_build)
        assert.is_nil(item_info)
    end)
end)
