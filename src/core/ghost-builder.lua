-- src/core/ghost-builder.lua
-- Core module for AutoGhostBuilder logic
-- Handles ghost detection, item checking, and automatic building

local GhostBuilder = {}

-- State table accessible for testing
-- Modes: "disabled", "hover", "click"
GhostBuilder.state = {
    mode = {}, -- player_index -> string (mode)
    feedback_mode = {}, -- player_index -> "active" or "muted"
    feedback_count = {} -- player_index -> number (for testing feedback spam)
}

--- Get the current mode for a player
---@param player_index number
---@return string mode "disabled", "hover", or "click"
function GhostBuilder.get_mode(player_index)
    return GhostBuilder.state.mode[player_index] or "disabled"
end

--- Check if ghost builder is enabled for a player (any mode except disabled)
---@param player_index number
---@return boolean
function GhostBuilder.is_enabled(player_index)
    local mode = GhostBuilder.get_mode(player_index)
    return mode == "hover" or mode == "click"
end

--- Cycle through modes: disabled -> hover -> click -> disabled
---@param player_index number
---@return string new_mode The new mode
function GhostBuilder.toggle(player_index)
    local current_mode = GhostBuilder.get_mode(player_index)
    local new_mode

    if current_mode == "disabled" then
        new_mode = "hover"
    elseif current_mode == "hover" then
        new_mode = "click"
    else -- "click"
        new_mode = "disabled"
    end

    GhostBuilder.state.mode[player_index] = new_mode
    return new_mode
end

--- Set the mode for a player
---@param player_index number
---@param mode string "disabled", "hover", or "click"
function GhostBuilder.set_mode(player_index, mode)
    GhostBuilder.state.mode[player_index] = mode
end

--- Set feedback mode for a player
---@param player_index number
---@param mode string "active" or "muted"
function GhostBuilder.set_feedback_mode(player_index, mode)
    GhostBuilder.state.feedback_mode[player_index] = mode
end

--- Get feedback mode for a player (defaults to "active")
---@param player_index number
---@return string mode "active" or "muted"
function GhostBuilder.get_feedback_mode(player_index)
    return GhostBuilder.state.feedback_mode[player_index] or "active"
end

--- Legacy compatibility: set enabled state (maps to hover/disabled)
---@param player_index number
---@param enabled boolean
function GhostBuilder.set_enabled(player_index, enabled)
    GhostBuilder.set_mode(player_index, enabled and "hover" or "disabled")
end

--- Find an item source (cursor or inventory) that has the required item with quality
---@param item_name string The item name to find
---@param quality any The quality to match
---@param cursor_stack LuaItemStack|nil The player's cursor stack
---@param inventory LuaInventory|nil The player's main inventory
---@return string|nil source "cursor" or "inventory" or nil if not found
function GhostBuilder.find_item_source(item_name, quality, cursor_stack, inventory)
    if cursor_stack and cursor_stack.valid_for_read then
        -- Never consume items with tags (contain metadata like factory contents)
        local has_tags = cursor_stack.is_item_with_tags
        if not has_tags and cursor_stack.name == item_name and cursor_stack.quality == quality then
            return "cursor"
        end
    end

    if inventory then
        for i = 1, #inventory do
            local stack = inventory[i]
            if stack and stack.valid_for_read then
                local has_tags = stack.is_item_with_tags
                if not has_tags and stack.name == item_name and stack.quality == quality then
                    return "inventory"
                end
            end
        end
    end

    return nil
end

