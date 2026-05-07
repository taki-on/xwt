# AGENTS.md

Conventions for contributing to xwt — especially around the user-facing
terminal UX. New commands and helpers should follow these rules so the
output stays consistent and behaves correctly when piped or non-interactive.

## Output channels

xwt routes output through `Terminal` (`Sources/xwt/Utilities/Terminal.swift`).
Do not call `print(...)` or `FileHandle.standardError.write(...)` directly
from command or service code.

| Goes to | Use                                       | When                                           |
|---------|-------------------------------------------|------------------------------------------------|
| stdout  | `Terminal.out(...)`                       | Step progress, success messages, summaries, structured output |
| stdout  | `Terminal.write(...)`                     | Inline prompts (no trailing newline)           |
| stderr  | `Terminal.err(...)`                       | Free-form lines associated with a warning/error block |
| stderr  | `Terminal.errorLine(msg)`                 | Hard error before `throw ExitCode.failure`     |
| stderr  | `Terminal.warningLine(msg)`               | Recoverable warning                            |
| stderr  | `Terminal.noteLine(msg)`                  | Informational note                             |

The split exists so that `xwt … | grep`, `xwt … > out.txt`, and CI logs all
behave correctly. Errors must never appear in stdout.

## Prefixes and symbols

| Situation                  | Prefix              | Style                |
|----------------------------|---------------------|----------------------|
| Hard error                 | `error:`            | bold red, on stderr  |
| Warning (non-fatal)        | `warning:`          | bold yellow, stderr  |
| Informational note         | `note:`             | cyan, stderr         |
| In-progress step           | `  ›` (2sp + U+203A)| cyan (`.info`)       |
| Step complete (success)    | `  ✓`               | green (`.success`)   |
| Step complete (failure)    | `  ✗`               | red (`.failure`)     |
| Continuation / child line  | `    ↳` (4sp)       | dim (`.muted`)       |
| Bullet                     | `  •`               | default              |
| Tree nodes                 | `  ├──` / `  └──`   | dim                  |

The `›` / `✓` / `✗` / `↳` vocabulary comes from `Spinner.around(...)` for
operations wrapped in a spinner — for those, you don't need to print the
step lines yourself, the spinner handles the in-progress and final state.

## Color usage

Color is on by default on a TTY and respects `NO_COLOR`, `CLICOLOR`,
`CLICOLOR_FORCE`, `FORCE_COLOR`, and `TERM=dumb`. xwt targets the **16-color
ANSI palette only** so that user terminal themes (Solarized, Dracula, etc.)
keep working as expected.

Do **not** hardcode color choices at call sites — always go through the
`Style` enum (`.success`, `.failure`, `.warning`, `.info`, `.muted`,
`.highlight`, `.heading`). If in doubt, use `.muted` rather than a saturated
color — over-colorization is worse than under-colorization.

## Emoji policy

| Where                                               | Allowed?      |
|-----------------------------------------------------|---------------|
| `xwt list` data display (`🟢`, `⚪`, `❌`, `📦`)     | Yes — they function as data icons in a table |
| `xwt init` interactive prompts (one icon per step)  | Yes — these are never piped |
| Progress / step lines, error / warning / note lines | **No** — use the `›` / `✓` / `✗` symbols + semantic color instead |
| Anything that may be piped or redirected            | **No** |

The unified step symbols carry the meaning without per-message emoji
clutter. Emoji also break column alignment because they are double-width.

## Message tone

- **Imperative present** for in-progress steps: `Creating worktree`,
  `Booting simulator`, `Building scheme`.
- **Past tense** for completion lines: `Worktree created`,
  `Simulator booted`, `Build succeeded`.
- **Sentence case**, not Title Case: `error: no task found`, not
  `Error: No Task Found`.
- **No trailing punctuation** on one-line step / completion messages.
- **Single-quote user-supplied values** in errors:
  `error: no task found for 'feature/login'`.
- **Never print raw stack traces** — catch errors and format them through
  `Terminal.errorLine(...)`.

## Spinners

Wrap long, output-quiet operations with `Spinner.around(...)`:

```swift
try Spinner.around(
    "Creating worktree at \(path)",
    final: "Worktree created at \(path)"
) {
    try WorktreeService.add(...)
}
```

Rules:
- Only wrap `ShellRunner.run(...)` calls (which capture subprocess output).
  **Never** wrap `ShellRunner.exec(...)` — its subprocess streams output to
  the terminal and the spinner redraws would interleave with it.
- The spinner degrades to a single `"<message>…"` line in non-TTY contexts
  and emits no escape codes, so piped output stays clean.
- `Spinner.around` calls `stop(.success, message: final)` on normal
  completion and `stop(.failure)` if the closure throws. SIGINT is handled
  globally by `SignalHandler.install()` (called from `Xwt.main`).

## New command checklist

When adding a new subcommand:

1. **Errors** route through `Terminal.errorLine(...)` immediately followed
   by `throw ExitCode.failure`. ArgumentParser will not print any extra
   text for `ExitCode.failure`, so your formatted error is the user's only
   message.
2. **Warnings** route through `Terminal.warningLine(...)` (continues
   execution).
3. **Long quiet shell calls** are wrapped with `Spinner.around(...)`.
4. **Step lines** use `Terminal.out(.info, "  › <verb>…")`; completion
   lines use `Terminal.out(.success, "  ✓ <past tense>")`.
5. **Final summary** prints a one-line `✓` followed by relevant key:value
   metadata (use `Terminal.styled(..., .muted)` for low-importance values).
6. **Smoke-test piped output**: `swift run xwt <cmd> | cat` must produce
   plain text with no escape sequences, and errors must still surface on
   stderr (`swift run xwt <cmd> 2>&1 >/dev/null` should print them).

## Build / test commands

- `swift build` — debug build at `.build/debug/xwt`.
- `swift run xwt <subcommand>` — run without installing.
- `make install` — release build that auto-bumps the integer in
  `Sources/xwt/Version.swift` and copies the binary to `~/.local/bin/xwt`.

There is no automated test suite; verify changes manually with the smoke
tests in step 6 above and by exercising the affected commands in a
disposable repo.
