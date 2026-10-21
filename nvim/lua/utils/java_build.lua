-- A compiler for neotest-java that waits for jdtls to finish building before
-- the tests start, and says how the build went.
--
-- neotest-java's own compiler sends `java/buildWorkspace` and returns at once,
-- so the JUnit JVM could start while jdtls was still writing target/classes:
-- tests then ran against old classes, or against the "Unresolved compilation
-- problem" stubs jdtls writes for classes that don't compile yet. Plugged in
-- through neotest-java's `lsp_compiler` dependency (configs/neotest.lua).
local M = {}

local TIMEOUT_MS = 120000

-- java/buildWorkspace result (jdtls' CompileWorkspaceStatus)
local FAILED, SUCCEED, WITH_ERROR, CANCELLED = 0, 1, 2, 3

local function notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Java build" })
  end)
end

---@return NeotestJavaCompiler
function M.compiler()
  return {
    -- Called from neotest's build_spec, inside a nio task, so it can block.
    compile = function(args)
      local nio = require "nio"
      local client = require("neotest-java.core.spec_builder.compiler").client_provider(args.base_dir)
      if not client or not client.initialized then
        notify("jdtls isn't ready, so the tests run on the last build", vim.log.levels.WARN)
        return
      end

      local full = args.compile_mode == "full"
      notify(full and "Compiling (full rebuild) before the tests..." or "Compiling before the tests...")

      local started = vim.uv.now()
      local done = nio.control.future()
      vim.schedule(function()
        local sent = client:request("java/buildWorkspace", full, function(err, status)
          done.set { err = err, status = status }
        end)
        if not sent then
          done.set { err = { message = "jdtls didn't accept the build request" } }
        end
      end)

      local res = nio.first {
        done.wait,
        function()
          nio.sleep(TIMEOUT_MS)
          return { timeout = true }
        end,
      }
      local secs = ("%.1fs"):format((vim.uv.now() - started) / 1000)

      if res.timeout then
        notify(
          ("jdtls is still building after %ds; running the tests anyway"):format(TIMEOUT_MS / 1000),
          vim.log.levels.WARN
        )
      elseif res.err then
        notify("Build request failed: " .. (res.err.message or vim.inspect(res.err)), vim.log.levels.ERROR)
      elseif res.status == SUCCEED then
        notify(("Compiled in %s, running the tests"):format(secs))
      elseif res.status == WITH_ERROR then
        notify(
          ("Compiled in %s with errors: classes that don't compile will throw "
            .. "\"Unresolved compilation problem\". :JdtCompile lists them"):format(secs),
          vim.log.levels.WARN
        )
      elseif res.status == CANCELLED then
        notify("Build was cancelled; the tests may run on old classes", vim.log.levels.WARN)
      elseif res.status == FAILED then
        notify("Build failed; the tests may run on old classes. :JdtCompile shows why", vim.log.levels.ERROR)
      end
    end,
  }
end

return M
