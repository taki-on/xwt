# xwt

Orchestrate git worktrees and iOS Simulators for parallel branch development.

`xwt` lets you spin up an isolated environment per branch — a git worktree, a dedicated iOS Simulator, and a separate DerivedData directory — so you can work on multiple features simultaneously without conflicts.

Designed for use with [XcodeBuildMCP](https://github.com/nicktmro/XcodeBuildMCP) and [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) — `xwt` automatically generates Copilot instruction files so that XcodeBuildMCP picks up the correct simulator and DerivedData path for each worktree without any manual configuration.

## Installation

### Prerequisites

- macOS 13+
- Swift 5.9+
- Xcode (for `xcrun simctl` and `xcodebuild`)

### Build from source

```bash
git clone https://github.com/taki-on/xwt.git
cd xwt
swift build -c release
```

The binary is produced at `.build/release/xwt`. You can copy it to your PATH:

```bash
cp .build/release/xwt /usr/local/bin/
```

### Run without installing

```bash
swift run xwt <command>
```

## Quick Start

```bash
# Set up xwt in your repo (interactive, one-time)
xwt init

# Start a new task for a feature branch
xwt start feature/login-refactor

# cd into the worktree
cd ~/worktrees/<repo>/feature-login-refactor

# Build and run on the branch's dedicated simulator
xwt run feature/login-refactor --scheme MyApp

# List all active tasks
xwt list

# Clean up when done
xwt remove feature/login-refactor
```

## Commands

### `xwt init`

Interactively creates or updates the `.xwt.json` configuration file in your repository root. Walks you through each setting with auto-detected options:

1. **Workspace / Project / Package** — scans the repo root for `.xcworkspace`, `.xcodeproj`, and `Package.swift` files
2. **Scheme** — runs `xcodebuild -list` to discover available schemes
3. **Device type** — lists available iPhone simulator types via `simctl`
4. **iOS runtime** — lists installed iOS runtimes
5. **Source simulator** — picks a simulator to copy the keychain from (for auto-login)
6. **Worktree directory** — base directory for worktrees (default `~/worktrees`)

After saving the config, `xwt init` offers to add `.xwt.json` and the Copilot instructions file to `.gitignore` or `.git/info/exclude`.

If a `.xwt.json` already exists, its values are used as defaults so you can update individual settings without re-entering everything.

### `xwt start <branch>`

Creates a full isolated environment for a branch:

- Creates a git worktree
- Creates (or reuses) a simulator named `xwt-<slug>`
- Boots the simulator
- Creates a dedicated DerivedData directory
- Saves task state to `~/.xwt/`
- Writes Copilot instructions for XcodeBuildMCP auto-setup

| Option | Description | Default |
|---|---|---|
| `--device <type>` | Simulator device type | `iPhone 17 Pro` |
| `--runtime <version>` | iOS runtime version | `iOS 26.4` |
| `--copy-auth-from <sim>` | Copy keychain from this simulator (name or UDID) to skip re-login | — |
| `--no-copy-auth` | Skip keychain copy even when `sourceSimulator` is configured | `false` |
| `--no-boot` | Skip booting the simulator | `false` |

### `xwt list`

Lists all active tasks with branch, worktree path, simulator info, and status.

| Option | Description |
|---|---|
| `--repo <name>` | Filter by repository name |

### `xwt run <branch>`

Builds the project for the branch's assigned simulator using `xcodebuild`.

| Option | Description |
|---|---|
| `--scheme <name>` | Override the build scheme |
| `--build-only` | Build without launching |

### `xwt remove <branch>`

Removes a task and cleans up its resources.

| Option | Description |
|---|---|
| `--delete-simulator` | Also delete the simulator device |
| `--clean-derived-data` | Also remove the DerivedData directory |
| `--force` | Skip confirmation prompt |

## Configuration

Create a `.xwt.json` file in your repository root to set project defaults:

```json
{
  "workspace": "MyApp.xcworkspace",
  "scheme": "MyApp",
  "deviceType": "iPhone 16 Pro Max",
  "runtime": "iOS 18.0"
}
```

Supported fields: `workspace`, `project`, `package`, `scheme`, `deviceType`, `runtime`, `sourceSimulator`, `worktreeDir`.

`workspace`, `project`, and `package` are mutually exclusive. Use `package` for Swift Package repositories (typically `"Package.swift"`); `xwt run` invokes `xcodebuild` from the worktree root with no `-workspace` / `-project` flag, letting `xcodebuild` discover the package automatically.

### Auth / Keychain Copy

When you log in to your app on a simulator, the auth tokens are stored in the simulator's keychain. New simulators created by `xwt start` don't have these tokens, requiring a fresh login each time.

To skip re-authentication, set `sourceSimulator` in your `.xwt.json` to the name (or UDID) of a simulator that is already logged in:

```json
{
  "workspace": "MyApp.xcworkspace",
  "scheme": "MyApp",
  "sourceSimulator": "iPhone 17 Pro"
}
```

Now every `xwt start` will automatically copy the keychain from that simulator to the new one. Use `--no-copy-auth` to skip the copy, or `--copy-auth-from <name-or-udid>` to override the source on a per-invocation basis.

## File Layout

| Path | Purpose |
|---|---|
| `~/.xwt/repos/<repo>/<slug>.json` | Persisted task state |
| `~/worktrees/<repo>/<slug>/` | Git worktrees |
| `~/Library/Developer/Xcode/DerivedData/xwt/<slug>/` | Build artifacts |

## Copilot Instructions & XcodeBuildMCP Integration

When you run `xwt start`, the tool writes a [Copilot instructions file](https://docs.github.com/copilot/customizing-copilot/adding-repository-instructions-for-github-copilot) into the worktree at:

```
<worktree>/.github/instructions/xwt.instructions.md
```

This file tells Copilot (and XcodeBuildMCP) which simulator and DerivedData path to use for the branch. A generated file looks like this:

```markdown
---
applyTo: "**"
---

<!-- Auto-generated by xwt — do not edit -->

## XcodeBuildMCP Session Setup

At the start of every session, before any build, run, or test action,
configure XcodeBuildMCP session defaults by calling `session_set_defaults`
with the following values. Do **not** set `persist: true`.

- simulatorName: xwt-feature-login-refactor
- simulatorId: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
- derivedDataPath: ~/Library/Developer/Xcode/DerivedData/xwt/feature-login-refactor
- workspacePath: MyApp.xcworkspace
- scheme: MyApp
```

When Copilot CLI opens a session inside the worktree, it picks up this instruction file automatically and configures XcodeBuildMCP's session defaults — the correct simulator and DerivedData directory are used without any manual steps.

### Git exclusion

The instructions file is specific to each developer's local environment (it contains simulator UDIDs and local paths), so it should **not** be committed. `xwt start` automatically adds the file to the repository's `.git/info/exclude`:

```
.github/instructions/xwt.instructions.md
```

`.git/info/exclude` works exactly like `.gitignore` but is local to your machine — it won't appear in diffs or affect other contributors, and there is no need to add anything to `.gitignore`.

## Using xwt with GitHub Copilot CLI

[GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) can drive `xwt` through natural language. Launch `copilot` inside a xwt-managed worktree and ask it to manage your parallel development workflow.

### Set up a branch environment

```
> Set up a new xwt task for the feature/auth branch using an iPhone 16 Pro on iOS 18.0
```

Copilot CLI will run:
```bash
xwt start feature/auth --device "iPhone 16 Pro" --runtime "iOS 18.0"
```

### Initialize project configuration

```
> Initialize xwt in this repo
```

Copilot CLI will run:
```bash
xwt init
```

### Build and iterate on a branch

```
> Build my auth branch with the LoginKit scheme
```

Copilot CLI will run:
```bash
xwt run feature/auth --scheme LoginKit
```

### Review active tasks

```
> Show me all my active xwt tasks
```

Copilot CLI will run:
```bash
xwt list
```

### Clean up a branch

```
> Remove the auth branch task and delete its simulator and derived data
```

Copilot CLI will run:
```bash
xwt remove feature/auth --delete-simulator --clean-derived-data --force
```

### End-to-end workflow in Copilot CLI

You can ask Copilot CLI to handle the full workflow in a single prompt:

```
> I need to work on the feature/payments branch. Set up a xwt task with
> an iPhone 16 Pro Max simulator.
```

Or use **plan mode** (`Shift+Tab` to switch) for multi-step orchestration:

```
> [[PLAN]] I want to set up parallel development for three branches:
> feature/auth, feature/payments, and bugfix/crash-on-launch.
> Each should have its own simulator and worktree.
```

### Use with `@` file mentions

Reference your `.xwt.json` config directly in Copilot CLI prompts:

```
> @.xwt.json Update the default device type to iPhone 16 Pro Max
```

### Use with `/diff` and `/review`

After building and making changes in a xwt worktree, use Copilot CLI's built-in commands:

```
/diff    # Review changes made in the current worktree
/review  # Run code review on your changes
```

## License

MIT
