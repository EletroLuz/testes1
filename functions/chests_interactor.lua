local Movement = require("functions.movement")
local interactive_patterns = require("enums.interactive_patterns")
local explorer = require("data.explorer")
local PathCalculator = require("functions.path_calculator")
local RouteOptimizer = require("functions.route_optimizer")

local waypoints_visited = {}  -- Tabela para rastrear waypoints visitados
local total_waypoints = 0     -- Total de waypoints na rota
local ChestsInteractor = {}
local missed_chests = {}
local current_direction = "forward" -- "forward" ou "backward"
local last_waypoint_index = nil
local target_missed_chest = nil
local MAX_INTERACTION_ATTEMPTS = 5
local current_attempt = 0
local last_interaction_time = 0
local INTERACTION_COOLDOWN = 0.5 -- segundos entre tentativas
local check_start_time = nil
local cinders_before = nil
local VFX_CHECK_INITIAL_WAIT = 4  -- Tempo inicial de espera
local VFX_CHECK_TIMEOUT = 5       -- Tempo máximo de espera
local failed_attempts = 0
local MAX_TIME_STUCK_ON_CHEST = 30  -- segundos máximos tentando interagir com um baú
local MAX_ATTEMPTS_BEFORE_SKIP = 3   -- tentativas máximas antes de pular o baú
local last_chest_interaction_time = 0 -- tempo da última interação com o baú atual
local COMPLETION_THRESHOLD = 0.95 -- 95% dos waypoints
local MAX_TIME_TRYING_TO_REACH = 60  -- Tempo máximo tentando alcançar o baú
local MIN_MOVEMENT_DISTANCE = 1.0 -- Distancia Minima para considerar movimento
local STUCK_CHECK_INTERVAL = 15          -- Verificações mais espaçadas se esta preso no is stuck reaching chest
local MAX_STUCK_COUNT = 3               -- Ainda mais tentativas
local INTERACTION_RETRY_DISTANCE = 2     -- Nova constante para distância de retry

-- Variáveis de controle
local last_explorer_position = nil
local explorer_start_time = nil
local last_check_time = nil
local stuck_count = 0

local function find_valid_chest(objects, interactive_patterns)
    for _, obj in ipairs(objects) do
        if is_valid_chest(obj, interactive_patterns) and not is_blacklisted(obj) then
            local obj_name = obj:get_skin_name()
            console.print(string.format("Encontrado baú válido: %s", obj_name))
            return obj
        end
    end
    return nil
end

local function is_valid_chest(obj, interactive_patterns)
    if not obj then return false end
    
    local obj_name = obj:get_skin_name()
    if not obj_name then return false end
    
    -- Verifica se está na tabela de padrões interativos
    if not interactive_patterns[obj_name] then
        console.print(string.format("Objeto '%s' não está na tabela de padrões", obj_name))
        return false
    end
    
    return true
end

local function reset_chest_tracking()
    explorer_start_time = nil
    last_explorer_position = nil
    last_check_time = nil
    stuck_count = 0
    console.print("Estado de rastreamento do baú resetado")
end

local function is_stuck_reaching_chest()
    local current_time = os.clock()
    
    -- Inicialização
    if not explorer_start_time then
        explorer_start_time = current_time
        last_explorer_position = get_local_player():get_position()
        last_check_time = current_time
        stuck_count = 0
        console.print("Iniciando rastreamento do novo baú")
        return false
    end
    
    -- Período de graça inicial (15 segundos)
    if current_time - explorer_start_time < 15 then
        return false
    end
    
    -- Verifica se está próximo o suficiente para tentar interagir
    if targetObject then
        local player_pos = get_local_player():get_position()
        local target_pos = targetObject:get_position()
        local distance = player_pos:dist_to(target_pos)
        
        if distance <= INTERACTION_RETRY_DISTANCE then
            console.print(string.format("Próximo do baú (%.2f metros) - Tentando interagir", distance))
            return false
        end
    end
    
    -- Verifica movimento periodicamente
    if current_time - last_check_time >= STUCK_CHECK_INTERVAL then
        local current_position = get_local_player():get_position()
        local distance_moved = current_position:dist_to(last_explorer_position)
        
        console.print(string.format(
            "Progresso até o baú:\n" ..
            "- Distância movida: %.2f\n" ..
            "- Tempo decorrido: %.1f/%.1f segundos\n" ..
            "- Tentativas: %d/%d",
            distance_moved,
            current_time - explorer_start_time,
            MAX_TIME_TRYING_TO_REACH,
            stuck_count,
            MAX_STUCK_COUNT
        ))
        
        -- Atualiza posição e tempo
        last_explorer_position = current_position
        last_check_time = current_time
        
        if distance_moved < MIN_MOVEMENT_DISTANCE then
            stuck_count = stuck_count + 1
            console.print(string.format("Aviso: Movimento limitado detectado (%d/%d)", 
                stuck_count, MAX_STUCK_COUNT))
            
            -- Tenta reposicionar se estiver próximo
            if targetObject then
                local distance_to_chest = current_position:dist_to(targetObject:get_position())
                if distance_to_chest <= INTERACTION_RETRY_DISTANCE then
                    console.print("Próximo do baú - Tentando reposicionar")
                    return false
                end
            end
            
            if stuck_count >= MAX_STUCK_COUNT then
                console.print("Desistindo após múltiplas tentativas sem progresso")
                reset_chest_tracking()
                return true
            end
        else
            if stuck_count > 0 then
                console.print("Movimento detectado - resetando contador")
                stuck_count = 0
            end
        end
    end
    
    return false
end

