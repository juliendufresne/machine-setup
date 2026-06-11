---
name: fix-shell-style
description: >
  Format shell scripts to follow the project's bash style guide: double-bracket
  tests, structured docblocks, typed locals, blank-line rules, readonly
  functions, main-function wrapping, and dependency-first function ordering.
  Pass a file path, a directory, or nothing to scan all scripts.
---

## Scope

Arguments: `$ARGUMENTS`

Determine the target file(s) from the arguments:

- **Empty**: fix every shell script tracked in the repository. Discover them
  (e.g. `git ls-files` filtered by a `*.sh`/`*.bash` extension or a `#!.*sh`
  shebang) rather than assuming a fixed set of paths.
- **Single file path** (e.g. `lib/output.sh`): fix only that file.
- **Directory path** (e.g. `lib/`): fix every shell script found recursively
  inside it.

Read each target file before editing it.

## Rules

Apply the rules in [`dev/docs/shell-style.md`](../../../dev/docs/shell-style.md)
(at the repository root), and **only** those rules. Read that file before
editing so you apply the current ruleset. It is the single source of truth for
the project's bash style; this skill is the mechanical application of it.

Do not refactor logic, rename identifiers, or add features.

## Workflow

1. Determine the target file list from the arguments.
2. Read `dev/docs/shell-style.md` for the ruleset.
3. For each file: read it, identify all violations of those rules, then apply
   fixes with the Edit tool (or Write for full rewrites).
4. After all edits, run the project's shell linter to confirm no new warnings.
   Use whatever wrapper the project provides - a `make lint-shell` target, a
   script under `dev/`, or `shellcheck <files>` directly if none exists yet.
5. Report a summary of what was changed per file.
