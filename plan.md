# Plan: Agent Lattice (lat.md) Integration for AI-Uprising-Game

This plan outlines the steps to integrate `lat.md` (Agent Lattice) into the [ai-uprising-game](file:///C:/dev/private/ai-uprising-game) repository. The goal is to build a structured, machine-navigable knowledge graph of the codebase. This allows AI coding assistants (like Claude, Gemini, and Antigravity) to explore architecture, requirements, and systems efficiently without reading massive amounts of code or getting lost in context drift.

---

## 🎯 Objectives
1. **Reduce Context Overhead:** Allow AI agents to quickly find relevant code paths using semantic searches and explicit wiki links.
2. **Prevent Documentation Drift:** Enforce referential integrity using `lat check` so that as features evolve, documentation is updated.
3. **Standardize GDScript Integration:** Establish clean guidelines for linking Godot 4.7+ components (autoloads, scenes, scripts) back to architectural specs.
4. **Deepen AI Tools Integration:** Configure MCP (Model Context Protocol) to let Antigravity query the knowledge graph dynamically.

---

## 🗺️ Implementation Roadmap

### Phase 1: Environment & Tooling Setup
- [x] **Initialize Agent Lattice:** Run `lat init` to create the `lat.md/` configuration directory.
- [ ] **Manage Dependencies:** Create a minimal [package.json](file:///C:/dev/private/ai-uprising-game/package.json) in the project root to manage the `lat.md` CLI version locally (as a `devDependency`) so all contributors use the same version.
- [ ] **Configure MCP (Model Context Protocol):** Register the `lat mcp` server in the Antigravity configuration settings (`C:\Users\isber\.gemini\config\mcp_servers.json`) so the agent has direct tool access to search and query the lattice.

### Phase 2: Building the Knowledge Graph Nodes
Create core markdown files in the [lat.md/](file:///C:/dev/private/ai-uprising-game/lat.md) directory to map out the codebase:
1. **`lat.md/architecture.md`**: High-level game flow, core state machine, and Autoloads mapping (`GameState`, `AIDirector`, etc.).
2. **`lat.md/level-system.md`**: Procedural building system, def keys (`docs/LEVEL_DEF_KEYS.md`), scales, and coordinate mappings.
3. **`lat.md/enemies.md`**: CharacterBody3D state machines (`scripts/enemies/enemy_base.gd`), scaling, and roster (`docs/ENEMY_ROSTER.md`).
4. **`lat.md/weapons.md`**: Weapon management, weapon resource data (.tres), and collision layer definitions.
5. **`lat.md/testing.md`**: Verification philosophy, probe-writing rules, and test runner configurations.

### Phase 3: Anchoring Code to Markdown (Code Annotations)
- [ ] Add `# @lat: [[section-id]]` annotations to key GDScript files.
- [ ] Focus initial annotations on:
  - Autoload scripts: [game_state.gd](file:///C:/dev/private/ai-uprising-game/scripts/autoload/game_state.gd), [ai_director.gd](file:///C:/dev/private/ai-uprising-game/scripts/autoload/ai_director.gd)
  - Core mechanics: [enemy_base.gd](file:///C:/dev/private/ai-uprising-game/scripts/enemies/enemy_base.gd), [player.gd](file:///C:/dev/private/ai-uprising-game/scripts/player.gd)
  - Builder script: [level_builder.gd](file:///C:/dev/private/ai-uprising-game/scripts/levels/level_builder.gd)

### Phase 4: Enforcing Referential Integrity & CI Integration
- [ ] Update [tools/run_tests.ps1](file:///C:/dev/private/ai-uprising-game/tools/run_tests.ps1) and [tools/run_tests.sh](file:///C:/dev/private/ai-uprising-game/tools/run_tests.sh) to run `lat check` as part of the validation suite.
- [ ] Add `lat check` validation to pre-commit git hooks using `husky` or simple shell scripts to prevent dirty commits that break documentation links.

### Phase 5: Generating AI Profiles
- [ ] Add rules to [CLAUDE.md](file:///C:/dev/private/ai-uprising-game/CLAUDE.md) instructing external agents to run `lat search <query>` or `lat check` before proposing code changes.
- [ ] Generate standard AI agent profiles in the project root:
  - Run `lat gen agents.md` to produce instructions for standard coding assistants.
  - Run `lat gen cursor-rules.md` to set up rules for Cursor IDE.

---

## 📈 Success Metrics
- **Context Efficiency:** The AI can locate the files needed for a change in 1-2 tool calls (via semantic search/lattice navigation) rather than brute-force `grep` or file listings.
- **Reference Health:** Running `npx lat check` reports `0 errors` for markdown links and code references.
- **Continuous Sync:** Documentation changes happen alongside code changes in the same PR/commit, verified by hooks.
