local waypoint_loader = require("functions.waypoint_loader")
local explorer = require("data.explorer")

local Movement = {}

-- Estados
local States = {
    IDLE = "IDLE",
    MOVING = "MOVING",
    INTERACTING = "INTERACTING",
    EXPLORING = "EXPLORING",
    STUCK = "STUCK",
    EXPLORER_CONTROL = "EXPLORER_CONTROL"
}

-- Variáveis locais
local state = States.IDLE
local waypoints = {}
local current_waypoint_index = 1
local previous_player_pos = nil
local last_movement_time = 0
local stuck_check_time = 0
local force_move_cooldown = 0
local interaction_end_time = nil
local last_used_index = 1
local anti_stuck_enabled = true
local reverse_mode = false
local target_waypoint_index = nil
local explorer_timeout = 30  -- timeout em segundos
local explorer_start_time = 0
local is_interacting = false
local STUCK_CHECK_INTERVAL = 3 -- intervalo de verificação de stuck
local STUCK_DISTANCE_THRESHOLD = 1.0  --distancia para considerar o player preso
local last_explorer_position = nil
local last_explorer_check_time = nil
local explorer_stuck_time = 0
local MAX_EXPLORER_STUCK_TIME = 20 -- tempo maximo de stuck do explorer


-- Configuração
local stuck_threshold = 10
local move_threshold = 12

-- Funções auxiliares
local function get_distance(point)
    return get_player_position():squared_dist_to_ignore_z(point)
end

function Movement.reverse_waypoint_direction(target_index)
    reverse_mode = true
    target_waypoint_index = target_index
    console.print("Movimento reverso ativado até waypoint " .. target_index)
end

local function update_waypoint_index(is_maiden_plugin)
    if reverse_mode then
        if target_waypoint_index and current_waypoint_index > target_waypoint_index then
            current_waypoint_index = current_waypoint_index - 1
        else
            -- Chegamos ao waypoint alvo, ativar explorer para ir até o baú
            if ChestsInteractor and ChestsInteractor.get_missed_chest_position then
                local chest_position = ChestsInteractor.get_missed_chest_position()
                if chest_position then
                    explorer.set_target(chest_position)
                    explorer.enable()
                    state = States.EXPLORER_CONTROL
                    console.print("Alcançou waypoint alvo, movendo até o baú")
                    return
                end
            end
            
            -- Após interagir com o baú, isso será chamado para retomar o movimento
            reverse_mode = false
            target_waypoint_index = nil
            current_waypoint_index = current_waypoint_index + 1
            console.print("Retomando movimento forward a partir do índice " .. current_waypoint_index)
        end
    else
        current_waypoint_index = current_waypoint_index + 1
        if current_waypoint_index > #waypoints then
            if is_maiden_plugin then
                current_waypoint_index = #waypoints
                state = States.IDLE
                console.print("Reached the end of Maiden waypoints. Stopping movement.")
            else
                current_waypoint_index = 1
            end
        end
    end
end

function Movement.get_current_waypoint_index()
    return current_waypoint_index
end

local function check_explorer_stuck()
    if state ~= States.EXPLORER_CONTROL and state ~= States.EXPLORING then
        return false
    end

    local current_time = os.clock()
    
    if not last_explorer_check_time then
        last_explorer_check_time = current_time
        last_explorer_position = get_player_position()
        return false
    end
    
    if current_time - last_explorer_check_time >= STUCK_CHECK_INTERVAL then
        local current_position = get_player_position()
        local distance_moved = current_position:dist_to(last_explorer_position)
        
        if distance_moved < STUCK_DISTANCE_THRESHOLD then
            explorer_stuck_time = explorer_stuck_time + STUCK_CHECK_INTERVAL
            --console.print(string.format("Explorer possivelmente preso. Tempo: %.1f segundos", explorer_stuck_time))
            
            if explorer_stuck_time >= MAX_EXPLORER_STUCK_TIME then
                console.print("Local considerado inacessível")
                return true
            end
        else
            explorer_stuck_time = 0
        end
        
        last_explorer_position = current_position
        last_explorer_check_time = current_time
    end
    
    return false
end

-- Adicionar variável de controle global
local explorer_active = false

local function handle_stuck_player(current_waypoint, current_time, teleport)
    -- Se estiver em controle do explorer ou anti_stuck desativado, não faz nada
    if not anti_stuck_enabled or state == States.EXPLORER_CONTROL then
        return false
    end

    -- Se o explorer já está ativo, não reinicia
    if explorer.is_enabled() then
        return true
    end

    if current_time - stuck_check_time > stuck_threshold then
        --console.print("Player preso por " .. stuck_threshold .. " segundos")
        
        if current_waypoint then
            --console.print("Ativando explorer")
            explorer.set_target(current_waypoint)
            explorer.enable()
            state = States.EXPLORING
            return true
        end
    end
    return false
