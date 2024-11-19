local menu = require("menu")
local maidenmain = require("data.maidenmain")

local menu_renderer = {}

local function safe_render(menu_item, label, description, value)
    if type(value) == "boolean" then
        value = value and 1 or 0
    elseif type(value) ~= "number" then
        value = 0
    end
    menu_item:render(label, description, value)
end

function menu_renderer.render_menu(
    plugin_enabled, 
    doorsEnabled, 
    loopEnabled, 
    revive_enabled, 
    profane_mindcage_enabled, 
    profane_mindcage_count, 
    moveThreshold,
    -- Parâmetros do Vendor Manager (removido prefixo vm_)
    vendor_enabled,
    during_helltide,
    end_helltide,
    repair,
    sell,
    salvage,
    stash,
    stash_boss,
    auto_move,
    items_threshold,
    greater_affix_threshold
)
    if menu.main_tree:push("HellChest Farmer (EletroLuz)-V2.2") then
        -- Seção principal existente
        safe_render(menu.plugin_enabled, "Enable Plugin Chests Farm", "Enable or disable the chest farm plugin", plugin_enabled)
        safe_render(menu.main_openDoors_enabled, "Open Chests", "Enable or disable the chest plugin", doorsEnabled)
        safe_render(menu.loop_enabled, "Enable Loop", "Enable or disable looping waypoints", loopEnabled)
        safe_render(menu.revive_enabled, "Enable Revive Module", "Enable or disable the revive module", revive_enabled)

        -- Seção Profane Mindcage existente
        if menu.profane_mindcage_tree:push("Profane Mindcage Settings") then
            safe_render(menu.profane_mindcage_toggle, "Enable Profane Mindcage Auto Use", "Enable or disable automatic use of Profane Mindcage", profane_mindcage_enabled)
            safe_render(menu.profane_mindcage_slider, "Profane Mindcage Count", "Number of Profane Mindcages to use", profane_mindcage_count)
            menu.profane_mindcage_tree:pop()
        end

        -- Seção Move Threshold existente
        if menu.move_threshold_tree:push("Chest Move Range Settings") then
            safe_render(menu.move_threshold_slider, "Move Range", "maximum distance the player can detect and move towards a chest in the game", moveThreshold)
            menu.move_threshold_tree:pop()
        end

        -- Nova seção Vendor Manager
        if menu.vendor_manager_tree:push("Vendor Manager") then
            safe_render(menu.vendor_enabled, "Enable Vendor Manager", "Enable or disable the vendor manager", vendor_enabled)
            safe_render(menu.enable_during_helltide, "Enable During Helltide", "Automatically manage vendors while Helltide is active", during_helltide)
            safe_render(menu.enable_end_helltide, "Enable End Helltide", "Automatically manage vendors when Helltide ends", end_helltide)

            if menu.actions_tree:push("Automatic Actions") then
                safe_render(menu.auto_repair, "Auto Repair", "Automatically repair items when visiting vendor", repair)
                safe_render(menu.auto_sell, "Auto Sell", "Automatically sell items when visiting vendor", sell)
                safe_render(menu.auto_salvage, "Auto Salvage", "Automatically salvage items at blacksmith", salvage)
                safe_render(menu.auto_stash, "Auto Stash", "Automatically stash items with Greater Affixes >= threshold", stash)
                safe_render(menu.auto_stash_boss_materials, "Auto Stash Boss Materials", "Automatically stash boss materials when stack reaches 50", stash_boss)
                menu.actions_tree:pop()
            end

            if menu.settings_tree:push("Settings") then
                safe_render(menu.auto_move, "Auto Move to Vendor", "Automatically move to nearest vendor", auto_move)
                safe_render(menu.items_threshold, "Items Threshold (1-33)", "Number of items before selling/salvaging", items_threshold)
                safe_render(menu.greater_affix_threshold, "Greater Affix Threshold (0-4)", "0=Sell all, 1+=Keep items with X or more Greater Affixes", greater_affix_threshold)
                menu.settings_tree:pop()
            end

            menu.vendor_manager_tree:pop()
        end

        -- Seção Helltide Maiden existente
        if menu.main_tree:push("Helltide Maiden") then
            maidenmain.render_menu()
            menu.main_tree:pop()
        end

        menu.main_tree:pop()
    end
end

return menu_renderer