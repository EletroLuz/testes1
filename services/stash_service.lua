local menu = require("menu")
local enums = require("data.enums")
local BossMaterialsService = require("services.boss_materials_service")

local StashService = {
    CONSTANTS = {
        INTERACTION_DISTANCE = 3.0,
        PROCESS_DELAY = 0.2
    },

    state = {
        is_processing = false,
        last_stash_time = 0,
        items_stashed = 0
    }
}

local function calculate_distance(point1, point2)
    if not point1 or not point2 then return 999999 end
    return point1:dist_to_ignore_z(point2)
end

-- Função para interagir com o stash
function StashService:interact_stash(stash_pos)
    if not stash_pos then 
        console.print("Posição do stash inválida")
        return false 
    end
    
    console.print("Tentando interagir com stash...")
    
    -- Encontra o stash na posição especificada
    local actors = actors_manager:get_all_actors()
    local closest_stash = nil
    local min_distance = 999999
    
    for _, actor in pairs(actors) do
        if actor:is_interactable() then
            local name = actor:get_skin_name()
            if name == enums.misc.stash then
                local distance = calculate_distance(actor:get_position(), stash_pos)
                if distance < min_distance then
                    min_distance = distance
                    closest_stash = actor
                end
            end
        end
    end
    
    if not closest_stash then
        console.print("Nenhum stash encontrado na posição")
        return false
    end
    
    -- Tenta interagir com o stash encontrado
    console.print("Chamando interact_vendor com stash...")
    interact_vendor(closest_stash)
    
    -- Aguarda um pouco para a janela abrir
    local current_time = os.clock()
    while os.clock() - current_time < self.CONSTANTS.PROCESS_DELAY do end
    
    -- Assume que a interação foi bem sucedida
    console.print("Interação com stash realizada")
    return true
end

-- Verifica se um item deve ir para o stash
function StashService:should_stash_item(item_data)
    -- Se o parâmetro for uma tabela de itens, verifica se há algum item para stash
    if type(item_data) == "table" then
        for _, item in ipairs(item_data) do
            if item and self:should_stash_item(item) then
                return true
            end
        end
        return false
    end

    -- Verifica se o item é válido
    if not item_data then 
        return false 
    end

    -- Verifica se o item tem métodos necessários
    if not item_data.get_display_name then
        return false
    end

    -- Verifica materiais de boss primeiro
    if BossMaterialsService:should_stash_material(item_data) then
        return true
    end
    
    -- Verifica itens normais
    if menu.auto_stash:get() then
        local display_name = item_data:get_display_name()
        if not display_name then return false end
        
        local greater_affix_count = 0
        for _ in display_name:gmatch("GreaterAffix") do
            greater_affix_count = greater_affix_count + 1
        end
        
        return greater_affix_count >= menu.greater_affix_threshold:get()
    end
    
    return false
end

-- Encontra o stash mais próximo
function StashService:find_nearest_stash()
    return enums.positions.stash_position
end