end

local function force_move_if_stuck(player_pos, current_time, current_waypoint)
    -- Se o jogador está parado por mais de 5 segundos, força o movimento
    if current_time - last_movement_time > 5 then
        local randomized_waypoint = waypoint_loader.randomize_waypoint(current_waypoint)
        pathfinder.force_move_raw(randomized_waypoint)
        last_movement_time = current_time
    end
    
    -- Atualiza a última posição se o jogador se moveu
    if not previous_player_pos or player_pos:squared_dist_to_ignore_z(previous_player_pos) > 3 then
        previous_player_pos = player_pos
        last_movement_time = current_time
    end
end

-- Manipuladores de estado
local function handle_idle_state()
    -- Não faz nada no estado ocioso
end

local function handle_moving_state(current_time, teleport, is_maiden_plugin)
    local current_waypoint = waypoints[current_waypoint_index]
    if current_waypoint then
        local player_pos = get_player_position()
        local distance = get_distance(current_waypoint)
        
        -- Verifica se estamos em modo reverso e alcançamos o waypoint alvo
        if reverse_mode and target_waypoint_index and current_waypoint_index <= target_waypoint_index then
            if distance < 2 then
                console.print("Chegou ao waypoint do baú alvo: " .. current_waypoint_index)
                if ChestsInteractor and ChestsInteractor.handle_missed_chest then
                    ChestsInteractor.handle_missed_chest()
                    return
                end
            end
        else
            -- Movimento normal (não reverso)
            if distance < 2 then
                update_waypoint_index(is_maiden_plugin)
                last_movement_time = current_time
                force_move_cooldown = 0
                previous_player_pos = player_pos
                stuck_check_time = current_time
                
                if is_maiden_plugin and state == States.IDLE then
                    return
                end
            else
                -- Primeiro tenta force_move
                force_move_if_stuck(player_pos, current_time, current_waypoint)
                
                -- Só depois verifica se precisa do explorer
                if handle_stuck_player(current_waypoint, current_time, teleport) then
                    state = States.EXPLORING
                    return
                end

                if current_time > force_move_cooldown then
                    local randomized_waypoint = waypoint_loader.randomize_waypoint(current_waypoint)
                    pathfinder.request_move(randomized_waypoint)
                end
            end
        end
    else
        console.print("Erro: Waypoint atual não encontrado")
        if is_maiden_plugin then
            state = States.IDLE
        else
            current_waypoint_index = 1
        end
    end
end

local function handle_interacting_state(current_time)
    if interaction_end_time and current_time > interaction_end_time then
        state = States.MOVING
    end
end

-- Modificar handle_exploring_state para manter o explorer ativo
local function handle_exploring_state()
    if explorer.is_target_reached() then
        explorer.disable()
        state = States.MOVING
    elseif not explorer.is_enabled() then
        state = States.MOVING
    end
end

-- Função principal de movimento
function Movement.pulse(plugin_enabled, loopEnabled, teleport, is_maiden_plugin)
    if not plugin_enabled then
        return
    end

    -- Se for plugin da maiden e já chegou ao último waypoint, não continua o movimento
    if is_maiden_plugin and current_waypoint_index >= #waypoints then
        state = States.IDLE
        return
    end

    if Movement.is_interacting() then
        if Movement.get_interaction_end_time() and os.clock() < Movement.get_interaction_end_time() then
            return  -- Não faz nada enquanto estiver em interação
        end
    end

    local current_time = os.clock()

    if (state == States.EXPLORER_CONTROL or state == States.EXPLORING) and check_explorer_stuck() then
        console.print("Explorer está preso, retornando ao movimento normal")
        explorer.disable()
        state = States.MOVING
        Movement.enable_anti_stuck()
        
        -- Reset das variáveis de stuck
        last_explorer_check_time = nil
        last_explorer_position = nil
        explorer_stuck_time = 0
        return
    end

    if state == States.IDLE then
        handle_idle_state()
    elseif state == States.MOVING then
        handle_moving_state(current_time, teleport, is_maiden_plugin)
    elseif state == States.INTERACTING then
        handle_interacting_state(current_time)
    elseif state == States.EXPLORING then
        handle_exploring_state()
    elseif state == States.EXPLORER_CONTROL then
        -- Não faz nada, deixa o explorer controlar o movimento
    end
