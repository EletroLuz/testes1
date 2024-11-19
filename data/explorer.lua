local MinHeap = {}
MinHeap.__index = MinHeap

function MinHeap.new(compare)
    return setmetatable({heap = {}, compare = compare or function(a, b) return a < b end}, MinHeap)
end

function MinHeap:push(value)
    table.insert(self.heap, value)
    self:siftUp(#self.heap)
end

function MinHeap:pop()
    if self:empty() then return nil end
    local root = self.heap[1]
    self.heap[1] = self.heap[#self.heap]
    table.remove(self.heap)
    if #self.heap > 1 then
        self:siftDown(1)
    end
    return root
end

function MinHeap:peek()
    return self.heap[1]
end

function MinHeap:empty()
    return #self.heap == 0
end

function MinHeap:siftUp(index)
    local parent = math.floor(index / 2)
    while index > 1 and self.compare(self.heap[index], self.heap[parent]) do
        self.heap[index], self.heap[parent] = self.heap[parent], self.heap[index]
        index = parent
        parent = math.floor(index / 2)
    end
end

function MinHeap:siftDown(index)
    local size = #self.heap
    local smallest = index
    while true do
        local left = 2 * index
        local right = 2 * index + 1
        if left <= size and self.compare(self.heap[left], self.heap[smallest]) then
            smallest = left
        end
        if right <= size and self.compare(self.heap[right], self.heap[smallest]) then
            smallest = right
        end
        if smallest == index then break end
        self.heap[index], self.heap[smallest] = self.heap[smallest], self.heap[index]
        index = smallest
    end
end

function MinHeap:contains(value)
    for _, v in ipairs(self.heap) do
        if v == value then return true end
    end
    return false
end

local enabled = false
local explored_areas = {}
local target_position = nil
local grid_size = 0.8
local exploration_radius = 10
local explored_buffer = 0
local max_target_distance = 80
local target_distance_states = {80, 40, 20, 5}
local target_distance_index = 1
local unstuck_target_distance = 5
local stuck_threshold = 4
local last_position = nil
local last_move_time = 0
local last_explored_targets = {}
local max_last_targets = 50
local start_time = 0
local min_duration = 30
local jump_points_used = {}
local JUMP_POINT_COOLDOWN = 10  -- segundos
local static_count = static_count or 0
local last_check_pos = last_check_pos or player_pos
local last_check_time = last_check_time or current_time

local current_path = {}
local path_index = 1

local exploration_mode = "unexplored"
local exploration_direction = { x = 10, y = 0 }
local last_movement_direction = nil

local function vec3_to_string(v)
    if type(v) == "userdata" and v.x and v.y and v.z then
        return string.format("(%.2f, %.2f, %.2f)", v:x(), v:y(), v:z())
    else
        return tostring(v)
    end
end

local function calculate_distance(point1, point2)
    if not point2.x and point2 then
        return point1:dist_to_ignore_z(point2:get_position())
    end
    return point1:dist_to_ignore_z(point2)
end

local function enable()
    enabled = true
    start_time = os.clock()
end

local function disable()
    enabled = false
    target_position = nil
    current_path = {}
    path_index = 1
end

local function is_enabled()
    return enabled
end

local function set_target(new_target)
    target_position = new_target
    current_path = {}
    path_index = 1
end

local function is_target_reached()
    if not target_position then
        return true
    end
    local player_pos = get_player_position()
    return calculate_distance(player_pos, target_position) < 2
end

local function set_height_of_valid_position(point)
    return utility.set_height_of_valid_position(point)
end

local function get_grid_key(point)
    return math.floor(point:x() / grid_size) .. "," ..
        math.floor(point:y() / grid_size) .. "," ..
        math.floor(point:z() / grid_size)
end

local explored_area_bounds = {
    min_x = math.huge,
    max_x = -math.huge,
    min_y = math.huge,
    max_y = -math.huge,
    min_z = math.huge,
    max_z = -math.huge
}

local function update_explored_area_bounds(point, radius)
    explored_area_bounds.min_x = math.min(explored_area_bounds.min_x, point:x() - radius)
    explored_area_bounds.max_x = math.max(explored_area_bounds.max_x, point:x() + radius)
    explored_area_bounds.min_y = math.min(explored_area_bounds.min_y, point:y() - radius)
    explored_area_bounds.max_y = math.max(explored_area_bounds.max_y, point:y() + radius)
    explored_area_bounds.min_z = math.min(explored_area_bounds.min_z, point:z() - radius)
    explored_area_bounds.max_z = math.max(explored_area_bounds.max_z, point:z() + radius)
end

local function is_point_in_explored_area(point)
    return point:x() >= explored_area_bounds.min_x and point:x() <= explored_area_bounds.max_x and
        point:y() >= explored_area_bounds.min_y and point:y() <= explored_area_bounds.max_y and
        point:z() >= explored_area_bounds.min_z and point:z() <= explored_area_bounds.max_z
end

local function mark_area_as_explored(center, radius)
    update_explored_area_bounds(center, radius)
end

local function check_walkable_area()
    if os.time() % 5 ~= 0 then return end

    local player_pos = get_player_position()
    local check_radius = 10

    mark_area_as_explored(player_pos, exploration_radius)

    for x = -check_radius, check_radius, grid_size do
        for y = -check_radius, check_radius, grid_size do
            for z = -check_radius, check_radius, grid_size do
                local point = vec3:new(
                    player_pos:x() + x,
                    player_pos:y() + y,
                    player_pos:z() + z
                )
                point = set_height_of_valid_position(point)

                if utility.is_point_walkeable(point) then
                    if is_point_in_explored_area(point) then
                        -- graphics.text_3d("Explored", point, 15, color_white(128))
                    else
                        -- graphics.text_3d("unexplored", point, 15, color_green(255))
                    end
                end
            end
        end
    end
end

local function reset_exploration()
    explored_area_bounds = {
        min_x = math.huge,
        max_x = -math.huge,
        min_y = math.huge,
        max_y = -math.huge,
        min_z = math.huge,
        max_z = -math.huge
    }
    target_position = nil
    last_position = nil
    last_move_time = 0
    current_path = {}
    path_index = 1
    exploration_mode = "unexplored"
    last_movement_direction = nil
end

local function is_near_wall(point)
    local wall_check_distance = 1
    local directions = {
        { x = 1, y = 0 }, { x = -1, y = 0 }, { x = 0, y = 1 }, { x = 0, y = -1 },
        { x = 1, y = 1 }, { x = 1, y = -1 }, { x = -1, y = 1 }, { x = -1, y = -1 }
    }
    
    for _, dir in ipairs(directions) do
        local check_point = vec3:new(
            point:x() + dir.x * wall_check_distance,
            point:y() + dir.y * wall_check_distance,
            point:z()
        )
        check_point = set_height_of_valid_position(check_point)
        if not utility.is_point_walkeable(check_point) then
            return true
        end
    end
    return false
end

local function find_central_unexplored_target()
    local player_pos = get_player_position()
    local check_radius = max_target_distance
    local unexplored_points = {}
    local min_x, max_x, min_y, max_y = math.huge, -math.huge, math.huge, -math.huge

    for x = -check_radius, check_radius, grid_size do
        for y = -check_radius, check_radius, grid_size do
            local point = vec3:new(
                player_pos:x() + x,
                player_pos:y() + y,
                player_pos:z()
            )

            point = set_height_of_valid_position(point)

            if utility.is_point_walkeable(point) and not is_point_in_explored_area(point) then
                table.insert(unexplored_points, point)
                min_x = math.min(min_x, point:x())
                max_x = math.max(max_x, point:x())
                min_y = math.min(min_y, point:y())
                max_y = math.max(max_y, point:y())
            end
        end
    end

    if #unexplored_points == 0 then
        return nil
    end

    local center_x = (min_x + max_x) / 2
    local center_y = (min_y + max_y) / 2
    local center = vec3:new(center_x, center_y, player_pos:z())
    center = set_height_of_valid_position(center)

    table.sort(unexplored_points, function(a, b)
        return calculate_distance(a, center) < calculate_distance(b, center)
    end)

    return unexplored_points[1]
end

local function find_random_explored_target()
    local player_pos = get_player_position()
    local check_radius = max_target_distance
    local explored_points = {}

    for x = -check_radius, check_radius, grid_size do
        for y = -check_radius, check_radius, grid_size do
            local point = vec3:new(
                player_pos:x() + x,
                player_pos:y() + y,
                player_pos:z()
            )
            point = set_height_of_valid_position(point)
            local grid_key = get_grid_key(point)
            if utility.is_point_walkeable(point) and explored_areas[grid_key] and not is_near_wall(point) then
                table.insert(explored_points, point)
            end
        end
    end

    if #explored_points == 0 then
        return nil
    end

    return explored_points[math.random(#explored_points)]
end

function vec3.__add(v1, v2)
    return vec3:new(v1:x() + v2:x(), v1:y() + v2:y(), v1:z() + v2:z())
end

local function is_in_last_targets(point)
    for _, target in ipairs(last_explored_targets) do
        if calculate_distance(point, target) < grid_size * 2 then
            return true
        end
    end
    return false
end

local function add_to_last_targets(point)
    table.insert(last_explored_targets, 1, point)
    if #last_explored_targets > max_last_targets then
        table.remove(last_explored_targets)
    end
end

local function find_explored_direction_target()
    local player_pos = get_player_position()
    local max_attempts = 200
    local attempts = 0
    local best_target = nil
    local best_distance = 0

    while attempts < max_attempts do
        local direction_vector = vec3:new(
            exploration_direction.x * max_target_distance * 0.5,
            exploration_direction.y * max_target_distance * 0.5,
            0
        )
        local target_point = player_pos + direction_vector
        target_point = set_height_of_valid_position(target_point)

        if utility.is_point_walkeable(target_point) and is_point_in_explored_area(target_point) then
            local distance = calculate_distance(player_pos, target_point)
            if distance > best_distance and not is_in_last_targets(target_point) then
                best_target = target_point
                best_distance = distance
            end
        end

        local angle = math.atan2(exploration_direction.y, exploration_direction.x) + math.random() * math.pi / 2 - math.pi / 4
        exploration_direction.x = math.cos(angle)
        exploration_direction.y = math.sin(angle)
        attempts = attempts + 1
    end

    if best_target then
        add_to_last_targets(best_target)
        return best_target
    end

    return nil
end

local function find_unstuck_target()
    local player_pos = get_player_position()
    local valid_targets = {}

    for x = -unstuck_target_distance, unstuck_target_distance, grid_size do
        for y = -unstuck_target_distance, unstuck_target_distance, grid_size do
            local point = vec3:new(
                player_pos:x() + x,
                player_pos:y() + y,
                player_pos:z()
            )
            point = set_height_of_valid_position(point)

            local distance = calculate_distance(player_pos, point)
            if utility.is_point_walkeable(point) and distance >= 2 and distance <= unstuck_target_distance then
                table.insert(valid_targets, point)
            end
        end
    end

    if #valid_targets > 0 then
        return valid_targets[math.random(#valid_targets)]
    end

    return nil
end

local function find_target(include_explored)
    last_movement_direction = nil

    if include_explored then
        return find_unstuck_target()
    else
        if exploration_mode == "unexplored" then
            local unexplored_target = find_central_unexplored_target()
            if unexplored_target then
                return unexplored_target
            else
                exploration_mode = "explored"
                last_explored_targets = {}
            end
        end
        
        if exploration_mode == "explored" then
            local explored_target = find_explored_direction_target()
            if explored_target then
                return explored_target
            else
                reset_exploration()
                exploration_mode = "unexplored"
                return find_central_unexplored_target()
            end
        end
    end
    
    return nil
end

local function heuristic(a, b)
    return calculate_distance(a, b)
end

local function get_neighbors(point)
    local neighbors = {}
    local directions = {
        { x = 1.2, y = 0 }, { x = -1.2, y = 0 }, { x = 0, y = 1.2 }, { x = 0, y = -1.2 },
        { x = 1.2, y = 1.2 }, { x = 1.2, y = -1.2 }, { x = -1.2, y = 1.2 }, { x = -1.2, y = -1.2 }
    }
    
    for _, dir in ipairs(directions) do
        local neighbor = vec3:new(
            point:x() + dir.x * grid_size,
            point:y() + dir.y * grid_size,
            point:z()
        )
        neighbor = set_height_of_valid_position(neighbor)
        if utility.is_point_walkeable(neighbor) then
            if not last_movement_direction or
                (dir.x ~= -last_movement_direction.x or dir.y ~= -last_movement_direction.y) then
                table.insert(neighbors, neighbor)
            end
        end
    end
    
    if #neighbors == 0 and last_movement_direction then
        local back_direction = vec3:new(
            point:x() - last_movement_direction.x * grid_size,
            point:y() - last_movement_direction.y * grid_size,
            point:z()
        )
        back_direction = set_height_of_valid_position(back_direction)
        if utility.is_point_walkeable(back_direction) then
            table.insert(neighbors, back_direction)
        end
    end
    
    return neighbors
end

local function reconstruct_path(came_from, current)
    local path = { current }
    while came_from[get_grid_key(current)] do
        current = came_from[get_grid_key(current)]
        table.insert(path, 1, current)
    end

    local filtered_path = { path[1] }
    for i = 2, #path - 1 do
        local prev = path[i - 1]
        local curr = path[i]
        local next = path[i + 1]

        local dir1 = { x = curr:x() - prev:x(), y = curr:y() - prev:y() }
        local dir2 = { x = next:x() - curr:x(), y = next:y() - curr:y() }

        local dot_product = dir1.x * dir2.x + dir1.y * dir2.y
        local magnitude1 = math.sqrt(dir1.x^2 + dir1.y^2)
        local magnitude2 = math.sqrt(dir2.x^2 + dir2.y^2)
        local angle = math.acos(dot_product / (magnitude1 * magnitude2))

        if angle > math.rad(40) then
            table.insert(filtered_path, curr)
        end
    end
    table.insert(filtered_path, path[#path])

    return filtered_path
end

local function a_star(start, goal, max_distance)
    local closed_set = {}
    local came_from = {}
    local g_score = { [get_grid_key(start)] = 0 }
    local f_score = { [get_grid_key(start)] = heuristic(start, goal) }
    local iterations = 0

    local open_set = MinHeap.new(function(a, b)
        return f_score[get_grid_key(a)] < f_score[get_grid_key(b)]
    end)
    open_set:push(start)

    while not open_set:empty() do
        iterations = iterations + 1
        if iterations > 1000 then
            console.print("Max iterations reached, aborting!")
            break
        end

        local current = open_set:pop()
        if calculate_distance(current, goal) < grid_size then
            return reconstruct_path(came_from, current)
        end

        closed_set[get_grid_key(current)] = true

        for _, neighbor in ipairs(get_neighbors(current)) do
            if not closed_set[get_grid_key(neighbor)] and calculate_distance(start, neighbor) <= max_distance then
                local tentative_g_score = g_score[get_grid_key(current)] + calculate_distance(current, neighbor)

                if not g_score[get_grid_key(neighbor)] or tentative_g_score < g_score[get_grid_key(neighbor)] then
                    came_from[get_grid_key(neighbor)] = current
                    g_score[get_grid_key(neighbor)] = tentative_g_score
                    f_score[get_grid_key(neighbor)] = g_score[get_grid_key(neighbor)] + heuristic(neighbor, goal)

                    if not open_set:contains(neighbor) then
                        open_set:push(neighbor)
                    end
                end
            end
        end
    end

    return nil
end

local last_path_calculation_time = 0
local path_recalculation_interval = 1.0

local function smooth_path(path, smoothness)
    if #path < 3 then return path end
    
    local smoothed_path = {path[1]}
    for i = 2, #path - 1 do
        local prev = smoothed_path[#smoothed_path]
        local curr = path[i]
        local next = path[i + 1]
        
        local smooth_x = prev:x() * (1 - smoothness) + curr:x() * smoothness
        local smooth_y = prev:y() * (1 - smoothness) + curr:y() * smoothness
        local smooth_z = prev:z() * (1 - smoothness) + curr:z() * smoothness
        
        table.insert(smoothed_path, vec3:new(smooth_x, smooth_y, smooth_z))
    end
    table.insert(smoothed_path, path[#path])
    
    return smoothed_path
end

local function find_closest_walkable_point(start, goal, max_distance)
    local best_point = nil
    local best_distance = math.huge
    local step = grid_size
    local max_steps = math.floor(max_distance / step)

    for dx = -max_steps, max_steps do
        for dy = -max_steps, max_steps do
            local test_point = vec3:new(
                goal:x() + dx * step,
                goal:y() + dy * step,
                goal:z()
            )
            test_point = set_height_of_valid_position(test_point)
            
            if utility.is_point_walkeable(test_point) then
                local dist_to_start = calculate_distance(start, test_point)
                local dist_to_goal = calculate_distance(test_point, goal)
                local total_dist = dist_to_start + dist_to_goal
                
                if total_dist < best_distance then
                    best_distance = total_dist
                    best_point = test_point
                end
            end
        end
    end

    return best_point
end

local function find_partial_path(start, goal)
    local path = {start}
    local current = start
    local max_steps = 100
    local max_search_distance = 20 * grid_size

    for i = 1, max_steps do
        local next_point = find_closest_walkable_point(current, goal, max_search_distance)
        if not next_point then
            break
        end
        
        table.insert(path, next_point)
        current = next_point
        
        if calculate_distance(current, goal) < grid_size then
            console.print("Target reached!")
            break
        end
    end
    
    return path
end

local function has_clear_path(start, goal)
    local direction = vec3:new(goal:x() - start:x(), goal:y() - start:y(), 0)
    local distance = calculate_distance(start, goal)
    local step_size = grid_size
    local steps = math.floor(distance / step_size)
    
    -- Adiciona verificação de distância mínima
    if distance < 2 then
        return true
    end
    
    -- Aumenta o número de pontos de verificação
    for i = 1, steps do
        local t = i / steps
        local check_point = vec3:new(
            start:x() + direction:x() * t,
            start:y() + direction:y() * t,
            start:z()
        )
        check_point = set_height_of_valid_position(check_point)
        
        -- Verifica pontos adjacentes também
        local offset = grid_size * 0.5
        local adjacent_points = {
            vec3:new(check_point:x() + offset, check_point:y(), check_point:z()),
            vec3:new(check_point:x() - offset, check_point:y(), check_point:z()),
            vec3:new(check_point:x(), check_point:y() + offset, check_point:z()),
            vec3:new(check_point:x(), check_point:y() - offset, check_point:z())
        }
        
        if not utility.is_point_walkeable(check_point) then
            --console.print("Caminho bloqueado em: " .. vec3_to_string(check_point))
            return false
        end
        
        for _, adj_point in ipairs(adjacent_points) do
            if not utility.is_point_walkeable(adj_point) then
                --console.print("Caminho bloqueado próximo a: " .. vec3_to_string(adj_point))
                return false
            end
        end
    end
    
    return true
end

local STAIR_SKIN_NAMES = {
    "Traversal_Gizmo_FreeClimb_Down",
    "Traversal_Gizmo_FreeClimb_Up",
    "Traversal_Gizmo_Jump",
}

local function is_stair(point)
    local all_actors = actors_manager.get_ally_actors()
    --console.print("Verificando escadas próximas a " .. vec3_to_string(point))
    for _, actor in ipairs(all_actors) do
        if actor and actor:get_position() then
            local actor_name = actor:get_skin_name()
            local actor_pos = actor:get_position()
            local distance = calculate_distance(point, actor_pos)
            --console.print("Ator encontrado: " .. actor_name .. " na posição " .. vec3_to_string(actor_pos) .. ", distância: " .. distance)
            for _, stair_name in ipairs(STAIR_SKIN_NAMES) do
                if actor_name:find(stair_name) and distance < grid_size * 2 then
                    --console.print("Escada encontrada: " .. actor_name .. " na posição " .. vec3_to_string(actor_pos))
                    return true
                end
            end
        end
    end
    --console.print("Nenhuma escada encontrada próxima a " .. vec3_to_string(point))
    return false
end

local function find_nearest_stair(start, goal)
    --console.print("Procurando a escada mais próxima entre " .. vec3_to_string(start) .. " e " .. vec3_to_string(goal))
    local all_actors = actors_manager.get_ally_actors()
    local nearest_stair = nil
    local nearest_distance = math.huge

    for _, actor in ipairs(all_actors) do
        if actor and actor:get_position() then
            local actor_name = actor:get_skin_name()
            local actor_pos = actor:get_position()
            --console.print("Verificando ator: " .. actor_name .. " na posição " .. vec3_to_string(actor_pos))
            for _, stair_name in ipairs(STAIR_SKIN_NAMES) do
                if actor_name:find(stair_name) then
                    local stair_pos = actor_pos
                    local dist_to_start = calculate_distance(start, stair_pos)
                    local dist_to_goal = calculate_distance(stair_pos, goal)
                    local total_dist = dist_to_start + dist_to_goal

                    --console.print("Escada encontrada: " .. actor_name .. ", distância total: " .. total_dist)

                    if total_dist < nearest_distance then
                        nearest_stair = stair_pos
                        nearest_distance = total_dist
                        --console.print("Nova escada mais próxima encontrada: " .. actor_name .. " na posição " .. vec3_to_string(stair_pos))
                    end
                    break
                end
            end
        end
    end

    if nearest_stair then
        --console.print("Escada mais próxima encontrada na posição " .. vec3_to_string(nearest_stair))
    else
        --console.print("Nenhuma escada encontrada no caminho")
    end

    return nearest_stair
end

local function is_jump_point_on_cooldown(point)
    local current_time = os.time()
    for jump_point, use_time in pairs(jump_points_used) do
        if calculate_distance(point, jump_point) < grid_size and current_time - use_time < JUMP_POINT_COOLDOWN then
            return true
        end
    end
    return false
end

local function add_jump_point_to_cooldown(point)
    jump_points_used[point] = os.time()
end

local function movement_spell_to_target(target)
    local local_player = get_local_player()
    if not local_player then return false end

    local movement_spell_id = {
        288106, -- Teleporte do Feiticeiro
        358761, -- Dash do Ladino
        355606, -- Passo das Sombras do Ladino
        337031  -- Evasão Geral
    }

    for _, spell_id in ipairs(movement_spell_id) do
        if local_player:is_spell_ready(spell_id) then
            local success = cast_spell.position(spell_id, target, 3.0)
            if success then
                console.print("Habilidade de movimento usada com sucesso para o alvo.")
                return true
            end
        end
    end
    console.print("Nenhuma habilidade de movimento disponível ou falha ao usar.")
    return false
end

local function check_if_stuck()
    local current_pos = get_player_position()
    local current_time = os.time()
    
    if last_position and calculate_distance(current_pos, last_position) < 2 then
        if current_time - last_move_time > stuck_threshold then
            console.print("Personagem está preso. Tentando usar habilidade de movimento.")
            if movement_spell_to_target(target_position) then
                last_move_time = current_time
                return false
            end
            return true
        end
    else
        last_move_time = current_time
    end
    
    last_position = current_pos
    
    return false
end

local function move_to_target()
    if target_position then
        local player_pos = get_player_position()
        local current_time = os.clock()
        local dist_to_target = calculate_distance(player_pos, target_position)

        --console.print(string.format("Estado atual - Distância: %.2f, Tem caminho: %s, Índice: %d/%d", 
            --dist_to_target,
            --current_path and #current_path or "não",
            --path_index,
            --current_path and #current_path or 0
        --))

        if calculate_distance(player_pos, target_position) > 500 then
            console.print("Alvo muito distante. Cancelando movimento.")
            target_position = nil
            current_path = {}
            path_index = 1
            return
        end

        -- Verificação de progresso
        local static_count = static_count or 0
        local last_check_pos = last_check_pos or player_pos
        local last_check_time = last_check_time or current_time

        if calculate_distance(player_pos, last_check_pos) < 0.1 then
            static_count = static_count + 1
            if static_count > 10 then  -- Se ficar parado por muito tempo
                --console.print("Sem progresso detectado, forçando recálculo com A*")
                current_path = {}
                path_index = 1
                last_path_calculation_time = 0
                static_count = 0
            end
        else
            static_count = 0
        end

        if current_time - last_check_time > 1.0 then
            last_check_pos = player_pos
            last_check_time = current_time
        end

        -- Verifica se precisa recalcular o caminho
        local need_recalculation = not current_path or #current_path == 0 or 
                                 path_index > #current_path or 
                                 (current_time - last_path_calculation_time > path_recalculation_interval)

        if need_recalculation then
            --console.print("Recalculando caminho...")
            path_index = 1

            if has_clear_path(player_pos, target_position) then
                local dist_to_target = calculate_distance(player_pos, target_position)
                if dist_to_target > 10 and dist_to_target < 50 then  -- Limita distância máxima também
                    --console.print("Caminho direto encontrado, distância: " .. string.format("%.2f", dist_to_target))
                    pathfinder.request_move(target_position)
                    current_path = {player_pos, target_position}
                    path_index = 1
                    last_path_calculation_time = current_time
                else
                    --console.print("Distância inadequada para caminho direto, usando A*")
                    local raw_path = a_star(player_pos, target_position, max_target_distance)
                    if raw_path then
                        current_path = smooth_path(raw_path, 0.5)
                        last_path_calculation_time = current_time
                    end
                end
            else
                local nearest_stair = find_nearest_stair(player_pos, target_position)

                if nearest_stair and 
                   calculate_distance(player_pos, nearest_stair) < calculate_distance(player_pos, target_position) and 
                   not is_jump_point_on_cooldown(nearest_stair) then
                    
                    --console.print("Usando ponto de travessia: " .. vec3_to_string(nearest_stair))
                    local path_to_stair = a_star(player_pos, nearest_stair, max_target_distance)
                    
                    if path_to_stair then
                        --console.print("Caminho para travessia encontrado")
                        current_path = smooth_path(path_to_stair, 0.5)
                        last_path_calculation_time = current_time
                    else
                        --console.print("Tentando caminho direto após falha na travessia")
                        local raw_path = a_star(player_pos, target_position, max_target_distance)
                        if raw_path then
                            current_path = smooth_path(raw_path, 0.5)
                        else
                            local partial_path = find_partial_path(player_pos, target_position)
                            if partial_path and #partial_path > 0 then
                                current_path = partial_path
                            else
                                --console.print("Nenhum caminho encontrado")
                                return
                            end
                        end
                        last_path_calculation_time = current_time
                    end
                else
                    --console.print("Calculando caminho normal com A*")
                    local raw_path = a_star(player_pos, target_position, max_target_distance)
                    if raw_path then
                        current_path = smooth_path(raw_path, 0.5)
                    else
                        local partial_path = find_partial_path(player_pos, target_position)
                        if partial_path and #partial_path > 0 then
                            current_path = partial_path
                        else
                            --console.print("Nenhum caminho encontrado")
                            return
                        end
                    end
                    last_path_calculation_time = current_time
                end
            end
        end

        -- Move para o próximo ponto no caminho
        if current_path and #current_path > 0 then
            local next_point = current_path[path_index + 1]
            if next_point and not next_point:is_zero() then
                local dist_to_next = calculate_distance(player_pos, next_point)
                --console.print(string.format("Próximo ponto %d/%d - Distância: %.2f", 
                    --path_index, 
                    --#current_path,
                    --dist_to_next
                --))
                pathfinder.request_move(next_point)

                if calculate_distance(player_pos, next_point) < grid_size then
                    local direction = {
                        x = next_point:x() - player_pos:x(),
                        y = next_point:y() - player_pos:y()
                    }
                    last_movement_direction = direction
                    path_index = path_index + 1

                    if path_index > #current_path then
                        if is_stair(next_point) then
                            --console.print("Ponto de travessia alcançado, recalculando")
                            add_jump_point_to_cooldown(next_point)
                            current_path = {}
                            path_index = 1
                            last_path_calculation_time = 0
                        else
                            --console.print("Fim do caminho atual")
                            current_path = {}
                            path_index = 1
                            last_path_calculation_time = 0  -- Força recálculo imediato
                        end
                    end
                end
            end
        end

        if calculate_distance(player_pos, target_position) < 2 then
            console.print("Alvo alcançado")
            mark_area_as_explored(player_pos, exploration_radius)
            disable()
        end
    end
end

on_update(function()
    if enabled then
        if os.clock() - start_time < min_duration then
            check_walkable_area()
            local is_stuck = check_if_stuck()
            
            if is_stuck then
                --console.print("Personagem está preso. Encontrando novo alvo.")
                target_position = find_target(true)
                target_position = set_height_of_valid_position(target_position)
                last_move_time = os.time()
                current_path = {}
                path_index = 1
            end
            
            move_to_target()

            if current_path and #current_path > 0 and is_stair(current_path[path_index]) then
                --console.print("Acabamos de usar um ponto de travessia. Adicionando à lista de cooldown.")
                add_jump_point_to_cooldown(current_path[path_index])
                current_path = {}
                path_index = 1
                last_path_calculation_time = 0
            end
        else
            if is_target_reached() then
                disable()
            else
                check_walkable_area()
                local is_stuck = check_if_stuck()
                
                if is_stuck then
                    --console.print("Personagem está preso. Encontrando novo alvo.")
                    target_position = find_target(true)
                    target_position = set_height_of_valid_position(target_position)
                    last_move_time = os.time()
                    current_path = {}
                    path_index = 1
                end
                
                move_to_target()

                if current_path and #current_path > 0 and is_stair(current_path[path_index]) then
                    --console.print("Acabamos de usar um ponto de travessia. Adicionando à lista de cooldown.")
                    add_jump_point_to_cooldown(current_path[path_index])
                    current_path = {}
                    path_index = 1
                    last_path_calculation_time = 0
                end
            end
        end
    end
end)
       
local render_buffer = {}
local last_update_time = 0
local update_interval = 1/80  -- 30x per sec

local TARGET_COLOR = color_red(200)
local PATH_COLOR = color_green(200)
local CURRENT_PATH_COLOR = color_yellow(200)
local TARGET_SIZE = 25
local PATH_SIZE = 20

local function update_render_buffer()
    render_buffer = {}

    if target_position then
        table.insert(render_buffer, {
            text = "TARGET",
            position = target_position,
            size = TARGET_SIZE,
            color = TARGET_COLOR
        })
    end

    if current_path and #current_path > 0 then
        for i, point in ipairs(current_path) do
            table.insert(render_buffer, {
                text = "PATH",
                position = point,
                size = PATH_SIZE,
                color = (i == path_index) and CURRENT_PATH_COLOR or PATH_COLOR
            })
        end
    end
end

local function render_buffer_contents()
    for _, item in ipairs(render_buffer) do
        local render_position = item.position
        if not render_position.z then
            local player_pos = get_player_position()
            render_position = vec3:new(item.position.x, item.position.y, player_pos.z)
        end
        graphics.text_3d(item.text, render_position, item.size, item.color)
    end
end

on_update(function()
    local current_time = os.clock()
    if current_time - last_update_time >= update_interval then
        last_update_time = current_time
        update_render_buffer()
    end
end)

on_render(function()
    render_buffer_contents()
end)

return {
    enable = enable,
    disable = disable,
    set_target = set_target,
    is_target_reached = is_target_reached,
    calculate_distance = calculate_distance,
    is_enabled = is_enabled
}