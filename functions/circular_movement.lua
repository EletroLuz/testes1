local explorer = require("data.explorer")
local circular_movement = {}

-- Variáveis de Movimento Circular
local run_explorer = 0
local explorer_point = nil
local explorer_go_next = 1
local explorer_threshold = 1.5
local explorer_thresholdvar = 3.0
local last_explorer_threshold_check = 0
local explorer_circle_radius_prev = 0

-- Variáveis de controle de movimento
local movement_paused = false
local movement_activated = false
local last_move_time = 0
local last_player_position = nil
local last_position_check = 0

-- Função para verificar se o boss está vivo
local function is_boss_alive(actor)
    if actor.is_dead and actor:is_dead() then
        return false
    end
    
    if actor.get_current_health then
        local health = actor:get_current_health()
        return health and health > 0
    end
    
    return true
end

-- Função para gerar próximo ponto no círculo
local function get_next_circle_point(center_point, radius)
    local angle = math.random() * 2 * math.pi
    local x = center_point:x() + radius * math.cos(angle)
    local y = center_point:y() + radius * math.sin(angle)
    return vec3:new(x, y, center_point:z())
end

-- Função para verificar se está travado
local function is_stuck(current_pos, last_pos, time_diff)
    if not last_pos then return false end
    local dist_squared = current_pos:squared_dist_to_ignore_z(last_pos)
    return dist_squared < 1.0 and time_diff > 2.0
end

-- Função para medir tempo de execução
local function measure_execution_time(func, name)
    local start_time = os.clock()
    func()
    local end_time = os.clock()
    local execution_time = end_time - start_time
    if execution_time > 0.016 then
        console.print(name .. " took " .. execution_time .. " seconds")
    end
end

-- Função para pausar movimento
function circular_movement.pause_movement()
    movement_paused = true
end

-- Função para resumir movimento
function circular_movement.resume_movement()
    movement_paused = false
end

-- Função para verificar se está perto da maiden
function circular_movement.is_near_maiden(player_position, maiden_position, radius)
    return player_position:dist_to(maiden_position) <= radius * 1.2
end

-- Função para verificar se está fora do círculo
function circular_movement.is_player_outside_circle(player_position, circle_center, radius)
    local distance_squared = player_position:squared_dist_to_ignore_z(circle_center)
    return distance_squared > (radius * radius)
end

-- Função para verificar e mover para o boss
local function check_and_move_to_boss()
    local actors = actors_manager.get_all_actors()
    if not actors or #actors == 0 then
        return false
    end

    local local_player = get_local_player()
    if not local_player then
        return false
    end

    local player_position = local_player:get_position()
    if not player_position then
        return false
    end
    
    for _, actor in ipairs(actors) do
        if actor and actor.is_enemy and actor.get_skin_name then
            local skin_name = actor:get_skin_name()
            if actor:is_enemy() and is_boss_alive(actor) and skin_name == "S04_demon_succubus_miniboss" then
                local boss_position = actor:get_position()
                if boss_position then
                    explorer.set_target(boss_position)
                    explorer.enable()
                    pathfinder.clear_stored_path()
                    return true
                end
            end
        end
    end
    
    return false
end

local function check_for_interactable_altars()
    local actors = actors_manager.get_all_actors()
    if not actors then return false end
    
    for _, obj in ipairs(actors) do
        if not obj then return false end
        
        local obj_name = obj:get_skin_name()
        local is_interactable = obj:is_interactable()
        
        if obj_name == "S04_SMP_Succuboss_Altar_A_Dyn" and is_interactable then
            local player_pos = get_local_player():get_position()
            local altar_pos = obj:get_position()
            if player_pos:dist_to(altar_pos) < 20 then
                return true
            end
        end
    end
    return false
end

