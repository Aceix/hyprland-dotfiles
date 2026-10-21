return {
  "akinsho/flutter-tools.nvim",
  ft = "dart",
  event = { "BufReadPost pubspec.yaml" }, -- its pub-get-on-save hook
  cmd = {
    "FlutterRun",
    "FlutterDevices",
    "FlutterEmulators",
    "FlutterReload",
    "FlutterRestart",
    "FlutterQuit",
    "FlutterOutlineToggle",
    "FlutterDevTools",
    "FlutterCopyProfilerUrl",
    "FlutterLspRename",
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  opts = require "configs.flutter",
}
