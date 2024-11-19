local actors = {}

local permanent_blacklist = {}
local expiration_time = 10 -- Expiration time in seconds for temporarily ignored objects
local movement_timers = {}
local max_movement_time = 15 -- Maximum time in seconds to attempt to move to an object
local initial_gold = 0
local gold_gained = 0

-- Definição dos materiais que queremos monitorar
local materials_gained = {
    living_steel = {sno_id = 1502128, count = 0, display_name = "Total Living Steel"},
    distilled_fear = {sno_id = 1518053, count = 0, display_name = "Total Distilled Fear"},
    exquisite_blood = {sno_id = 1522891, count = 0, display_name = "Total Exquisite Blood"},
    malignant_heart = {sno_id = 1489420, count = 0, display_name = "Total Malignant Heart"},
    compass = {key_pattern = "S05_DungeonSigil_BSK", count = 0, display_name = "Total Infernal Compasses"},
    tributes = {key_pattern = "X1_Undercity_TributeKeySigil", count = 0, display_name = "Total Tributes"}
}

local function format_number(number)
    local formatted = tostring(number)
    local k = formatted:len()
    while k > 3 do
        k = k - 3
        formatted = formatted:sub(1, k) .. "." .. formatted:sub(k + 1)
    end
    
    -- Formatação especial para milhões
    if number >= 1000000 then
        return string.format("%.1fM", number / 1000000)
    end
    
    return formatted
end

-- Armazena o último estado conhecido dos consumíveis
local last_consumable_state = nil

local ignored_objects = {
    "Lilith",
    "QST_Class_Necro_Shrine",
    "LE_Shrine_Goatman_Props_Arrangement_SP",
    "fxKit_seamlessSphere_twoSided2_lilithShrine_idle",
    "LE_Shrine_Zombie_Props_Arrangement_SP",
    "_Shrine_Moss_",
    "g_gold"
}

local actor_types = {
    shrine = {
        pattern = "Shrine_",
        move_threshold = 12,
        interact_threshold = 2.5,
        interact_function = function(obj) 
            interact_object(obj)
        end
    },
    goblin = {
        pattern = "treasure_goblin",
        move_threshold = 20,
        interact_threshold = 2,
        interact_function = function(actor)
            console.print("Interacting with the Goblin")
        end
    },
    harvest_node = {
        pattern = "HarvestNode_Ore",
        move_threshold = 12,
        interact_threshold = 1.0,
        interact_function = function(obj)
            interact_object(obj)
        end
    },
    Misterious_Chest = {
        pattern = "Hell_Prop_Chest_Rare_Locked",
        move_threshold = 12,
        interact_threshold = 1.0,
        interact_function = function(obj)
            interact_object(obj)
        end
    },
    Herbs = {
        pattern = "HarvestNode_Herb",
        move_threshold = 8,
        interact_threshold = 1.0,
        interact_function = function(obj)
            interact_object(obj)
        end
    }
}

local actor_display_names = {
    shrine = "Total Shrines Interacted",
    goblin = "Total Goblins Killed",
    harvest_node = "Total Iron Nodes Interacted",
    Misterious_Chest = "Total Silent Chests Opened",
    Herbs = "Total Herbs Interacted"
}

local interacted_actor_counts = {}
for actor_type in pairs(actor_types) do
    interacted_actor_counts[actor_type] = 0
end

local function initialize_gold()
    local local_player = get_local_player()
    if local_player then
        initial_gold = local_player:get_gold()
    end
end

local function should_ignore_object(skin_name)
    for _, ignored_pattern in ipairs(ignored_objects) do
        if skin_name:match(ignored_pattern) then
            return true
        end
    end
    return false
end

local function is_permanently_blacklisted(obj)
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()
    
    for _, blacklisted_obj in ipairs(permanent_blacklist) do
        if blacklisted_obj.name == obj_name and blacklisted_obj.position:dist_to(obj_pos) < 0.1 then
            return true
        end
    end
    
    return false
end


local function add_to_permanent_blacklist(obj)
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()
    
    local pos_string = "unknown position"
    if obj_pos then
        pos_string = string.format("(%.2f, %.2f, %.2f)", obj_pos:x(), obj_pos:y(), obj_pos:z())
    end
    
    table.insert(permanent_blacklist, {name = obj_name, position = obj_pos})
end

local function is_actor_of_type(skin_name, actor_type)
    return skin_name:match(actor_types[actor_type].pattern) ~= nil
end

local function should_interact_with_actor(position, player_pos, actor_type)
    return position:dist_to(player_pos) <= actor_types[actor_type].interact_threshold
end

local function move_to_actor(actor_position, player_position, actor_type)
    local move_threshold = actor_types[actor_type].move_threshold
    local distance = actor_position:dist_to(player_position)
    
    if distance <= move_threshold then
        pathfinder.request_move(actor_position)
        return true
    end
    
    return false
end

