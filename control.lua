-- control.lua
-- Event wiring for AutoGhostBuilder

local GhostBuilder = require("src.core.ghost-builder")

-- Tests are loaded automatically in development (excluded from release builds)
pcall(require, "src.tests.test-harness")

-- Event for handling the shortcut press directly
script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "ghost-builder-toggle" then
        GhostBuilder.on_toggle(game.get_player(event.player_index))
    end
end)

-- Event for handling the custom key input (e.g., CONTROL + G)
script.on_event("ghost-builder-toggle", function(event)
    GhostBuilder.on_toggle(game.get_player(event.player_index))
end)

-- Event for checking and building ghosts
script.on_event(defines.events.on_selected_entity_changed, function(event)
    GhostBuilder.on_selected_entity_changed(game.get_player(event.player_index))
end)

-- Event for click mode - builds when player clicks to build
script.on_event("ghost-builder-on-build-click", function(event)
    GhostBuilder.on_build_click(game.get_player(event.player_index))
end)
