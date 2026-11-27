# Neovim config

A VS Code-like Neovim setup built on NvChad: language servers, debugging, tests, git, AI, remote work.

Setup takes about 5 minutes and three commands.

## 1. Install the requirements

macOS:

```sh
brew install neovim git ripgrep fd node
brew install --cask font-jetbrains-mono-nerd-font
```

Linux: install the same tools with your package manager, plus a C compiler (`gcc` or `clang`).

Then check:

```sh
nvim --version    # must be 0.12.5 or newer
```

Set your terminal's font to the Nerd Font you installed, or icons will show as boxes. Kitty or Ghostty is recommended; the VS Code-style shortcuts need one of them.

## 2. Put this folder in place

If you already have a Neovim config, move it out of the way first:

```sh
mv ~/.config/nvim ~/.config/nvim.backup
mv ~/.local/share/nvim ~/.local/share/nvim.backup
```

Copy this folder to `~/.config/nvim`. When you are done, `~/.config/nvim/init.lua` must exist.

## 3. Install everything

Run these two commands and wait for each to finish:

```sh
nvim --headless "+Lazy! restore" +qa
nvim --headless -c "Lazy! load mason-tool-installer.nvim" -c "MasonToolsInstallSync" -c qa
```

The first installs the plugins (about 1 minute). The second installs the language servers, formatters and debuggers (about 1 minute). Both print a lot of text; that is normal. Expect about 2.5 GB of downloads in `~/.local/share/nvim`.

## 4. Check that it works

```sh
~/.config/nvim/tests/smoke.sh
```

It must end with `0 failed`. It never touches your sessions or settings.

Then open Neovim (`nvim`) and run:

```
:checkhealth utils
```

Errors (red) must be fixed. Warnings (yellow) only tell you which optional tools are missing and what each one is for.

You are done.

## Optional extras

Do these only if you want the feature.

| Feature | What to do |
|---|---|
| Copilot ghost text and next-edit suggestions | Run `:LspCopilotSignIn` once |
| Claude Code inside Neovim (`<leader>al`) | Install the `claude` CLI |
| AI agent chat (`<leader>aA`) | Install `claude-agent-acp`, `codex-acp` or `gemini` |
| Jupyter REPL (`<leader>N`) | Run `:MoltenSetup` once (needs `python3`) |
| Go, Python, Java, Flutter, PHP, Rust tests and debugging | Install that language's toolchain; `:checkhealth utils` lists what is missing |
| Image previews | `brew install imagemagick` |
| GitHub pull requests and issues | `brew install gh` |

PHP, Rust, shell, Docker and SQL tooling installs itself the first time you open a file of that type. The first open takes up to a minute; after that it is instant.

## First keys to know

The leader key is `Space`. Press it and wait: a menu shows every shortcut.

| Keys | Action |
|---|---|
| `Space Space` | Find a file |
| `Space f g` | Search text in the project |
| `Ctrl+b` | Toggle the file explorer |
| ``Ctrl+` `` | Toggle the terminal |
| `Space c a` | Code actions |
| `Space c r` | Rename a symbol |
| `Space c f` | Format the file |
| `Space g g` | Source control |
| `Space u` | On/off switches (format on save, inline diagnostics, and so on) |

## Changing the config

- Personal on/off flags: `lua/settings.lua`.
- Add a plugin: one file in `lua/plugins/`.
- Add a language: one file in `lua/langs/` plus one line in `lua/langs/init.lua`.
- Add an on/off switch: one entry in `lua/configs/toggles.lua`.
- After any change, run `tests/smoke.sh`.

## If something goes wrong

| Problem | Fix |
|---|---|
| Icons show as boxes | Set the terminal font to a Nerd Font |
| A plugin is missing or broken | `:Lazy restore` |
| A language server does not start | `:Mason`, then check the server is installed; `:checkhealth vim.lsp` |
| No syntax colours in a file | `:TSInstallAll` |
| Start over completely | Delete `~/.local/share/nvim` and `~/.local/state/nvim`, then repeat step 3 |

## Credits

Built on [NvChad](https://github.com/NvChad/NvChad), whose starter was inspired by the [LazyVim starter](https://github.com/LazyVim/starter).
