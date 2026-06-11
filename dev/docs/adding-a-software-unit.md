# Adding a software unit

This guide walks through adding a new software unit end to end: the unit source
file, a one-line description, the spec file(s), and the checks that must pass.
Follow it top to bottom and you will have a working, tested, lint-clean unit.

Read it alongside the two style guides this repo enforces:

- `dev/docs/shell-style.md` (also applied by the `fix-shell-style` skill),
- `dev/docs/shellspec-style.md` (also applied by the `fix-shellspec-style` skill).

The worked reference unit is `git`. Every file below mirrors it, so when in doubt
open the git files and copy their shape:

- `libexec/ubuntu_26.04/software/git.sh`
- `dev/test/shell/libexec/ubuntu_26.04/software/git_spec.sh`

## What a software unit is

A software unit is **one source file per supported OS target**, plus a second
that is created only when the unit configures something:

1. **One per-OS file per supported target**, `libexec/<os-id>_<version>/software/<name>.sh`,
   executable. It implements the install side of the `unit::*` contract and calls
   `runner::run`. The current matrix is a single target, Ubuntu 26.04, so the file
   is `libexec/ubuntu_26.04/software/<name>.sh`. There is no per-unit dispatcher:
   the orchestrator resolves the host OS token itself (through `lib/os.sh`) and
   runs the matching file directly.
