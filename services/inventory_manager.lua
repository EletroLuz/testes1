local menu = require("menu")
local enums = require("data.enums")
local BossMaterialsService = require("services.boss_materials_service")
local StashService = require("services.stash_service")
local SalvageService = require("services.salvage_service")
local SellService = require("services.sell_service")
local RepairService = require("services.repair_service")
local PortalService = require("services.portal_service")
local vendor_teleport = require("data.vendor_teleport")
local GameStateChecker = require("functions.game_state_checker")


local InventoryManager = {
    CONSTANTS = {
        VENDOR_CHECK_INTERVAL = 5, -- segundos entre verificações
        INTERACTION_DISTANCE = 3.0,
        MOVEMENT_THRESHOLD = 2.5,
        TELEPORT_CHECK_INTERVAL = 1,
        ACTION_DELAY = 0.5,
        MAX_RETRIES = 5,  -- Nova constante
        HELLTIDE_CHECK_INTERVAL = 2 -- intervalo para verificar estado da helltide
    },

    state = {
        is_processing = false,
        current_target = nil,
        last_check_time = 0,
        last_action_time = 0,
        current_action = nil,
        retries = 0,
        last_helltide_check = 0,
        last_teleport_check = 0,
        waiting_for_teleport = false,
        teleport_completed = false,
        portal_target = nil,
        portal_used = false
    }
}

function InventoryManager:ensure_explorer_disabled()
    if explorer and explorer.is_enabled() then
        console.print("Desativando explorer que estava ativo indevidamente")
        explorer.disable()
    end
end

-- Adicionar nova função para gerenciar o processo durante helltide
function InventoryManager:handle_helltide_vendor()
    -- Adicionar mais logs para debug
    console.print("==== Debug Helltide Vendor ====")
    console.print("Enable During Helltide: " .. tostring(menu.enable_during_helltide:get()))
    
    local local_player = get_local_player()
    if not local_player then return end
    
    local is_helltide = GameStateChecker.is_in_helltide(local_player)
    console.print("Is in Helltide: " .. tostring(is_helltide))
    console.print("Waiting for teleport: " .. tostring(self.state.waiting_for_teleport))
    console.print("Teleport completed: " .. tostring(self.state.teleport_completed))
    
    if not menu.enable_during_helltide:get() then
        return
    end
    
    if not is_helltide then
        return
    end

    console.print("Verificando necessidade de vendor durante Helltide...")
    
    -- Verifica se há necessidade de vender/guardar itens
    local next_action = self:get_next_action()
    local needs_vendor = next_action ~= nil
    
    console.print("Necessita vendor: " .. tostring(needs_vendor))
    console.print("Próxima ação: " .. tostring(next_action))
    console.print("Aguardando teleporte: " .. tostring(self.state.waiting_for_teleport))

    if needs_vendor and not self.state.waiting_for_teleport then
        console.print("Iniciando processo de vendor durante Helltide")
        
        -- Desativa o plugin principal
        console.print("Desativando plugin principal...")
        menu.plugin_enabled:set(false)
        
        -- Inicia processo de teleporte
        self.state.waiting_for_teleport = true
        self.state.teleport_completed = false
        
        -- Limpa alvos atuais
        self.state.current_target = nil
        self.state.current_action = nil
        
        return
    end

    if self.state.waiting_for_teleport then
        console.print("Estado atual: Aguardando teleporte")
        if not self.state.teleport_completed then
            -- Verifica o estado atual do teleporte
            local teleport_state = vendor_teleport.get_state()
            local teleport_info = vendor_teleport.get_info()
            console.print(string.format("Estado do teleporte: %s (Tentativas: %d/%d)", 
                teleport_state, teleport_info.attempts, teleport_info.max_attempts))
            
            -- Se já estiver em idle e na cidade, considera teleporte concluído
            local current_world = world.get_current_world()
            if current_world and teleport_state == "idle" then
                local zone_name = current_world:get_current_zone_name()
                console.print("Zona atual: " .. tostring(zone_name))
                
                if zone_name == "Hawe_Bog" then
                    console.print("Chegou na cidade!")
                    self.state.teleport_completed = true
                    self.state.waiting_for_teleport = false  -- Limpa o estado de espera
                    return
                end
            end
            
            -- Tenta teleportar para a cidade
            local teleport_result = vendor_teleport.teleport_to_tree()
            console.print("Resultado do teleporte: " .. tostring(teleport_result))
            
            -- Se o teleporte foi bem sucedido
            if teleport_result then
                console.print("Teleporte para cidade iniciado")
            elseif teleport_state == "cooldown" then
                -- Se entrou em cooldown, reseta os estados
                console.print("Teleporte em cooldown, resetando estados...")
                self.state.waiting_for_teleport = false
                self.state.teleport_completed = false
                vendor_teleport.reset()
                menu.plugin_enabled:set(true)
            end
        else
            -- Se já completou o teleporte, processa as vendas
            console.print("Teleporte concluído, processando vendas...")
            self:update()
        end
        return
    end
