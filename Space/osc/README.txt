OPEN SPACE CONTROL v0.1.0
Target: Minecraft 1.12.2 / OpenComputers 1.8.9a / NTM CE 2.5.0.5 / HBM Space 0.9.2

THIS BUILD IS READ-ONLY WITH RESPECT TO HBM SPACE.
It does not launch rockets, change destinations, change energy settings, or mutate HBM machines.

REAL HBM SPACE API USED:
ntm_stardar
- getPlanetStats(string)
- getCurrentPlanet()
- getSatellites(string)

The HBM Space API exposed by the supplied specification does NOT expose satellite/rocket
world-space position or velocity through ntm_stardar. Therefore this build never invents
those values. The 3D viewport renders a blocky planet from real planet statistics and
keeps satellite names in telemetry. Position/velocity remain unavailable until a real
source for them is connected.

INSTALL:
Copy the project files to the computer filesystem, preserving paths.
Run:
  /boot.lua

Or create autorun:
  /boot.lua

API inspector:
  osc_inspect

Space:
  space

IMPORTANT:
For Star Dar, NTM's OC integration is native. The supplied HBM Space documentation says
compatible NTM machines can be connected directly to the OC network by OC cable without
an adapter. If component.list() shows ntm_stardar, the network side is working.

PERFORMANCE:
The renderer targets 10 FPS and uses a small character rasterizer. This is intentionally
CPU-light for OpenComputers. It is not a Minecraft world renderer.
