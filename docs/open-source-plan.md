# Going open source

The steps from a private repo to a public project people can download, read about and report
problems to. Tick each box as it lands. Steps marked **(owner)** need the owner: a go-ahead to
push or publish, money, or their own writing. Everything else can be done locally first.

The decisions behind this plan are D-016 to D-025 in [decisions.md](decisions.md).

## Phase 1: make the repo publishable (about 3 hours)

- [x] Fold the `desktop-app` branch into the release pull request ("Bring the repo up to date
      and prepare it for a public release"). **(owner: push)**
- [x] Get CI to pass on that pull request. It has never run.
- [ ] Install from the README, step by step, on a fresh macOS user account. Fix what the steps
      get wrong. **(owner: 30 minutes at the Mac)** The steps and what each should print are
      in [install-test.md](install-test.md). The parts that need no second account are done:
      a fresh clone builds and passes, and `scripts/claude-hooks` now handles a missing
      settings file.
- [x] Add `CONTRIBUTING.md`: how to build, test and send a change, and what is in scope (macOS,
      the Codex Micro, Claude Code in the app and in a terminal).
- [x] Add issue templates. A bug report asks for macOS version, firmware (`micro status`), the
      app it happened in, and the lines from `~/Library/Logs/micro-bridge.log`.
- [x] Say plainly at the top of the README and the site: unofficial, not affiliated with
      OpenAI, Work Louder or Anthropic.
- [x] Turn the development log into a short `CHANGELOG.md` for readers. Keep `decisions.md`.
- [x] Make the public repo from one clean commit, with the noreply identity (D-016, D-017).
      Made on 2026-11-22. `scripts/public-snapshot <folder> "<name> <noreply address>"` makes
      the commit in a new folder and pushes nothing. It first runs `scripts/check-public`, which
      looks for home folder paths, email addresses, session ids and keys; CI runs it on every
      change too.

## Phase 2: a download that just works (1 to 2 days of waiting, then about 2 hours)

- [ ] Join the Apple Developer Program (D-018). **(owner: 99 US dollars a year, identity check)**
- [x] Write the release script (`scripts/release`, steps in [releasing.md](releasing.md)). Its
      test zip is signed with the hardened runtime and runs.
- [ ] The first Developer ID build and notarization, once the membership is active.
      **(owner: about 15 minutes)**
- [ ] Let a downloaded app set itself up without the `scripts` folder: start at login, and add
      the Claude Code hook. Decided (D-024, D-025) and built: Setup's "Start at login" and
      "Copy the command" (`micro hooks install`), and the MicroBridge plugin. Not yet tried on
      a real login: that is part of the install test.
- [ ] Publish a `.zip` or `.dmg` on GitHub Releases, with its changelog. **(owner: publish)**
- [ ] Later: a Homebrew cask, then automatic updates.

## Phase 3: the site and the first post (about 3 hours, plus writing)

- [ ] Host `site/index.html` on GitHub Pages, with a Download button for the latest release.
      **(owner: publish)** The Site workflow is ready: turn on Pages (Settings, Pages, Source:
      GitHub Actions) and set the repository variable `SITE` to `on`. The Download button waits
      for the first release and for how a downloaded app sets itself up.
- [ ] Record a 30 to 60 second demo: approve a prompt, answer a question card, scroll with the
      stick, switch panes. **(owner: recording)**
- [ ] First post on the owner's portfolio site (D-020): how the pad was mapped, why a locked
      Mac refuses the lights, why the Claude app scrolls only what is under the pointer.
      **(owner: writing)**

## Phase 4: show it to people (one day, after Phase 2)

The owner moved two of these forward (D-036): LinkedIn and r/ClaudeAI come right after the repo
is public, before the signed download. Those posts say to build from source.

- [ ] Show HN.
- [ ] r/ClaudeAI, r/MacApps and keyboard communities.
- [ ] Write to Work Louder, who make the pad.
- [ ] The owner's own social accounts, linking the post.

## Phase 5: keep it going (1 to 2 hours a week)

- [ ] Read new issues once a week; label them; mark good first issues.
- [ ] Release with version numbers and a changelog entry.
- [ ] After each Claude app update, check that Approve, Decline and the question cards still
      find their buttons (`micro buttons`). The config lets people patch a renamed button
      before a release does.
- [ ] Keep the scope small, and say so when declining a request.
