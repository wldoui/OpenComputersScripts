local component = require("component")

print("=== COMPONENTS ===")
print()

for address, componentType in component.list() do
    print(componentType)
    print("  " .. address)
    print()
end