-- Função principal de movimento circular
function circular_movement.update(menu_elements, helltide_final_maidenpos, explorer_circle_radius)
    local current_time = os.clock()
    local local_player = get_local_player()
    if not local_player then
        return
    end

    if not menu_elements.main_helltide_maiden_auto_plugin_enabled:get() then
        return
    end

    -- Verificar altares antes de qualquer movimento
    if check_for_interactable_altars() then
        movement_paused = true
        return
    else
        movement_paused = false
    end

    if movement_paused then
        return
    end

    if check_and_move_to_boss() then
        return
    end

    local player_position = local_player:get_position()

    -- Verifica se está perto da maiden para ativar movimento
    if circular_movement.is_near_maiden(player_position, helltide_final_maidenpos, explorer_circle_radius) then
        console.print("Movement activated - Distance from maiden: " .. player_position:dist_to(helltide_final_maidenpos))
        movement_activated = true
    end

    -- Verifica se está fora do círculo e precisa retornar
    if movement_activated and circular_movement.is_player_outside_circle(player_position, helltide_final_maidenpos, explorer_circle_radius) then
        console.print("Player outside the circle. Returning to center.")
        
        local direction = vec3:new(
            player_position:x() - helltide_final_maidenpos:x(),
            player_position:y() - helltide_final_maidenpos:y(),
            player_position:z() - helltide_final_maidenpos:z()
        ):normalize()
        
        local target_position = vec3:new(
            helltide_final_maidenpos:x() + direction:x() * (explorer_circle_radius * 0.9),
            helltide_final_maidenpos:y() + direction:y() * (explorer_circle_radius * 0.9),
            helltide_final_maidenpos:z() + direction:z() * (explorer_circle_radius * 0.9)
        )
        
        explorer.set_target(target_position)
        explorer.enable()
        pathfinder.clear_stored_path()
        return
    end

    -- Verifica se está travado
    if last_player_position and movement_activated then
        if is_stuck(player_position, last_player_position, current_time - last_position_check) then
            console.print("Stuck detected - resetting movement")
            pathfinder.clear_stored_path()
            explorer_go_next = 1
            local escape_point = get_next_circle_point(helltide_final_maidenpos, explorer_circle_radius * 0.8)
            pathfinder.force_move_raw(escape_point)
        end
    end
    last_player_position = player_position
    last_position_check = current_time

    -- Lógica principal de movimento
    if menu_elements.main_helltide_maiden_auto_plugin_run_explorer:get() and helltide_final_maidenpos then
        measure_execution_time(function()
            if explorer_go_next == 1 then
                if current_time - last_explorer_threshold_check >= explorer_threshold then
                    last_explorer_threshold_check = current_time
                    
                    local next_point = get_next_circle_point(helltide_final_maidenpos, explorer_circle_radius * 0.9)
                    if utility.is_point_walkeable(next_point) then
                        pathfinder.clear_stored_path()
                        explorer_point = next_point
                        
                        explorer_threshold = menu_elements.main_helltide_maiden_auto_plugin_explorer_threshold:get() * 0.5
                        explorer_thresholdvar = math.random(0, 2)
                        explorer_threshold = explorer_threshold + explorer_thresholdvar
                        
                        pathfinder.force_move_raw(explorer_point)
                        explorer_go_next = 0
                        
                        console.print("Moving to new point. Threshold: " .. explorer_threshold)
                    end
                end
            else
                if explorer_point and not explorer_point:is_zero() then
                    if player_position:squared_dist_to_ignore_z(explorer_point) < 25 then
                        explorer_go_next = 1
                        console.print("Reached point, selecting next")
                    else
                        if current_time - last_move_time > 0.1 then
                            pathfinder.force_move_raw(explorer_point)
                            last_move_time = current_time
                        end
                    end
                else
                    explorer_go_next = 1
                end
            end
        end, "Movement calculation")
    else
        run_explorer = 0
        pathfinder.clear_stored_path()
    end
end

-- Limpar blacklist (se necessário)
function circular_movement.clearBlacklist()
    -- lógica de blacklist, se necessário
end

return circular_movement