end

-- Verifica se pode realizar uma ação
function InventoryManager:can_perform_action()
    local current_time = os.clock()
    if current_time - self.state.last_action_time >= self.CONSTANTS.ACTION_DELAY then
        self.state.last_action_time = current_time
        return true
    end
    return false
end

-- Determina a próxima ação necessária
function InventoryManager:get_next_action()
    local local_player = get_local_player()
    if not local_player then return nil end
    -- Ordem de prioridade das ações
    local actions = {
        {
            name = "stash_boss_materials",
            enabled = menu.auto_stash_boss_materials:get(),
            check = function() 
                local consumable_items = local_player:get_consumable_items()
                if not consumable_items then return false end
                
                for _, item in pairs(consumable_items) do
                    if BossMaterialsService:should_stash_material(item) then
                        local stack_count = item:get_stack_count() or 0
                        console.print(string.format("Material encontrado com stack %d", stack_count))
                        return true
                    end
                end
                return false
            end
        },
        {
            name = "stash",
            enabled = menu.auto_stash:get(),
            check = function() 
                return StashService:should_stash_item(local_player:get_inventory_items()) 
            end
        },
        {
            name = "salvage",
            enabled = menu.auto_salvage:get(),
            check = function() 
                return SalvageService:has_items_to_salvage() 
            end
        },
        {
            name = "repair",
            enabled = menu.auto_repair:get(),
            check = function() 
                return RepairService:has_items_to_repair() 
            end
        },  
        {
            name = "sell",
            enabled = menu.auto_sell:get(),
            check = function() 
                return SellService:has_items_to_sell() 
            end
        }
    }
    
    -- Verifica cada ação na ordem de prioridade
    for _, action in ipairs(actions) do
        if action.enabled and action.check() then
            console.print("Próxima ação:", action.name)
            return action.name
        end
    end
    
    return nil
end

-- Encontra o vendor apropriado para a ação atual
function InventoryManager:find_vendor_for_action(action)
    if action == "stash" or action == "stash_boss_materials" then
        return enums.positions.stash_position
    elseif action == "salvage" or action == "repair" then  -- Repair usa mesmo vendor que salvage
        return enums.positions.blacksmith_position
    elseif action == "sell" then
        return enums.positions.jeweler_position
    end
    return nil
end

-- Processa a ação atual com o vendor
function InventoryManager:process_action(action, vendor)
    if action == "stash_boss_materials" then
        console.print("Processando materiais de boss...")
        return StashService:process_boss_materials(vendor)
    elseif action == "stash" then
        console.print("Processando itens normais...")
        return StashService:process_stash_items(vendor)
    elseif action == "salvage" then
        return SalvageService:process_salvage_items(vendor)
    elseif action == "repair" then
        console.print("Processando reparo de itens...")
        return RepairService:process_repair_items(vendor)
    elseif action == "sell" then
        return SellService:process_sell_items(vendor)
    end
    return false
end

