# xwt

Orchestrate git worktrees and iOS Simulators for parallel branch development.

`xwt` lets you spin up an isolated environment per branch — a git worktree, a dedicated iOS Simulator, and a separate DerivedData directory — so you can work on multiple features simultaneously without conflicts.

Designed for use with [XcodeBuildMCP](https://github.com/nicktmro/XcodeBuildMCP), [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli), and [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — `xwt` automatically generates instruction files so that XcodeBuildMCP picks up the correct simulator and DerivedData path for each worktree without any manual configuration.

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

### Shell integration (recommended)

xwt can hand-jump to a worktree (`xwt cd <branch>`) and automatically
`cd` into a new worktree after `xwt start`. Because no subprocess can
change its parent shell's working directory on its own, this needs a
tiny shell wrapper. Add the appropriate one-liner to your shell's rc
file:

| Shell | Where | Line |
|---|---|---|
| zsh  | `~/.zshrc`                       | `eval "$(xwt shell-init zsh)"` |
| bash | `~/.bash_profile` (macOS) or `~/.bashrc` (Linux) | `eval "$(xwt shell-init bash)"` |
| fish | `~/.config/fish/config.fish`     | `xwt shell-init fish \| source` |

Then `source` the file (or open a new terminal) to activate it.

`xwt init` will offer to add the right line to the right rc file the
first time you run it. Subsequent runs detect that it's already
installed and stay quiet.

To opt out of the auto-cd after `xwt start`, set `XWT_NO_CD=1` in your
environment (or one-off: `XWT_NO_CD=1 xwt start feature/login`).

## Quick Start

```bash
# Set up xwt in your repo (interactive, one-time)
xwt init

# Start a new task for a feature branch — auto-cds you into the worktree
xwt start feature/login-refactor

# Build and run on the branch's dedicated simulator
xwt run feature/login-refactor --scheme MyApp

# Jump back to a worktree from anywhere
xwt cd feature/login-refactor

# List all active tasks
xwt list

# Clean up when done
xwt remove feature/login-refactor
```

> The `xwt cd` and auto-cd-after-`start` ergonomics require the shell
> integration — see [Shell integration](#shell-integration-recommended).

### Stacked PRs

```bash
# Start the first branch (auto-cds into the worktree)
xwt start feature/auth

# From inside the worktree, start a child branch — auto-detected!
xwt start feature/auth-ui
# prints: 🔗 Stacking on 'feature/auth' (auto-detected from current worktree)

# Or be explicit
xwt start feature/auth-tests --base feature/auth

# Hop between worktrees in the stack
xwt cd feature/auth
xwt cd feature/auth-ui

# Create PRs with correct base branches
xwt pr feature/auth          # PR: feature/auth → main
xwt pr feature/auth-ui       # PR: feature/auth-ui → feature/auth

# After updating a parent branch, rebase the stack
xwt restack feature/auth

# List shows the tree structure
xwt list
```

## Commands

### `xwt init`

Interactively creates or updates the `.xwt.json` configuration file in your repository root. Walks you through each setting with auto-detected options:

1. **Workspace / Project / Package** — scans the repo root for `.xcworkspace`, `.xcodeproj`, and `Package.swift` files
2. **Scheme** — runs `xcodebuild -list` to discover available schemes
3. **Device type** — lists available iPhone simulator types via `simctl`
4. **iOS runtime** — lists installed iOS runtimes
5. **Source simulator** — picks a simulator to copy auth (keychain + session) from (for auto-login)
6. **Worktree directory** — base directory for worktrees (default `~/worktrees`)

After saving the config, `xwt init` offers to add `.xwt.json` and the generated instruction files to `.gitignore` or `.git/info/exclude`.

Finally, on the first run on a new machine, `xwt init` offers to install
the [shell integration](#shell-integration-recommended) line into your
shell's rc file so `xwt cd` and auto-cd-on-start just work. On
subsequent `xwt init` runs, this step detects that the line is already
installed and skips silently.

If a `.xwt.json` already exists, its values are used as defaults so you can update individual settings without re-entering everything.

### `xwt start <branch>`

Creates a full isolated environment for a branch:

- Creates a git worktree
- Creates (or reuses) a simulator named `xwt-<slug>`
- Boots the simulator
- Creates a dedicated DerivedData directory
- Saves task state to `~/.xwt/`
- Writes Copilot and Claude Code instructions for XcodeBuildMCP auto-setup

| Option | Description | Default |
|---|---|---|
| `--device <type>` | Simulator device type | `iPhone 17 Pro` |
| `--runtime <version>` | iOS runtime version | `iOS 26.4` |
| `--copy-auth-from <sim>` | Copy auth from this simulator (name or UDID) to skip re-login | — |
| `--no-copy-auth` | Skip auth copy even when `sourceSimulator` is configured | `false` |
| `--no-boot` | Skip booting the simulator | `false` |
| `--base <branch>` | Base branch to stack on (creates new branch from this base) | auto-detect |
| `--no-base` | Don't auto-detect base branch from current worktree | `false` |

**Stacking auto-detection**: when you run `xwt start` from inside an xwt-managed worktree, the new branch automatically stacks on the current worktree's branch. Use `--no-base` to opt out.

When stacking, the keychain is automatically copied from the parent task's simulator (unless `--copy-auth-from` or `--no-copy-auth` is specified). At `start` time only the keychain is copied — the app's session cookies are copied later by `xwt run` once the app is installed (see [Auth / Session Copy](#auth--session-copy)).

### `xwt list`

Lists all active tasks with branch, worktree path, simulator info, and status. When tasks have parent-child relationships (stacked branches), they are displayed as a tree.

| Option | Description |
|---|---|
| `--repo <name>` | Filter by repository name |

### `xwt run <branch>`

Builds the project for the branch's assigned simulator using `xcodebuild`.

| Option | Description |
|---|---|
| `--scheme <name>` | Override the build scheme |
| `--build-only` | Build without launching |
| `--copy-auth-from <sim>` | Copy auth (keychain + session) from this simulator on first install |
| `--no-copy-auth` | Skip copying auth on first install |

On the **first install** of the app (when the target simulator has no session
yet), `xwt run` copies the keychain **and** the app's session cookies from the
source simulator so the app launches already logged in. It never overwrites an
existing session on subsequent runs — use `xwt sync-auth` to force a re-sync.
The source is resolved as `--copy-auth-from` > the parent task's simulator >
`sourceSimulator` in `.xwt.json`.

### `xwt sync-auth <branch>`

Force-copies auth state (keychain + session cookies) from a source simulator
into the task's simulator, overwriting any existing session. Useful when the
source simulator's login changed, or after `xwt start --no-copy-auth`. Relaunch
the app afterwards to pick up the copied session.

| Option | Description |
|---|---|
| `--copy-auth-from <sim>` | Source simulator (name or UDID); overrides parent task / `.xwt.json` |
| `--bundle-id <id>` | App bundle identifier; defaults to the built app's `CFBundleIdentifier` |

The app must be installed on the target simulator (run `xwt run` first) so its
data container exists. The bundle ID is read from the app built into the task's
DerivedData unless `--bundle-id` is given.

### `xwt remove <branch>`

Removes a task and cleans up its resources. If the task has child branches (stacked on it), you must specify how to handle them.

| Option | Description |
|---|---|
| `--keep-simulator` | Keep the simulator device instead of deleting it |
| `--keep-derived-data` | Keep the DerivedData directory |
| `--force` | Skip confirmation prompt |
| `--reparent` | Re-point child tasks to this task's parent before removing |
| `--cascade` | Remove this task and all its descendants |

### `xwt pr <branch>`

Creates a GitHub pull request using `gh`. Automatically sets the PR base to the parent branch for stacked PRs, or to the main branch for root tasks.

| Option | Description |
|---|---|
| `--draft` | Create a draft pull request |
| `--title <text>` | PR title (inferred from commits if omitted) |
| `--body <text>` | PR body |
| `--fill` | Use first commit message as title and body |

### `xwt restack [<branch>]`

Rebases stacked branches onto their updated parents in topological order. Validates that all worktrees are clean before starting.

- If `<branch>` is given, restacks that branch and all its descendants.
- If omitted, restacks all stacked branches in the repo.
- On conflict, stops and tells you which worktree to resolve in.

### `xwt cd <branch>`

Jumps to a branch's worktree directory. Requires the [shell
integration](#shell-integration-recommended) to be installed (a
subprocess can't change its parent shell's `cwd`, so we ship a tiny
shell function that does it for you).

```bash
xwt cd feature/login        # accepts branch name
xwt cd feature-login        # or slug
```

When run inside a repo, `xwt cd` uses that repo's tasks. When run
elsewhere it scans all known repos for a unique match — pass
`--repo <name>` to disambiguate.

### `xwt path <branch>`

Prints the absolute worktree path on stdout (errors go to stderr), so
it's safe inside command substitution:

```bash
cd "$(xwt path feature/login)"
code "$(xwt path feature/login)"
```

This is the building block `xwt cd` is built on; you can use it
directly when you don't want to install the shell integration.

| Option | Description |
|---|---|
| `--repo <name>` | Constrain lookup to this repo (defaults to the cwd's repo, or scans all known repos). |

### `xwt shell-init <shell>`

Prints the shell wrapper function for the given shell (`zsh`, `bash`,
or `fish`). See the [Shell integration](#shell-integration-recommended)
section for installation instructions.

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

Supported fields: `workspace`, `project`, `package`, `scheme`, `deviceType`, `runtime`, `sourceSimulator`, `sourceRuntime`, `worktreeDir`.

`workspace`, `project`, and `package` are mutually exclusive. Use `package` for Swift Package repositories (typically `"Package.swift"`); `xwt run` invokes `xcodebuild` from the worktree root with no `-workspace` / `-project` flag, letting `xcodebuild` discover the package automatically.

### Auth / Session Copy

When you log in to your app on a simulator, the auth state is split across two
places: the simulator **keychain** (`data/Library/Keychains/keychain-2-debug.db`)
and the app's **session cookies / URL-session storage**
(`…/Containers/Data/Application/<uuid>/Library/HTTPStorages/<bundleID>/httpstorages.sqlite`).
Modern apps keep their logged-in session in the latter, so copying the keychain
alone is not enough to stay logged in. New simulators created by `xwt start`
have neither, requiring a fresh login each time.

To skip re-authentication, set `sourceSimulator` in your `.xwt.json` to the name
(or UDID) of a simulator that is already logged in:

```json
{
  "workspace": "MyApp.xcworkspace",
  "scheme": "MyApp",
  "sourceSimulator": "iPhone 17 Pro",
  "sourceRuntime": "iOS 26.4"
}
```

When several simulators share the same name across different iOS runtimes, add
`sourceRuntime` (e.g. `"iOS 26.4"`) to pin which one to copy from. It applies
only when the source is resolved from `sourceSimulator`; if no simulator matches
both the name and the runtime, the copy fails rather than falling back to a
different runtime. (Pass a UDID to `--copy-auth-from` for the same precision on
the command line.)

How the copy happens:

- **`xwt start`** copies the **keychain** from the source to the new simulator.
  The keychain is simulator-level, so it can be copied immediately. Use
  `--no-copy-auth` to skip, or `--copy-auth-from <name-or-udid>` to override the
  source.
- **`xwt run`** copies the **keychain + session cookies** on the *first install*
  of the app — the session lives inside the app's data container, which only
  exists once the app is installed. It never overwrites a session you've already
  established on the target.
- **`xwt sync-auth <branch>`** force-copies keychain + session on demand,
  overwriting the target's existing session. Relaunch the app afterwards.

The source for `run` / `sync-auth` is resolved as `--copy-auth-from` > the
parent task's simulator (when stacking) > `sourceSimulator`. Both simulators are
briefly shut down during the copy to flush SQLite WAL journals; the source is
rebooted afterwards if it was running.

## File Layout

| Path | Purpose |
|---|---|
| `~/.xwt/repos/<repo>/<slug>.json` | Persisted task state |
| `~/worktrees/<repo>/<slug>/` | Git worktrees |
| `~/Library/Developer/Xcode/DerivedData/xwt/<slug>/` | Build artifacts |

## AI Agent Instructions & XcodeBuildMCP Integration

When you run `xwt start`, the tool writes instruction files into the worktree for both **Copilot CLI** and **Claude Code**:

```
<worktree>/.github/instructions/xwt.instructions.md   (Copilot CLI)
<worktree>/CLAUDE.local.md                             (Claude Code)
```

These files tell the AI agent (and XcodeBuildMCP) which simulator and DerivedData path to use for the branch.

### Copilot CLI instructions

The generated Copilot instructions file looks like this:

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

### Claude Code instructions

For Claude Code, `xwt` writes the same session defaults into `CLAUDE.local.md` — the local-only instructions file that Claude Code reads automatically. The content is wrapped in `<!-- xwt:start -->` / `<!-- xwt:end -->` markers so it coexists safely with any existing user instructions in the file.

### Git exclusion

The instructions files are specific to each developer's local environment (they contain simulator UDIDs and local paths), so they should **not** be committed. `xwt start` automatically adds them to the repository's `.git/info/exclude`:

```
.github/instructions/xwt.instructions.md
CLAUDE.local.md
```

`.git/info/exclude` works exactly like `.gitignore` but is local to your machine — it won't appear in diffs or affect other contributors, and there is no need to add anything to `.gitignore`.

## Typical Workflow

```bash
# 1. Start a new task — creates worktree, simulator, and instruction files,
#    and (with shell integration) auto-cds you into the worktree.
xwt start feature/login-refactor

# 2. Launch your AI coding agent and develop the feature
copilot          # GitHub Copilot CLI
claude           # Claude Code
# Both auto-detect the correct simulator and DerivedData via the generated instruction files.

# 3. Need a stacked branch? Run xwt start — auto-stacks and auto-cds.
xwt start feature/login-tests

# 4. Hop back to a parent in the stack
xwt cd feature/login-refactor

# 5. When done, clean up the environment
xwt remove feature/login-refactor
```

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
