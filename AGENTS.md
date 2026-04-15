# Repository Guidelines

## Project Structure & Module Organization
`scenes/` contains the playable scenes and test beds: `start_game.tscn` is the main entry, `jing_chuan.tscn` is the 3D world scene, `industry_area.tscn` is the GridMap build-mode scene, `builder.tscn` is the Control-based construction/material UI, and `test_offline_production.tscn` is the offline-production validation scene. `scripts/` is a mixed-language gameplay folder: `scripts/controllers/` owns scene-level GDScript controllers, `scripts/industry_system/` contains camera/build-mode helpers, and `scripts/industry_map/` contains the C# offline-production stack split into `data/`, `engine/`, and `runtime/`. `resources/` stores shared assets including `resources/build_pic/`, fonts under `resources/font/`, the GridMap MeshLibrary at `resources/grid_map/industry.tres`, and shared `.tres` resources. `Auracole.sln` and `Auracole.csproj` define the .NET side of the project. Treat `addons/godot_mcp/` as vendor-style integration code unless you are intentionally modifying MCP behavior. Core engine settings live in `project.godot`.

## Build, Test, and Development Commands
Use Godot 4.6 with .NET support because `project.godot` declares `config/features=PackedStringArray("4.6", "C#", "Forward Plus")`.

```powershell
godot --editor --path .
godot --path .
godot --headless --path . --check-only
dotnet build Auracole.sln
```

`godot --editor --path .` opens the project in the editor. `godot --path .` runs the main scene, currently `scenes/start_game.tscn`. `godot --headless --path . --check-only` is the fastest Godot-side syntax/config validation pass. `dotnet build Auracole.sln` validates the C# gameplay code under `scripts/industry_map/`. If your local binary is named `godot4`, substitute that executable.

## Coding Style & Naming Conventions
Follow existing GDScript style: tabs for indentation, typed variables where practical, compact scene scripts, and `lower_snake_case` for `.gd` and `.tscn` filenames. Keep node names in `PascalCase`. For C#, follow the current project style: `PascalCase` type names, `Auracole.*` namespaces, concise XML doc comments on public APIs or non-obvious runtime entry points, and one class per file. Keep scripts focused on one scene or subsystem. Add brief comments only where snapping, coordinate conversion, save/restore flow, or other non-obvious behavior would be hard to infer. Prefer editor-based changes for `project.godot` and `.tscn` files so imports and metadata stay consistent.

## Gameplay System Notes
`industry_area.tscn` uses a `GridMap` with `cell_size = Vector3(1, 1, 1)` as the placement grid. `scripts/industry_system/spawn_equipment.gd` owns hover preview rendering, grouped footprint snapping, and left-click placement. Hover preview is intentionally implemented with a dedicated `MeshInstance3D` instead of temporary GridMap cells, while actual placement writes cube cells into the GridMap. `snap_size_in_cells` controls both the preview footprint and grouped snapping, so placement-size changes should go through that exported property or `set_snap_size()` rather than duplicating footprint math.

`test_offline_production.tscn` is the manual harness for the offline-production feature. `scripts/industry_map/runtime/ProductionLineManager.cs` coordinates UI refresh, snapshot save/load, and offline simulation. Core deterministic simulation logic lives in `scripts/industry_map/engine/OfflineSimulationEngine.cs`, while runtime machine state is managed by `scripts/industry_map/runtime/MachineController.cs`. Snapshot data is persisted to `user://production_snapshot.json`, so tests that depend on prior state should account for existing user data.

## Testing Guidelines
There is no dedicated automated test suite yet. Run `godot --headless --path . --check-only` for script/config validation, and run `dotnet build Auracole.sln` whenever you touch `scripts/industry_map/` or other C# files. Validate scene changes in-editor and include a short manual test note in your change summary, such as “clicked title screen, confirmed transition into `jing_chuan.tscn`.”

For build-mode changes, manually verify entering top-view mode, hover preview alignment, footprint size changes such as `4x4`, and left-click placement without overlapping existing cells. For offline-production changes, open `test_offline_production.tscn` and verify the `Simulate 24 Hours`, `Manual Feed`, and `Save and Quit` flows, including snapshot reuse across relaunches when relevant. For `builder.tscn` work, verify material selection, description refresh, submission feedback, and the build action flow.

## Commit & Pull Request Guidelines
The current history uses scoped Conventional Commit prefixes, for example `feat(project): 添加MCP插件`. Keep that pattern: `type(scope): short summary`. Pull requests should describe the gameplay or editor impact, list validation steps, and include screenshots or short recordings for scene or UI changes. Link the related issue when one exists.
