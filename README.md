# xwt

Orchestrate git worktrees and iOS Simulators for parallel branch development.

`xwt` lets you spin up an isolated environment per branch — a git worktree, a dedicated iOS Simulator, and a separate DerivedData directory — so you can work on multiple features simultaneously without conflicts.

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

Supported fields: `workspace`, `project`, `scheme`, `deviceType`, `runtime`, `sourceSimulator`.

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
