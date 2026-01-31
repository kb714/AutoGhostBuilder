-- scripts/ghost-builder.lua
-- Testeable module for AutoGhostBuilder logic

local GhostBuilder = {}

-- State table accessible for testing
GhostBuilder.state = {
    enabled = {} -- player_index -> boolean
}

--- Check if ghost builder is enabled for a player
---@param player_index number
---@return boolean
function GhostBuilder.is_enabled(player_index)
    return GhostBuilder.state.enabled[player_index] == true
end

--- Toggle ghost builder for a player
---@param player_index number
---@param current_value boolean|nil Optional current value, if nil will read from state
---@return boolean new_state The new enabled state
function GhostBuilder.toggle(player_index, current_value)
    if current_value == nil then
        current_value = GhostBuilder.state.enabled[player_index]
    end
    local new_state = not current_value
    GhostBuilder.state.enabled[player_index] = new_state
    return new_state
end

--- Set the enabled state for a player
---@param player_index number
---@param enabled boolean
function GhostBuilder.set_enabled(player_index, enabled)
    GhostBuilder.state.enabled[player_index] = enabled
end

--- Find an item source (cursor or inventory) that has the required item with quality
---@param item_name string The item name to find
---@param quality any The quality to match
---@param cursor_stack LuaItemStack|nil The player's cursor stack
---@param inventory LuaInventory|nil The player's main inventory
---@return string|nil source "cursor" or "inventory" or nil if not found
function GhostBuilder.find_item_source(item_name, quality, cursor_stack, inventory)
    -- Check cursor first (priority)
    if cursor_stack and cursor_stack.valid_for_read then
        if cursor_stack.name == item_name and cursor_stack.quality == quality then
            return "cursor"
        end
    end

    -- Check inventory
    if inventory then
        local count = inventory.get_item_count({ name = item_name, quality = quality })
        if count > 0 then
            return "inventory"
        end
    end

    return nil
end

--- Check if a ghost can be built by the player
---@param ghost_entity LuaEntity The ghost entity to check
---@param player LuaPlayer The player attempting to build
---@return boolean can_build Whether the ghost can be built
---@return table|nil item_info Table with {name, quality} if can build
function GhostBuilder.can_build_ghost(ghost_entity, player)
    -- Validate ghost entity
    if not ghost_entity or ghost_entity.name ~= "entity-ghost" then
        return false, nil
    end

    local ghost_prototype = ghost_entity.ghost_prototype
    if not ghost_prototype then
        return false, nil
    end

    -- Check if player can place the entity
    if not player.can_place_entity({
        name = ghost_entity.ghost_name,
        position = ghost_entity.position,
        direction = ghost_entity.direction
    }) then
        return false, nil
    end

    -- Check for items
    local item_list = ghost_prototype.items_to_place_this
    local inventory = player.get_inventory(defines.inventory.character_main)
    local cursor_stack = player.cursor_stack

    for _, item in pairs(item_list) do
        local source = GhostBuilder.find_item_source(
            item.name,
            ghost_entity.quality,
            cursor_stack,
            inventory
        )
        if source then
            return true, { name = item.name, quality = ghost_entity.quality, source = source }
        end
    end

    return false, nil
end

--- Try to build a ghost entity for a player
---@param player LuaPlayer The player building the ghost
---@param ghost_entity LuaEntity The ghost entity to build
---@return boolean success Whether the ghost was built successfully
function GhostBuilder.try_build_ghost(player, ghost_entity)
    local can_build, item_info = GhostBuilder.can_build_ghost(ghost_entity, player)
    if not can_build or not item_info then
        return false
    end

    local inventory = player.get_inventory(defines.inventory.character_main)
    local cursor_stack = player.cursor_stack

    -- Remove item from source
    if item_info.source == "cursor" then
        cursor_stack.count = cursor_stack.count - 1
    else
        inventory.remove({ name = item_info.name, count = 1, quality = item_info.quality })
    end

    -- Revive the ghost
    local revived, _ = ghost_entity.revive({ raise_revive = true })

    if not revived then
        -- Return the item if reviving failed
        player.insert({ name = item_info.name, count = 1, quality = item_info.quality })
        player.create_local_flying_text({
            text = "Failed to build, item returned.",
            position = player.position,
            color = { r = 1, g = 0, b = 0 },
            time_to_live = 600
        })
        return false
    end

    return true
end

--- Handle toggle event for a player (includes UI feedback)
---@param player LuaPlayer The player toggling
function GhostBuilder.on_toggle(player)
    if not player then return end

    local new_state = GhostBuilder.toggle(player.index)

    -- Update shortcut button state
    player.set_shortcut_toggled("ghost-builder-toggle", new_state)

    -- Provide feedback
    if new_state then
        player.print("Auto Ghost Builder enabled")
    else
        player.print("Auto Ghost Builder disabled")
    end
end

--- Handle selected entity changed event
---@param player LuaPlayer The player whose selection changed
function GhostBuilder.on_selected_entity_changed(player)
    if not player then return end

    -- Initialize state from shortcut if not set
    if GhostBuilder.state.enabled[player.index] == nil then
        GhostBuilder.state.enabled[player.index] = player.is_shortcut_toggled("ghost-builder-toggle")
    end

    -- Check if enabled
    if not GhostBuilder.is_enabled(player.index) then return end

    -- Check if hovering over a ghost
    local hovered_entity = player.selected
    if hovered_entity and hovered_entity.name == "entity-ghost" then
        GhostBuilder.try_build_ghost(player, hovered_entity)
    end
end

--- Reset state (useful for testing)
function GhostBuilder.reset_state()
    GhostBuilder.state.enabled = {}
end

return GhostBuilder
