local enums = require("data.enums")
local explorer = require("data.explorer")

local PortalService = {
    CONSTANTS = {
        INTERACTION_DISTANCE = 3.0,
        MOVEMENT_THRESHOLD = 2.5,
        PROCESS_DELAY = 0.2
    },

    state = {
        is_processing = false,
        last_interaction_time = 0
    }
}

-- Encontra o portal mais próximo
function PortalService:find_portal()
    return {
        object = enums.misc.portal,
        position = enums.positions.portal_position,
        type = "portal"
    }
end

-- Move até o portal
function PortalService:move_to_portal(target_pos)
    if not target_pos then return false end
    
    local player_pos = get_player_position()
    if not player_pos then return false end
    
    local distance = player_pos:dist_to_ignore_z(target_pos)
    
    -- Se já está perto o suficiente
    if distance <= self.CONSTANTS.MOVEMENT_THRESHOLD then
        if explorer.is_enabled() then
            explorer.disable()
        end
        return true
    end
    
    -- Se ainda não está perto, move até o alvo
    if not explorer.is_enabled() then
        explorer.enable()
    end
    explorer.set_target(target_pos)
    
    console.print(string.format("Distance to portal: %.2f", distance))
    return false
end

-- Interage com o portal
function PortalService:interact_portal(portal_pos)
    if not portal_pos then return false end
    
    -- Procura o portal real
    local actors = actors_manager:get_all_actors()
    for _, actor in pairs(actors) do
        if actor:is_interactable() then
            local name = actor:get_skin_name()
            if name == enums.misc.portal then
                local actor_pos = actor:get_position()
                local dist = actor_pos:dist_to_ignore_z(portal_pos)
                if dist < self.CONSTANTS.INTERACTION_DISTANCE then
                    console.print("Portal encontrado, interagindo...")
                    return interact_object(actor)
                end
            end
        end
    end
    
    console.print("Portal não encontrado na posição")
    return false
end

-- Processa a interação com o portal
function PortalService:process_portal(target)
    if self.state.is_processing then return false end
    
    -- Primeiro move até o portal
    if not self:move_to_portal(target.position) then
        return false
    end
    
    -- Depois tenta interagir
    self.state.is_processing = true
    local success = self:interact_portal(target.position)
    self.state.is_processing = false
    
    return success
end

return PortalService