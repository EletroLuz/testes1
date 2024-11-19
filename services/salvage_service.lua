local menu = require("menu")
local enums = require("data.enums")
local StashService = require("services.stash_service")

local SalvageService = {
    CONSTANTS = {
        INTERACTION_DISTANCE = 3.0,
        PROCESS_DELAY = 0.5
    },

    state = {
        is_processing = false,
        last_salvage_time = 0,
        items_processed = 0
    }
}

local function calculate_distance(point1, point2)
    if not point1 or not point2 then return 999999 end
    return point1:dist_to_ignore_z(point2)
end

-- Função para interagir com o blacksmith
function SalvageService:interact_vendor(vendor_pos)
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

-- Verifica se um item pode ser salvaged
function SalvageService:should_salvage_item(item_data)
    if not item_data then return false end
    
    -- Não salva itens que devem ir para o stash
    if StashService:should_stash_item(item_data) then
        return false
    end
    
    local display_name = item_data:get_display_name()
    if not display_name then return false end
    
    -- Conta Greater Affixes
    local greater_affix_count = 0
    for _ in display_name:gmatch("GreaterAffix") do
        greater_affix_count = greater_affix_count + 1
    end
    
    return greater_affix_count < menu.greater_affix_threshold:get()
end

-- Verifica se há itens para salvage no inventário
function SalvageService:has_items_to_salvage()
    local local_player = get_local_player()
    if not local_player then return false end
    
    local inventory_items = local_player:get_inventory_items()
    if not inventory_items then return false end
    
    -- Verifica thresholds do menu
    local items_threshold = menu.items_threshold:get()
    local total_items = #inventory_items
    
    if total_items < items_threshold then
        console.print(string.format("Total de itens (%d) menor que threshold (%d)", 
            total_items, items_threshold))
        return false
    end
    
    -- Verifica se há itens elegíveis para salvage
    for _, item_data in ipairs(inventory_items) do
        if self:should_salvage_item(item_data) then
            return true
        end
    end
    
    return false
end

-- Encontra o blacksmith mais próximo
function SalvageService:find_blacksmith()
    return enums.positions.blacksmith_position
end

-- Processa salvage dos itens
function SalvageService:process_salvage_items(vendor_pos)
    if self.state.is_processing then 
        console.print("Já está processando salvage")
        return false 
    end
    
    console.print("Iniciando processo de salvage...")
    
    -- Verifica se já está na tela do vendor antes de tentar interagir
    if not loot_manager.is_in_vendor_screen() then
        if not self:interact_vendor(vendor_pos) then
            console.print("Falha ao abrir janela do blacksmith, abortando salvage")
            return false
        end
    else
        console.print("Já está na tela do blacksmith, continuando com salvage")
    end
    
    local local_player = get_local_player()
    if not local_player then 
        console.print("Player não encontrado")
        return false 
    end
    
    local inventory_items = local_player:get_inventory_items()
    if not inventory_items then 
        console.print("Não foi possível obter itens do inventário")
        return false 
    end
    
    console.print(string.format("Encontrados %d itens no inventário", #inventory_items))
    
    self.state.is_processing = true
    self.state.items_salvaged = 0
    local initial_count = local_player:get_item_count()
    local current_time = os.clock()
    
    -- Processa cada item
    for _, item_data in ipairs(inventory_items) do
        -- Verifica se ainda está na tela do vendor
        if not loot_manager.is_in_vendor_screen() then
            console.print("Perdeu conexão com blacksmith, tentando reconectar...")
            if not self:interact_blacksmith(blacksmith) then
                console.print("Falha ao reconectar com blacksmith, abortando salvage")
                break
            end
        end
        
        if self:should_salvage_item(item_data) then
            local display_name = item_data:get_display_name()
            console.print(string.format("Tentando salvar: %s", display_name))
            
            if loot_manager.salvage_specific_item(item_data) then
                while os.clock() - current_time < self.CONSTANTS.PROCESS_DELAY do end
                current_time = os.clock()
                
                local new_count = local_player:get_item_count()
                if new_count < initial_count then
                    self.state.items_salvaged = self.state.items_salvaged + 1
                    initial_count = new_count
                    console.print(string.format("Item salvaged com sucesso: %s", display_name))
                else
                    console.print(string.format("Falha ao salvar item: %s (contagem não mudou)", display_name))
                end
            else
                console.print(string.format("Falha ao executar salvage do item: %s", display_name))
            end
        end
    end
    
    local success = self.state.items_salvaged > 0
    self.state.is_processing = false
    
    if success then
        console.print(string.format("Salvage concluído com sucesso. Total de itens salvaged: %d", 
            self.state.items_salvaged))
    else
        console.print("Nenhum item foi salvaged")
    end
    
    return success
end

-- Obtém estatísticas do último processamento
function SalvageService:get_stats()
    return {
        items_processed = self.state.items_processed,
        is_processing = self.state.is_processing,
        last_process_time = self.state.last_salvage_time
    }
end

return SalvageService