end

-- Funções de configuração
function Movement.set_waypoints(new_waypoints)
    waypoints = new_waypoints
    if current_waypoint_index > #new_waypoints then
        current_waypoint_index = 1
    end
    state = States.MOVING
    
    -- Resetar todos os tempos
    local current_time = os.clock()
    last_movement_time = current_time
    stuck_check_time = current_time
    
    -- Forçar primeiro movimento
    local current_waypoint = waypoints[current_waypoint_index]
    if current_waypoint then
        local randomized_waypoint = waypoint_loader.randomize_waypoint(current_waypoint)
        pathfinder.force_move_raw(randomized_waypoint)
    end
end

function Movement.set_moving(moving)
    if moving then
        state = States.MOVING
    else
        state = States.IDLE
    end
end

function Movement.set_interacting(state_value)
    is_interacting = state_value
    if state_value then
        state = States.INTERACTING
    else
        state = States.MOVING
    end
end

function Movement.set_interaction_end_time(end_time)
    interaction_end_time = end_time
    state = States.INTERACTING
end

function Movement.reset(is_maiden_plugin)
    if is_maiden_plugin then
        current_waypoint_index = 1
    else
        current_waypoint_index = last_used_index
    end
    state = States.IDLE
    previous_player_pos = nil
    last_movement_time = 0
    stuck_check_time = os.clock()
    force_move_cooldown = 0
    interaction_end_time = nil
    last_explorer_check_time = nil
    last_explorer_position = nil
    explorer_stuck_time = 0
end

function Movement.save_last_index()
    last_used_index = current_waypoint_index
end

function Movement.get_last_index()
    return last_used_index
end

function Movement.set_move_threshold(value)
    move_threshold = value
end

function Movement.get_move_threshold()
    return move_threshold
end

function Movement.is_idle()
    return state == States.IDLE
end

function Movement.set_explorer_control(enabled)
    if enabled then
        state = States.EXPLORER_CONTROL
        explorer.enable()
        explorer_start_time = os.clock()  -- Inicia o timer
    else
        state = States.MOVING
        explorer.disable()
    end
end

function Movement.is_explorer_control()
    return state == States.EXPLORER_CONTROL
end

function Movement.disable_anti_stuck()
    anti_stuck_enabled = false
end

function Movement.enable_anti_stuck()
    anti_stuck_enabled = true
end

function Movement.is_reverse_mode()
    return reverse_mode
end

function Movement.get_waypoints()
    return waypoints
end

function Movement.is_interacting()
    return is_interacting
end

function Movement.clear_interaction_state()
    interaction_end_time = nil
    is_interacting = false
    state = States.MOVING
end

function Movement.get_interaction_end_time()
    return interaction_end_time
end

function Movement.reset_reverse_mode()
    reverse_mode = false
    target_waypoint_index = nil
    state = States.MOVING
    console.print("Modo reverso desativado, retomando movimento forward")
end

-- Nova função para trabalhar com ChestsInteractor
function Movement.handle_missed_chest(chest_position)
    explorer.set_target(chest_position)
    explorer.enable()
    state = States.EXPLORER_CONTROL
    console.print("Movendo para baú perdido")
end

-- Verifica se está no primeiro waypoint
function Movement.is_at_first_waypoint()
    local current_index = Movement.get_current_waypoint_index()
    local player_pos = get_local_player():get_position()
    local first_waypoint = Movement.get_waypoints()[1]
    
    return current_index == 1 and player_pos:dist_to(first_waypoint) < 20
end

-- Obtém distância até um waypoint específico
function Movement.get_distance_to_waypoint(waypoint_index)
    local waypoints = Movement.get_waypoints()
    local target_waypoint = waypoints[waypoint_index]
    if not target_waypoint then return math.huge end
    
    local player_pos = get_local_player():get_position()
    return player_pos:dist_to(target_waypoint)
end

-- Verifica se chegou ao waypoint alvo
function Movement.has_reached_target_waypoint(target_index)
    local current_index = Movement.get_current_waypoint_index()
    return current_index == target_index
end

-- Obtém direção atual do movimento
function Movement.get_current_direction()
    return Movement.is_reverse_mode() and "backward" or "forward"
end

-- Define direção do movimento baseado na string
function Movement.set_direction(direction)
    if direction == "backward" and not Movement.is_reverse_mode() then
        Movement.enable_reverse_mode()
    elseif direction == "forward" and Movement.is_reverse_mode() then
        Movement.disable_reverse_mode()
    end
end

return Movement