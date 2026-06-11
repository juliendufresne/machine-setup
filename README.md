# machine-setup

Install and configure software on a machine, idempotently and reversibly. Each
piece of software has one lifecycle (install, configure, uninstall, status) driven
by a shared runner. The orchestrator discovers and selects software only; after it
installs the chosen software it runs two thin provisioners, `workspace` and
`dotfiles`, each of which fetches a self-contained installer script and runs it (the
script downloads its repository and lays it down), so your personal configuration
lives in its own repo rather than here. The provisioners are a fixed post-install
step, never listed beside the software.

## Installation

On a fresh machine, fetch the bootstrap and run it with `sh`. Pass the script as
an argument rather than piping it in: the orchestrator asks questions with
`read`, and a pipe (`... | sh`) ties up stdin so those prompts never reach the
terminal. Ubuntu ships `wget` (and not always `curl`), so the `wget` form is the
safe default:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/juliendufresne/machine-setup/main/install.sh)"
```

If the host has `curl` instead:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/juliendufresne/machine-setup/main/install.sh)"
```

The bootstrap ([`install.sh`](install.sh)) currently bootstraps Ubuntu (apt),
and is structured to extend to other OS/package managers. It installs `git` and
a recent enough `bash`, clones this repository under
`$XDG_DATA_HOME/machine-setup` (default `~/.local/share/machine-setup`), then
hands over to `bin/machine-setup`. Every step is idempotent, so re-running the
command updates the checkout and runs again.

