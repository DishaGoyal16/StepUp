# Contributing to the StepUp website

Use the `steup-website` branch for the React dashboard and optional Express demo API.

## Start locally

1. Install Node.js 20.19 or later.
2. Run `npm run install:all` from the repository root.
3. Run `npm run dev` and open http://localhost:5173.
4. Use the **Sign in as demo user** button to explore the dashboard.

The default demo runs without a backend. To try the API, copy
`backend/.env.example` to `backend/.env`, run `npm run dev:api` in a second
terminal, and set `VITE_API_URL=http://localhost:4000` in `frontend/.env`.
Restart the frontend after changing its environment variables.

All activity values are sample data. Keep that distinction visible when adding
screens or changing labels.

## Before committing

- Run `npm test` with Node.js 24 to check display formatting, distance conversion,
  greeting boundaries, and calendar dates across time zones.
- Run `npm run build` when changing application code; it checks TypeScript and
  builds both packages. This is a build check, not an automated test suite.
- For UI changes, check login, navigation, and logout in the browser.
- Check the affected screen at a narrow mobile width and a desktop width.
- For data changes, check that saved demo settings still survive a page reload.
- Review `git diff --check` and `git diff --staged` before committing.
- Keep credentials, `.env` files, dependencies, and build output out of commits.
- Describe checks you actually performed; identify any checks still pending.

## Make a focused update

From a clean checkout of this branch:

```bash
git switch steup-website
git pull --ff-only origin steup-website
# Make and review one useful change.
git diff --check
git add CONTRIBUTING.md
git diff --staged
git commit -m "docs: clarify website contribution workflow"
git push origin steup-website
```

Replace the example filename and message with the files and purpose of your
actual change. If the pull or push reports a conflict, resolve it before
continuing; avoid force-pushing over someone else's work.

Good small updates include fixing a visible UI issue, improving keyboard
navigation, documenting a reproducible bug, or adding a meaningful test.
Keep commits tied to real progress so the history remains useful.
