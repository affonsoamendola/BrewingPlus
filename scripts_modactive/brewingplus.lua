-- Complicated Brewing Plugin (Needs to be enabled if mod installed!)

-- these lines indicate that the script supports the "enable"
-- API so you can start it by running "enable example-mod" and
-- stop it by running "disable example-mod"
--@ module=true
--@ enable=true

-- this is the help text that will appear in `help` and
-- `gui/launcher`. see possible tags here:
-- https://docs.dfhack.org/en/stable/docs/Tags.html
--[====[
brewingplus
===========

Tags: fort | gameplay

Short one-sentence description.

Longer description ...

Usage
-----

    enable brewingplus
    disable brewingplus
]====]

local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')
local repeatUtil = require('repeat-util')
local eventful = require "plugins.eventful"
local utils = require "utils"
local gui = require('gui')

local GLOBAL_KEY = 'brewingplus'

local MAX_SLOTS = 3

local tracked_racks = nil
local tracked_racks_unsavable = nil
local current_rack = nil

local sheet = df.global.game.main_interface.view_sheets
local scroll_pos = sheet.scroll_position_linked_buildings

FermentingWidget = defclass(FermentingWidget, overlay.OverlayWidget)
FermentingWidget.ATTRS{
    name="FermentingWidget",
    default_enabled = true,
    default_pos={x=-41, y=24},
    frame = {w=56, h=7},
    frame_style=gui.FRAME_MEDIUM,
    frame_background=gui.CLEAR_PEN,
    viewscreens = 'dwarfmode/ViewSheets/BUILDING/Workshop/Custom/BARREL_RACK/Tasks'
}

FermentingWidgetItems = defclass(FermentingWidgetItems, overlay.OverlayWidget)
FermentingWidgetItems.ATTRS{
    name="FermentingWidgetItems",
    default_enabled = true,
    default_pos={x=-39, y=43},
    frame = {w=59},
    auto_height = true,
    viewscreens = 'dwarfmode/ViewSheets/BUILDING/Workshop/Custom/BARREL_RACK/Tasks'
}

function findRack(building)
    if(tracked_racks == nil or building == nil) then
        return nil
    end

    for i = 1, #tracked_racks, 1 do
        if( building.centerx == tracked_racks[i].building_x and
            building.centery == tracked_racks[i].building_y and
            building.z == tracked_racks[i].building_z) then
            
            return tracked_racks[i]
        end
    end

    return nil
end

