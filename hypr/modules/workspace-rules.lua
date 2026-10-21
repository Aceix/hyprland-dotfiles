---------------------
-- WORKSPACE RULES --
---------------------

local vars = require("modules.variables")
local aocMonitor = vars.monitors.aoc
local dellMonitor = vars.monitors.dell

-- assign workspace 1 to aoc monitor, 10 to dell monitor
hl.workspace_rule({ workspace = "1", monitor = aocMonitor })
hl.workspace_rule({ workspace = "9", monitor = aocMonitor })
hl.workspace_rule({ workspace = "10", monitor = dellMonitor })
