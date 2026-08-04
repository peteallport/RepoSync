# RepoSync

RepoSync is a small, user-controlled macOS LaunchAgent that keeps selected Git
repositories fetched and safely fast-forwards clean `main` working trees.

It has no menu-bar item, background application, or resident daemon. `launchd`
wakes a short-lived worker every ten minutes; the worker exits when the sync is
complete. A `reposync` command provides status and control.

## Safety contract

RepoSync always fetches configured repositories when the remote is available.
It changes a working tree only when all of these conditions hold:

- the checked-out branch is `main`;
- the index and working tree contain no staged, unstaged, or untracked changes;
- no merge, rebase, cherry-pick, revert, or bisect is in progress;
- local `main` can fast-forward to `origin/main`.

RepoSync never switches branches, stashes changes, rebases, resets, force
updates, resolves conflicts, or creates merge commits. Dirty repositories and
feature branches are fetch-only.

## Requirements

- macOS
- Git
- Bash 3.2 or newer (included with macOS)

## Install

```bash
git clone https://github.com/peteallport/RepoSync.git
cd RepoSync
./install.sh
```

The installer creates:

- `~/.local/bin/reposync`
- `~/.local/libexec/reposync-worker`
- `~/.config/reposync/repos`
- `~/.local/state/reposync/`
- `~/Library/LaunchAgents/io.github.peteallport.reposync.plist`
- `~/Library/Logs/RepoSync/`

No administrator privileges are required.

Make sure `~/.local/bin` is on your shell's `PATH`, then add repositories:

```bash
reposync add ~/Developer/project-one ~/Developer/project-two
reposync run
reposync status
```

## Control

```text
reposync status              Show schedule and last per-repository results
reposync run                 Run once, including while scheduling is paused
reposync pause               Persistently pause scheduled runs
reposync resume              Resume scheduled runs
reposync logs [--follow]     Read or follow the activity log
reposync list                List configured repositories
reposync add <path>...       Add Git working trees
reposync remove <path>...    Remove Git working trees
reposync doctor              Check the installation
reposync uninstall [--purge] Remove RepoSync; preserve data unless --purge
```

`pause` disables and unloads the user LaunchAgent without interrupting an
active Git command. A manual `reposync run` remains available while paused.

## Authentication

Scheduled runs are non-interactive. Existing SSH agents and macOS Keychain Git
credentials can be used, but RepoSync will not display a password prompt. An
authentication failure is recorded in `reposync status` and `reposync logs`.

## Development

Run the end-to-end safety suite on macOS:

```bash
./test/run.sh
```

The tests create temporary local remotes and verify clean fast-forwards plus
fetch-only behavior for staged, unstaged, untracked, feature-branch, and
diverged repositories.

## License

RepoSync is available under the [MIT License](LICENSE).
