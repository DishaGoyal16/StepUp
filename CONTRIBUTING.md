# Contributing to StepUp

StepUp keeps its Android application, browser dashboard and team website on different branches. Start from the branch for the component you intend to change.

## Choose the branch

| Component | Base branch | Setup and validation guidance |
|---|---|---|
| Repository documentation and academic reports | `main` | [Repository overview](README.md) and files in `docs/` |
| Flutter application, Kotlin step engine and Firebase backend | `Complete_Flutter_App` | `README.md`, `TESTING_GUIDE.md` and `KNOWN_LIMITATIONS.md` on that branch |
| React browser dashboard and optional Express API | `steup-website` | `README.md` and `AWS_DEPLOYMENT.md` on that branch |
| Team presentation website and architecture assets | `Team_Website` | Website files and presentation material on that branch |

The `App`, `Backend` and `Frontend` branches contain earlier work. Check the repository overview before using them as a development base.

## Prepare a change

1. Check `git status` and keep unrelated local changes separate.
2. Fetch the current remote branches with `git fetch origin`.
3. Create a working branch from the appropriate remote base. For example, for repository documentation:

   ```bash
   git switch -c docs/describe-your-change origin/main
   ```

4. Make a focused change and review it with `git diff`.
5. Run checks appropriate to the component. Follow that branch's testing guide; record commands and actual results in the pull request.
6. Run `git diff --check` to catch whitespace errors before committing.
7. Stage only the intended files, make a descriptive commit and push your working branch.
8. Open a pull request against the same component branch used as the base.

For documentation, check that links resolve, paths match the intended branch, and instructions distinguish implemented features from planned work. Do not describe a test as passed unless it was actually run.

## Keep the three products distinct

The team website presents the project. The browser dashboard is a separate demonstration application. The Flutter application contains the native Android verified-step path and its Firebase integration. A successful website build does not validate the Android sensor algorithm or demonstrate that a production backend has been deployed.

When reporting sensor results, identify the device, carrying position, scenario and recording or test evidence. Keep raw steps separate from verified steps. Label synthetic inputs and replay results explicitly, and retain known limitations when updating documentation.

## Check deployment triggers before publishing a branch

A branch push can be observed by services outside the repository's workflow files. Before pushing a deployment or handover branch, coordinate with the person maintaining the live site and check:

- GitHub Pages' configured publishing source.
- GitHub Actions triggers and branch filters in the relevant commit.
- Repository webhooks and installed GitHub Apps.
- Connected hosting projects, including production and preview deployment rules.
- AWS source connections and pipeline triggers, when AWS is used.

An empty repository webhook list does not establish that every external deployment integration is disabled. Record what was checked and what remains unverified. Do not change publishing settings as part of an unrelated contribution.

## Protect private data

Do not commit credentials, tokens, private Firebase configuration, personal sensor recordings or user exports. Use clearly labelled sample data when documentation needs an example. If a credential has been exposed, notify the maintainer and rotate it through the provider; deleting a file from the latest commit does not remove it from Git history.