local function should_return_to_missed_chests()
    local current_cinders = get_helltide_coin_cinders()
    local player_pos = get_local_player():get_position()
    local MAX_RETURN_DISTANCE = 10
    
    --console.print("Verificando baús perdidos. Cinders atuais: " .. current_cinders)
    
    for key, chest in pairs(missed_chests) do
        local distance = player_pos:dist_to(chest.position)
        console.print(string.format("Baú perdido: %s requer %d cinders (distância: %.2f metros)", 
            chest.name, chest.required_cinders, distance))
            
        if current_cinders >= chest.required_cinders and distance <= MAX_RETURN_DISTANCE then
            console.print("Temos cinders suficientes e distância adequada para retornar!")
            return true
        end
    end
    
    if next(missed_chests) == nil then
        --console.print("Nenhum baú perdido registrado")
    end
    return false
end

local function get_nearest_missed_chest()
    local player_pos = get_local_player():get_position()
    local nearest_chest = nil
    local min_distance = math.huge
    local current_cinders = get_helltide_coin_cinders()
    
    for key, chest in pairs(missed_chests) do
        if current_cinders >= chest.required_cinders then
            local distance = player_pos:dist_to(chest.position)
            if distance < min_distance then
                min_distance = distance
                nearest_chest = chest
            end
        end
    end
    
    return nearest_chest
end

function ChestsInteractor.check_missed_chests()
    if should_return_to_missed_chests() and current_direction == "forward" then
        local nearest_chest = get_nearest_missed_chest()
        if nearest_chest then
            target_missed_chest = nearest_chest
            current_direction = "backward"
            Movement.reverse_waypoint_direction(nearest_chest.waypoint_index)
            console.print("Retornando para baú perdido no waypoint " .. nearest_chest.waypoint_index)
            return true
        end
    end
    return false
end

-- Colors
local color_red = color.new(255, 0, 0)
local color_green = color.new(0, 255, 0)
local color_white = color.new(255, 255, 255, 255)

-- Estados
local States = {
    IDLE = "IDLE",
    MOVING = "MOVING",
    INTERACTING = "INTERACTING",
    MOVING_TO_MISSED_CHEST = "MOVING_TO_MISSED_CHEST",
    VERIFYING_CHEST_OPEN = "VERIFYING_CHEST_OPEN"
}

-- Variáveis de estado
local currentState = States.IDLE
local targetObject = nil
local interactedObjects = {}
local expiration_time = 0
local permanent_blacklist = {}
local temporary_blacklist = {}
local temporary_blacklist_duration = 60 -- 1 minuto em segundos
local max_attempts = 5
local max_return_attempts = 2
local vfx_check_start_time = 0
local vfx_check_duration = 8
local successful_chests_opened = 0
local state_start_time = 0
local max_state_duration = 30
local max_interaction_distance = 2
local last_known_chest_position = nil
local max_chest_search_attempts = 5
local chest_search_attempts = 0
local cinders_before_interaction = 0

-- Nova tabela para rastrear tentativas por baú
local chest_attempts = {}
local current_chest_key = nil

local function increment_successful_chests()
    successful_chests_opened = successful_chests_opened + 1
    console.print("Total de baús Helltide abertos: " .. successful_chests_opened)
end

-- Funções auxiliares
local function get_chest_key(obj)
    if not obj then return nil end
    if type(obj) == "table" and obj.position then
        -- Se for uma tabela com posição (como target_missed_chest)
        local pos = obj.position
        return string.format("%s_%.2f_%.2f_%.2f", obj.name or "unknown", pos:x(), pos:y(), pos:z())
    elseif type(obj.get_skin_name) == "function" and type(obj.get_position) == "function" then
        -- Se for um objeto do jogo
        local obj_name = obj:get_skin_name()
        local obj_pos = obj:get_position()
        return string.format("%s_%.2f_%.2f_%.2f", obj_name, obj_pos:x(), obj_pos:y(), obj_pos:z())
    end
    return nil
end

local function init_waypoint_tracking()
    waypoints_visited = {}
    total_waypoints = #Movement.get_waypoints()
    console.print(string.format("Iniciando rastreamento: %d waypoints totais", total_waypoints))
end

local function count_visited_waypoints()
    local count = 0
    for _ in pairs(waypoints_visited) do
        count = count + 1
    end
    return count
end

local function has_visited_all_waypoints()
    local visited_count = count_visited_waypoints()
    local threshold = math.floor(total_waypoints * COMPLETION_THRESHOLD)
    return visited_count >= threshold
end

local function count_missed_chests()
    local count = 0
    for _ in pairs(missed_chests) do
        count = count + 1
    end
    return count
end

-- Após as declarações de variáveis, adicione:
local function clear_chest_state()
    console.print("Limpando estado do baú atual")
    
    -- Remove o baú atual da lista de missed_chests
    if targetObject then
        local chest_key = get_chest_key(targetObject)
        if chest_key and missed_chests[chest_key] then
            missed_chests[chest_key] = nil
            console.print("Baú atual removido da lista de missed_chests")
        end
    end
    
    -- Remove o baú alvo da lista de missed_chests
    if target_missed_chest then
        local chest_key = get_chest_key(target_missed_chest)
        if chest_key and missed_chests[chest_key] then
            missed_chests[chest_key] = nil
            console.print("Baú alvo removido da lista de missed_chests")
        end
    end
    
    target_missed_chest = nil
    current_direction = "forward"
    Movement.reset_reverse_mode()
    Movement.set_moving(true)
    Movement.set_explorer_control(false)
    Movement.enable_anti_stuck()
    explorer.disable()
    currentState = States.IDLE
    
    console.print("Estado do baú atual limpo com sucesso")
end

-- Função para obter o próximo custo do baú
local function get_next_cost(obj_name, current_cinders)
    local costs = interactive_patterns[obj_name]
    if type(costs) ~= "table" then 
        return nil 
    end
    
    -- Ordena os custos em ordem crescente
    local sorted_costs = {}
    for _, cost in ipairs(costs) do
        table.insert(sorted_costs, cost)
    end
    table.sort(sorted_costs)
    
    -- Procura o próximo custo maior que os cinders atuais
    for _, cost in ipairs(sorted_costs) do
        if cost > current_cinders then
            console.print(string.format("Próximo custo para %s: %d cinders", obj_name, cost))
            return cost
        end
    end
    
    console.print(string.format("Não há próximo custo para %s (cinders atuais: %d)", obj_name, current_cinders))
    return nil
