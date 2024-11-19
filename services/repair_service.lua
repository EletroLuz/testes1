local menu = require("menu")
local enums = require("data.enums")

local RepairService = {
    CONSTANTS = {
        INTERACTION_DISTANCE = 3.0,
        PROCESS_DELAY = 0.2
    },

    state = {
        is_processing = false,
        last_repair_time = 0
    }
}

-- Encontra o blacksmith mais próximo
function RepairService:find_nearest_blacksmith()
    return enums.positions.blacksmith_position
end

-- Função para interagir com o vendor
function RepairService:interact_vendor(vendor_pos)
    if not vendor_pos then 
        console.print("Posição do vendor inválida")
        return false 
    end
    
    -- Verifica se já está na tela do vendor
    if loot_manager.is_in_vendor_screen() then
        console.print("Já está na tela do vendor")
        return true
    end
    
    -- Encontra o vendor na posição especificada
    local actors = actors_manager:get_all_actors()
    local closest_vendor = nil
    local min_distance = 999999
    
    for _, actor in pairs(actors) do
        if actor:is_interactable() then
            local name = actor:get_skin_name()
            if name == enums.misc.blacksmith then
                local distance = calculate_distance(actor:get_position(), vendor_pos)
                if distance < min_distance then
                    min_distance = distance
                    closest_vendor = actor
                end
            end
        end
    end
    
    if not closest_vendor then
        console.print("Nenhum vendor encontrado na posição")
        return false
    end
    
    -- Tenta interagir com o vendor encontrado
    interact_vendor(closest_vendor)
    
    -- Aguarda um pouco para a janela abrir
    local current_time = os.clock()
    while os.clock() - current_time < self.CONSTANTS.PROCESS_DELAY do end
    
    -- Verifica se a janela abriu
    if loot_manager.is_in_vendor_screen() then
        console.print("Janela do vendor aberta com sucesso")
        return true
    end
    
    console.print("Falha ao abrir janela do vendor")
    return false
end

-- Verifica se há itens para reparar
function RepairService:has_items_to_repair()
    local local_player = get_local_player()
    if not local_player then 
        console.print("Não foi possível obter local player")
        return false 
    end
    
    local equipped_items = local_player:get_equipped_items()
    if not equipped_items then
        console.print("Não foi possível obter itens equipados")
        return false
    end
    
    -- Verifica cada item equipado
    for _, item in ipairs(equipped_items) do
        if item then
            local durability = item:get_durability()
            if durability and durability < 100 then
                -- Verifica se a durabilidade não está próxima de 100
                if math.abs(durability - 100) > 0.1 then
                    return true
                end
            end
        end
    end
    
    return false
end

-- Processa reparo dos itens
function RepairService:process_repair_items(vendor_pos)
    if self.state.is_processing then 
        console.print("Já está processando reparo")
        return false 
    end
    
    -- Primeiro verifica se há itens para reparar
    if not self:has_items_to_repair() then
        console.print("Não há itens para reparar")
        return true  -- Retorna true pois não há nada para fazer
    end
    
    console.print("Iniciando processo de reparo...")
    
    -- Verifica se já está na tela do vendor antes de tentar interagir
    if not loot_manager.is_in_vendor_screen() then
        if not self:interact_vendor(vendor_pos) then
            console.print("Falha ao abrir janela do vendor, abortando reparo")
            return false
        end
    else
        console.print("Já está na tela do vendor, continuando com reparo")
    end
    
    -- Processa o reparo
    self.state.is_processing = true
    local current_time = os.clock()
    
    if loot_manager.interact_with_vendor_and_repair_all() then
        while os.clock() - current_time < self.CONSTANTS.PROCESS_DELAY do end
        console.print("Reparo concluído com sucesso")
        self.state.is_processing = false
        return true
    end
    
    console.print("Falha ao reparar itens")
    self.state.is_processing = false
    return false
end

return RepairService