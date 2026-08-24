local component = require("component")

print("=== HBM ENERGY NETWORK ===")
print()

local count = 0

for address in component.list("ntm_energy_storage") do

    count = count + 1

    local battery =
        component.proxy(address)

    print("--------------------------------")
    print("BATTERY #" .. count)
    print("Address:", address)
    print()

    local current, maximum, delta =
        battery.getEnergyInfo()

    print("Energy:", current, "HE")
    print("Maximum:", maximum, "HE")
    print("Delta:", delta, "HE/s")

    local low, high, priority =
        battery.getModeInfo()

    print()
    print("Mode without redstone:", low)
    print("Mode with redstone:", high)
    print("Priority:", priority)

    local name, charge, discharge =
        battery.getPackInfo()

    print()
    print("Battery:", name)
    print("Charge:", charge, "HE/t")
    print("Discharge:", discharge, "HE/t")
end

print()
print("TOTAL BATTERIES:", count)