function findRackIdx(building)
    --print("SEARCHING RACKS")
    if(tracked_racks == nil or building == nil or #tracked_racks == 0) then
        return nil
    end

    for i = 1, #tracked_racks, 1 do
        if( tracked_racks[i] ~= nil and
            building.centerx == tracked_racks[i].building_x and
            building.centery == tracked_racks[i].building_y and
            building.z == tracked_racks[i].building_z)  then
            
            return i
        end
    end

    return nil
end

function FermentingWidget:up_time()
    rack_id = findRackIdx(current_rack)

    tracked_racks[rack_id].ferment_time = tracked_racks[rack_id].ferment_time + 1
    dfhack.persistent.saveSiteData('brewingplus_data', tracked_racks)
end

function FermentingWidget:down_time()
    rack_id = findRackIdx(current_rack)

    tracked_racks[rack_id].ferment_time = tracked_racks[rack_id].ferment_time - 1

    if(tracked_racks[rack_id].ferment_time == -2) then
        tracked_racks[rack_id].ferment_time = -1
    end

    dfhack.persistent.saveSiteData('brewingplus_data', tracked_racks)
end

function FermentingWidget:disable()
    rack_id = findRackIdx(current_rack)

    if(tracked_racks[rack_id].ferment_time == 0) then
        tracked_racks[rack_id].ferment_time = -1
    else
        tracked_racks[rack_id].ferment_time = 0
    end
    
    dfhack.persistent.saveSiteData('brewingplus_data', tracked_racks)
end

function FermentingWidget:aging_toggle()
    rack_id = findRackIdx(current_rack)

    if(tracked_racks[rack_id].aging) then
        tracked_racks[rack_id].aging = false
    else
        tracked_racks[rack_id].aging = true
    end

    dfhack.persistent.saveSiteData('brewingplus_data', tracked_racks)
end

function buildingLookUp(id)
    local tokens={}
    local lookup={ Workshop=df.workshop_type,Furnace=df.furnace_type,Trap=df.trap_type,
        SiegeEngine=df.siegeengine_type}
    for i in string.gmatch(id, "[^:]+") do
        table.insert(tokens,i)
    end
    local ret={}
    ret.type=df.building_type[tokens[1]]
    if tokens[2] then
        local type_array=lookup[tokens[1]]
        if type_array then
            ret.subtype=type_array[tokens[2]]
        end
        if tokens[2]=="Custom"  and tokens[3] then --TODO cache for faster lookup
            if ret.type==df.building_type.Workshop then
                for k,v in pairs(df.global.world.raws.buildings.workshops) do
                    if v.code==tokens[3] then
                        ret.custom=v.id
                        return ret
                    end
                end
            elseif ret.type==df.building_type.Furnace then
                for k,v in pairs(df.global.world.raws.buildings.furnaces) do
                    if v.code==tokens[3] then
                        ret.custom=v.id
                        return ret
                    end
                end
            end
        end
        qerror("Invalid custom building:"..tokens[3])
    end
    return ret
end

local barrel_rack_bld_desc = buildingLookUp("Workshop:Custom:BARREL_RACK")
local material_info_records = nil

eventful.enableEvent(eventful.eventType.BUILDING, 100)

eventful.onBuildingCreatedDestroyed.brewingplus = function(buildingId)
    --print("[BrewingPlus] Creating Barrel Racks")
    for _, bld in ipairs(df.global.world.buildings.all) do
        if(bld.id == buildingId) then
            if(bld:getSubtype() == barrel_rack_bld_desc.subtype and bld:getCustomType() == barrel_rack_bld_desc.custom)then
                index = #tracked_racks + 1

                for i=1,#tracked_racks do
                    if(tracked_racks[i] == nil) then
                        
                        index = i
                    end
                end

                tracked_racks[index] = {}
                tracked_racks_unsavable[index] = {}
                tracked_racks[index].building_x = bld.centerx
                tracked_racks[index].building_y = bld.centery
                tracked_racks[index].building_z = bld.z
                tracked_racks[index].barrels_name = {nil, nil, nil, nil, nil, nil}
                tracked_racks[index].barrels_type = {nil, nil, nil, nil, nil, nil}
                --tracked_racks[index].barrels_aging = {false, false, false, false, false, false}
                tracked_racks_unsavable[index].job = nil
                tracked_racks_unsavable[index].barrels = {nil, nil, nil, nil, nil, nil}
                tracked_racks_unsavable[index].item_id = {nil, nil, nil, nil, nil, nil}
                tracked_racks[index].barrels_start_days = {nil, nil, nil, nil, nil, nil}
                tracked_racks[index].creator = {nil, nil, nil, nil, nil, nil}
                tracked_racks[index].ferment_time = 0

                dfhack.buildings.constructBuilding{pos = utils.getBuildingCenter(bld), type=df.building_type.DisplayFurniture, abstract =true}
                
                dfhack.persistent.saveSiteData('brewingplus_data', tracked_racks)
            end
        end
    end
end

DRINK_TYPES = 
{
    BEER = 1,
    WINE = 2,
    MEAD = 3, 
}

function Getddmmyyyy(days_)
    days_corrected = days_ -1

    days =(days_corrected % 28) + 1 
    months = ((days_corrected // 28) % 12) + 1
    years = days_corrected // 336

    return "" .. days .. "/" .. months .. "/" .. years
end

function FermentingWidgetItems:init()
    self:addviews { 
        widgets.Label {
            view_id = 'label_barrel_1',
            text = 'Fermenting1...',
            frame= {l = 6},
        },
        widgets.Label {
            view_id = 'label_barrel_1a',
            text = 'Start: xx/xx/xxxx',
            frame= {l = 6},
        },
        widgets.Label {
            view_id = 'label_barrel_2',
            text = 'Fermenting2...',
            frame= {l = 6},
        },
        widgets.Label {
            view_id = 'label_barrel_2a',
            text = 'Start: xx/xx/xxxx',
            frame= {l = 6},
        },
        widgets.Label {
            view_id = 'label_barrel_3',
            text = 'Fermenting3...',
            frame= {l = 6},
        },
        widgets.Label {
            view_id = 'label_barrel_3a',
            text = 'Start: xx/xx/xxxx',
            frame= {l = 6},
        },
      --  widgets.Label {
       --     view_id = 'label_barrel_4',
       --     text = 'Fermenting4...',
      -- -     frame= {l = 6},
      ---  },
     --   widgets.Label {
      --      view_id = 'label_barrel_4a',
     --       text = 'Start: xx/xx/xxxx',
        --    frame= {l = 6},
      --  },
      --  widgets.Label {
     --       view_id = 'label_barrel_5',
       --     text = 'Fermenting4...',
       --     frame= {l = 6},
      --  },
      --  widgets.Label {
      --      view_id = 'label_barrel_5a',
      --      text = 'Start: xx/xx/xxxx',
      --      frame= {l = 6},
      --  },
      --  widgets.Label {
      --      view_id = 'label_barrel_6',
      --      text = 'Fermenting4...',
      --      frame= {l = 6},
      --  },
      --  widgets.Label {
       --     view_id = 'label_barrel_6a',
       --     text = 'Start: xx/xx/xxxx',
       --     frame= {l = 6},
      --  }
    }
end

function FermentingWidgetItems:fix_layout()
    local h = self.parent_height - 47
    self.frame.h = h + 1 --includes lower border
end

function FermentingWidgetItems:preUpdateLayout(parent_rect)
    self.parent_height = parent_rect.height
    self:fix_layout()
end

function brewmaster_has_room(unit) 
    if(unit == nil) then
        return false
    end 

    found = false
    for _,v in pairs(unit.owned_buildings) do
       
        for _x,blds in pairs(v.contained_buildings) do
            if(blds._type == df.building_chairst) then
                found = true
            end
        end
    end
    return found
end

function FermentingWidgetItems:onRenderBody(dc)
    local building = dfhack.gui.getSelectedBuilding(true)

    if(building ~= nil) then
        rack_id = findRackIdx(building)
    end
    if(rack_id ~= nil) then
        barrel_indexes = {nil, nil, nil, nil}

        for i=1, #tracked_racks_unsavable[rack_id].barrels do
            for j=1, #building.contained_items-1 do
                if(building.contained_items[j].item.id == tracked_racks_unsavable[rack_id].item_id[i]) then
                    barrel_indexes[i] = j
                end
            end
        end

        brewmaster = nil
        brewmaster_skill_lvl = -1

        brewmaster = dfhack.units.getUnitByNobleRole("BREWMASTER")
        if(brewmaster) then
            brewmaster_skill_lvl = dfhack.units.getEffectiveSkill(brewmaster, df.job_skill.BREWING)
        end

        for slot_i =1, MAX_SLOTS do
            if(barrel_indexes[slot_i] ~= nil) then
                self.subviews["label_barrel_" .. slot_i]:setText("Fermenting...   Started: " ..  Getddmmyyyy(tracked_racks[rack_id].barrels_start_days[slot_i]))

                brewmaster_predict = ""
                time_left =  tracked_racks[rack_id].barrels_start_days[slot_i] + tracked_racks[rack_id].barrels_type[slot_i] - getCurrentAbsDay() 

                if(brewmaster_skill_lvl == 0) then -- Doesnt Know about brewing, zero experience
                    brewmaster_predict = "The brewmaster doesnt know"
                elseif(brewmaster_skill_lvl <= 4) then -- Novice, adequate competent and skilled
                    if(time_left > 35) then
                        brewmaster_predict = "More then a month left"
                    elseif(time_left > 20) then
                        brewmaster_predict = "More then a few weeks left"
                    elseif(time_left > 20) then
                        brewmaster_predict = "Less then a few weeks left"
                    end
                elseif(brewmaster_skill_lvl <= 9) then -- Professionals
                    if(time_left > 32) then
                        brewmaster_predict = "More then a month left"
                    elseif(time_left > 24) then
                        brewmaster_predict = "About a month left"
                    elseif(time_left > 16) then
                        brewmaster_predict = "Less then a month left"
                    elseif(time_left > 10) then
                        brewmaster_predict = "About a couple of weeks left"
                    elseif(time_left > 6) then
                        brewmaster_predict = "About a week left"
                    elseif(time_left > 3) then
                        brewmaster_predict = "A few days left"
                    else
                        brewmaster_predict = "Almost done"
                    end
                else -- Masters
                    brewmaster_predict = "" .. time_left .. " days left" 
                end

                if(brewmaster_has_room(brewmaster) == false ) then
                    brewmaster_predict = "Brewmaster has no office"
                end

                if(brewmaster == nil) then
                    brewmaster_predict = "No Brewmaster assigned"
                end
                

                self.subviews["label_barrel_" .. slot_i .."a"]:setText(brewmaster_predict)
                self.subviews["label_barrel_" .. slot_i].visible = true
                self.subviews["label_barrel_" .. slot_i .. "a"].visible = true

                self.subviews["label_barrel_" .. slot_i].frame.t = 3 - sheet.scroll_position_item + (barrel_indexes[slot_i]-1) * 3
                self.subviews["label_barrel_" .. slot_i .. "a"].frame.t = 5 - sheet.scroll_position_item + (barrel_indexes[slot_i]-1) * 3
                
            else
                self.subviews["label_barrel_" .. slot_i].visible = false
                self.subviews["label_barrel_" .. slot_i .. "a"].visible = false
            end
        end
        self:updateLayout()
    end
end
                      

material_info_drinktypes = {DRINK_TYPES.WINE, --MUSHROOM_HELMET_PLUMP                            
                            DRINK_TYPES.BEER, --GRASS_TAIL_PIG
                            DRINK_TYPES.BEER, --GRASS_WHEAT_CAVE
                            DRINK_TYPES.WINE, --BERRIES_PRICKLE
                            DRINK_TYPES.WINE, --BERRIES_STRAW
                            DRINK_TYPES.BEER, --GRASS_LONGLAND
                            DRINK_TYPES.BEER, --WEED_RAT
                            DRINK_TYPES.WINE, --BERRIES_FISHER
                            DRINK_TYPES.WINE, --VINE_WHIP

                            DRINK_TYPES.WINE, --ARTICHOKE
                            DRINK_TYPES.WINE, --BEET
                            DRINK_TYPES.WINE, --WILD_CARROT
                            DRINK_TYPES.WINE, --CASSAVA
                            DRINK_TYPES.WINE, --PARSNIP
                            DRINK_TYPES.WINE, --POTATO
                            DRINK_TYPES.WINE, --RADISH
                            DRINK_TYPES.WINE, --SWEET_POTATO
                            DRINK_TYPES.WINE, --TOMATO
                            DRINK_TYPES.WINE, --TOMATILLO
                            DRINK_TYPES.WINE, --TURNIP
                            DRINK_TYPES.WINE, --PASSION_FRUIT
                            DRINK_TYPES.WINE, --GRAPE
                            DRINK_TYPES.WINE, --CRANBERRY
                            DRINK_TYPES.WINE, --BILBERRY
                            DRINK_TYPES.WINE, --BLUEBERRY
                            DRINK_TYPES.WINE, --BLACKBERRY
                            DRINK_TYPES.WINE, --RASPBERRY
                            DRINK_TYPES.WINE, --PINEAPPLE

                            DRINK_TYPES.BEER, --SINGLE-GRAIN_WHEAT
                            DRINK_TYPES.BEER, --TWO-GRAIN_WHEAT
                            DRINK_TYPES.BEER, --SOFT_WHEAT
                            DRINK_TYPES.BEER, --HARD_WHEAT
                            DRINK_TYPES.BEER, --SPELT
                            DRINK_TYPES.BEER, --BARLEY
                            DRINK_TYPES.BEER, --BUCKWHEAT
                            DRINK_TYPES.BEER, --RYE
                            DRINK_TYPES.BEER, --SORGHUM
                            DRINK_TYPES.BEER, --RICE
                            DRINK_TYPES.BEER, --MAIZE
                            DRINK_TYPES.BEER, --QUINOA
                            DRINK_TYPES.BEER, --KANIWA
                            DRINK_TYPES.BEER, --PENDANT_AMARANTH
                            DRINK_TYPES.BEER, --BLOOD_AMARANTH
                            DRINK_TYPES.BEER, --PURPLE_AMARANTH
                            DRINK_TYPES.BEER, --PEARL_MILLET
                            DRINK_TYPES.BEER, --WHITE_MILLET
                            DRINK_TYPES.BEER, --FINGER_MILLET
                            DRINK_TYPES.BEER, --FOXTAIL_MILLET
                            DRINK_TYPES.BEER, --FONIO
                            DRINK_TYPES.BEER, --TEFF

                            DRINK_TYPES.WINE,   --POD_SWEET
                            DRINK_TYPES.WINE,   --POD_SWEET
                            DRINK_TYPES.BEER,   --ROOT_MUCK
                            DRINK_TYPES.BEER,   --TUBER_BLOATED
                            DRINK_TYPES.WINE,   --HERB_VALLEY
                            DRINK_TYPES.BEER,   --REED_ROPE
                            DRINK_TYPES.BEER,   --SLIVER_BARB
                            DRINK_TYPES.WINE,   --BERRY_SUN
                            DRINK_TYPES.WINE,   --MANGO
                            DRINK_TYPES.WINE,   --BANANA
                            DRINK_TYPES.WINE,   --CARAMBOLA
                            DRINK_TYPES.WINE,   --DURIAN
                            DRINK_TYPES.WINE,   --GUAVA
                            DRINK_TYPES.WINE,   --PAPAYA
                            DRINK_TYPES.WINE,   --RAMBUTAN
                            DRINK_TYPES.WINE,   --CUSTARD-APPLE
                            DRINK_TYPES.WINE,   --DATE_PALM
                            DRINK_TYPES.WINE,   --LYCHEE
                            DRINK_TYPES.WINE,   --POMEGRANATE
                            DRINK_TYPES.WINE,   --APPLE
                            DRINK_TYPES.WINE,   --APRICOT
                            DRINK_TYPES.WINE,   --BAYBERRY
                            DRINK_TYPES.WINE,   --CHERRY
                            DRINK_TYPES.WINE,   --PEACH
                            DRINK_TYPES.WINE,   --PEAR
                            DRINK_TYPES.WINE,   --PERSIMMON
                            DRINK_TYPES.WINE,   --PLUM
                            DRINK_TYPES.WINE,   --SAND_PEAR
                            DRINK_TYPES.MEAD,   -- HONEYBEEMEAD
                            DRINK_TYPES.MEAD}   -- BUMBLEBEEMEAD

material_info_records= {    dfhack.matinfo.find("MUSHROOM_HELMET_PLUMP:FERMENT"),
                            dfhack.matinfo.find("GRASS_TAIL_PIG:FERMENT"),
                            dfhack.matinfo.find("GRASS_WHEAT_CAVE:FERMENT"),
                            dfhack.matinfo.find("BERRIES_PRICKLE:FERMENT"),
                            dfhack.matinfo.find("BERRIES_STRAW:FERMENT"),
                            dfhack.matinfo.find("GRASS_LONGLAND:FERMENT"),
                            dfhack.matinfo.find("WEED_RAT:FERMENT"),
                            dfhack.matinfo.find("BERRIES_FISHER:FERMENT"),
                            dfhack.matinfo.find("VINE_WHIP:FERMENT"),

                            dfhack.matinfo.find("ARTICHOKE:FERMENT"),
                            dfhack.matinfo.find("BEET:FERMENT"),
                            dfhack.matinfo.find("WILD_CARROT:FERMENT"),
                            dfhack.matinfo.find("CASSAVA:FERMENT"),
                            dfhack.matinfo.find("PARSNIP:FERMENT"),
                            dfhack.matinfo.find("POTATO:FERMENT"),
                            dfhack.matinfo.find("RADISH:FERMENT"),
                            dfhack.matinfo.find("SWEET_POTATO:FERMENT"),
                            dfhack.matinfo.find("TOMATO:FERMENT"),
                            dfhack.matinfo.find("TOMATILLO:FERMENT"),
                            dfhack.matinfo.find("TURNIP:FERMENT"),
                            dfhack.matinfo.find("PASSION_FRUIT:FERMENT"),
                            dfhack.matinfo.find("GRAPE:FERMENT"),
                            dfhack.matinfo.find("CRANBERRY:FERMENT"),
                            dfhack.matinfo.find("BILBERRY:FERMENT"),
                            dfhack.matinfo.find("BLUEBERRY:FERMENT"),
                            dfhack.matinfo.find("BLACKBERRY:FERMENT"),
                            dfhack.matinfo.find("RASPBERRY:FERMENT"),
                            dfhack.matinfo.find("PINEAPPLE:FERMENT"),

                            dfhack.matinfo.find("SINGLE-GRAIN_WHEAT:FERMENT"),
                            dfhack.matinfo.find("TWO-GRAIN_WHEAT:FERMENT"),
                            dfhack.matinfo.find("SOFT_WHEAT:FERMENT"),
                            dfhack.matinfo.find("HARD_WHEAT:FERMENT"),
                            dfhack.matinfo.find("SPELT:FERMENT"),
                            dfhack.matinfo.find("BARLEY:FERMENT"),
                            dfhack.matinfo.find("BUCKWHEAT:FERMENT"),
                            dfhack.matinfo.find("RYE:FERMENT"),
                            dfhack.matinfo.find("SORGHUM:FERMENT"),
                            dfhack.matinfo.find("RICE:FERMENT"),
                            dfhack.matinfo.find("MAIZE:FERMENT"),
                            dfhack.matinfo.find("QUINOA:FERMENT"),
                            dfhack.matinfo.find("KANIWA:FERMENT"),
                            dfhack.matinfo.find("PENDANT_AMARANTH:FERMENT"),
                            dfhack.matinfo.find("BLOOD_AMARANTH:FERMENT"),
                            dfhack.matinfo.find("PURPLE_AMARANTH:FERMENT"),
                            dfhack.matinfo.find("PEARL_MILLET:FERMENT"),
                            dfhack.matinfo.find("WHITE_MILLET:FERMENT"),
                            dfhack.matinfo.find("FINGER_MILLET:FERMENT"),
                            dfhack.matinfo.find("FOXTAIL_MILLET:FERMENT"),
                            dfhack.matinfo.find("FONIO:FERMENT"),
                            dfhack.matinfo.find("TEFF:FERMENT"),

                            dfhack.matinfo.find("POD_SWEET:FERMENT"),
                            dfhack.matinfo.find("POD_SWEET:FERMENT2"),
                            dfhack.matinfo.find("ROOT_MUCK:FERMENT"),
                            dfhack.matinfo.find("TUBER_BLOATED:FERMENT"),
                            dfhack.matinfo.find("HERB_VALLEY:FERMENT"),
                            dfhack.matinfo.find("REED_ROPE:FERMENT"),
                            dfhack.matinfo.find("SLIVER_BARB:FERMENT"),
                            dfhack.matinfo.find("BERRY_SUN:FERMENT"),
                            dfhack.matinfo.find("MANGO:FERMENT"),
                            dfhack.matinfo.find("BANANA:FERMENT"),
                            dfhack.matinfo.find("CARAMBOLA:FERMENT"),
                            dfhack.matinfo.find("DURIAN:FERMENT"),
                            dfhack.matinfo.find("GUAVA:FERMENT"),
                            dfhack.matinfo.find("PAPAYA:FERMENT"),
                            dfhack.matinfo.find("RAMBUTAN:FERMENT"),
                            dfhack.matinfo.find("CUSTARD-APPLE:FERMENT"),
                            dfhack.matinfo.find("DATE_PALM:FERMENT"),
                            dfhack.matinfo.find("LYCHEE:FERMENT"),
                            dfhack.matinfo.find("POMEGRANATE:FERMENT"),
                            dfhack.matinfo.find("APPLE:FERMENT"),
                            dfhack.matinfo.find("APRICOT:FERMENT"),
                            dfhack.matinfo.find("BAYBERRY:FERMENT"),
                            dfhack.matinfo.find("CHERRY:FERMENT"),
                            dfhack.matinfo.find("PEACH:FERMENT"),
                            dfhack.matinfo.find("PEAR:FERMENT"),
                            dfhack.matinfo.find("PERSIMMON:FERMENT"),
                            dfhack.matinfo.find("PLUM:FERMENT"),
                            dfhack.matinfo.find("SAND_PEAR:FERMENT"),
                            dfhack.matinfo.find("HONEY_BEE:FERMENT"),
                            dfhack.matinfo.find("BUMBLEBEE:FERMENT")}

material_info_drink = {     dfhack.matinfo.find("MUSHROOM_HELMET_PLUMP:DRINK"), -- 1
                            dfhack.matinfo.find("GRASS_TAIL_PIG:DRINK"),
                            dfhack.matinfo.find("GRASS_WHEAT_CAVE:DRINK"),
                            dfhack.matinfo.find("BERRIES_PRICKLE:DRINK"),
                            dfhack.matinfo.find("BERRIES_STRAW:DRINK"),
                            dfhack.matinfo.find("GRASS_LONGLAND:DRINK"),
                            dfhack.matinfo.find("WEED_RAT:DRINK"),
                            dfhack.matinfo.find("BERRIES_FISHER:DRINK"),
                            dfhack.matinfo.find("VINE_WHIP:DRINK"),

                            dfhack.matinfo.find("ARTICHOKE:DRINK"),
                            dfhack.matinfo.find("BEET:DRINK"),
                            dfhack.matinfo.find("WILD_CARROT:DRINK"),
                            dfhack.matinfo.find("CASSAVA:DRINK"),
                            dfhack.matinfo.find("PARSNIP:DRINK"),
                            dfhack.matinfo.find("POTATO:DRINK"),
                            dfhack.matinfo.find("RADISH:DRINK"),
                            dfhack.matinfo.find("SWEET_POTATO:DRINK"),
                            dfhack.matinfo.find("TOMATO:DRINK"),
                            dfhack.matinfo.find("TOMATILLO:DRINK"),
                            dfhack.matinfo.find("TURNIP:DRINK"),
                            dfhack.matinfo.find("PASSION_FRUIT:DRINK"),
                            dfhack.matinfo.find("GRAPE:DRINK"),
                            dfhack.matinfo.find("CRANBERRY:DRINK"),
                            dfhack.matinfo.find("BILBERRY:DRINK"),
                            dfhack.matinfo.find("BLUEBERRY:DRINK"),
                            dfhack.matinfo.find("BLACKBERRY:DRINK"),
                            dfhack.matinfo.find("RASPBERRY:DRINK"),
                            dfhack.matinfo.find("PINEAPPLE:DRINK"),

                            dfhack.matinfo.find("SINGLE-GRAIN_WHEAT:DRINK"),
                            dfhack.matinfo.find("TWO-GRAIN_WHEAT:DRINK"),
                            dfhack.matinfo.find("SOFT_WHEAT:DRINK"),
                            dfhack.matinfo.find("HARD_WHEAT:DRINK"),
                            dfhack.matinfo.find("SPELT:DRINK"),
                            dfhack.matinfo.find("BARLEY:DRINK"),
                            dfhack.matinfo.find("BUCKWHEAT:DRINK"),
                            dfhack.matinfo.find("RYE:DRINK"),
                            dfhack.matinfo.find("SORGHUM:DRINK"),
                            dfhack.matinfo.find("RICE:DRINK"),
                            dfhack.matinfo.find("MAIZE:DRINK"),
                            dfhack.matinfo.find("QUINOA:DRINK"),
                            dfhack.matinfo.find("KANIWA:DRINK"),
                            dfhack.matinfo.find("PENDANT_AMARANTH:DRINK"),
                            dfhack.matinfo.find("BLOOD_AMARANTH:DRINK"),
                            dfhack.matinfo.find("PURPLE_AMARANTH:DRINK"),
                            dfhack.matinfo.find("PEARL_MILLET:DRINK"),
                            dfhack.matinfo.find("WHITE_MILLET:DRINK"),
                            dfhack.matinfo.find("FINGER_MILLET:DRINK"),
                            dfhack.matinfo.find("FOXTAIL_MILLET:DRINK"),
                            dfhack.matinfo.find("FONIO:DRINK"),
                            dfhack.matinfo.find("TEFF:DRINK"),  -- 50

                            dfhack.matinfo.find("POD_SWEET:DRINK"),
                            dfhack.matinfo.find("POD_SWEET:DRINK2"),
                            dfhack.matinfo.find("ROOT_MUCK:DRINK"),
                            dfhack.matinfo.find("TUBER_BLOATED:DRINK"),
                            dfhack.matinfo.find("HERB_VALLEY:DRINK"),
                            dfhack.matinfo.find("REED_ROPE:DRINK"),
                            dfhack.matinfo.find("SLIVER_BARB:DRINK"),
                            dfhack.matinfo.find("BERRY_SUN:DRINK"),
                            dfhack.matinfo.find("MANGO:DRINK"),
                            dfhack.matinfo.find("BANANA:DRINK"),
                            dfhack.matinfo.find("CARAMBOLA:DRINK"),
                            dfhack.matinfo.find("DURIAN:DRINK"),
                            dfhack.matinfo.find("GUAVA:DRINK"),
                            dfhack.matinfo.find("PAPAYA:DRINK"),
                            dfhack.matinfo.find("RAMBUTAN:DRINK"),
                            dfhack.matinfo.find("CUSTARD-APPLE:DRINK"),
                            dfhack.matinfo.find("DATE_PALM:DRINK"),
                            dfhack.matinfo.find("LYCHEE:DRINK"),
                            dfhack.matinfo.find("POMEGRANATE:DRINK"),
                            dfhack.matinfo.find("APPLE:DRINK"),
                            dfhack.matinfo.find("APRICOT:DRINK"),
                            dfhack.matinfo.find("BAYBERRY:DRINK"),
                            dfhack.matinfo.find("CHERRY:DRINK"),
                            dfhack.matinfo.find("PEACH:DRINK"),
                            dfhack.matinfo.find("PEAR:DRINK"),
                            dfhack.matinfo.find("PERSIMMON:DRINK"),
                            dfhack.matinfo.find("PLUM:DRINK"),
                            dfhack.matinfo.find("SAND_PEAR:DRINK"),
                            dfhack.matinfo.find("HONEY_BEE:DRINK"),
                            dfhack.matinfo.find("BUMBLEBEE:DRINK")}

local last_month = 0
local current_month = 0

input_filter_defaults = {
    item_type = -1,
    item_subtype = -1,
    mat_type = -1,
    mat_index = -1,
    flags1 = {},
    -- Instead of noting those that allow artifacts, mark those that forbid them.
    -- Leaves actually enabling artifacts to the discretion of the API user,
    -- which is the right thing because unlike the game UI these filters are
    -- used in a way that does not give the user a chance to choose manually.
    flags2 = { allow_artifact = true },
    flags3 = {},
    flags4 = 0,
    flags5 = 0,
    reaction_class = '',
    has_material_reaction_product = '',
    metal_ore = -1,
    min_dimension = -1,
    has_tool_use = -1,
    quantity = 1
}

function clean_tracked_racks()
    for i=1, #tracked_racks do
        if(tracked_racks[i] == nil) then
            goto continue_clean_racks
        end
        bld = dfhack.buildings.findAtTile(tracked_racks[i].building_x, tracked_racks[i].building_y, tracked_racks[i].building_z)
        if( bld == nil or 
            bld:getSubtype() ~= barrel_rack_bld_desc.subtype or 
            bld:getCustomType() ~= barrel_rack_bld_desc.custom) then
            
            tracked_racks[i] = nil
        end

        ::continue_clean_racks::
    end
end

---checks that unit can path to workshop
---@param unit df.unit
---@param workshop df.building_workshopst
---@return boolean
function canAccessWorkshop(unit, workshop)
    local workshop_position = xyz2pos(workshop.centerx, workshop.centery, workshop.z)
    return dfhack.maps.canWalkBetween(unit.pos, workshop_position)
end

---check if unit can perform labor at workshop
---@param unit df.unit
---@param unit_labor df.unit_labor
---@param workshop df.building
---@return boolean
function availableLaborer(unit, unit_labor, workshop)
    return unit.status.labors[unit_labor]
       and dfhack.units.isJobAvailable(unit)
       and canAccessWorkshop(unit, workshop)
end

---find unit with a particular labor enabled
---@param unit_labor df.unit_labor
---@param job_skill df.job_skill
---@param workshop df.building
---@return df.unit|nil
---@return integer|nil
 function findAvailableLaborer(unit_labor, job_skill, workshop)
    local max_unit = nil
    local max_skill = -1
    for _, unit in ipairs(dfhack.units.getCitizens(true, false)) do
        if
            availableLaborer(unit, unit_labor, workshop)
        then
            local unit_skill = dfhack.units.getNominalSkill(unit, job_skill, true)
            if unit_skill > max_skill then
                max_unit = unit
                max_skill = unit_skill
            end
        end
    end
    return max_unit, max_skill
end

function checkMaterial(mat_type, mat_index) 
    for j=1, #material_info_records do
        if(mat_type == material_info_records[j].type and mat_index == material_info_records[j].index) then
            return j
        end
    end
    return nil
end

function checkMaterialDrinks(mat_type, mat_index) 
    for j=1, #material_info_drink do
        if(mat_type == material_info_drink[j].type and mat_index == material_info_drink[j].index) then
            return j
        end
    end
    return nil
end


local function findFermentableBarrel(min_stack, stockpile_list)
    local possible_targets = {}
    local items = {}

    if(stockpile_list and #stockpile_list > 0) then
        for targets_i=1, #stockpile_list do
            items = dfhack.buildings.getStockpileContents(stockpile_list[targets_i])

            for items_i = 1, #items do
                possible_targets[#possible_targets + 1] = items[items_i]
            end
        end
    else
        for items_i = 1, #df.global.world.items.other.FOOD_STORAGE do
            possible_targets[#possible_targets + 1] = df.global.world.items.other.FOOD_STORAGE[items_i-1]
        end
    end

    for _, container in ipairs(possible_targets) do
        if
            not (container.flags.in_job or container.flags.forbid) and
            container.flags.container and #container.general_refs >= min_stack
        then
            local content_reference = dfhack.items.getGeneralRef(container, df.general_ref_type.CONTAINS_ITEM)
            local contained_item = df.item.find(content_reference and content_reference.item_id or -1)
            if contained_item then
                local mat_info = dfhack.matinfo.decode(contained_item)
                local found_mat = checkMaterial(mat_info.type, mat_info.index)
                local distilled = false

                if(aging) then
                    found_mat = checkMaterialDrinks(mat_info.type, mat_info.index)
                end

                if(found_mat) then
                     for rack_i=1, #tracked_racks do
                        if(tracked_racks[rack_i] == nil) then
                            goto continue_rackloop
                        end
                        for barrel_i=1, MAX_SLOTS do

                            barrel = tracked_racks_unsavable[rack_i].barrels[barrel_i]

                            if(barrel == container) then
                                goto continue_findfermentablebarrel
                            end
                        end
                        ::continue_rackloop::
                    end
                    return container
                end
            end
        end
        ::continue_findfermentablebarrel::
    end
end

function getCurrentAbsDay()
    return dfhack.world.ReadCurrentYear() * 336 +  dfhack.world.ReadCurrentMonth() * 28 + dfhack.world.ReadCurrentDay()
end

---
---   
---     From what I gathered in Wikipedia:
---     Wine has several phases  in production, im going to simplify everything to "put it in a barrel and forget it" for 2-n months
---     
---     Mead seems to be very similar to wine as well so Ill treat it exactly the same
---
---     Beer seems to also have some phases, but Im going to treat it like wine and do the same thing but with a shorter time like 3 weeks to 3 months
---
---     Distillation should be quicker, but still take a few weeks and spend fuel but in the end be more a more valuable base
---     
---     Values go from 
---     Beer - 2 base value same as normal game (Sewer Brew at 1)
---     Wine - 3 base value (Prickle Berry at 2)
---     Mead - 3 base value 
---     Spirits - 4 base value (The more expensive one, makes sense as it needs fuel and uncommon crops)
--- 
---     Every 2 weeks in storage over the sufficient time to ferment into wine adds some base value
---      1 for beer
---      2 for wine
---      3 for mead
---      4 for spirits


FERMENTATION_DURATION = {
    30, 
    45, 
    15,
}

FERMENTATION_VALUE = {
    1,  --BEER
    3,  --WINE
    2, -- MEAD
    10, --spirits
}

function month_call() 
   --print("periodic call")
    clean_tracked_racks()
    dfhack.persistent.saveSiteData('brewingplus_data', tracked_racks)

   -- print("tracking " .. #tracked_racks .. " " .. #tracked_racks_unsavable)


    for rack_i = 1, #tracked_racks do
        if(tracked_racks[rack_i] ~= nil) then
            for barrel_i = 1, MAX_SLOTS do
                if(tracked_racks_unsavable[rack_i].barrels[barrel_i] ~= nil) then
                    if(tracked_racks[rack_i].barrels_start_days[barrel_i] ~= nil)then
                        if( getCurrentAbsDay() - 
                            tracked_racks[rack_i].barrels_start_days[barrel_i] > 
                            tracked_racks[rack_i].barrels_type[barrel_i]) then
                            local contents = dfhack.items.getContainedItems(tracked_racks_unsavable[rack_i].barrels[barrel_i])
                            local mat_info = nil
                            local found_mat = nil
                            local drink_type = nil
                            local distilled = false

                            mat_info = dfhack.matinfo.decode(contents[1])

                           -- if(tracked_racks[rack_i].barrels_aging[barrel_i]) then
                             --   found_mat = checkMaterialDrinks(mat_info.type, mat_info.index)

--                                if(found_mat > 50) then
  --                                  found_mat = found_mat - 50
    --                                distilled = true
      --                          end
        --                    else
                                found_mat = checkMaterial(mat_info.type, mat_info.index)
           --                 end

                            --print("Found mat = " .. found_mat)

                            total_fermentable = 0
                            
                            for contents_i = 1, #contents do
                                total_fermentable = total_fermentable + contents[contents_i]:getStackSize()    
                                --print("total fermentable = " .. total_fermentable)
                            end
                            
                            if(found_mat ~= nil) then
                                --print("Creating Item")
                                creator = tracked_racks[rack_i].creator[barrel_i]
                                found_creator = nil

                                for _, unit in pairs(df.global.world.units.active) do
                                    if(unit.id == creator) then
                                        found_creator = unit
                                    end
                                end

                                if(found_creator == nil) then
                                    goto skip_create_item
                                end

                                --if(tracked_racks[rack_i].barrels_aging[barrel_i] == false) then
                                   
                                   -- print("type = " .. material_info_drink[found_mat].type)
                                    --print("index = " .. material_info_drink[found_mat].index)
                                    items = dfhack.items.createItem(found_creator, 
                                                                    dfhack.items.findType("DRINK"), -1, 
                                                                    material_info_drink[found_mat].type, 
                                                                    material_info_drink[found_mat].index)
                                    item = items[1]

                                    item:setStackSize(total_fermentable)
                                --else
                                 --   item = contents[1]
                                --end

                                drink_type = material_info_drinktypes[found_mat]

                                --[[ originally it was intended that aging the drinks would make them more valuable, but I cant change
                                     the values of individual barrels of drinks, so the idea was scrapped

                                if(distilled) then
                                    item.value = material_info_distilled_values[found_mat] + tracked_racks[rack_i].ferment_time * FERMENTATION_VALUE[4]
                                else
                                    print("material_info_base_values[drink_type]" ..  material_info_base_values[found_mat])
                                    print("tracked_racks[rack_i].ferment_time" ..  tracked_racks[rack_i].ferment_time)
                                    print("FERMENTATION_VALUE[drink_type]" ..  FERMENTATION_VALUE[found_mat])
                                    item.value = material_info_base_values[found_mat] + tracked_racks[rack_i].ferment_time * FERMENTATION_VALUE[drink_type]
                                end
                                --]]
                                --if(tracked_racks[rack_i].barrels_aging[barrel_i] == false) then
                                    dfhack.items.moveToContainer(item, tracked_racks_unsavable[rack_i].barrels[barrel_i])

                                    for contents_i = 1, #contents do
                                        dfhack.items.remove(contents[contents_i])
                                    end
                                --end
                            end
   --                         bld = dfhack.items.getHolderBuilding(tracked_racks[rack_i].barrels[barrel_i])

                            ::skip_create_item::
                            dfhack.items.moveToBuilding(tracked_racks_unsavable[rack_i].barrels[barrel_i], bld, df.building_item_role_type.TEMP)
                            tracked_racks_unsavable[rack_i].barrels[barrel_i].flags.in_building = false
                            --tracked_racks_unsavable[rack_i].barrels[barrel_i].use_mode = df.building_item_role_type.TEMP
                            --tracked_racks_unsavable[rack_i].barrels[barrel_i].flags.in_building = false
                            --dfhack.items.moveToGround(tracked_racks_unsavable[rack_i].barrels[barrel_i], {  x = tracked_racks[rack_i].building_x,
                            --                                                                                y = tracked_racks[rack_i].building_y, 
                            --                                                                                z = tracked_racks[rack_i].building_z})

                            tracked_racks_unsavable[rack_i].item_id[barrel_i] = nil
                            tracked_racks_unsavable[rack_i].barrels[barrel_i] = nil
                            tracked_racks[rack_i].barrels_name[barrel_i] = nil
                            tracked_racks[rack_i].barrels_type[barrel_i] = nil
                            tracked_racks[rack_i].barrels_start_days[barrel_i] = nil
                            --tracked_racks[rack_i].barrels_aging[barrel_i] = false

          --                  local temp_tracked_racks = tracked_racks
        --                    local temp_tracked_racks_uns = tracked_racks_unsavable

      --                      for rack_ip = rack_i, MAX_SLOTS-1 do
    --                            temp_tracked_racks[rack_ip] = tracked_racks[rack_ip+1]
  --                              temp_tracked_racks_uns[rack_ip] = tracked_racks_unsavable[rack_ip+1]
--                            end

                            --tracked_racks = temp_tracked_racks
                            --tracked_racks_unsavable = temp_tracked_racks_uns

                            --barrel_i = barrel_i -1 
                        end
                    end
                end
                ::month_call_continue::
            end
        end
    end
end

function GetStockpileLinksTo(bld)
    local sps = df.global.world.buildings.other.STOCKPILE

    local sps_with_links = {}

    for sp_i=1, #sps do
       -- print("sps " .. #sps)
        if(sps[sp_i-1].links == nil) then
            goto continue_get_stockpiles_to
        end

        for wsp_i=1, #sps[sp_i-1].links.give_to_workshop do
            if(#sps[sp_i-1].links.give_to_workshop >= 1) then
                list_to = sps[sp_i-1].links.give_to_workshop
                if(sps[sp_i-1].links.give_to_workshop[wsp_i-1] == bld) then
                    sps_with_links[#sps_with_links+1] = sps[sp_i-1]
                end
            end
        end

        ::continue_get_stockpiles_to::
    end

    return sps_with_links
end

function GetStockpileLinksFrom(bld)
    sps = df.global.world.buildings.other.STOCKPILE

    sps_with_links = {}
    
    for sp_i=1, #sps do
        if(sps[sp_i].links == nil) then
            goto continue_get_stockpiles_from
        end

        for wsp_i=1, #sps[sp_i].links.take_from_workshop do
            if(#sps[sp_i].links.take_from_workshop >= 1) then
                if(sps[sp_i].links.take_from_workshop[wsp_i] == bld) then
                    sps_with_links[#sps_with_links] = sps[sp_i]
                end
            end
        end

        ::continue_get_stockpiles_from:: 
    end

    return sps_with_links
end
  
function CancelJob(unit)
    local c_job=unit.job.current_job
    if c_job then
        unit.job.current_job =nil --todo add real cancelation
        for k,v in pairs(c_job.general_refs) do
            if df.general_ref_unit_workerst:is_instance(v) then
                v:delete()
                c_job.general_refs:erase(k)
                return
            end
        end
    end
end

local function RemoveJob(item)
    local inJob = dfhack.items.getSpecificRef(item, df.specific_ref_type.JOB)
    local job = inJob and inJob.data.job
    if job then dfhack.job.removeJob(job) end
end

function update_tick()
    if(tracked_racks == nil) then
        return
    end
    --print("tick call")
    current_month = getCurrentAbsDay()
    if(current_month - last_month > 1) then
        month_call()
        last_month = current_month
    end

    for i=1, #tracked_racks do
        if(tracked_racks[i] == nil) then
            goto continue
        end

        bld = dfhack.buildings.findAtTile(tracked_racks[i].building_x, tracked_racks[i].building_y, tracked_racks[i].building_z)

        if(bld and bld.flags.exists and tracked_racks[i].ferment_time ~= -1 and tracked_racks_unsavable[i].job == nil) then
            --print("Debug - BrewingPlus Creating job rack")
            local pos = utils.getBuildingCenter(bld)

            free_index = -1
            for barrel_i = MAX_SLOTS, 1, -1 do
                if(tracked_racks_unsavable[i].barrels[barrel_i] == nil) then
                    free_index = barrel_i
                end
            end

            if(free_index == -1) then -- No free slot, abort
               -- print("Debug - BrewingPlus No Free Slot in rack")
                goto continue
            end

            local stockpile_list = GetStockpileLinksTo(bld)

            barrel =  findFermentableBarrel(1, stockpile_list)

            if(barrel == nil) then
               -- print("Debug - BrewingPlus No Barrel")
                goto continue
            end

            local job = dfhack.job.createLinked()
            job.job_type = df.job_type.StoreItemInLocation
            job.pos = pos

           -- print("found = " .. #stockpile_list)

            if not dfhack.job.attachJobItem(job, barrel, df.job_role_type.Hauled, -1, -1) then
                dfhack.error('could not attach item')
            end

            dfhack.job.assignToWorkshop(job, bld)

            worker, _  = findAvailableLaborer(df.unit_labor.HAUL_ITEM, df.job_skill.BREWING, bld)

            if(worker == nil) then
               -- print("Debug - BrewingPlus No Worker")
                goto continue
            end

            tracked_racks[i].creator[free_index] = worker.id

            dfhack.job.addWorker(job, worker)
            dfhack.units.setPathGoal(worker, barrel.pos, df.unit_path_goal.GrabJobResources)

            job.items[0].flags.is_fetching = true
            job.flags.fetching = true            

            local contents = dfhack.items.getContainedItems(barrel)

            tracked_racks[i].current_target_index = free_index
            tracked_racks[i].barrels_name[free_index] = dfhack.items.getDescription(barrel, 0) .. dfhack.items.getDescription(contents[1], 0) -- Nasty hack, apparently ID`s arent shared between sessions, 
            tracked_racks_unsavable[i].barrels[free_index] = barrel
            tracked_racks_unsavable[i].item_id[free_index] = barrel.id
            tracked_racks_unsavable[i].job = job
         --   tracked_racks[i].barrels_aging[free_index] = false

            mat_info = dfhack.matinfo.decode(contents[1])
            found_mat = checkMaterial(mat_info.type, mat_info.index)

            if(found_mat == nil) then
                found_mat = checkMaterialDrinks(mat_info.type, mat_info.index)

                if(found_mat == nil) then
                    print("ERROR! Attempting to ferment unknown liquid")
                    goto continue
                end

                --tracked_racks[i].barrels_aging[free_index] = true
            end


           -- if(tracked_racks[i].barrels_aging[free_index] ==  false) then
                drink_type = material_info_drinktypes[found_mat]
                ferment_time = FERMENTATION_DURATION[drink_type]
           -- else
            --    drink_type = material_info_drinktypes[found_mat]
            --    ferment_time = 7
            --end
            
            
            tracked_racks[i].barrels_type[free_index] = ferment_time

            
            dfhack.persistent.saveSiteData('brewingplus_data', tracked_racks)

            --local strMove = 'Tasking %d %s for immediate burial.'
            --print(string.format(strMove, item.id, itemName))

           -- local pos = utils.getBuildingCenter(bld)
            --local job = dfhack.job.createLinked()
           -- job.job_type = df.job_type.Entomb
           -- job.pos = pos 

          --  local jitem = df.job_item:new()
           -- jitem.item_type = df.item_type.LIQUID_MISC
           -- jitem.item_subtype=-1
           -- jitem.quantity = 1
           -- jitem.vector_id = df.job_item_vector_id.LIQUID_MISC
           -- jitem.mat_type = material_info_record.type
           -- jitem.mat_index = material_info_record.index
            --job.job_items.elements:insert('#', jitem)

            --dfhack.job.assignToWorkshop(job, bld)
            
        else
            bld = dfhack.buildings.findAtTile(tracked_racks[i].building_x, tracked_racks[i].building_y, tracked_racks[i].building_z)
           
            if(bld and #bld.jobs == 0) then
               -- dfhack.job.removeJob(tracked_racks_unsavable[i].job)
                for barrel_i = 1, MAX_SLOTS do
                    barrel_obj = tracked_racks_unsavable[i].barrels[barrel_i]
                    if(barrel_obj ~= nil) then

                        barrel_obj.flags.forbid = true
                        holder = dfhack.items.getHolderUnit(barrel_obj)

                        if(holder ~= nil) then
                            CancelJob(holder)
                        end

                        barrel_obj.flags.forbid = false

                        if barrel_obj.flags.in_job then RemoveJob(barrel_obj) end

                        success = dfhack.items.moveToGround(tracked_racks_unsavable[i].barrels[barrel_i], utils.getBuildingCenter(bld))
                        success = dfhack.items.moveToBuilding(tracked_racks_unsavable[i].barrels[barrel_i], bld)

                        barrel_obj.flags.in_building = true
                        if(success == true) then
                            tracked_racks_unsavable[i].job = nil
                            tracked_racks[i].barrels_start_days[barrel_i] = getCurrentAbsDay()
                        end
                    end
                end
            end
            
            dfhack.persistent.saveSiteData('brewingplus_data', tracked_racks)
        end
        ::continue::
    end
end

function do_disable()
    --print("Disabling")
end

local args = {...}

if(args[1] == "reset") then
    print("Resetting")
    tracked_racks = {}
    tracked_racks_unsavable = {}
    dfhack.persistent.saveSiteData('brewingplus_data', tracked_racks)
    do_enable()
end

function do_enable()
    --print("Enabling")
    
    repeatUtil.scheduleEvery(GLOBAL_KEY,40,'ticks',update_tick)
    tracked_racks = dfhack.persistent.getSiteData('brewingplus_data', {})

    if(tracked_racks_unsavable == nil) then
        tracked_racks_unsavable = {}
    end

    rack = nil

    for _, bld in ipairs(df.global.world.buildings.all) do
        if(bld:getSubtype() == barrel_rack_bld_desc.subtype and bld:getCustomType() == barrel_rack_bld_desc.custom)then
            index = findRackIdx(bld)
            if(index == nil) then
                index = #tracked_racks + 1

                tracked_racks[index] = {}
                tracked_racks_unsavable[index] = {}
                tracked_racks[index].building_x = bld.centerx
                tracked_racks[index].building_y = bld.centery
                tracked_racks[index].building_z = bld.z
                tracked_racks[index].barrels_name = {nil, nil, nil, nil, nil, nil}
                tracked_racks[index].barrels_type = {nil, nil, nil, nil, nil, nil}
                --tracked_racks[index].barrels_aging = {false, false, false, false, false, false}
                tracked_racks[index].creator = {nil, nil, nil, nil, nil, nil}
                tracked_racks_unsavable[index].job = nil
                tracked_racks_unsavable[index].barrels = {nil, nil, nil, nil, nil, nil}
                tracked_racks_unsavable[index].item_id = {nil, nil, nil, nil, nil, nil}
                tracked_racks[index].barrels_start_days = {nil, nil, nil, nil, nil, nil}
                tracked_racks[index].ferment_time = 0
            else
                tracked_racks_unsavable[index] = {}
                tracked_racks_unsavable[index].job = nil
                tracked_racks_unsavable[index].barrels = {nil, nil, nil, nil, nil, nil}
                tracked_racks_unsavable[index].item_id = {nil, nil, nil, nil, nil, nil}
            end
        end
    end

    for i=1,#tracked_racks do
        rack = dfhack.buildings.findAtTile(tracked_racks[i].building_x, tracked_racks[i].building_y, tracked_racks[i].building_z)

        if not rack or not rack.flags or not rack.flags.exists then goto continue_fermentingwidget_init end

        if(rack ~= nil) then
            already_matched = {}

            for _,barrel in ipairs(rack.contained_items) do
                local contents = dfhack.items.getContainedItems(barrel.item)
                local name = nil
                if(contents ~= nil and contents[1] ~= nil) then 
                    name = dfhack.items.getDescription(barrel.item, 0)
                    name = name .. dfhack.items.getDescription(contents[1], 0) -- Nasty hack, apparently ID`s arent shared between sessions, 
                end

                for id_i = 1, MAX_SLOTS do

                    for matched_id_i= 1 , #already_matched do
                        if(id_i == already_matched[matched_id_i] ) then
                            goto continue_slots 
                        end
                    end

                    if name and name == tracked_racks[i].barrels_name[id_i] then
                        mat_info = dfhack.matinfo.decode(contents[1])
                        found_mat = checkMaterial(mat_info.type, mat_info.index)

                        drink_type = material_info_drinktypes[found_mat]
                        ferment_time = FERMENTATION_DURATION[drink_type]

                        tracked_racks_unsavable[i].barrels[id_i] = barrel.item
                        tracked_racks_unsavable[i].item_id[id_i] = barrel.item.id
                        tracked_racks[index].barrels_type[id_i] = ferment_time

                        already_matched[#already_matched + 1] = id_i
                        goto continue_contained_items
                    end
                    ::continue_slots::
                end
                ::continue_contained_items::
            end
        end
        ::continue_fermentingwidget_init::
    end


   -- self.subviews.label_time:setText("" .. tracked_racks[rack_id].ferment_time .. " months")
end

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_MAP_UNLOADED then
        do_disable()

        -- ensure our mod doesn't run when a different
        -- world is loaded where we are *not* active
        dfhack.onStateChange[GLOBAL_KEY] = nil

        return
    end

    if sc ~= SC_MAP_LOADED or not dfhack.world.isFortressMode() then
        return
    end

    -- retrieve state saved in game. merge with default state so config
    -- saved from previous versions can pick up newer defaults.

    --utils.assign(tracked_racks, dfhack.persistent.getSiteData(brewingplus_data, {}))
    do_enable()
end

function update_selection()
    
end

function FermentingWidget:overlay_onupdate()  
    --
end

function FermentingWidget:init()
    self:addviews {
            widgets.Label{
            view_id='label1',
            text='Current Barrel Rack Status:',
            frame= {t = 0, l = 1}
            },
            widgets.Label{
            view_id='barrel_rack_status',
            text='_______',
            frame= {t = 2, l = 2}
            },
            widgets.HotkeyLabel {
            view_id = 'button_disable',
            label = 'Toggle',
            key = 'CUSTOM_CTRL_O',
            frame= {t = 4, l = 2},
            on_activate = self:callback('disable'),
        },
        --[[
        widgets.Label{
            view_id='label',
            text='Let drinks age for:',
            frame= {t = 2, l = 2}
        },
        widgets.Label{
            view_id='label2',
            text='(More time means more value and more quality!)',
            frame= {t = 3, l = 4}
        },
        widgets.Label{
            view_id='label_time',
            text="RUN \"ENABLE BREWINGPLUS\"",
            frame= {t = 4, l = 4}
        },
        widgets.HotkeyLabel {
            view_id = 'button_up',
            label = 'More Time',
            key = 'CUSTOM_CTRL_P',
            frame= {t = 7, l = 2},
            on_activate = self:callback('up_time'),
        },   
        widgets.HotkeyLabel {
            view_id = 'button_down',
            label = 'Less Time',
            key = 'CUSTOM_CTRL_O',
            frame= {t = 8, l = 2},
            on_activate = self:callback('down_time'),
        },
        widgets.Label{
            view_id='label_more_aging',
            text="Grab drinks for more aging?",
            frame= {t = 10, l = 2}
        },
        widgets.Label{
            view_id='label_more_aging_toggle',
            text="___",
            frame= {t = 11, l = 2}
        },
        widgets.HotkeyLabel {
            view_id = 'label_more_aging_toggle_button',
            label = 'Change',
            key = 'CUSTOM_CTRL_A',
            frame= {t = 12, l = 2},
            on_activate = self:callback('aging_toggle'),
        }
            --]]
    }
end


function FermentingWidget:fix_layout()
    --local h = self.parent_height - 46
    --self.frame.h = h + 1 --includes lower border
end

function FermentingWidget:preUpdateLayout(parent_rect)
    --self.parent_height = parent_rect.height
    self:fix_layout()
end

function FermentingWidget:onRenderBody(dc)
    local building = dfhack.gui.getSelectedBuilding(true)
    
    if(building ~= nil) then
        rack_id = findRackIdx(building)
    end

    current_rack = building

    if(rack_id ~= nil) then
        if(tracked_racks[rack_id].ferment_time == 0) then
            self.subviews.barrel_rack_status:setText("Working")
        else
            self.subviews.barrel_rack_status:setText("Disabled")
        end
        --[[
        if(tracked_racks[rack_id].ferment_time > -1) then
            self.subviews.label_time:setText("" .. tracked_racks[rack_id].ferment_time .. " months")
        else
            self.subviews.label_time:setText("Disabled")
        end

        if(tracked_racks[rack_id].aging) then
            self.subviews.label_more_aging_toggle:setText("yes")
        else
            self.subviews.label_more_aging_toggle:setText("no")
        end
        --]]
    end
end

OVERLAY_WIDGETS = { ferment=FermentingWidget,
                    ferment_items=FermentingWidgetItems}
overlay.rescan()