local function initialize_consumable_state()
    local local_player = get_local_player()
    if not local_player then
        return
    end

    local consumable_items = local_player:get_consumable_items()
    if not consumable_items then
        return
    end

    last_consumable_state = {}
    for _, item in pairs(consumable_items) do
        if item and item:is_valid() then
            local sno_id = item:get_sno_id()
            last_consumable_state[sno_id] = (last_consumable_state[sno_id] or 0) + (item:get_stack_count() or 0)
        end
    end
end

local function update_material_counts()
    local local_player = get_local_player()
    if not local_player then
        return
    end

    -- Inicializar o estado na primeira execução
    if last_consumable_state == nil then
        initialize_consumable_state()
        return
    end

    -- Obter lista atual de consumíveis e dungeon keys
    local consumable_items = local_player:get_consumable_items()
    local dungeon_keys = local_player:get_dungeon_key_items()
    
    if not consumable_items and not dungeon_keys then
        return
    end

    -- Criar mapa do estado atual
    local current_state = {}
    
    -- Processar consumíveis
    if consumable_items then
        for _, item in pairs(consumable_items) do
            if item and item:is_valid() then
                local sno_id = item:get_sno_id()
                current_state[sno_id] = (current_state[sno_id] or 0) + (item:get_stack_count() or 0)
            end
        end
    end
    
    -- Processar dungeon keys (compass e tributes)
    if dungeon_keys then
        -- Primeiro, vamos contar quantos temos de cada tipo
        local compass_count = 0
        local tribute_count = 0
        
        for _, item in pairs(dungeon_keys) do
            if item and item:is_valid() then
                local item_name = item:get_name()
                -- Contar Compass
                if item_name:match("S05_DungeonSigil_BSK") then
                    compass_count = compass_count + 1
                end
                -- Contar Tributes
                if item_name:match("X1_Undercity_TributeKeySigil") then
                    tribute_count = tribute_count + 1
                end
            end
        end
    
        -- Atualizar o estado atual
        current_state["compass_total"] = compass_count
        current_state["tribute_total"] = tribute_count
    
        -- Verificar a diferença com o estado anterior
        local last_compass = last_consumable_state["compass_total"] or compass_count -- Inicializa com o valor atual se for nil
        local last_tribute = last_consumable_state["tribute_total"] or tribute_count -- Inicializa com o valor atual se for nil
    
        -- Atualizar apenas se houver aumento
        if compass_count > last_compass then
            materials_gained.compass.count = materials_gained.compass.count + (compass_count - last_compass)
            --console.print(string.format("Novo(s) Compass encontrado(s): +%d", compass_count - last_compass))
        end
    
        if tribute_count > last_tribute then
            materials_gained.tributes.count = materials_gained.tributes.count + (tribute_count - last_tribute)
            --console.print(string.format("Novo(s) Tribute encontrado(s): +%d", tribute_count - last_tribute))
        end
    end

    -- Verificar diferenças e atualizar contadores
    for material_key, material_data in pairs(materials_gained) do
        if material_data.sno_id then
            -- Para consumíveis normais
            local current_count = current_state[material_data.sno_id] or 0
            local last_count = last_consumable_state[material_data.sno_id] or 0
            
            if current_count > last_count then
                local gained = current_count - last_count
                material_data.count = material_data.count + gained
                --console.print(string.format("Novo(s) %s encontrado(s): +%d", material_data.display_name, gained))
            end
        else
            -- Para compass e tributes
            local current_count = current_state[material_key] or 0
            local last_count = last_consumable_state[material_key] or 0
            
            if current_count > last_count then
                local gained = current_count - last_count
                material_data.count = material_data.count + gained
                --console.print(string.format("Novo(s) %s encontrado(s): +%d", material_data.display_name, gained))
            end
        end
    end

    -- Atualizar último estado conhecido
    last_consumable_state = current_state
end

function actors.update()
    local local_player = get_local_player()
    if not local_player then
        return
    end

        local player_pos = local_player:get_position()
    local all_actors = actors_manager.get_ally_actors()
    local current_time = os.clock()

    if initial_gold == 0 then
        initialize_gold()
    end

    local current_gold = local_player:get_gold()
    gold_gained = current_gold - initial_gold

    -- Chama a função de debug
    --actors.debug_dungeon_keys()

    -- Update material counts
    update_material_counts()

    -- Clean up old timers
    for id, time in pairs(movement_timers) do
        if current_time - time > max_movement_time * 2 then
            movement_timers[id] = nil
        end
    end

    table.sort(all_actors, function(a, b)
        return a:get_position():squared_dist_to_ignore_z(player_pos) <
               b:get_position():squared_dist_to_ignore_z(player_pos)
    end)

    for _, obj in ipairs(all_actors) do
        if obj and not is_permanently_blacklisted(obj) then
            local position = obj:get_position()
            local skin_name = obj:get_skin_name()

            for actor_type, config in pairs(actor_types) do
                if skin_name and is_actor_of_type(skin_name, actor_type) then
                    local distance = position:dist_to(player_pos)
                    if distance <= config.move_threshold then
                        if not movement_timers[obj:get_id()] then
                            movement_timers[obj:get_id()] = current_time
                        end

                        if current_time - movement_timers[obj:get_id()] > max_movement_time then
                            add_to_permanent_blacklist(obj)
                            movement_timers[obj:get_id()] = nil
                        else
                            if move_to_actor(position, player_pos, actor_type) then
                                if should_interact_with_actor(position, player_pos, actor_type) then
                                    config.interact_function(obj)
                                    add_to_permanent_blacklist(obj)
                                    movement_timers[obj:get_id()] = nil
                                    interacted_actor_counts[actor_type] = interacted_actor_counts[actor_type] + 1
                                end
                            end
                        end
                    else
                        movement_timers[obj:get_id()] = nil
                    end
                end
            end
        end
    end
