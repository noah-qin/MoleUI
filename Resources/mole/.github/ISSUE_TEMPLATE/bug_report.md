---
name: CLI Bug Report
about: Report a bug in the Mole command-line tool
title: '[BUG] '
labels: bug
assignees: ''
---

## Before submitting

Run `mo update` to install the latest stable version, then check `mo --version`. Reproduce the problem with that version. If updating itself fails, report that failure and your installed version.

- [ ] I updated and reproduced the problem, or this report explains why I cannot update.

## Describe the bug

A clear and concise description of what the bug is. We suggest using English for better global understanding.

If you believe the issue may allow unsafe deletion, path validation bypass, privilege boundary bypass, or release/install integrity issues, do not file a public bug report. Report it privately using the contact details in `SECURITY.md`.

## Steps to reproduce

1. Run command: `mo ...`
2. ...
3. See error

## Expected behavior

A clear and concise description of what you expected to happen.

## Debug logs

Please run the command with `--debug` flag and paste the output here:

```bash
mo <command> --debug
# Example: mo clean --debug
```

<details>
<summary>Debug output</summary>

```text
Paste the debug output here
```

</details>

## Environment

Paste the output of `mo --version` from the version used to reproduce the problem:

```text
Paste mo --version output here
```

## Additional context

Add any other context about the problem here, such as screenshots or related issues.
