---
name: fix-shellspec-style
description: >
  Format shellspec test files (*_spec.sh) to follow the project's testing
  conventions: file header, Include guard, section separators, description
  sentences, stream subject names, test structure order, blank stream
  assertions, eq vs include, wrapper naming, dependency mocking, filesystem
  isolation, and spacing rules. Pass a file path, a directory, or nothing to
  scan all spec files.
---

## Scope

Arguments: `$ARGUMENTS`

Determine the target file(s) from the arguments:

- **Empty**: fix every spec file in the project: all files matching
  `**/*_spec.sh` (discover them rather than assuming a fixed spec directory).
- **Single file path** (e.g. `spec/output_spec.sh`): fix only that file.
- **Directory path** (e.g. `spec/`): fix every `*_spec.sh` file found
  recursively inside it.

Read each target file before editing it.

## Rules

Apply the rules in
[`dev/docs/shellspec-style.md`](../../../dev/docs/shellspec-style.md) (at the
repository root), and **only** those rules. Read that file before editing so you
apply the current ruleset. It is the single source of truth for the project's
shellspec conventions; this skill is the mechanical application of it.

This skill edits only `*_spec.sh` files. The companion bash conventions for the
scripts under test live in
[`dev/docs/shell-style.md`](../../../dev/docs/shell-style.md).

Do not refactor test logic, rename variables, or change what is being tested.

## Workflow

1. Determine the target file list from the arguments.
2. Read `dev/docs/shellspec-style.md` for the ruleset.
3. For each file: read it, identify all violations of those rules, then apply
   fixes with the Edit tool.
4. Report a summary of what was changed per file.
