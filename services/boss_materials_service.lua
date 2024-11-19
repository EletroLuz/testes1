local menu = require("menu")
local enums = require("data.enums")

local BossMaterialsService = {
    CONSTANTS = {
        MIN_STACK_SIZE = 50,
        PROCESS_DELAY = 0.5
    },

    state = {
        is_processing = false,
        last_process_time = 0
    }
}

-- Verifica se um item específico é material de boss
function BossMaterialsService:is_boss_material(item_data)
    if not item_data then return false end
    
    local sno_id = item_data:get_sno_id()
    for material_name, material_data in pairs(enums.boss_materials) do
        if sno_id == material_data.sno_id then
            return true, material_name, material_data.display_name
        end
    end
    return false
end

-- Verifica se deve enviar para stash
function BossMaterialsService:should_stash_material(item_data)
    if not item_data or not menu.auto_stash_boss_materials:get() then 
        return false 
    end
    
    local is_material, material_name, display_name = self:is_boss_material(item_data)
    if not is_material then
        return false
    end
    
    -- Verifica se o stack é exatamente 50
    local stack_size = item_data:get_stack_count() or 0
    if stack_size == self.CONSTANTS.MIN_STACK_SIZE then
        console.print(string.format("Stack de 50 encontrado: %s", display_name))
        return true
    end
    
    return false
end

-- Conta materiais no inventário
function BossMaterialsService:count_materials()
    local local_player = get_local_player()
    if not local_player then return 0 end

    local consumable_items = local_player:get_consumable_items()
    if not consumable_items then return 0 end

    local stacks_of_50 = 0

    -- Processa cada item
    for _, item in pairs(consumable_items) do
        if item and item:is_valid() then
            local is_material, _, display_name = self:is_boss_material(item)
            if is_material then
                local stack_count = item:get_stack_count() or 0
                console.print(string.format("%s: Stack de %d", display_name, stack_count))
                
                if stack_count == self.CONSTANTS.MIN_STACK_SIZE then
                    stacks_of_50 = stacks_of_50 + 1
                end
            end
        end
    end

    self.state.last_process_time = os.clock()
    return stacks_of_50
end

-- Processa materiais de boss
function BossMaterialsService:process_boss_materials()
    if not menu.auto_stash_boss_materials:get() then 
        console.print("Auto stash de materiais de boss desativado")
        return false 
    end
    
    local stacks_of_50 = self:count_materials()
    
    if stacks_of_50 == 0 then
        console.print("Nenhum stack de 50 encontrado")
        return false
    end
    
    console.print(string.format("Encontrados %d stacks de 50", stacks_of_50))
    return true
end

-- Obtém estatísticas
function BossMaterialsService:get_stats()
    return {
        last_process_time = self.state.last_process_time,
        is_processing = self.state.is_processing
    }
end

return BossMaterialsService