end

function ChestsInteractor.get_missed_chest_position()
    if target_missed_chest then
        return target_missed_chest.position
    end
    return nil
end

function ChestsInteractor.update_cinders()
    local current_cinders = get_helltide_coin_cinders()
    -- Aqui você pode adicionar lógica adicional se necessário
    -- Por exemplo, atualizar uma variável global ou fazer algo com o valor atual de cinders
    --console.print("Cinders atualizados: " .. current_cinders)
end

local function get_required_cinders(obj_name)
    local required = interactive_patterns[obj_name]
    if type(required) == "table" then
        if #required > 0 then
            return math.max(unpack(required))
        else
            console.print("Aviso: Tabela vazia para " .. obj_name)
            return 0
        end
    elseif type(required) == "number" then
        return required
    else
        console.print("Aviso: Padrão não reconhecido para " .. obj_name)
        return 0
    end
end

-- Adicionar constante para duração da pausa
local CHEST_INTERACTION_DURATION = 5  -- segundos

local function pause_movement_for_interaction()
    Movement.set_moving(false)  -- Para o movimento
    Movement.set_explorer_control(false)  -- Desativa controle do explorer
    Movement.disable_anti_stuck()  -- Desativa anti-stuck
    explorer.disable()  -- Desativa o explorer
    Movement.set_interaction_end_time(os.clock() + CHEST_INTERACTION_DURATION)  -- Define tempo de pausa
    Movement.set_interacting(true)  -- Sinaliza que está em interação
end

-- Modificar a função register_missed_chest para incluir todos os custos
local function register_missed_chest(obj, waypoint_index)
    if not obj then
        console.print("Erro: Objeto nulo passado para register_missed_chest")
        return
    end

    local obj_name = obj:get_skin_name()
    if not obj_name then
        console.print("Erro: Nome do objeto é nulo")
        return
    end

    local current_cinders = get_helltide_coin_cinders()
    local next_cost = get_next_cost(obj_name, current_cinders)
    
    if not next_cost then
        console.print("Não há próximo custo disponível para " .. obj_name)
        return
    end

    local chest_key = get_chest_key(obj)
    if not chest_key then
        console.print("Erro: Não foi possível gerar a chave do baú")
        return
    end
    
    if not missed_chests[chest_key] then
        local obj_pos = obj:get_position()
        if not obj_pos then
            console.print("Erro: Não foi possível obter a posição do objeto")
            return
        end

        local current_waypoint_index = Movement.get_current_waypoint_index()
        missed_chests[chest_key] = {
            name = obj_name,
            position = obj_pos,
            waypoint_index = waypoint_index or current_waypoint_index,
            required_cinders = next_cost,
            timestamp = os.clock()
        }
        
        console.print(string.format("Registrado baú perdido em waypoint %d. Próximo custo: %d cinders", 
            missed_chests[chest_key].waypoint_index, next_cost))
    end
end

local function add_to_permanent_blacklist(obj)
    if not obj then return end
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()
    table.insert(permanent_blacklist, {name = obj_name, position = obj_pos})
end

-- Mova esta função para ANTES de handle_after_interaction
local function add_to_temporary_blacklist(obj)
    if not obj then return end
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()
    local expiration_time = os.clock() + temporary_blacklist_duration
    table.insert(temporary_blacklist, {name = obj_name, position = obj_pos, expires_at = expiration_time})
end

-- Modificar a função que lida com a interação após VFX
local function handle_after_interaction(obj)
    if not obj then return end
    
    -- Adiciona ao blacklist permanente se gastou cinders
    local current_cinders = get_helltide_coin_cinders()
    if cinders_before_interaction > current_cinders then
        add_to_permanent_blacklist(obj)
        return
    end
    
    -- Se não gastou cinders, verifica próximo custo
    local obj_name = obj:get_skin_name()
    local next_cost = get_next_cost(obj_name, current_cinders)
    
    if next_cost then
        console.print(string.format("Baú tem próximo custo de %d cinders, registrando como missed chest", next_cost))
        register_missed_chest(obj)
    end
    
    add_to_temporary_blacklist(obj)
end

local function is_player_too_far_from_target()
    if not targetObject then return true end
    local player = get_local_player()
    if not player then return true end
    local player_pos = player:get_position()
    local target_pos = targetObject:get_position()
    return player_pos:dist_to(target_pos) > max_interaction_distance
end

local function has_enough_cinders(obj_name)
    local current_cinders = get_helltide_coin_cinders()
    local required_cinders = interactive_patterns[obj_name]
    
    if type(required_cinders) == "table" then
        -- Ordena os custos em ordem crescente
        local sorted_costs = {}
        for _, cost in ipairs(required_cinders) do
            table.insert(sorted_costs, cost)
        end
        table.sort(sorted_costs)
        
        -- Verifica o menor custo que podemos pagar
        for _, cost in ipairs(sorted_costs) do
            if current_cinders >= cost then
                return true
            end
        end
    elseif type(required_cinders) == "number" then
        if current_cinders >= required_cinders then
            return true
        end
    end
    
    return false
end

local function isObjectInteractable(obj, interactive_patterns, current_waypoint_index)
    if not obj then return false end
    local obj_name = obj:get_skin_name()
    local is_interactable = obj:is_interactable()
    local has_cinders = has_enough_cinders(obj_name)
    
    -- Debug temporário
    --if is_interactable then
        --console.print(string.format(
            --"Objeto verificado: %s\n" ..
            --"- Na tabela de padrões: %s\n" ..
            --"- Tem cinders: %s\n" ..
            --"- Já interagido: %s",
            --obj_name,
            --interactive_patterns[obj_name] and "Sim" or "Não",
            --has_cinders and "Sim" or "Não",
            --interactedObjects[obj_name] and "Sim" or "Não"
        --))
    --end
    
    if not has_cinders and is_interactable and interactive_patterns[obj_name] then
        register_missed_chest(obj, current_waypoint_index)
    end
    
    return interactive_patterns[obj_name] and 
           (not interactedObjects[obj_name] or os.clock() > interactedObjects[obj_name]) and
           has_cinders and
           is_interactable
