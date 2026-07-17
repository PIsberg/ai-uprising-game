# Specification: Agent Lattice (lat.md) Configuration

This document specifies the standards, directory structure, annotation conventions, and validation rules for using [lat.md](https://www.lat.md/) in the **ai-uprising-game** codebase.

---

## 📁 1. Directory Structure

All Agent Lattice definitions live within the [lat.md/](file:///C:/dev/private/ai-uprising-game/lat.md) directory. The structure is configured as follows:

```
C:\dev\private\ai-uprising-game\lat.md\
├── lat.md               # Registry file / introductory note
├── architecture.md      # Core game loops, Autoload state machines, systems layout
├── level-system.md      # Procedural levels, def structures, and coordinate scaling
├── enemies.md           # Enemy Base state machine, scaling formulas, and roster
├── weapons.md           # WeaponManager, custom Weapon resources, and collision physics
└── testing.md           # Headless test verification, probes structure, and criteria
```

---

## 📝 2. Markdown Reference Syntax

We use double-bracket wiki-style links (`[[...]]`) to connect documentation nodes and source code files.

### A. Linking Between Markdown Nodes
To link to a specific section in another lattice document:
* **Syntax:** `[[filename#Section Name#Sub Section]]`
* **Example:** `[[architecture#Autoloads#GameState]]`

### B. Linking to Code Symbols
To tie a design specification to its actual code implementation:
* **Syntax:** `[[relative/path/to/file.gd#symbol_name]]`
* **Example:** `[[scripts/autoload/game_state.gd#advance_level]]`
* **Scope:** Standard Godot file paths relative to the project root must be used (e.g. `scripts/...` or `tests/...`).

---

## 🏷️ 3. Source Code Annotation (GDScript & Godot Files)

To anchor GDScript source code back to the architectural definitions, developers and AI agents must insert `@lat` annotations in the code comments.

### A. GDScript Code
GDScript uses `#` for comments. The annotation must follow this exact format:
```gdscript
# @lat: [[architecture#Autoloads#GameState]]
func advance_level() -> void:
    # State-transition logic here
```
* The token `@lat:` is followed by a space and a valid wiki link pointing to the section in `lat.md/` that defines this concept.

### B. Scenes (`.tscn`) and Resources (`.tres`)
Godot scenes and resource files are plain-text formats (YAML-like). We can annotate them with metadata or comment blocks at the top of the file:
```gdscript
; @lat: [[weapons#Weapon Manager]]
[gd_scene load_steps=3 format=3 uid="uid://c1x..."]
```

---

## 🔬 4. Referential Contracts (`require-code-mention`)

Certain critical systems (e.g., scoring rules, player damage limits, test specifications) require strict implementation or verification. We enforce this using the `require-code-mention` frontmatter/tag.

### A. Marking a Section in Markdown
If a concept **must** be explicitly referenced in the codebase, include `require-code-mention: true` in its block structure:
```markdown
### Ultimate Weapon Scaling
<!-- lat: { "require-code-mention": true } -->
The Ultimate charge rate scales quadratically relative to player performance score.
```

### B. Fulfilling the Contract
To satisfy this contract, at least one code file must contain a backlink comment:
```gdscript
# @lat: [[weapons#Ultimate Weapon Scaling]]
func _update_charge_rate() -> void:
    ...
```
If no code file references this section, `lat check` will fail.

---

## 🛠️ 5. Validation and Verification Commands

We run `lat check` commands to ensure documentation and code remain in sync.

| Command | Purpose | Coverage |
| :--- | :--- | :--- |
| `npx lat check md` | Validate Markdown links | Verifies that all `[[wiki links]]` between documents are valid and point to existing headings. |
| `npx lat check code-refs` | Validate Code links | Ensures all source code references (`# @lat:`) target existing documentation headers and all `require-code-mention` contracts are met. |
| `npx lat check index` | Validate Index files | Checks the integrity of directories and registry indices within `lat.md/`. |
| `npx lat check sections` | Validate Section formatting | Enforces formatting and introductory paragraph styles in the documentation. |
| `npx lat check` | Complete Sweep | Runs all validation checks in sequence. Returns exit code `0` on success and non-zero on broken links. |

---

## 🤖 6. AI Agent Integration & MCP Setup

To enable optimal context navigation for AI agents, we configure the Model Context Protocol (MCP) server for `lat.md`.

### A. Registering the MCP Server
Add the following configuration to the Antigravity/Gemini workspace MCP settings (e.g., `mcp_servers.json`):
```json
{
  "mcpServers": {
    "lat-md": {
      "command": "npx",
      "args": ["-p", "lat.md", "lat", "mcp"],
      "env": {}
    }
  }
}
```

### B. Standard AI Workflow for Context Navigation
When an AI agent starts a task:
1. **Search Context:** Run `npx lat search "query"` to find the most relevant architectural concepts in the project lattice.
2. **Retrieve Details:** Run `npx lat section "Section Name"` to read structural constraints, design decisions, and linked code paths.
3. **Write & Link Code:** Modify files, adding `# @lat:` backlinks to ensure the changes are anchored to their specifications.
4. **Validate Change:** Run `npx lat check` before completing the task to confirm no links are broken.