-- Processa stash dos itens normais do inventário
function StashService:process_stash_items(stash)
    if self.state.is_processing then 
        console.print("Já está processando stash")
        return false 
    end
    
    console.print("Iniciando processo de stash...")
    
    -- Tenta interagir com o stash
    if not self:interact_stash(stash) then
        console.print("Falha ao interagir com stash, abortando operação")
        return false
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
    self.state.items_stashed = 0
    local initial_count = local_player:get_item_count()
    local current_time = os.clock()
    
    -- Processa cada item
    for _, item_data in ipairs(inventory_items) do
        if self:should_stash_item(item_data) then
            local display_name = item_data:get_display_name()
            console.print(string.format("Tentando guardar no stash: %s", display_name))
            
            -- Tenta mover o item
            if loot_manager.move_item_to_stash(item_data) then
                while os.clock() - current_time < self.CONSTANTS.PROCESS_DELAY do end
                current_time = os.clock()
                
                local new_count = local_player:get_item_count()
                if new_count < initial_count then
                    self.state.items_stashed = self.state.items_stashed + 1
                    initial_count = new_count
                    console.print(string.format("Item guardado com sucesso: %s", display_name))
                else
                    -- Tenta interagir novamente com o stash
                    self:interact_stash(stash)
                    -- Tenta mover o item novamente
                    if loot_manager.move_item_to_stash(item_data) then
                        while os.clock() - current_time < self.CONSTANTS.PROCESS_DELAY do end
                        current_time = os.clock()
                        new_count = local_player:get_item_count()
                        if new_count < initial_count then
                            self.state.items_stashed = self.state.items_stashed + 1
                            initial_count = new_count
                            console.print(string.format("Item guardado com sucesso na segunda tentativa: %s", display_name))
                        else
                            console.print(string.format("Falha ao guardar item após segunda tentativa: %s", display_name))
                        end
                    end
                end
            else
                console.print(string.format("Falha ao mover item para stash: %s", display_name))
                -- Tenta interagir novamente com o stash
                self:interact_stash(stash)
            end
        end
    end
    
    local success = self.state.items_stashed > 0
    self.state.is_processing = false
    
    if success then
        console.print(string.format("Stash concluído com sucesso. Total de itens guardados: %d", 
            self.state.items_stashed))
    else
        console.print("Nenhum item foi guardado no stash")
    end
    
    return success
end

-- Processa stash dos materiais de boss
function StashService:process_boss_materials(stash)
    if self.state.is_processing then 
        console.print("Já está processando stash")
        return false 
    end
    
    console.print("Iniciando processo de stash para materiais de boss...")
    
    -- Tenta interagir com o stash
    if not self:interact_stash(stash) then
        console.print("Falha ao interagir com stash, abortando operação")
        return false
    end
    
    local local_player = get_local_player()
    if not local_player then 
        console.print("Player não encontrado")
        return false 
    end
    
    local consumable_items = local_player:get_consumable_items()
    if not consumable_items then 
        console.print("Não foi possível obter itens consumíveis")
        return false 
    end
    
    console.print(string.format("Encontrados %d itens consumíveis", #consumable_items))
    
    self.state.is_processing = true
    self.state.items_stashed = 0
    local initial_count = local_player:get_item_count()
    local current_time = os.clock()
    
    -- Processa cada material de boss
    for _, item_data in pairs(consumable_items) do
        if BossMaterialsService:should_stash_material(item_data) then
            local stack_count = item_data:get_stack_count() or 0
            console.print(string.format("Tentando guardar stack de %d no stash", stack_count))
            
            -- Tenta mover o item
            if loot_manager.move_item_to_stash(item_data) then
                while os.clock() - current_time < self.CONSTANTS.PROCESS_DELAY do end
                current_time = os.clock()
                
                local new_count = local_player:get_item_count()
                if new_count < initial_count then
                    self.state.items_stashed = self.state.items_stashed + 1
                    initial_count = new_count
                    console.print(string.format("Material guardado com sucesso (stack %d)", stack_count))
                    self.state.is_processing = false
                    return true -- Retorna true após guardar um item com sucesso
                else
                    -- Tenta interagir novamente com o stash
                    self:interact_stash(stash)
                    -- Tenta mover o item novamente
                    if loot_manager.move_item_to_stash(item_data) then
                        while os.clock() - current_time < self.CONSTANTS.PROCESS_DELAY do end
                        current_time = os.clock()
                        new_count = local_player:get_item_count()
                        if new_count < initial_count then
                            self.state.items_stashed = self.state.items_stashed + 1
                            initial_count = new_count
                            console.print(string.format("Material guardado na segunda tentativa (stack %d)", stack_count))
                            self.state.is_processing = false
                            return true -- Retorna true após guardar um item com sucesso
                        else
                            console.print("Falha ao guardar material após segunda tentativa")
                        end
                    end
                end
            else
                console.print("Falha ao mover material para stash")
                -- Tenta interagir novamente com o stash
                self:interact_stash(stash)
            end
        end
    end
    
    self.state.is_processing = false
    return self.state.items_stashed > 0
end

return StashService