end

local function is_blacklisted(obj)
    if not obj then return false end
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()
    
    -- Verifica blacklist permanente
    for _, blacklisted_obj in ipairs(permanent_blacklist) do
        if blacklisted_obj.name == obj_name and blacklisted_obj.position:dist_to(obj_pos) < 0.1 then
            return true
        end
    end
    
    -- Verifica blacklist temporária
    local current_time = os.clock()
    for i, blacklisted_obj in ipairs(temporary_blacklist) do
        if blacklisted_obj.name == obj_name and blacklisted_obj.position:dist_to(obj_pos) < 0.1 then
            if current_time < blacklisted_obj.expires_at then
                return true
            else
                table.remove(temporary_blacklist, i)
                return false
            end
        end
    end
    
    return false
end

local function increment_chest_attempts()
    if current_chest_key then
        chest_attempts[current_chest_key] = (chest_attempts[current_chest_key] or 0) + 1
        return chest_attempts[current_chest_key]
    end
    return 0
end

local function get_chest_attempts()
    return current_chest_key and chest_attempts[current_chest_key] or 0
end

local function reset_chest_attempts()
    if current_chest_key then
        chest_attempts[current_chest_key] = nil
    end
end

-- Função para verificar se o baú foi aberto
local function check_chest_opened()
    local success_by_actor = false
    local success_by_cinders = false
    
    -- Verificação 1: Pelo nome do ator
    local actors = actors_manager.get_all_actors()
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name == "Hell_Prop_Chest_Helltide_01_Client_Dyn" then
            console.print("Baú aberto com sucesso (detectado pelo ator)")
            success_by_actor = true
            break
        end
    end
    
    -- Verificação 2: Pela diferença de cinders
    local current_cinders = get_helltide_coin_cinders()
    if cinders_before_interaction and current_cinders < cinders_before_interaction then
        console.print(string.format(
            "Baú aberto com sucesso (cinders: %d -> %d)", 
            cinders_before_interaction, 
            current_cinders
        ))
        success_by_cinders = true
    end
    
    -- Se qualquer uma das verificações for bem-sucedida
    if success_by_actor or success_by_cinders then
        successful_chests_opened = successful_chests_opened + 1
        console.print("Total de baús abertos: " .. successful_chests_opened)
        return true
    end
    
    return false
end

local function resume_waypoint_movement()
    -- NOVO: Verifica se ainda está no tempo de pausa
    if Movement.get_interaction_end_time() and os.clock() < Movement.get_interaction_end_time() then
        return false  -- Não retoma o movimento se ainda estiver no tempo de pausa
    end

    Movement.set_explorer_control(false)
    Movement.set_moving(true)
    return true
end

local function reset_state()
    -- NOVO: Verifica se ainda está no tempo de pausa
    if Movement.get_interaction_end_time() and os.clock() < Movement.get_interaction_end_time() then
        return  -- Mantém o estado atual se ainda estiver no tempo de pausa
    end

    targetObject = nil
    last_known_chest_position = nil
    chest_search_attempts = 0
    current_attempt = 0
    last_interaction_time = 0
    last_chest_interaction_time = 0  -- Reseta o tempo da última interação
    Movement.set_interacting(false)
    explorer.disable()
    Movement.set_explorer_control(false)
    Movement.enable_anti_stuck()
    state_start_time = os.clock()
    resume_waypoint_movement()
end

local function move_to_object(obj)
    -- Verifica se está há muito tempo tentando interagir com o mesmo baú
    if last_chest_interaction_time > 0 and os.clock() - last_chest_interaction_time > MAX_TIME_STUCK_ON_CHEST then
        console.print("Tempo máximo excedido tentando interagir com o baú, desistindo...")
        add_to_temporary_blacklist(targetObject)
        reset_state()
        return States.IDLE
    end

    if not obj then 
        if last_known_chest_position then
            explorer.set_target(last_known_chest_position)
            explorer.enable()
            Movement.set_explorer_control(true)
            Movement.disable_anti_stuck()
            chest_search_attempts = chest_search_attempts + 1
            
            -- Verifica número de tentativas
            if chest_search_attempts >= MAX_ATTEMPTS_BEFORE_SKIP then
                console.print("Máximo de tentativas atingido, desistindo do baú...")
                add_to_temporary_blacklist(targetObject)
                reset_state()
                return States.IDLE
            end
            
            console.print("Voltando para o baú. Tentativa atual: " .. get_chest_attempts())
            return States.MOVING
        else
            reset_state()
            return States.IDLE
        end
    end
    
    local obj_pos = obj:get_position()
    last_known_chest_position = obj_pos
    explorer.set_target(obj_pos)
    explorer.enable()
    Movement.set_explorer_control(true)
    Movement.disable_anti_stuck()
    chest_search_attempts = 0
    last_chest_interaction_time = os.clock()  -- Atualiza o tempo da última interação
    console.print("Movendo-se para o baú. Tentativa atual: " .. get_chest_attempts())
    return States.MOVING
end

-- Adicionar nova função para gerenciar a interação com baú perdido
function ChestsInteractor.handle_missed_chest()
    if not target_missed_chest then
        console.print("Erro: Nenhum baú alvo definido")
        return
    end

    -- Salva uma cópia das informações do baú
    local saved_chest = {
        position = target_missed_chest.position,
        name = target_missed_chest.name,
        required_cinders = target_missed_chest.required_cinders,
        waypoint_index = target_missed_chest.waypoint_index
    }
    
    console.print("Iniciando processo de interação com baú perdido")
    Movement.set_explorer_control(true)
    explorer.set_target(saved_chest.position)
    explorer.enable()
    currentState = States.MOVING_TO_MISSED_CHEST
    
    -- Atualiza o target_missed_chest com a cópia
    target_missed_chest = saved_chest