--- Check if all required items are available (entity + modules from upgrade planner)
---@param ghost_entity LuaEntity The ghost entity
---@param player LuaPlayer The player
---@return boolean all_available True if all items are available
---@return table|nil missing_items List of missing items {name, count, quality}
---@return table|nil required_items List of all required items
function GhostBuilder.check_all_items_available(ghost_entity, player)
    local inventory = player.get_inventory(defines.inventory.character_main)
    local cursor_stack = player.cursor_stack
    local required_items = {}
    local missing_items = {}

    -- 1. Check entity item (the ghost itself)
    local ghost_prototype = ghost_entity.ghost_prototype
    if ghost_prototype then
        local item_list = ghost_prototype.items_to_place_this
        for _, item in pairs(item_list) do
            local source = GhostBuilder.find_item_source(
                item.name,
                ghost_entity.quality,
                cursor_stack,
                inventory
            )
            table.insert(required_items, {
                name = item.name,
                quality = ghost_entity.quality,
                count = 1,
                source = source,
                is_module = false
            })
            if not source then
                table.insert(missing_items, {
                    name = item.name,
                    quality = ghost_entity.quality,
                    count = 1
                })
            end
        end
    end

    -- Check module requests
    local item_requests = ghost_entity.item_requests
    if item_requests then
        for _, item_request in pairs(item_requests) do
            local item_name = item_request.name
            local count = item_request.count
            local item_quality = item_request.quality or ghost_entity.quality

            -- Normalize quality to LuaQualityPrototype for comparison
            if type(item_quality) == "string" then
                item_quality = prototypes.quality[item_quality]
            end

            local available_count = 0

            if cursor_stack and cursor_stack.valid_for_read then
                if not cursor_stack.is_item_with_tags and
                   cursor_stack.name == item_name and
                   cursor_stack.quality == item_quality then
                    available_count = available_count + cursor_stack.count
                end
            end

            if inventory then
                for i = 1, #inventory do
                    local stack = inventory[i]
                    if stack and stack.valid_for_read then
                        if not stack.is_item_with_tags and
                           stack.name == item_name and
                           stack.quality == item_quality then
                            available_count = available_count + stack.count
                        end
                    end
                end
            end

            table.insert(required_items, {
                name = item_name,
                quality = item_quality,
                count = count,
                available = available_count,
                is_module = true
            })

            if available_count < count then
                table.insert(missing_items, {
                    name = item_name,
                    quality = item_quality,
                    count = count - available_count
                })
            end
        end
    end

    local all_available = #missing_items == 0
    return all_available, (#missing_items > 0 and missing_items or nil), required_items
end

--- Check if a ghost can be built by the player
---@param ghost_entity LuaEntity The ghost entity to check
---@param player LuaPlayer The player attempting to build
---@return boolean can_build Whether the ghost can be built
---@return table|nil item_info Table with {required_items, missing_items} or nil
function GhostBuilder.can_build_ghost(ghost_entity, player)
    -- Validate ghost entity
    if not ghost_entity or ghost_entity.name ~= "entity-ghost" then
        return false, nil
    end

    local ghost_prototype = ghost_entity.ghost_prototype
    if not ghost_prototype then
        return false, nil
    end

    -- Note: We skip player.can_place_entity() check because the ghost itself
    -- blocks placement. The revive() method handles placement validation internally.

    -- Check for ALL required items (entity + modules from upgrade planner)
    local all_available, missing_items, required_items = GhostBuilder.check_all_items_available(ghost_entity, player)

    if all_available then
        return true, {
            required_items = required_items,
            missing_items = nil
        }
    else
        return false, {
            required_items = required_items,
            missing_items = missing_items
        }
    end
end

--- Helper to remove items from player inventory (avoiding tagged items)
---@param player LuaPlayer The player
---@param item_name string Item name to remove
---@param quality any Quality of the item
---@param count number Number of items to remove
---@return boolean success Whether all items were removed
local function remove_items_from_player(player, item_name, quality, count)
    local inventory = player.get_inventory(defines.inventory.character_main)
    local cursor_stack = player.cursor_stack
    local remaining = count

    -- Try cursor first
    if cursor_stack and cursor_stack.valid_for_read then
        if not cursor_stack.is_item_with_tags and
           cursor_stack.name == item_name and
           cursor_stack.quality == quality then
            local to_remove = math.min(remaining, cursor_stack.count)
            cursor_stack.count = cursor_stack.count - to_remove
            remaining = remaining - to_remove
        end
    end

    -- Then inventory
    if remaining > 0 and inventory then
        for i = 1, #inventory do
            local stack = inventory[i]
            if stack and stack.valid_for_read then
                if not stack.is_item_with_tags and
                   stack.name == item_name and
                   stack.quality == quality then
                    local to_remove = math.min(remaining, stack.count)
                    stack.count = stack.count - to_remove
                    remaining = remaining - to_remove
                    if remaining == 0 then
                        break
                    end
                end
            end
        end
    end

    return remaining == 0
end

--- Try to build a ghost entity for a player
---@param player LuaPlayer The player building the ghost
---@param ghost_entity LuaEntity The ghost entity to build
---@return boolean success Whether the ghost was built successfully
function GhostBuilder.try_build_ghost(player, ghost_entity)
    local can_build, item_info = GhostBuilder.can_build_ghost(ghost_entity, player)

    if not can_build and item_info and item_info.missing_items then
        local missing_list = {}
        for _, item in ipairs(item_info.missing_items) do
            local quality_name = "normal"
            if item.quality then
                if type(item.quality) == "string" then
                    quality_name = item.quality
                elseif item.quality.name then
                    quality_name = item.quality.name
                end
            end
            table.insert(missing_list, item.count .. "x " .. item.name .. " (" .. quality_name .. ")")
        end

        GhostBuilder.state.feedback_count[player.index] = (GhostBuilder.state.feedback_count[player.index] or 0) + 1
        player.create_local_flying_text({
            text = {"autoghostbuilder.messages.missing-multiple-items", table.concat(missing_list, ", ")},
            position = player.position,
            color = { r = 1, g = 0.5, b = 0 },
            time_to_live = 600
        })
        return false
    end

    if not can_build or not item_info then
        return false
    end

    -- Remove ALL required items (entity + modules)
    local items_removed = {}
    for _, required in ipairs(item_info.required_items) do
        local success = remove_items_from_player(player, required.name, required.quality, required.count)
        if success then
            table.insert(items_removed, required)
        else
            -- Failed to remove - return everything we already took
            for _, returned in ipairs(items_removed) do
                player.insert({ name = returned.name, count = returned.count, quality = returned.quality })
            end
            player.create_local_flying_text({
                text = {"autoghostbuilder.messages.build-failed"},
                position = player.position,
                color = { r = 1, g = 0, b = 0 },
                time_to_live = 600
            })
            return false
        end
    end

    -- Use raise_revive = false since this is automatic building
    local revived, entity, revive_result = ghost_entity.revive({ raise_revive = false })

    if not revived then
        -- Return ALL items if reviving failed
        for _, returned in ipairs(items_removed) do
            player.insert({ name = returned.name, count = returned.count, quality = returned.quality })
        end
        player.create_local_flying_text({
            text = {"autoghostbuilder.messages.build-failed"},
            position = player.position,
            color = { r = 1, g = 0, b = 0 },
            time_to_live = 600
        })
        return false
    end

    -- Insert modules into the constructed entity
    if entity and entity.valid then
        for _, item in ipairs(items_removed) do
            -- Only insert items marked as modules
            if item.is_module then
                local inserted = entity.insert({ name = item.name, count = item.count, quality = item.quality })
                if inserted < item.count then
                    -- Failed to insert all modules, return the remaining
                    local remaining = item.count - inserted
                    player.insert({ name = item.name, count = remaining, quality = item.quality })
                end
            end
        end

        -- Remove item-request-proxy if it exists (created automatically by revive)
        local proxies = entity.surface.find_entities_filtered{
            name = "item-request-proxy",
            position = entity.position,
            force = entity.force
        }
        for _, proxy in pairs(proxies) do
            if proxy.proxy_target == entity then
                proxy.destroy()
            end
        end
    end

    return true
end

--- Handle toggle event for a player (includes UI feedback)
---@param player LuaPlayer The player toggling
function GhostBuilder.on_toggle(player)
    if not player then return end

    local new_mode = GhostBuilder.toggle(player.index)

    -- Update shortcut button state (enabled for hover and click modes)
    local is_active = (new_mode ~= "disabled")
    player.set_shortcut_toggled("ghost-builder-toggle", is_active)

    -- Provide feedback with localized messages
    if new_mode == "hover" then
        player.print({"autoghostbuilder.messages.mode-hover"})
    elseif new_mode == "click" then
        player.print({"autoghostbuilder.messages.mode-click"})
    else
        player.print({"autoghostbuilder.messages.disabled"})
    end
end

--- Handle build click event (for click mode)
---@param player LuaPlayer The player who clicked to build
function GhostBuilder.on_build_click(player)
    if not player then return end

    local mode = GhostBuilder.get_mode(player.index)

    -- Only process in click mode
    if mode ~= "click" then return end

    -- Check if hovering over a ghost
    local hovered_entity = player.selected
    if hovered_entity and hovered_entity.name == "entity-ghost" then
        GhostBuilder.try_build_ghost(player, hovered_entity)
    end
end

--- Handle selected entity changed event
---@param player LuaPlayer The player whose selection changed
function GhostBuilder.on_selected_entity_changed(player)
    if not player then return end

    -- Initialize state from shortcut if not set
    if GhostBuilder.state.mode[player.index] == nil then
        local is_toggled = player.is_shortcut_toggled("ghost-builder-toggle")
        GhostBuilder.state.mode[player.index] = is_toggled and "hover" or "disabled"
    end

    local mode = GhostBuilder.get_mode(player.index)

    -- Only process in hover mode (click mode is handled by build event)
    if mode ~= "hover" then return end

    -- Check if hovering over a ghost
    local hovered_entity = player.selected
    if hovered_entity and hovered_entity.name == "entity-ghost" then
        GhostBuilder.try_build_ghost(player, hovered_entity)
    end
end

--- Reset state (useful for testing)
function GhostBuilder.reset_state()
    GhostBuilder.state.mode = {}
    GhostBuilder.state.feedback_mode = {}
    GhostBuilder.state.feedback_count = {}
end

return GhostBuilder
