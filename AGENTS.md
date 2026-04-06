# Repository Guidelines

## Project Structure & Module Organization
`scenes/` contains playable Godot scenes such as `start_game.tscn` and `jing_chuan.tscn`. `scripts/` holds attached GDScript logic; right now `start_game.gd` drives the title-screen click-through. `resources/` stores imported assets, currently fonts under `resources/font/`. `addons/godot_mcp/` is a project plugin and should be treated as vendor-style integration code unless you are intentionally changing MCP behavior. Core project settings live in `project.godot`.

## Build, Test, and Development Commands
Use Godot 4.6 for local work because `project.godot` declares `config/features=PackedStringArray("4.6", "Forward Plus")`.

```powershell
godot --editor --path .
godot --path .
godot --headless --path . --check-only
```

`godot --editor --path .` opens the project in the editor. `godot --path .` runs the main scene, which currently starts at `scenes/start_game.tscn`. `godot --headless --path . --check-only` is the quickest syntax/config validation pass before pushing changes. If your local binary is named `godot4`, substitute that executable.

## Coding Style & Naming Conventions
Follow existing GDScript style: tabs for indentation, typed variables where practical, and compact scene scripts. Use `lower_snake_case` for `.gd` and `.tscn` filenames, `PascalCase` for scene node names, and keep one script focused on one scene or gameplay concern. Prefer editor-based changes for `project.godot` and `.tscn` files so imports and metadata stay consistent.

## Testing Guidelines
There is no dedicated automated test suite yet. Validate changes by running the project and checking the affected scene flow in-editor. For script-only edits, run the headless validation command above; for scene/UI work, include a short manual test note such as “clicked title screen, confirmed transition into `jing_chuan.tscn`.”

## Commit & Pull Request Guidelines
The current history uses scoped Conventional Commit prefixes, for example `feat(project): 添加MCP插件`. Keep that pattern: `type(scope): short summary`. Pull requests should describe the gameplay or editor impact, list validation steps, and include screenshots or short recordings for scene/UI changes. Link the related issue when one exists.