end

local stateFunctions = {
    [States.IDLE] = function(objects, interactive_patterns)
        reset_state()
        for _, obj in ipairs(objects) do
            if isObjectInteractable(obj, interactive_patterns) and not is_blacklisted(obj) then
                local new_chest_key = get_chest_key(obj)
                if new_chest_key ~= current_chest_key then
                    current_chest_key = new_chest_key
                    reset_chest_tracking()  -- Reseta o controle de stuck do bau
                    reset_chest_attempts()
                    console.print("Novo baú selecionado. Contador de tentativas resetado.")
                end
                targetObject = obj
                return move_to_object(obj)
            end
        end
        return States.IDLE
    end,

    [States.MOVING] = function(objects, interactive_patterns)
        if not targetObject then
            console.print("Alvo perdido durante movimento")
            return States.IDLE
        end

        if not is_valid_chest(targetObject, interactive_patterns) then
            console.print("Alvo atual não é um baú válido - resetando")
            targetObject = nil
            return States.IDLE
        end
        
        local player = get_local_player()
        if not player then return States.IDLE end
        
        local distance = player:get_position():dist_to(targetObject:get_position())
        --console.print(string.format("Distância atual até o baú: %.2f metros", distance))
        
        -- Se está próximo, tenta interagir mesmo que pareça preso
        if distance <= max_interaction_distance then
            console.print("Alcançou distância de interação - Preparando interação")
            pause_movement_for_interaction()
            return States.INTERACTING
        end
        
        -- Só verifica se está preso se estiver longe do baú
        if Movement.is_explorer_control() and is_stuck_reaching_chest() and distance > INTERACTION_RETRY_DISTANCE then
            console.print("Detectado que está preso longe do baú - desistindo")
            add_to_temporary_blacklist(targetObject)
            reset_chest_tracking()
            
            targetObject = nil
            Movement.set_moving(true)
            Movement.set_explorer_control(false)
            Movement.enable_anti_stuck()
            explorer.disable()
            
            return States.IDLE
        end
        
        return States.MOVING
    end,

    [States.INTERACTING] = function()
        if not targetObject or not targetObject:is_interactable() then 
            console.print("Objeto alvo não interativo")
            targetObject = nil
            if target_missed_chest then
                clear_chest_state()
                return States.IDLE
            end
            return move_to_object(targetObject)
        end
    
        if is_player_too_far_from_target() then
            console.print("Jogador muito longe do alvo")
            return move_to_object(targetObject)
        end
    
        -- Adiciona verificação de cinders antes da interação
        cinders_before_interaction = get_helltide_coin_cinders()
        console.print("Cinders antes da interação: " .. cinders_before_interaction)
    
        pause_movement_for_interaction()
        Movement.set_interacting(true)
        
        local obj_name = targetObject:get_skin_name()
        interactedObjects[obj_name] = os.clock() + expiration_time
        interact_object(targetObject)
        console.print("Interagindo com " .. obj_name)
        
        vfx_check_start_time = os.clock()
        console.print("=== DEBUG INTERACTING ===")
        console.print("vfx_check_start_time definido como: " .. vfx_check_start_time)
        return States.VERIFYING_CHEST_OPEN
    end,

    [States.VERIFYING_CHEST_OPEN] = function()
        if not vfx_check_start_time then
            vfx_check_start_time = os.clock()
            cinders_before_interaction = get_helltide_coin_cinders() -- Salva cinders atuais
            return States.VERIFYING_CHEST_OPEN
        end
    
        local current_time = os.clock()
        local elapsed_time = current_time - vfx_check_start_time
        
        -- Verifica se os cinders mudaram
        local current_cinders = get_helltide_coin_cinders()
        if current_cinders < cinders_before_interaction then
            console.print("Cinders gastos! Baú aberto com sucesso")
            
            -- Pausa após sucesso
            Movement.set_moving(false)
            Movement.set_explorer_control(false)
            Movement.disable_anti_stuck()
            explorer.disable()
            Movement.set_interaction_end_time(os.clock() + CHEST_INTERACTION_DURATION)
            Movement.set_interacting(true)
            
            -- Remove o baú da lista de missed_chests se existir
            if targetObject then
                local chest_key = get_chest_key(targetObject)
                if chest_key and missed_chests[chest_key] then
                    missed_chests[chest_key] = nil
                    console.print("Baú removido da lista de missed_chests")
                end
                add_to_permanent_blacklist(targetObject)
            end
            
            if target_missed_chest then
                clear_chest_state()
            end

            -- Incrementa apenas uma vez
            successful_chests_opened = successful_chests_opened + 1
            
            -- Limpa o estado
            failed_attempts = 0
            vfx_check_start_time = nil
            cinders_before_interaction = nil
            targetObject = nil
            
            -- Mantém o estado até o fim da pausa
            if Movement.get_interaction_end_time() and os.clock() < Movement.get_interaction_end_time() then
                return States.INTERACTING
            end

            -- Reseta tudo e volta para IDLE
            Movement.set_interacting(false)
            Movement.set_moving(true)
            Movement.enable_anti_stuck()
            Movement.set_interacting(false)
            return States.IDLE
        end
    
        -- Verifica timeout
        if elapsed_time > vfx_check_duration then
            failed_attempts = failed_attempts + 1
            console.print(string.format(
                "Tentativa %d falhou - Cinders não mudaram (Antes: %d, Atual: %d)",
                failed_attempts,
                cinders_before_interaction,
                current_cinders
            ))
            
            if failed_attempts >= max_attempts then
                console.print("Máximo de tentativas atingido")
                
                if targetObject then
                    local obj_name = targetObject:get_skin_name()
                    
                    -- Adiciona ao blacklist temporário
                    add_to_temporary_blacklist(targetObject)
                    
                    -- Verifica se tem próximo custo
                    local next_cost = get_next_cost(obj_name, current_cinders)
                    if next_cost then
                        console.print(string.format(
                            "Baú %s tem próximo custo: %d cinders",
                            obj_name,
                            next_cost
                        ))
                    else
                        console.print(string.format(
                            "Baú %s não tem custos maiores. Mantendo na lista para tentar novamente depois.",
                            obj_name
                        ))
                    end
                    
                    -- Registra como missed chest em ambos os casos
                    register_missed_chest(targetObject, Movement.get_current_waypoint_index())
                end

                -- Limpa o estado completamente
                failed_attempts = 0
                vfx_check_start_time = nil
                cinders_before_interaction = nil
                targetObject = nil
                
                -- Pausa após falha máxima
                Movement.set_moving(false)
                Movement.set_explorer_control(false)
                Movement.disable_anti_stuck()
                explorer.disable()
                Movement.set_interaction_end_time(os.clock() + CHEST_INTERACTION_DURATION)
                Movement.set_interacting(true)

                -- Limpa o estado
                failed_attempts = 0
                vfx_check_start_time = nil
                cinders_before_interaction = nil
                
                -- Mantém o estado até o fim da pausa
                if Movement.get_interaction_end_time() and os.clock() < Movement.get_interaction_end_time() then
                    return States.INTERACTING
                end
                
                -- Reseta tudo e volta para IDLE
                Movement.set_interacting(false)
                Movement.set_moving(true)
                Movement.enable_anti_stuck()
                return States.IDLE
            else
                -- Pausa antes de tentar novamente
                Movement.set_moving(false)
                Movement.set_explorer_control(false)
                Movement.disable_anti_stuck()
                explorer.disable()
                Movement.set_interaction_end_time(os.clock() + CHEST_INTERACTION_DURATION)
                Movement.set_interacting(true)
                
                -- Mantém o estado até o fim da pausa
                if Movement.get_interaction_end_time() and os.clock() < Movement.get_interaction_end_time() then
                    return States.INTERACTING
                end
                
                -- Tenta interagir novamente
                if targetObject and targetObject:is_interactable() then
                    vfx_check_start_time = nil  -- Reset para nova verificação
                    cinders_before_interaction = current_cinders  -- Atualiza cinders antes da nova tentativa
                    interact_object(targetObject)
                    console.print("Tentando interagir novamente com o baú")
                    return States.VERIFYING_CHEST_OPEN
                end

                -- Se não conseguir interagir, volta para movimento
                Movement.set_interacting(false)
                Movement.set_moving(true)
                Movement.enable_anti_stuck()
                return move_to_object(targetObject)
            end
        end
    
        return States.VERIFYING_CHEST_OPEN
    end,

    [States.MOVING_TO_MISSED_CHEST] = function(objects, interactive_patterns)
        if not target_missed_chest then
            console.print("Erro: Perdeu referência do baú alvo")
            clear_chest_state()  -- Adicionado aqui
            reset_state()
            return States.IDLE
        end
    
        -- Verifica se está preso
        if Movement.is_explorer_control() and Movement.is_stuck() then
            console.print("Local do baú inacessível, removendo da lista")
            clear_chest_state()  -- Adicionado aqui
            current_attempt = 0
            return States.IDLE
        end
    
        if explorer.is_target_reached() then
            console.print("Explorer alcançou o baú perdido, procurando objeto")
            
            -- Verifica cooldown entre tentativas
            if os.clock() - last_interaction_time < INTERACTION_COOLDOWN then
                return States.MOVING_TO_MISSED_CHEST
            end
            
            -- Procura o objeto do baú nas proximidades
            for _, obj in ipairs(objects) do
                if obj:get_position():dist_to(target_missed_chest.position) < 3.0 then
                    console.print(string.format("Tentativa %d/%d de interagir com o baú", 
                        current_attempt + 1, MAX_INTERACTION_ATTEMPTS))
                    
                    targetObject = obj
                    last_interaction_time = os.clock()
                    
                    if current_attempt >= MAX_INTERACTION_ATTEMPTS then
                        console.print("Máximo de tentativas atingido, removendo baú")
                        clear_chest_state()  -- Adicionado aqui
                        current_attempt = 0
                        return States.IDLE
                    end
                    
                    current_attempt = current_attempt + 1
                    pause_movement_for_interaction()
                    return States.INTERACTING
                end
            end
            
            -- Se não encontrou o baú, tenta reposicionar
            explorer.set_target(target_missed_chest.position:add(vec3:new(1, 0, 1)))
            return States.MOVING_TO_MISSED_CHEST
        end
        
        return States.MOVING_TO_MISSED_CHEST
    end
}

