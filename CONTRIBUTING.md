# Contributing

Contributions are welcome. Please preserve RepoSync's central rule: background
synchronization must never disrupt active work.

Before opening a pull request:

1. Keep the worker compatible with the Bash version shipped by macOS.
2. Add or update an end-to-end safety test for behavior changes.
3. Run `./test/run.sh` on macOS.
4. Explain any change that can modify Git refs, the index, or working trees.

Changes that introduce automatic stashing, branch switching, rebasing, resets,
forced ref updates, or conflict resolution will not be accepted.
