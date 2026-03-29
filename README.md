# simi

Orchestrate git worktrees and iOS Simulators for parallel branch development.

`simi` lets you spin up an isolated environment per branch — a git worktree, a dedicated iOS Simulator, and a separate DerivedData directory — so you can work on multiple features simultaneously without conflicts.

## Installation

### Prerequisites

- macOS 13+
- Swift 5.9+
- Xcode (for `xcrun simctl` and `xcodebuild`)

### Build from source

```bash
git clone https://github.com/taki-on/simi.git
cd simi
swift build -c release
```

The binary is produced at `.build/release/simi`. You can copy it to your PATH:

```bash
cp .build/release/simi /usr/local/bin/
```

### Run without installing

```bash
swift run simi <command>
```

## Quick Start

```bash
# Start a new task for a feature branch
simi start feature/login-refactor

# cd into the worktree and load environment variables
cd ~/worktrees/<repo>/feature-login-refactor
source .simi-context

# Build and run on the branch's dedicated simulator
simi run feature/login-refactor --scheme MyApp

# List all active tasks
simi list

# Clean up when done
simi remove feature/login-refactor
```

## Commands

### `simi start <branch>`

Creates a full isolated environment for a branch:

- Creates a git worktree
- Creates (or reuses) a simulator named `simi-<slug>`
- Boots the simulator
- Creates a dedicated DerivedData directory
- Saves task state to `~/.simi/`
- Writes a `.simi-context` file with environment variables

| Option | Description | Default |
|---|---|---|
| `--device <type>` | Simulator device type | `iPhone 17 Pro` |
| `--runtime <version>` | iOS runtime version | `iOS 26.4` |
| `--no-boot` | Skip booting the simulator | `false` |

### `simi list`

Lists all active tasks with branch, worktree path, simulator info, and status.

| Option | Description |
|---|---|
| `--repo <name>` | Filter by repository name |

### `simi shell <branch>`

Opens an interactive shell session inside the branch's worktree directory.

### `simi run <branch>`

Builds the project for the branch's assigned simulator using `xcodebuild`.

| Option | Description |
|---|---|
| `--scheme <name>` | Override the build scheme |
| `--build-only` | Build without launching |

### `simi remove <branch>`

Removes a task and cleans up its resources.

| Option | Description |
|---|---|
| `--delete-simulator` | Also delete the simulator device |
| `--clean-derived-data` | Also remove the DerivedData directory |
| `--force` | Skip confirmation prompt |

## Configuration

Create a `.simi.json` file in your repository root to set project defaults:

```json
{
  "workspace": "MyApp.xcworkspace",
  "scheme": "MyApp",
  "deviceType": "iPhone 16 Pro Max",
  "runtime": "iOS 18.0"
}
```

Supported fields: `workspace`, `project`, `scheme`, `deviceType`, `runtime`.

## File Layout

| Path | Purpose |
|---|---|
| `~/.simi/repos/<repo>/<slug>.json` | Persisted task state |
| `~/worktrees/<repo>/<slug>/` | Git worktrees |
| `~/Library/Developer/Xcode/DerivedData/simi/<slug>/` | Build artifacts |
| `<worktree>/.simi-context` | Shell env vars (`source` this) |

## Using simi with GitHub Copilot CLI

[GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) can drive `simi` through natural language. Launch `copilot` inside a simi-managed worktree and ask it to manage your parallel development workflow.

### Set up a branch environment

```
> Set up a new simi task for the feature/auth branch using an iPhone 16 Pro on iOS 18.0
```

Copilot CLI will run:
```bash
simi start feature/auth --device "iPhone 16 Pro" --runtime "iOS 18.0"
```

### Build and iterate on a branch

```
> Build my auth branch with the LoginKit scheme
```

Copilot CLI will run:
```bash
simi run feature/auth --scheme LoginKit
```

### Review active tasks

```
> Show me all my active simi tasks
```

Copilot CLI will run:
```bash
simi list
```

### Clean up a branch

```
> Remove the auth branch task and delete its simulator and derived data
```

Copilot CLI will run:
```bash
simi remove feature/auth --delete-simulator --clean-derived-data --force
```

### End-to-end workflow in Copilot CLI

You can ask Copilot CLI to handle the full workflow in a single prompt:

```
> I need to work on the feature/payments branch. Set up a simi task with
> an iPhone 16 Pro Max simulator, then open a shell in the worktree.
```

Or use **plan mode** (`Shift+Tab` to switch) for multi-step orchestration:

```
> [[PLAN]] I want to set up parallel development for three branches:
> feature/auth, feature/payments, and bugfix/crash-on-launch.
> Each should have its own simulator and worktree.
```

### Use with `@` file mentions

Reference your `.simi.json` config directly in Copilot CLI prompts:

```
> @.simi.json Update the default device type to iPhone 16 Pro Max
```

### Use with `/diff` and `/review`

After building and making changes in a simi worktree, use Copilot CLI's built-in commands:

```
/diff    # Review changes made in the current worktree
/review  # Run code review on your changes
```

## License

MIT
