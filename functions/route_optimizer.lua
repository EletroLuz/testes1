local Movement = require("functions.movement")
local PathCalculator = require("functions.path_calculator")

local RouteOptimizer = {
    initial_loop_completed = false,
    in_optimized_route = false,
    current_route = nil,
    missed_chests_count = 0
}

local CITY_RADIUS = 20

function RouteOptimizer.is_in_city()
    local player_pos = get_local_player():get_position()
    local first_waypoint = Movement.get_waypoints()[1]
    return player_pos:dist_to(first_waypoint) < CITY_RADIUS
end

function RouteOptimizer.has_completed_initial_loop()
    return RouteOptimizer.initial_loop_completed
end

function RouteOptimizer.plan_optimized_route(missed_chests)
    if RouteOptimizer.in_optimized_route then return false end
    
    local best_route = PathCalculator.calculate_best_missed_chests_route(missed_chests)
    if best_route then
        RouteOptimizer.current_route = best_route
        RouteOptimizer.in_optimized_route = true
        
        if best_route.direction == "backward" then
            Movement.reverse_waypoint_direction(best_route.waypoints[1])
        end
        
        return true
    end
    
    return false
end

function RouteOptimizer.complete_initial_loop()
    RouteOptimizer.initial_loop_completed = true
end

function RouteOptimizer.reset()
    RouteOptimizer.initial_loop_completed = false
    RouteOptimizer.in_optimized_route = false
    RouteOptimizer.current_route = nil
    RouteOptimizer.missed_chests_count = 0
    console.print("RouteOptimizer resetado")
end

return RouteOptimizer