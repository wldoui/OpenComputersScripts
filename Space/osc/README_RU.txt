OPEN SPACE CONTROL v0.1.1
==========================
Цель: Minecraft 1.12.2 / OpenComputers / NTM CE 2.5.0.5 / HBM Space 0.9.2

ЧТО ЕСТЬ
- нативный компонент HBM Space: ntm_stardar
- getCurrentPlanet()
- getPlanetStats(name)
- getSatellites(name)
- 3D blocky space viewport на GPU Screen
- камера: вращение, zoom, reset
- telemetry Star Dar
- обнаружение ntm_rocket_pad без запуска ракет
- безопасный inspector без вызова mutating GPU методов

ВАЖНО
Позиции/скорости спутников и ракет не выдумываются: если конкретный OC API их не отдаёт,
UI показывает N/A. Данные берутся из реального ntm_stardar API.

БЫСТРАЯ УСТАНОВКА
1. Распакуй архив на OpenComputers filesystem так, чтобы получилась папка:
   /home/open_space_control/

2. В OpenOS выполни:
   lua /home/open_space_control/install.lua

3. Запуск:
   space
   или
   /boot.lua

4. Проверка HBM:
   lua /home/open_space_control/osc_inspect.lua
   или из меню выбрать COMPONENTS.

5. Автозапуск (ОПЦИОНАЛЬНО):
   lua /home/open_space_control/install.lua --autorun

Если ntm_stardar уже появляется в component.list(), физическая OC-сеть Star Dar работает.
OC Adapter для самого Star Dar не требуется: подключай совместимый порт/узел HBM напрямую
к OC network согласно конструкции.

УДАЛЕНИЕ
Выполни:
   lua /home/open_space_control/install.lua --remove

Это удаляет установленные файлы OSC и его rc.d launcher.