2. **A `configure` fragment**, only when the unit configures something. It holds
   the three configuration functions (`unit::is_configured`, `unit::configure`,
   `unit::unconfigure`) and the helpers they share, and the per-OS scripts source
   it before `lib/runner.sh`. It is not a per-OS executable, so it lives under
   `lib/`, and the path records how widely the code applies:
   - `lib/software/<name>/configure` when the configuration is OS independent
     (for example editing shell rc files, as `fish` does). One file, every
     target sources it.
   - `lib/software/<name>/<scope>/configure` when it is not, where `<scope>`
     names the family it is valid for. `neovim` points `vi` at neovim with
     `update-alternatives`, a dpkg tool, so its fragment is
     `lib/software/neovim/debian-family/configure` and only the Debian-family
     per-OS scripts source it; a non-Debian target (RHEL's `alternatives`, say)
     would carry its own differently-scoped sibling directory. The point of
     splitting `configure` out of the per-OS file is to separate what is OS
     specific from what is not, so the path must not imply OS independence the
     code does not have. A unit that configures nothing ships no `configure`
     fragment and inherits the runner's no-op defaults for those three functions.

Plus **spec files** mirroring the source tree under `dev/test/shell/`:

3. `dev/test/shell/libexec/<os-id>_<version>/software/<name>_spec.sh` (the per-OS spec),
4. the configure spec, only when the unit ships a `configure` fragment, mirroring
   the fragment's path: `dev/test/shell/lib/software/<name>/configure_spec.sh`, or
   `dev/test/shell/lib/software/<name>/<scope>/configure_spec.sh` for a scoped one.

Plus a one-line **description** the orchestrator menu shows:

5. `share/machine-setup/<name>/description` (plain text, optional but recommended).

Nothing registers a unit explicitly. The orchestrator discovers it by globbing the
per-OS software files under the host OS token's directory
(`libexec/<os-id>_<version>/software/*.sh`) and reads the description from
`share/`; the linter and test runner discover the scripts and specs by globbing.
So "adding a unit" is just creating these files correctly and making the per-OS
file executable.

The shared library under `lib/` (the runner, OS detection, output, state, sudo,
host probing) does all the repetitive work. A unit only fills in its own hooks.

## Naming conventions

- `<name>` is the unit name: lowercase, the command/software it installs (`git`,
  `curl`, `docker`). It must be unique within the OS token's `software/`
  directory.
- The per-OS file lives under the OS token directory and is named for the unit:
  `libexec/<os-id>_<version>/software/<name>.sh`. The token `<os-id>_<version>` is
  the `ID` and `VERSION_ID` from `/etc/os-release`, joined with an underscore,
  version dotted: `ubuntu_26.04`. This is the token `os::file_token` produces; the
  orchestrator resolves the host's token and runs the matching file.
- The unit's local functions and entry point take the unit-name prefix:
  `<name>::main`, and any local helper `<name>::...` (the filename without `.sh`
  is the unit name, so this is just the normal filename rule). This is distinct
  from `unit::*` (the runner contract) and `runner::*` (reserved for the runner).

## Step 1: the per-OS file (`libexec/<os-id>_<version>/software/<name>.sh`)

This is where the install side of the work lives. It must define these **six**
`unit::*` contract functions, plus `<name>::main`:

| Function               | Purpose                                                  |
| ---------------------- | -------------------------------------------------------- |
| `unit::is_available`   | requirements are met to install (for example a desktop)  |
| `unit::is_installed`   | the unit is present on the host by any means             |
| `unit::is_managed`     | the unit is present via our own mechanism (our package)  |
| `unit::request_inputs` | declare/collect inputs, warm sudo                        |
| `unit::install`        | install or update (idempotent)                           |
| `unit::uninstall`      | remove the software                                      |

The remaining three contract functions are about configuration:

| Function               | Purpose                                                  |
| ---------------------- | -------------------------------------------------------- |
| `unit::is_configured`  | our configuration is in place                            |
| `unit::configure`      | ensure the configuration is correct (idempotent)         |
| `unit::unconfigure`    | restore configuration to its pre-our-config state        |

They are OS-independent, so they do not go in the per-OS file. A unit that
configures something puts them in a `configure` fragment under `lib/software/`
(see the configuration variant below); a unit that configures nothing omits them
entirely and inherits the runner's no-op defaults.

The runner (`lib/runner.sh`) calls these in a fixed order and computes status from
the four predicates. You do not call them yourself; you only implement them.

### The simplest case: a single apt package, no configuration

This is the git shape: a command-line tool, one package, nothing to configure.
Replace `git` with your package/command name throughout. The condensed body
(the real file adds a full docblock above every function, exactly like
`libexec/ubuntu_26.04/software/git.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# ─── Runner contracts ─────────────────────────────────────────────────────────
# The unit::* interface the runner calls. Every unit script defines all of it.

unit::is_available()   { true; }                          # no requirements
unit::is_installed()   { command -v <cmd> &>/dev/null; }  # present by any means
unit::is_managed()     { dpkg -s <pkg> &>/dev/null; }     # present via our package
unit::request_inputs() { sudo::warmup; }                  # no inputs; apt needs root

unit::install() {
    output::run 'Updating the package lists' sudo apt-get update -qq || return $?
    output::run 'Installing the <pkg> package' sudo apt-get install -y <pkg>
}

unit::uninstall() {
    output::run 'Purging the <pkg> package' sudo apt-get purge -y <pkg>
}

# ─── Main ─────────────────────────────────────────────────────────────────────

<name>::main() { runner::run "$@"; }
[[ -v TEST_FLAG ]] || readonly -f <name>::main

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || <name>::main "$@"
```

The file is three directories deep (`libexec/<token>/software/`), so the relative
path to `lib/` is `../../../lib/`. The `TEST_FLAG` guard keeps the function
non-readonly so the spec can source it and mock; the `Execute` guard keeps `main`
from running when the file is `Include`d by a spec (`${BASH_SOURCE[0]}` differs
from `$0` then).

Every function needs its own docblock and `[[ -v TEST_FLAG ]] || readonly -f`
line in the real file. Copy the git file and adapt; do not ship the condensed
form above.

Key points:

- `unit::is_installed` is the broad "is it usable" check (`command -v`).
  `unit::is_managed` is the narrow "did it come from our mechanism" check
  (`dpkg -s`). The runner uses the difference to refuse to take over a foreign
  install and to warn after uninstall if a copy remains. For a single apt package
  the two differ only in the command.
- `unit::install` is install-or-update: `apt-get install` upgrades an
  already-present package, so re-running install is idempotent by contract.
- `unit::uninstall` is unconditional: it removes the software whether or not we
  installed it, so a user who asks to uninstall always gets a clean removal.
- Every command that does work goes through `output::run '<message>' <command...>`
  so the user sees a spinner/result line, not the command's chatter. Chain
  `|| return $?` between steps so a failure stops the run and propagates.
- `unit::request_inputs` runs `sudo::warmup` because the apt steps need root. If
  your unit needs no root and no inputs, it can be `:` instead.

### Variant: the unit needs configuration

If your unit configures something (variables in files), create a `configure`
fragment under `lib/software/` and define the three configuration hooks there
instead of leaving them as runner defaults. Name it `lib/software/<name>/configure`
when the code is OS independent (every per-OS file sources the one file), or
`lib/software/<name>/<scope>/configure` when it is not, where `<scope>` is the
family it applies to - see the file list at the top of this guide for when each
applies. Configuration must be reversible: snapshot each variable's prior value
before changing it, and restore it on unconfigure.

The `configure` file is a sourced fragment, not an executable: same `#!/usr/bin/env
bash` and `set -euo pipefail` header as a `lib/` file, a re-source guard, its
helpers under `# ─── Functions ───`, and the three contract functions under
`# ─── Runner contracts ───`. It does not source `lib/runner.sh`; the per-OS file
does that. Model an OS-independent fragment on `lib/software/fish/configure`, and
a scoped one on `lib/software/neovim/debian-family/configure`:

```bash
#!/usr/bin/env bash
set -euo pipefail
# <unit>'s configuration contract, identical across OS targets.

! declare -F unit::is_configured &>/dev/null || return 0

# ─── Runner contracts ─────────────────────────────────────────────────────────

unit::is_configured() {
    # true only when every value we set is present and correct
    grep -q '^our-setting=' /etc/<pkg>/<pkg>.conf
}

unit::configure() {
    # snapshot the prior value once (empty snapshot = it was absent), then set it.
    state::remember our-setting "$(current_value_or_empty)"
    # ensure the desired state idempotently; do not blindly append.
    set_value our-setting desired
}

unit::unconfigure() {
    # restore exactly what was there before we touched it.
    local prior; prior="$(state::recall our-setting)"
    [[ -n "$prior" ]] && set_value our-setting "$prior" || unset_value our-setting
}
```

`state::remember`/`state::recall` key on the unit name automatically: before
`unit::configure` changes a variable it records the prior value (an empty record
means the variable was absent), and `unit::unconfigure` restores each to that
recorded value, so the configuration we applied is undone exactly.
`unit::configure` runs on every install (so it must be idempotent) and even when
the software was installed by other means (it never checks ownership).

Then source the `configure` fragment from each per-OS file, in its
`# ─── Imports ───` section, **before** `lib/runner.sh` (so the unit's hooks are
defined before the runner would fall back to its no-op defaults):

```bash
# shellcheck source=lib/software/<name>/configure
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/software/<name>/configure"
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"
```

### Variant: the unit needs user input

Collect inputs in `unit::request_inputs` with `state::ask <name> <prompt>`, and
read them later with `state::input <name>`:

```bash
unit::request_inputs() {
    state::ask <name>.user 'your user name'
    state::ask <name>.email 'your email'
    sudo::warmup
}

unit::configure() {
    local user; user="$(state::input <name>.user)"
    ...
}
```

`state::ask` prompts once and saves the value under `$XDG_STATE_HOME/machine-setup/inputs`.
A non-interactive run can supply it through the matching environment variable: the
input name is upper-cased with non-alphanumerics turned to `_`, so `git.name`
reads from `GIT_NAME`, `<name>.email` from `<NAME>_EMAIL`.

### Variant: the unit has host requirements

If the unit can only run on some hosts, express it in `unit::is_available`. The
known primitive is a desktop environment, for a GUI app:

```bash
unit::is_available() { host::has_desktop; }
```

This is false on a host with no desktop session (a headless server, or WSL), so the unit reports
`unavailable` and is skipped there. A unit with no requirements uses `true`.

### Variant: more than one OS target

The matrix grows by adding files, never by branching inside one file. To support
another target, add `libexec/<os-id>_<version>/software/<name>.sh` (for example
`libexec/debian_13/software/<name>.sh`) with its own full contract, and its own
spec. If two OS files share logic, factor the shared part into a `lib/` helper and
call it from each; each per-OS file stays the self-contained source of its own
verbs.

## Step 2: the description

The orchestrator (`bin/machine-setup`) labels each unit in its selection menu with
a one-line description, read from `share/machine-setup/<name>/description`. Create
it: a single plain-text line, no markup.

```sh
mkdir -p share/machine-setup/<name>
printf '%s\n' 'Short human description of <name>' >share/machine-setup/<name>/description
```

The unit scripts never read this file, so it does not affect install behaviour; it
is metadata for the menu only. A unit with no description file just shows an empty
description, so this step is recommended but not load-bearing.

## Step 3: the per-OS spec

Create `dev/test/shell/libexec/<os-id>_<version>/software/<name>_spec.sh`. Copy
`dev/test/shell/libexec/ubuntu_26.04/software/git_spec.sh` and adapt. The pattern:

- `TEST_FLAG=true` then `Include` the per-OS file (the `Execute` guard keeps it
  from running; `TEST_FLAG` keeps its functions non-readonly so you can mock).
- In `setup` (run via `BeforeEach`): call `helper::isolate` (fresh state store
  and HOME under the temp base), `export MACHINE_SETUP_UNIT_NAME=<name>` (so the
  runner resolves the unit name without depending on `$0`), and set up any spy
  log and presence flags with defaults.
- Stub every system-touching command (`apt-get`, `dpkg`, `sudo`, and `command`
  for `command -v`) so no spec touches the real host. Stub `sudo` to run the
  wrapped command; stub `apt-get` to log its arguments.
- Cover: each meaningful predicate the per-OS file defines (true and false), every
  reachable `runner::status` word, and `unit::install`/`unit::uninstall` success
  and failure-propagation, so the script is fully covered. The configuration hooks
  are not tested here; they live in the `configure` fragment and are covered by its
  own spec (Step 4). CI targets ~100% coverage.

The git per-OS spec is the canonical example, including how it drives presence
with `GIT_ON_PATH` (for `command -v`) and `GIT_PRESENT` (for `dpkg -s`) so a test
can pretend the software is present by any means, present via our package, or
absent, without touching the host.

Follow `dev/docs/shellspec-style.md` for the file header, section separators
(`# ===`), assertion order (`status`, then `stdout`, then `stderr`, then files),
`equal` vs `include`, and spacing. The `fix-shellspec-style` skill applies it.

## Step 4: the configure spec (only when the unit configures)

If you added a `configure` fragment in Step 1, mirror it with a spec at the
fragment's path: `dev/test/shell/lib/software/<name>/configure_spec.sh`, or
`dev/test/shell/lib/software/<name>/<scope>/configure_spec.sh` for a scoped
fragment. Copy `dev/test/shell/lib/software/fish/configure_spec.sh` and adapt. The
pattern differs from a per-OS spec: the `configure` file is a sourced fragment that
needs `output::run`, so include `lib/output.sh` before it, and there is no package
machinery to stub.

- `TEST_FLAG=true`, then `Include lib/output.sh` and `Include` the `configure`
  file.
- In `setup` (run via `BeforeEach`): call `helper::isolate` so the rc-file edits
  stay under the isolated HOME, and stub only what the hooks read (for fish, that
  is `getent` and `id` for the login shell).
- Cover the helpers and the three contract functions: `unit::is_configured` true
  and false, `unit::configure` and `unit::unconfigure` on the success path and
  with a failing edit (status propagation), and the idempotent skip paths.

A unit with no `configure` fragment has no configure spec; the runner's no-op
defaults are covered by the unit specs that exercise them.

## Step 5: make it executable, lint, and test

```sh
chmod +x libexec/<os-id>_<version>/software/<name>.sh
# the configure fragment is sourced, not executed, so it stays non-executable

make lint     # shellcheck (auto-discovers your scripts by shebang) + workflow lint
make test     # the shellspec suite
make check    # both
```

`make lint-shell` finds new scripts automatically by their `#!.../bash` shebang,
so there is nothing to register. The checks run in a pinned docker toolbox; the
only prerequisite is docker. To run the tools directly instead, install shellcheck
and shellspec and run `shellspec` and `shellcheck --rcfile dev/.shellcheckrc <scripts>`
from the repo root.

To exercise the unit for real (actual `apt-get`), use the disposable sandbox - a
throwaway Ubuntu container that mirrors a target host. **Never run a unit's
`install`/`uninstall` on your own machine: it runs real `apt-get` and will change
(and `purge`) packages on your host.**

```sh
make sandbox-run ARGS="status fish"      # one-shot, unattended
make sandbox-run ARGS="install fish"     # real install + configure, in the container
make sandbox-run ARGS="uninstall fish"   # real unconfigure + uninstall, in the container

make sandbox                             # interactive shell in the same throwaway host
#   dev@sandbox:/work$ libexec/ubuntu_26.04/software/tmux.sh install
#   dev@sandbox:/work$ libexec/ubuntu_26.04/software/tmux.sh uninstall
```

The sandbox mounts the repo read-only and is discarded on exit (`--rm`), so
nothing it installs, configures, or purges can reach your host or your checkout.
The only prerequisite is docker. Read-only checks (`status`) are safe anywhere,
but routing them through the sandbox too keeps one habit.

## Reference: the library functions you will call

From `unit::*` hooks you mostly call these. You never call `runner::*` (the runner
calls your hooks); `MACHINE_SETUP_UNIT_NAME` is a test-only override.

- `output::run '<message>' <command...>` - run a command behind a spinner/result
  line, hiding its output unless it fails. The workhorse of `install`/`configure`/
  `uninstall`. Chain `|| return $?`.
- `output::stage`, `output::success`, `output::warn`, `output::error`,
  `output::fatal`, `output::info` - lower-level output lines (the runner opens the
  stage for you; you rarely need these directly).
- `sudo::warmup` - prime the sudo session during input collection, when the unit
  needs root. `sudo::is_needed` - whether a sudo prompt would occur.
- `state::ask <name> <prompt>` / `state::input <name>` - collect and read a saved
  input (env var override: upper-cased name).
- `state::remember <key> <value>` / `state::recall <key>` - snapshot and restore a
  config variable's prior value (keyed on the unit name), for reversible config.
- `host::has_desktop` - host probe for `unit::is_available`.
- `os::id`, `os::version`, `os::file_token` - OS detection (the orchestrator uses
  `os::file_token` to find the per-OS file; you will not normally call these from a
  unit).

## Status semantics (what `status` prints)

The runner computes the word from the four predicates, in order:

| Condition                      | Output        |
| ------------------------------ | ------------- |
| `unit::is_available` is false  | `unavailable` |
| `unit::is_installed` is false  | `available`   |
| `unit::is_managed` is false    | `unmanaged`   |
| `unit::is_configured` is false | `installed`   |
| otherwise                      | `configured`  |

`unmanaged` means present on the host but not via our mechanism: install refuses
to take it over, and uninstall warns (without failing) if a copy remains.
`unavailable` comes from `unit::is_available` returning false on a host the unit
cannot run on (a GUI app on a headless host). A host with no per-OS file for the
unit has no such unit at all: the orchestrator only discovers files under the
host's own `libexec/<os-id>_<version>/software/` directory.

## Checklist

- [ ] `libexec/<os-id>_<version>/software/<name>.sh` created with the six install-side
      `unit::*` functions, `<name>::main`, docblocks, `readonly -f` guards, section
      banners, `chmod +x`.
- [ ] `unit::is_installed` (broad) and `unit::is_managed` (our mechanism) are
      genuinely different checks.
- [ ] `unit::install` is idempotent (install-or-update); `unit::uninstall` is
      unconditional; both route work through `output::run`.
- [ ] If the unit configures something: `lib/software/<name>/configure` (or a
      scoped `lib/software/<name>/<scope>/configure`) created (non-executable) with
      the three config functions and their helpers, sourced from each per-OS file
      before `lib/runner.sh`; configuration is reversible via
      `state::remember`/`state::recall`, and `unit::is_configured` reflects it. If
      it configures nothing: no `configure` fragment, the runner defaults apply.
- [ ] Inputs (if any) collected in `unit::request_inputs` via `state::ask`,
      read via `state::input`; `sudo::warmup` called when root is needed.
- [ ] `share/machine-setup/<name>/description` created with a one-line description.
- [ ] `dev/test/shell/libexec/<os-id>_<version>/software/<name>_spec.sh` created,
      covering predicates, status words, and install/uninstall success and failure.
- [ ] the configure spec under `dev/test/shell/lib/software/<name>/...` created
      (only when the unit ships a `configure` fragment), covering the helpers and
      the three config hooks.
- [ ] `make check` passes (lint + tests), and
      `libexec/<os-id>_<version>/software/<name>.sh status` reports sensibly on
      this host.
- [ ] Style guides satisfied (`fix-shell-style`, `fix-shellspec-style`).
```
