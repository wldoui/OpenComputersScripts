-- ==================================================================
-- data/known_base_components.lua
--
-- This is NOT an HBM API list. It is the set of standard, documented
-- OpenComputers 1.8.9a component TYPE NAMES (the string returned as
-- the second value from component.list()) that ship with the mod
-- itself or its official add-ons -- gpu, screen, filesystem, etc.
--
-- drivers/discovery.lua uses this only to figure out which
-- components on your network are "just OpenComputers" versus
-- everything else (candidates for HBM Space / NTM CE devices), so
-- Stage 5 knows where to point api_inspector.lua next.
--
-- Source: OpenComputers' own component type strings, as documented
-- on the OpenComputers wiki / oc:doc in-game. If your OC build adds
-- or renames one of these, just edit this list -- it changes nothing
-- else in the system.
-- ==================================================================

return {
  ["gpu"] = true,
  ["screen"] = true,
  ["keyboard"] = true,
  ["filesystem"] = true,
  ["computer"] = true,
  ["eeprom"] = true,
  ["modem"] = true,
  ["tunnel"] = true,
  ["internet"] = true,
  ["hologram"] = true,
  ["database"] = true,
  ["redstone"] = true,
  ["sound"] = true,
  ["disk_drive"] = true,
  ["data"] = true,
  ["crafting"] = true,
  ["generator"] = true,
  ["navigation"] = true,
  ["geolyzer"] = true,
  ["robot"] = true,
  ["drone"] = true,
  ["tank_controller"] = true,
  ["leash"] = true,
  ["tractor_beam"] = true,
  ["chunkloader"] = true,
  ["debug"] = true,
  ["carriage"] = true,
  ["motion_sensor"] = true,
  ["glasses"] = true,
  ["inventory_controller"] = true,
  ["experience"] = true,
  ["piston"] = true,
  ["world_sensor"] = true,
  ["neural_interface"] = true,
}