end

function actors.draw_actor_info()
    -- Configurações de UI centralizadas
    local UI_CONFIG = {
        base_x = 10,
        base_y = 10,
        line_height = 17, --20
        category_spacing = 0,
        font_size = 20
    }
    local current_y = UI_CONFIG.base_y

    -- Funções auxiliares
    local function draw_section_header(text)
        graphics.text_2d("=== " .. text .. " ===", 
            vec2:new(UI_CONFIG.base_x, current_y), 
            UI_CONFIG.font_size, 
            color_yellow(255))
        current_y = current_y + UI_CONFIG.line_height
    end

    local function draw_stat_line(label, value)
        graphics.text_2d(
            string.format("%s: %s", label, value),
            vec2:new(UI_CONFIG.base_x, current_y),
            UI_CONFIG.font_size,
            color_white(255)
        )
        current_y = current_y + UI_CONFIG.line_height
    end

    local function add_category_spacing()
        current_y = current_y + UI_CONFIG.category_spacing + UI_CONFIG.line_height
    end

    -- ACTORS
    draw_section_header("ACTORS")
    draw_stat_line(actor_display_names.shrine, interacted_actor_counts.shrine)
    draw_stat_line(actor_display_names.goblin, interacted_actor_counts.goblin)

    -- HARVEST MATERIALS
    add_category_spacing()
    draw_section_header("HARVEST MATERIALS")
    draw_stat_line(actor_display_names.harvest_node, interacted_actor_counts.harvest_node)
    draw_stat_line(actor_display_names.Herbs, interacted_actor_counts.Herbs)
    draw_stat_line(actor_display_names.Misterious_Chest, interacted_actor_counts.Misterious_Chest)

    -- BOSS MATERIALS
    add_category_spacing()
    draw_section_header("BOSS MATERIALS")
    local boss_materials = {
        "living_steel",
        "distilled_fear",
        "exquisite_blood",
        "malignant_heart"
    }
    for _, material in ipairs(boss_materials) do
        draw_stat_line(
            materials_gained[material].display_name,
            materials_gained[material].count
        )
    end

    -- DUNGEON KEYS
    add_category_spacing()
    draw_section_header("DUNGEON KEYS")
    draw_stat_line(materials_gained.compass.display_name, materials_gained.compass.count)
    draw_stat_line(materials_gained.tributes.display_name, materials_gained.tributes.count)

    -- GOLD
    add_category_spacing()
    draw_section_header("GOLD")
    draw_stat_line("Total Gold Gained", format_number(gold_gained))
end

function actors.clear_permanent_blacklist()
    permanent_blacklist = {}
    movement_timers = {}
    console.print("Permanent blacklist and movement timers have been cleared")
end

function actors.reset_interacted_counts()
    for actor_type in pairs(actor_types) do
        interacted_actor_counts[actor_type] = 0
    end
end

function actors.reset_gold_counter()
    initial_gold = 0
    gold_gained = 0
end

function actors.reset_material_counts()
    for _, material in pairs(materials_gained) do
        material.count = 0
    end
    last_consumable_state = nil -- Isso fará com que o estado seja reinicializado na próxima atualização
    console.print("Material counters have been reset")
end

-- Debug function to print current material counts
function actors.print_material_counts()
    console.print("=== Current Material Counts ===")
    for _, material in pairs(materials_gained) do
        console.print(string.format("%s: %d", 
            material.display_name, 
            material.count))
    end
end

function actors.debug_dungeon_keys()
    local local_player = get_local_player()
    if not local_player then return end
    
    local dungeon_keys = local_player:get_dungeon_key_items()
    if dungeon_keys then
        console.print("=== Dungeon Key Items ===")
        for _, item in pairs(dungeon_keys) do
            if item and item:is_valid() then
                console.print(string.format("Name: %s, ID: %d", 
                    item:get_name(),
                    item:get_sno_id()))
            end
        end
    else
        console.print("No dungeon keys found")
    end
end

return actors