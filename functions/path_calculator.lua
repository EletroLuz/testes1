local Movement = require("functions.movement")

local PathCalculator = {}

-- Calcula distância entre dois waypoints
function PathCalculator.calculate_waypoint_distance(start_index, end_index)
    local waypoints = Movement.get_waypoints()
    local total_distance = 0
    
    -- Se índices inválidos, retorna distância infinita
    if not waypoints[start_index] or not waypoints[end_index] then
        return math.huge
    end
    
    -- Calcula distância waypoint por waypoint
    local current_index = start_index
    while current_index ~= end_index do
        local current_wp = waypoints[current_index]
        local next_index = current_index + 1
        
        -- Se chegou ao fim da lista, volta ao início
        if next_index > #waypoints then
            next_index = 1
        end
        
        local next_wp = waypoints[next_index]
        total_distance = total_distance + current_wp:dist_to(next_wp)
        current_index = next_index
    end
    
    return total_distance
end

-- Calcula distância total do caminho completo
function PathCalculator.calculate_full_path_distance(current_index, target_index)
    local waypoints = Movement.get_waypoints()
    local forward_distance = 0
    local backward_distance = 0
    
    -- Calcula distância indo para frente
    local temp_index = current_index
    while temp_index ~= target_index do
        local next_index = temp_index + 1
        if next_index > #waypoints then
            next_index = 1
        end
        
        forward_distance = forward_distance + waypoints[temp_index]:dist_to(waypoints[next_index])
        temp_index = next_index
    end
    
    -- Calcula distância indo para trás
    temp_index = current_index
    while temp_index ~= target_index do
        local prev_index = temp_index - 1
        if prev_index < 1 then
            prev_index = #waypoints
        end
        
        backward_distance = backward_distance + waypoints[temp_index]:dist_to(waypoints[prev_index])
        temp_index = prev_index
    end
    
    return {
        forward = forward_distance,
        backward = backward_distance
    }
end

-- Determina melhor direção para alcançar um waypoint
function PathCalculator.determine_best_direction(target_waypoint_index)
    local current_index = Movement.get_current_waypoint_index()
    if not current_index then return nil end
    
    local distances = PathCalculator.calculate_full_path_distance(current_index, target_waypoint_index)
    
    return {
        direction = distances.forward <= distances.backward and "forward" or "backward",
        distance = math.min(distances.forward, distances.backward)
    }
end

-- Calcula melhor rota para baús perdidos
function PathCalculator.calculate_best_missed_chests_route(missed_chests)
    -- Agrupa baús por waypoint
    local waypoint_groups = {}
    for _, chest in pairs(missed_chests) do
        local wp_idx = chest.waypoint_index
        waypoint_groups[wp_idx] = waypoint_groups[wp_idx] or {}
        table.insert(waypoint_groups[wp_idx], chest)
    end
    
    -- Encontra melhor grupo de baús
    local best_route = {
        waypoints = {},
        chests = {},
        total_distance = math.huge
    }
    
    for wp_idx, chests in pairs(waypoint_groups) do
        local path_info = PathCalculator.determine_best_direction(wp_idx)
        if path_info and path_info.distance < best_route.total_distance then
            best_route = {
                waypoints = {wp_idx},
                chests = chests,
                total_distance = path_info.distance,
                direction = path_info.direction
            }
        end
    end
    
    if best_route.direction then
        console.print(string.format(
            "Melhor rota encontrada: %d baús no waypoint %d, direção %s, distância %.0f",
            #best_route.chests,
            best_route.waypoints[1],
            best_route.direction,
            best_route.total_distance
        ))
        return best_route
    end
    
    return nil
end

function PathCalculator.reset()
    -- Atualmente não há estados para resetar, mas esta função pode ser expandida no futuro
    console.print("PathCalculator resetado")
end

return PathCalculator