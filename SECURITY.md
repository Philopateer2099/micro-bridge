# Security

## What the bridge can do on your Mac

- Read the Codex Micro's keys, dial and stick (Input Monitoring).
- Type keys into the app in front, press buttons in it, and read the address of the Claude
  window (Accessibility).
- Run the shell commands your config file names in `sh:` actions.
- Read and write its own files in `~/Library/Application Support/micro-bridge`.

It makes no network connections. It sends the pad five commands and no others (see the
[README](README.md#safety-and-privacy)).

## Reporting a problem

Report it in private: on the repository's GitHub page, open **Security** and choose
**Report a vulnerability**. Say what you did, what happened and which version you ran.

Please do not open a public issue for something that lets another program or person type,
click or run commands through the bridge.