To pass options through to `bin/machine-setup`, append them after the command
string (`sh` assigns them to the script's positional parameters):

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/juliendufresne/machine-setup/main/install.sh)" -- <machine-setup options>
```

The bootstrap itself understands `--repository <url>` and `--directory <path>`
(or the `MACHINE_SETUP_REPOSITORY` / `MACHINE_SETUP_DIR` environment variables);
every other argument is forwarded unchanged.

## Status

In place so far:

- the shared library under `lib/` (runner, OS detection, host probing, sudo,
  state store, session, the checkbox menu, the sticky-header screen, logging),
- the `bin/machine-setup` orchestrator and the `install.sh` bootstrap,
- 19 pieces of software targeting Ubuntu 26.04, each its own
  `libexec/ubuntu_26.04/software/<name>.sh`: 12 command-line tools (`claude`,
  `fish`, `git`, `gpg`, `htop`, `httpie`, `neovim`, `openssh-client`, `pass`,
  `tmux`, `tree`, `vim`) and 7 desktop apps skipped on a headless host (`discord`,
  `docker-desktop`, `jetbrains-toolbox`, `keeweb`, `spotify`, `sublime-text`,
  `vlc`),
- the `workspace` and `dotfiles` provisioners: a fixed post-install step (not
  discovered software), each fetching a self-contained installer script and running
  it last, after every piece of software (the script downloads its repository and
  lays it down), so your personal configuration lands on top of the freshly installed
  tools,
- shellspec tests for every script, a `Makefile` that runs the checks in docker,
  and a CI workflow that runs them inside the real target OS.

The earlier identity toolkit (per-tree git/SSH/GPG setup, SSH/GPG key generation,
the reversible `~/.gitconfig` and `~/.ssh/config` blocks, the registration gate,
the fd-backed secret store) was moved out of scope; the workspace and dotfiles
provisioners now delegate all of that to the external repositories their installer
scripts download. The removed code stays recoverable in git history.

Not built yet: OS targets beyond Ubuntu 26.04.

## Layout

The tree splits into what runs on a target machine (`bin/`, `libexec/`, `lib/`)
and what only develops it (`dev/`).

```
bin/machine-setup                          orchestrator flow: usage, set-up, teardown, main; drives the software and provisioner libs
lib/                                       shared, sourced by every software script
lib/software.sh                            the software module: discover, run, status, the menus, install/uninstall, the status table
lib/software/<name>/.../configure          OS-independent config fragments a software script sources (fish, neovim)
libexec/<os>_<ver>/software/<name>.sh      one piece of software per OS+version, all four verbs inside
libexec/<os>_<ver>/system-upgrade          refresh the package manager + upgrade packages, not discovered software
lib/provisioner.sh                         the provisioner framework + menu: fetch and run an installer script (workspace, dotfiles), driven in-process by the orchestrator
share/machine-setup/<name>/description     one-line description, shown in the menu (software and provisioners)
dev/test/shell/                            shellspec specs, mirroring the source tree
```

## Running the full setup

`bin/machine-setup` is the orchestrator: it discovers every piece of software in
`libexec/`, drives the selection, runs the lifecycle across the whole set, then runs
the post-install provisioners.

```sh
bin/machine-setup                 # choose software interactively, set it up, then provision
bin/machine-setup tree git        # set up exactly the named software, unattended (no provisioners)
bin/machine-setup uninstall       # choose installed software to remove from a menu
bin/machine-setup uninstall tree  # unconfigure and remove the named software
bin/machine-setup status          # print "<name><tab><status>" for every piece of software
```

With no names it opens a checkbox menu (arrows or `j`/`k` move, space toggles, Enter
confirms) of the software this host can run, pre-ticked from a previous run, or every
available piece on a first run. Software that reports `unavailable` here (a GUI app on
a headless host, say) is left out. Deselecting a piece never removes it: removal is a
separate, explicit action (`uninstall`).

`uninstall` with no names opens a removal menu: a checklist of every installed piece,
each entry unticked and labelled with its current status (`installed`, `configured`,
or `unmanaged`), so you pick exactly what to remove. Removal is never the default, so
a piece is removed only if you explicitly tick it. The provisioners own no checkout, so
removal covers software only.

The software install goes in two phases: the orchestrator collects every selected
piece's inputs (the one interactive software step), refreshes the host package manager
once (so every piece installs against up-to-date package lists and an upgraded base),
then installs and configures each piece. There is no ordering between pieces. Removal
is staged the same way: collect inputs first, then unconfigure and uninstall.

After the software install, the interactive flow runs the post-install provisioners.
It offers a second toggle menu listing the `workspace` and `dotfiles` provisioners,
both ticked, and runs the ones you leave ticked, in a fixed order (the workspace before
the dotfiles), on top of the freshly installed tools. A named, unattended run installs
exactly the named software and never touches the provisioners; the provisioners run
only through this interactive post-install step.

With no terminal (a piped or unattended run) the menus fall back to their ticked sets:
the install menu to its pre-ticked software, the provisioner menu to both, the removal
menu to nothing. So `bin/machine-setup <names>` installs exactly that software and never
removes or provisions anything on its own.

The `workspace` and `dotfiles` provisioners share one framework in
`lib/provisioner.sh`, which the orchestrator drives in-process after loading each
one's record (its header and default installer): each fetches a self-contained
installer script and runs it, last, so your personal configuration (`config.fish`,
`tmux.conf`, the per-tree git/SSH/GPG
setup, and the like) lands on top of the freshly installed tools; the installer
downloads its repository and lays it down on its own. A provisioner asks for its one
input when it runs, not up front, so the question is asked right before the installer
runs: where the installer comes from (blank keeps the default), either an URL fetched to
a temporary file and run (with `wget`, or `curl` when wget is absent) or a path to a
local executable run directly. It downloads to a file and runs it rather than piping
into `sh`, so the installer keeps stdin on the terminal and can prompt you. Override it
with `WORKSPACE_INSTALLER` / `DOTFILES_INSTALLER`. Everything those repositories do (key
generation, `~/.gitconfig` wiring, host aliases) is now their own concern; the original
toolkit was removed from this tree and stays recoverable in git history.

Descriptions shown in the menu live in `share/machine-setup/<name>/description`, one
plain-text line per name (a missing file just means no description).

## Using a piece of software directly

A piece of software is the per-OS file `libexec/<os>_<version>/software/<name>.sh`,
directly executable and taking one action (default `install`). Run the file for
your host directly:

```sh
libexec/ubuntu_26.04/software/git.sh status      # unavailable | available | unmanaged | installed | configured
libexec/ubuntu_26.04/software/git.sh install     # install + configure (default action)
libexec/ubuntu_26.04/software/git.sh uninstall   # unconfigure + uninstall
```

The orchestrator picks the right per-OS file for your host (resolved through
`lib/os.sh`); running a piece by hand you choose the file under your OS token's
`software/` directory. A piece with OS-independent configuration sources it from
`lib/software/<name>/.../configure` (the `fish` hand-off block, the `neovim`
editor alternatives).

The `workspace` and `dotfiles` provisioners are OS-agnostic and own no executable of
their own: they are the shared framework in `lib/provisioner.sh`, which the
orchestrator drives in-process after loading each one's record. They are not
discovered software and never appear in the orchestrator's menus; the interactive
flow runs them as a fixed post-install step and is the only way to run them.
Provisioning is the only action: the framework collects the one input, then fetches
and runs the installer script. There is no removal or status (they own no checkout
and track no install state).

`install` and `uninstall` open a magenta stage header (`▶ Installing git`) and
then, inside it, one spinner line per command saying what it does, which turns
into a green check on success or a red cross plus the command's output on failure.
Piped or in CI the spinner and colours drop to plain result lines.

Inputs (such as `git user.name`) are prompted once and saved under
`$XDG_STATE_HOME/machine-setup`. A non-interactive run can supply them through
the matching environment variable, for example `GIT_NAME` and `GIT_EMAIL`.

## Development

The checks run in a pinned docker toolbox through the `Makefile`:

```sh
make lint     # shellcheck every script + lint the GitHub workflows
make test     # run the shellspec suite
make check    # both
```

To add a new software unit, see
[dev/docs/adding-a-software-unit.md](dev/docs/adding-a-software-unit.md): a
step-by-step guide covering the two source files, the two specs, and the checks.

`make lint` runs two linters: `lint-shell` (shellcheck over every script under
`bin/`, `lib/`, and `libexec/`) and `lint-github-workflows`, which checks that every
GitHub Actions reference is pinned to a SHA in the required format and
shellchecks the scripts embedded in the workflow `run:` steps. To resolve action
tags to SHAs or refresh them (both need network), use `make
github-actions-outdated`, `make github-actions-update` and `make
fix-github-workflows`.

The only prerequisite is docker. To run the tools directly instead, install
shellcheck and [shellspec](https://shellspec.info) and run `shellspec` and
`shellcheck --rcfile dev/.shellcheckrc <scripts>` from the repo root.