-- Atualiza o estado do gerenciador
function InventoryManager:update()
    if not menu.vendor_enabled:get() then 
        self:ensure_explorer_disabled()
        return 
    end

    -- Verificação inicial de zona e Helltide
    local local_player = get_local_player()
    local is_helltide = GameStateChecker.is_in_helltide(local_player)
    local current_world = world.get_current_world()
    local zone_name = current_world and current_world:get_current_zone_name()
    local in_vendor_city = (zone_name == "Hawe_Bog")

    -- Debug
    console.print("Debug estados:")
    console.print("- Zona atual: " .. tostring(zone_name))
    console.print("- Em Helltide: " .. tostring(is_helltide))
    console.print("- Menu enable_during_helltide: " .. tostring(menu.enable_during_helltide:get()))
    console.print("- Waiting for teleport: " .. tostring(self.state.waiting_for_teleport))

    -- Controle do explorer - só ativa na cidade ou durante teleporte
    if not in_vendor_city and not self.state.waiting_for_teleport then
        if explorer and explorer.is_enabled() then
            console.print("Desativando explorer fora da cidade")
            explorer.disable()
        end
    end

    -- Processo de Helltide
    if is_helltide and menu.enable_during_helltide:get() then
        local next_action = self:get_next_action()
        if next_action then
            console.print("Necessidade de vendor detectada durante Helltide")
            if not self.state.waiting_for_teleport then
                console.print("Iniciando processo de teleporte para cidade")
                self.state.waiting_for_teleport = true
                menu.plugin_enabled:set(false)
                return
            end
        end
    end

    -- Se estiver aguardando teleporte, verifica o processo
    if self.state.waiting_for_teleport then
        local current_time = os.clock()
        if current_time - self.state.last_teleport_check >= self.CONSTANTS.TELEPORT_CHECK_INTERVAL then
            self.state.last_teleport_check = current_time
            
            if current_world then
                local zone_name = current_world:get_current_zone_name()
                console.print("Verificando zona atual: " .. tostring(zone_name))
                
                if zone_name == "Hawe_Bog" then
                    console.print("Chegou na cidade!")
                    self.state.teleport_completed = true
                    self.state.waiting_for_teleport = false
                    return
                end
            end
            
            -- Tenta teleportar para a cidade
            local teleport_result = vendor_teleport.teleport_to_tree()
            console.print("Resultado do teleporte: " .. tostring(teleport_result))
            
            -- Se o teleporte está em cooldown, reseta os estados
            if vendor_teleport.get_state() == "cooldown" then
                console.print("Teleporte em cooldown, resetando estados...")
                self.state.waiting_for_teleport = false
                self.state.teleport_completed = false
                vendor_teleport.reset()
                menu.plugin_enabled:set(true)
            end
        end
        return
    end

    -- Se não está na cidade e não está em processo de teleporte, não processa vendors
    if not in_vendor_city and not self.state.waiting_for_teleport then
        return
    end

    -- Verificação normal do intervalo de vendor
    local current_time = os.clock()
    if current_time - self.state.last_check_time < self.CONSTANTS.VENDOR_CHECK_INTERVAL then
        return
    end
    self.state.last_check_time = current_time
    
    -- Se já estiver processando, aguarda
    if self.state.is_processing then return end
    
    -- Determina próxima ação
    local next_action = self:get_next_action()
    if not next_action then
        -- Se não há mais ações, tenta interagir com o portal
        if not self.state.portal_target then
            console.print("Todas as ações concluídas, movendo para o portal...")
            self.state.portal_target = PortalService:find_portal()
        end
        
        if self.state.portal_target then
            if PortalService:process_portal(self.state.portal_target) then
                console.print("Portal usado com sucesso, aguardando mudança de zona...")
                self.state.portal_used = true
                self.state.portal_use_time = os.clock()
                self.state.portal_target = nil
                return
            end
        end
        
        -- Verifica se usou o portal e mudou de zona
        if self.state.portal_used then
            local current_time = os.clock()
            local time_since_portal = current_time - (self.state.portal_use_time or 0)
            
            if time_since_portal >= 15 then
                local current_world = world.get_current_world()
                if current_world then
                    local zone_name = current_world:get_current_zone_name()
                    if zone_name ~= "Hawe_Bog" then
                        console.print("Chegou na nova zona: " .. tostring(zone_name))
                        
                        -- Limpa TODOS os estados
                        self.state = {
                            is_processing = false,
                            current_target = nil,
                            last_check_time = 0,
                            last_action_time = 0,
                            current_action = nil,
                            retries = 0,
                            last_helltide_check = 0,
                            waiting_for_teleport = false,
                            teleport_completed = false,
                            portal_target = nil,
                            last_teleport_check = 0,
                            portal_used = false,
                            portal_use_time = 0
                        }
                        
                        menu.plugin_enabled:set(true)
                        return
                    end
                end
            else
                console.print(string.format("Aguardando transição de zona... (%.1f segundos)", time_since_portal))
            end
        end
        
        self.state.current_target = nil
        self.state.current_action = nil
        self.state.retries = 0
        return
    end
    
    -- Se não tiver target atual, procura um novo
    if not self.state.current_target then
        local vendor = self:find_vendor_for_action(next_action)
        if vendor then
            self.state.current_target = vendor
            self.state.current_action = next_action
            self.state.retries = 0
        end
    end
    
    -- Se tiver target, processa a ação
    if self.state.current_target and self:can_perform_action() then
        self.state.is_processing = true
        
        local success = self:process_action(self.state.current_action, self.state.current_target)
        if success then
            console.print(string.format("Ação %s completada com sucesso", self.state.current_action))
            self.state.current_target = nil
            self.state.current_action = nil
            self.state.retries = 0
        else
            self.state.retries = self.state.retries + 1
            console.print(string.format("Tentativa %d de %d falhou", self.state.retries, self.CONSTANTS.MAX_RETRIES))
            
            if self.state.retries >= self.CONSTANTS.MAX_RETRIES then
                console.print("Máximo de tentativas atingido, mudando ação")
                self.state.current_target = nil
                self.state.current_action = nil
                self.state.retries = 0
            end
        end
        
        self.state.is_processing = false
    end
end

-- Obtém estatísticas de todos os serviços
function InventoryManager:get_stats()
    return {
        salvage_stats = SalvageService:get_stats(),
        sell_stats = SellService:get_stats(),
        boss_materials = BossMaterialsService:count_materials(),
        current_action = self.state.current_action,
        is_processing = self.state.is_processing,
        retries = self.state.retries  -- Novo campo
    }
end

return InventoryManager