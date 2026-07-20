# brisc documentation

Sphinx source for the docs at [brisc.run](https://brisc.run).

## Build

From the repo root:

```bash
pip install -e .[docs]     # compile brisc + install the Sphinx stack
make -C docs html          # output in docs/build/html
```

Live-reload while editing: `make -C docs livehtml`.

The API stub pages under `source/{singlecell,pseudobulk,de}/` are
autosummary-generated at build time and gitignored; only the hand-written
index and category pages are tracked. Building therefore requires an importable
`brisc` (R is not needed — `ryp` is imported lazily).

## Deploy

`.github/workflows/docs.yml` builds and deploys to Cloudflare Pages on pushes to
`main` touching `docs/**` or `brisc/**`. To deploy by hand, set
`CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` and run `bash docs/deploy.sh`.
