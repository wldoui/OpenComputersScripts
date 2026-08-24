local component = require("component")
local gpu = component.gpu

gpu.fill(1, 1, 80, 25, " ")

gpu.set(1, 1, "==============================")
gpu.set(1, 2, "      ENERGY CONTROL")
gpu.set(1, 3, "==============================")

gpu.set(1, 5, "System started.")

while true do
    os.sleep(1)
end