# The Agent Triforge website

The source of https://agent-triforge.dbenger.com. It is a static Astro site with React islands, Tailwind 4 and shadcn on Base UI. The skill, persona, docs and changelog pages, the install commands, the version and every count are built from the repo's own files on each deploy, so a new skill, persona, docs page or release note shows up on the next deploy without an edit here. The one exception is a new lead skill (`at-` prefix), which needs a line in `src/data/groups.mjs`. The build fails and names the skill until it has one.

## Build and check

Node 22.12 or later.

```bash
cd site
npm ci
npm run dev           # http://localhost:4321, with the dev-only media kit at /kit/
npx astro check
npm run build         # astro build, then the site gate (scripts/check-site.mjs)
cd .. && node --test 'site/test/**/*.test.mjs'
```

The data tests run without a build. The built-page tests skip themselves and say so until `site/dist` exists. CI runs all of this in the `site` job of `.github/workflows/gates.yml` on every pull request to `main`.

The repo validators (`scripts/validate-versions.sh` and the others under "Checks to run" in `AGENTS.md`) skip `site/dist`, `site/.astro` and `.vercel`, so they pass after a local build.

## Deploy

Vercel project `agent-triforge` (the team already has an unrelated project called `site`, so always name it). Project settings: Root Directory `site`, framework Astro, Node 24, files outside the root directory included (the build reads `../skills`, `../docs` and `../README.md`), preview protection off. `vercel.json` sets the install, build and ignore commands, the redirects and the cache headers.

Deploy only a pushed commit, from a clean worktree, never from a working checkout. A CLI upload from a checkout carries its ignored and untracked files (`ops/leases.toml`, `.agents/`, local notes) to Vercel and builds uncommitted edits into production.

```bash
SHA=$(git rev-parse origin/main)            # or the pull request's head for a preview
git worktree add ../triforge-deploy "$SHA"
cd ../triforge-deploy
test -z "$(git status --porcelain)" || { echo "dirty worktree, not deploying"; exit 1; }
vercel link --yes --project agent-triforge  # a new worktree has no .vercel/, so link it each time
vercel deploy --meta commit="$SHA"          # a preview; add --prod for production
cd - && git worktree remove ../triforge-deploy
```

The root `.gitignore` carries an exact `.vercel` line. Without it the CLI appends one on every link, which dirties each fresh worktree.

Once the repository is connected to Vercel, a push to `main` that changes a site input deploys production, and each pull request gets a preview. `scripts/ignore-build.sh` skips a build only when none of the files the build reads changed, and builds whenever it cannot tell.

## Media

The film, the four loops and the README hero are rendered from `motion/` (see `motion/RENDER.md`). Every install of the plugin copies this whole repository, and a Codex lead's install clones every branch with its history, so media are committed only in their final encoding: `public/media` stays under 8 MB and `docs/images/readme-hero.gif` under 500 KB.

## Installing the plugin from this checkout

Install the plugin only from a clean checkout. A local install from a checkout copies ignored files too, and `site/node_modules` alone is several hundred megabytes.
