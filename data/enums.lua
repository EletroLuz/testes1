-- Enumeration constants for the game
local enums = {
    -- Portal type definitions
    portal_names = {
        horde_portal = "Portal_Dungeon_Generic",
        town_portal = "TownPortal"
    },

    -- NPC and object identifiers
    misc = {
        obelisk = "TWN_Kehj_IronWolves_PitKey_Crafter",
        blacksmith = "TWN_Hawe_TreeOfWhispers_Crafter_Blacksmith",
        jeweler = "TWN_Hawe_TreeOfWhispers_Vendor_Silversmith",
        portal = "TownPortal",
        stash = "Stash"
    },

    -- Vendor and crafting positions
    positions = {
        blacksmith_position = vec3:new(-1293.869141, 742.803711, 1.403320),
        jeweler_position = vec3:new(-1301.755859, 740.065430, 2.320312),
        stash_position = vec3:new(-1296.65, 749.52, -0.46),
        
        -- Portal positions
        portal_position = vec3:new(-1305.780396, 740.528259, 2.164273),
    },

    -- Waypoint identifiers
    waypoints = {
        
        CERRIGAR = 0x76D58,
        LIBRARY = 0x10D63D,
        THE_TREE_OF_WHISPERS = 0x90557
    },

    -- Vendor types
    vendor_types = {
        BLACKSMITH = 1,
        JEWELER = 2,
        OCCULTIST = 3,
        STABLE = 4
    },

    -- Currency types
    currency = {
        GOLD = 0,
        OBOLS = 3
    },


    -- Storage types
    storage_types = {  -- Novo enum para tipos de armazenamento
        STASH = 1,
        VENDOR = 2
    },

    -- Boss materials definitions
    boss_materials = {
        living_steel = {sno_id = 1502128, count = 0, display_name = "Total Living Steel"},
        distilled_fear = {sno_id = 1518053, count = 0, display_name = "Total Distilled Fear"},
        exquisite_blood = {sno_id = 1522891, count = 0, display_name = "Total Exquisite Blood"},
        malignant_heart = {sno_id = 1489420, count = 0, display_name = "Total Malignant Heart"}
    },

    -- Protected items that should never be sold or salvaged
    protected_items = {
        { name = "Tyrael's Might", sno = 1901484 },
        { name = "The Grandfather", sno = 223271 },
        { name = "Andariel's Visage", sno = 241930 },
        { name = "Ahavarion, Spear of Lycander", sno = 359165 },
        { name = "Doombringer", sno = 221017 },
        { name = "Harlequin Crest", sno = 609820 },
        { name = "Melted Heart of Selig", sno = 1275935 },
        { name = "Ring of Starless Skies", sno = 1306338 },
        { name = "Shroud of False Death", sno = 2059803 },
        { name = "Nesekem, the Herald", sno = 1982241 },
        { name = "Heir of Perdition", sno = 2059799 },
        { name = "Shattered Vow", sno = 2059813 }
    }


}

return enums