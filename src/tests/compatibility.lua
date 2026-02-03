-- src/tests/compatibility.lua

local GhostBuilder = require("src.core.ghost-builder")

return function(run_test)
    local function get_player()
        local player = game.get_player(1)
        if not player then
            error("Player 1 not found in save")
        end
        return player
    end

    run_test("item-with-tags type always has is_item_with_tags true", function(assert)
        local player = get_player()
        player.clear_cursor()
        player.get_main_inventory().clear()

        -- Insert without setting any tags
        player.insert{name = "agb-test-tagged-item", count = 1}
        local inv = player.get_main_inventory()
        local slot = inv.find_item_stack("agb-test-tagged-item")

        log("TEST: Item without manual tags:")
        log("TEST:   is_item_with_tags = " .. tostring(slot.is_item_with_tags))
        log("TEST:   tags = " .. serpent.line(slot.tags))

        -- Items of type item-with-tags ALWAYS have is_item_with_tags = true
        -- This is the prototype type, not whether tags were manually added
        assert.is_true(slot.is_item_with_tags, "item-with-tags type always has is_item_with_tags = true")

        player.get_main_inventory().clear()
    end)

    run_test("find_item_source ignores item-with-tags type", function(assert)
        local player = get_player()
        player.clear_cursor()
        player.get_main_inventory().clear()

        -- Even without manually setting tags, this should be ignored
        local cursor = player.cursor_stack
        cursor.set_stack{name = "agb-test-tagged-item", count = 1}

        local quality = prototypes.quality["normal"]
        local result = GhostBuilder.find_item_source(
            "agb-test-tagged-item",
            quality,
            cursor,
            nil
        )

        assert.is_nil(result, "Should not use item-with-tags type from cursor")

        player.clear_cursor()
    end)

    run_test("find_item_source ignores item-with-tags in inventory", function(assert)
        local player = get_player()
        player.clear_cursor()
        player.get_main_inventory().clear()

        player.insert{name = "agb-test-tagged-item", count = 1}
        local inv = player.get_main_inventory()

        local quality = prototypes.quality["normal"]
        local result = GhostBuilder.find_item_source(
            "agb-test-tagged-item",
            quality,
            nil,
            inv
        )

        assert.is_nil(result, "Should not use item-with-tags type from inventory")

        player.get_main_inventory().clear()
    end)

    run_test("Tags are preserved on item-with-tags", function(assert)
        local player = get_player()
        player.clear_cursor()
        player.get_main_inventory().clear()

        player.insert{name = "agb-test-tagged-item", count = 1}
        local inv = player.get_main_inventory()
        local slot = inv.find_item_stack("agb-test-tagged-item")

        -- Set complex tag data (like Factorissimo factory contents)
        slot.set_tag("factory_contents", {
            machines = 50,
            items = {"iron-plate", "copper-plate"},
            energy = 1000000
        })

        -- Retrieve and verify
        local tag = slot.get_tag("factory_contents")
        assert.is_true(tag ~= nil, "Tag should exist")
        assert.equals(50, tag.machines, "Tag data should be preserved")
        assert.equals(1000000, tag.energy, "Complex tag data should be preserved")

        player.get_main_inventory().clear()
    end)
end
