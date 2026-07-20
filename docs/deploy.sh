#!/usr/bin/env bash
# Manually build and deploy the docs to Cloudflare Pages (brisc-docs -> brisc.run).
# Prerequisites: an env with the docs deps + an importable brisc
# (`pip install -e .[docs]` from the repo root), and Cloudflare auth
# (CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID, or `npx wrangler login`).
# CI (.github/workflows/docs.yml) does this automatically on pushes to main.
set -eo pipefail
cd "$(dirname "$0")"

make clean html
# Ship robots.txt and the pages.dev -> brisc.run redirect worker at the site root.
cp deploy/robots.txt deploy/_worker.js build/html/

npx --yes wrangler@latest pages deploy build/html \
  --project-name brisc-docs --branch main --commit-dirty=true
