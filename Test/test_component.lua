local component = require("component")

local battery = component.proxy("1db4f251-fa1d-4a68-8fd0-b15d001327fe")

print(battery.getEnergyInfo())