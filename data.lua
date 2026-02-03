-- data.lua

data:extend{
    -- Test item for automated testing of item-with-tags protection
    {
        type = "item-with-tags",
        name = "agb-test-tagged-item",
        icon = "__base__/graphics/icons/iron-chest.png",
        icon_size = 64,
        subgroup = "other",
        order = "z[test]",
        stack_size = 1,
        flags = {"not-stackable", "only-in-cursor"},
        hidden = true,
    },
    {
        type = "custom-input",
        name = "ghost-builder-toggle",
        key_sequence = "CONTROL + G",
        consuming = "none",
    },
    {
        type = "custom-input",
        name = "ghost-builder-on-build-click",
        key_sequence = "",
        linked_game_control = "build",
        consuming = "none",
    },
    {
        type = "shortcut",
        name = "ghost-builder-toggle",
        order = "a[ghost]-b[builder]",
        action = "lua",
        toggleable = true,
        localised_name = {"autoghostbuilder.gui.toggle-button"},
        associated_control_input = "ghost-builder-toggle",
        icons = {
            {
                icon = "__AutoGhostBuilder__/graphics/ghost-a.png",
                icon_size = 32,
                scale = 1,
            },
        },
        small_icons = {
            {
                icon = "__AutoGhostBuilder__/graphics/ghost-a-24.png",
                icon_size = 24,
                scale = 1,
            },
        },
        disabled_icons = {
            {
                icon = "__AutoGhostBuilder__/graphics/ghost-b.png",
                icon_size = 32,
                scale = 1,
            },
        },
        disabled_small_icons = {
            {
                icon = "__AutoGhostBuilder__/graphics/ghost-b-24.png",
                icon_size = 24,
                scale = 1,
            },
        },
    }
}