function ChestsInteractor.reset_after_reaching_missed_chest()
    console.print("Resetando estado e retomando movimento forward")
    current_direction = "forward"
    Movement.reset_reverse_mode()
    Movement.set_moving(true)
    
    if target_missed_chest then
        local chest_key = get_chest_key(target_missed_chest)
        if chest_key then
            missed_chests[chest_key] = nil
            console.print("Removido baú perdido da lista")
        end
    end
    
    target_missed_chest = nil
    Movement.set_explorer_control(false)  -- Desativa o explorer
    Movement.enable_anti_stuck()  -- Reativa o anti-stuck
end

function render_waypoints_3d()
    local waypoints = Movement.get_waypoints()
    local current_index = Movement.get_current_waypoint_index()

    for _, chest in pairs(missed_chests) do
        local target_waypoint = waypoints[chest.waypoint_index]
        if target_waypoint then
            graphics.circle_3d(target_waypoint, 5, color.new(255, 0, 0))
            graphics.text_3d("Baú Perdido", target_waypoint, 20, color_green)
        else
            console.print("Waypoint não encontrado para baú perdido no índice " .. chest.waypoint_index)
        end
    end

    if Movement.is_reverse_mode() and target_missed_chest then
        local target_index = target_missed_chest.waypoint_index
        
        for i = current_index, target_index, -1 do
            local waypoint = waypoints[i]
            if waypoint then
                graphics.text_3d("Backward", waypoint, 20, color_red)
            end
        end
    else
        for i = current_index, math.min(current_index + 5, #waypoints) do
            local waypoint = waypoints[i]
            if waypoint then
                graphics.text_3d("Forward", waypoint, 20, color_green)
            end
        end
    end
end

local retry_count = 0
local max_retries = math.huge

-- Adicione esta função ao seu ChestsInteractor
local function handle_player_too_far()
    if targetObject and is_player_too_far_from_target() and currentState ~= States.IDLE then
        retry_count = retry_count + 1
        --console.print("Tentativa " .. retry_count .. " de se aproximar do alvo")
        local target_pos = targetObject:get_position()
        explorer.set_target(target_pos)
        explorer.enable()
        currentState = States.MOVING
        return true
    else
        retry_count = 0
        return true
    end
end

-- Função principal de interação
function ChestsInteractor.interactWithObjects(doorsEnabled, interactive_patterns, current_waypoint_index)
    local local_player = get_local_player()
    if not local_player then return end
    
    -- Obter objetos do jogo
    local objects = actors_manager.get_ally_actors()
    if not objects then
        objects = {} 
    end
    
    -- Inicializa rastreamento se necessário
    if total_waypoints == 0 then
        init_waypoint_tracking()
    end
    
    -- Durante o loop inicial
    if not RouteOptimizer.has_completed_initial_loop() then
        -- Registra waypoint atual
        if current_waypoint_index then
            if not waypoints_visited[current_waypoint_index] then
                waypoints_visited[current_waypoint_index] = true
            end
        end
        
        local visited_count = count_visited_waypoints()
        -- Considera o loop completo se atingir 95% dos waypoints
        local completion_threshold = math.floor(total_waypoints * 0.95)
        
        -- Verifica se completou o loop inicial com threshold
        if visited_count >= completion_threshold and RouteOptimizer.is_in_city() then
            console.print(string.format(
                "Loop considerado completo (%d/%d waypoints - %.1f%%)",
                visited_count,
                total_waypoints,
                (visited_count/total_waypoints) * 100
            ))
            
            RouteOptimizer.complete_initial_loop()
            console.print(string.format(
                "Loop inicial completo! Baús perdidos: %d",
                count_missed_chests()
            ))
            
            -- Planeja rota otimizada se houver baús perdidos
            if next(missed_chests) then
                if RouteOptimizer.plan_optimized_route(missed_chests) then
                    console.print("Rota otimizada planejada!")
                end
            end
        end
        
        -- Continua com interação normal durante loop inicial
        local newState = stateFunctions[currentState](objects, interactive_patterns)
        if newState ~= currentState then
            currentState = newState
        end
        return
    end
    
    -- Se já completou o loop inicial, continua com a lógica normal
    if Movement.is_interacting() then
        if os.clock() < Movement.get_interaction_end_time() then
            return -- Ainda está no tempo de pausa
        else
            Movement.set_interacting(false)
            Movement.set_moving(true)
            Movement.set_explorer_control(false)
            Movement.enable_anti_stuck()
            explorer.disable()
        end
    end
    
    -- Verifica se precisa retornar para baús perdidos
    if ChestsInteractor.check_missed_chests() then
        return
    end
    
    -- Atualiza estado com base nos objetos disponíveis
    local newState = stateFunctions[currentState](objects, interactive_patterns)
    if newState ~= currentState then
        currentState = newState
    end
    
    -- Verifica se o jogador está muito longe do alvo
    if not handle_player_too_far() then
        return
    end
    
    -- Limpa blacklists temporárias expiradas
    ChestsInteractor.clearTemporaryBlacklist()
end

function ChestsInteractor.clearInteractedObjects()
    interactedObjects = {}
end

function ChestsInteractor.clearTemporaryBlacklist()
    local current_time = os.clock()
    for i = #temporary_blacklist, 1, -1 do
        if current_time >= temporary_blacklist[i].expires_at then
            table.remove(temporary_blacklist, i)
        end
    end
end

function ChestsInteractor.printBlacklists()
    console.print("Blacklist Permanente:")
    for i, item in ipairs(permanent_blacklist) do
        local pos_string = string.format("(%.2f, %.2f, %.2f)", item.position:x(), item.position:y(), item.position:z())
        console.print(string.format("Item %d: %s em %s", i, item.name, pos_string))
    end
    
    console.print("\nBlacklist Temporária:")
    local current_time = os.clock()
    for i, item in ipairs(temporary_blacklist) do
        local pos_string = string.format("(%.2f, %.2f, %.2f)", item.position:x(), item.position:y(), item.position:z())
        local time_remaining = math.max(0, item.expires_at - current_time)
        console.print(string.format("Item %d: %s em %s, tempo restante: %.2f segundos", i, item.name, pos_string, time_remaining))
    end
end

function ChestsInteractor.getSuccessfulChestsOpened()
    return successful_chests_opened
end

function ChestsInteractor.getSuccessfulChestsOpened()
    return successful_chests_opened
end

function ChestsInteractor.draw_chest_info()
    -- Configurações de UI centralizadas
    local UI_CONFIG = {
        base_x = 10,
        base_y = 550,
        line_height = 17,
        category_spacing = 0,
        indent = 10,
        font_size = 20
    }
    local current_y = UI_CONFIG.base_y

    -- Função auxiliar para desenhar cabeçalhos de seção
    local function draw_section_header(text)
        graphics.text_2d("=== " .. text .. " ===", 
            vec2:new(UI_CONFIG.base_x, current_y), 
            UI_CONFIG.font_size, 
            color_yellow(255))
        current_y = current_y + UI_CONFIG.line_height
    end

    -- HELLTIDE CHESTS STATUS
    draw_section_header("HELLTIDE CHESTS STATUS")
    graphics.text_2d(
        string.format("Total Helltide Chests Opened: %d", successful_chests_opened), 
        vec2:new(UI_CONFIG.base_x, current_y), 
        UI_CONFIG.font_size, 
        color_white
    )

    -- ROUTE STATUS
    current_y = current_y + UI_CONFIG.line_height + UI_CONFIG.category_spacing
    draw_section_header("ROUTE STATUS")
    
    -- Initial loop status
    local visited_count = count_visited_waypoints()
    local loop_status = RouteOptimizer.has_completed_initial_loop() 
        and "Complete" 
        or string.format("In Progress (%d/%d WPs)", visited_count, total_waypoints)
    graphics.text_2d(
        "Initial Loop: " .. loop_status, 
        vec2:new(UI_CONFIG.base_x, current_y), 
        UI_CONFIG.font_size, 
        color_white
    )
    current_y = current_y + UI_CONFIG.line_height

    -- Optimized route information
    if RouteOptimizer.in_optimized_route and RouteOptimizer.current_route then
        local route = RouteOptimizer.current_route
        graphics.text_2d(
            string.format(
                "Optimized Route: %d chests (Waypoint %d, Direction: %s)",
                #route.chests,
                route.waypoints[1],
                route.direction
            ),
            vec2:new(UI_CONFIG.base_x, current_y),
            UI_CONFIG.font_size,
            color_green
        )
        current_y = current_y + UI_CONFIG.line_height
    end

    -- CURRENT STATUS
    current_y = current_y + UI_CONFIG.category_spacing
    draw_section_header("CURRENT STATUS")

    -- Current state
    graphics.text_2d(
        string.format(
            "Current State: %s%s",
            currentState,
            Movement.is_interacting() and " (Interacting)" or ""
        ), 
        vec2:new(UI_CONFIG.base_x, current_y), 
        UI_CONFIG.font_size, 
        color_white
    )
    current_y = current_y + UI_CONFIG.line_height

    -- Cinders
    graphics.text_2d(
        string.format("Cinders: %d", get_helltide_coin_cinders()), 
        vec2:new(UI_CONFIG.base_x, current_y), 
        UI_CONFIG.font_size, 
        color_white
    )
    current_y = current_y + UI_CONFIG.line_height

    -- MISSED CHESTS
    current_y = current_y + UI_CONFIG.category_spacing
    draw_section_header("MISSED CHESTS")

    if next(missed_chests) then
        local player_pos = get_local_player():get_position()
        local current_cinders = get_helltide_coin_cinders()
        
        for _, chest in pairs(missed_chests) do
            local can_afford = current_cinders >= chest.required_cinders
            local status_symbol = can_afford and "✓" or "✗"
            local color_to_use = can_afford and color_green or color_red
            
            graphics.text_2d(
                string.format(
                    "• %s (%.0fm) - Cost: %d cinders %s", 
                    chest.name,
                    player_pos:dist_to(chest.position),
                    chest.required_cinders,
                    status_symbol
                ), 
                vec2:new(UI_CONFIG.base_x + UI_CONFIG.indent, current_y), 
                UI_CONFIG.font_size, 
                color_to_use
            )
            current_y = current_y + UI_CONFIG.line_height
        end
    else
        graphics.text_2d(
            "No missed chests recorded", 
            vec2:new(UI_CONFIG.base_x, current_y), 
            UI_CONFIG.font_size, 
            color_white
        )
    end

    -- Se estiver voltando para um baú específico
    if target_missed_chest then
        current_y = current_y + UI_CONFIG.line_height
        graphics.text_2d(
            string.format(
                "Returning to: %s (Waypoint %d)", 
                target_missed_chest.name,
                target_missed_chest.waypoint_index
            ),
            vec2:new(UI_CONFIG.base_x, current_y),
            UI_CONFIG.font_size,
            color_green
        )
    end
end

function ChestsInteractor.is_active()
    return currentState ~= States.IDLE
end

function ChestsInteractor.clearPermanentBlacklist()
    permanent_blacklist = {}
end

function ChestsInteractor.clearAllBlacklists()
    ChestsInteractor.clearTemporaryBlacklist()
    ChestsInteractor.clearPermanentBlacklist()
end

function ChestsInteractor.clear_missed_chests()
    missed_chests = {}
    console.print("Lista de baús perdidos limpa")
end

function ChestsInteractor.reset_for_new_helltide()
    -- Reseta variáveis de estado
    currentState = States.IDLE
    targetObject = nil
    last_known_chest_position = nil
    chest_search_attempts = 0
    current_attempt = 0
    failed_attempts = 0
    -- Removido: successful_chests_opened = 0  (mantém a contagem total)
    
    -- Limpa todas as listas
    missed_chests = {}
    permanent_blacklist = {}
    temporary_blacklist = {}
    interactedObjects = {}
    waypoints_visited = {}
    total_waypoints = 0
    
    -- Reseta contadores
    last_interaction_time = 0
    last_chest_interaction_time = 0
    vfx_check_start_time = nil
    state_start_time = os.clock()
    
    -- Reseta movimento
    Movement.set_interacting(false)
    Movement.set_explorer_control(false)
    Movement.enable_anti_stuck()
    explorer.disable()
    
    -- Reseta direção e modo
    current_direction = "forward"
    Movement.reset_reverse_mode()
    
    -- Limpa alvos
    target_missed_chest = nil
    
    -- Reseta tentativas de baús
    chest_attempts = {}
    current_chest_key = nil
    
    console.print("Estado resetado para nova Helltide (mantendo contagem total de baús)")
end

on_render(render_waypoints_3d)

return ChestsInteractor