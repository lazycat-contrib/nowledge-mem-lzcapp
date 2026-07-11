# nowledge-mem-lzcapp

LazyCat package for NowledgeMem and Nowledge Mem Snap.

## Automated releases

`.github/workflows/lazycat.yml` checks both upstream images daily and can be
started manually. Pull requests run the same inspection in dry-run mode. A new
`mem` version updates the package version, copies both selected Linux amd64
images to the LazyCat Registry, creates tag `v<version>`, and uploads:

```text
community.lazycat.app.nowledge-mem-v<version>.lpk
```

The verified LPK is submitted to both the LazyCat official store and the
MiaoMiao private store. Equal online versions are skipped.

Required GitHub Actions Secrets:

- `LAZYCAT_TOKEN`
- `APPSTORE_URL`
- `APPSTORE_TOKEN`

`PRIVATE_STORE_GROUP_CODES` is optional for group-restricted private apps.
`APP_ID` is not required; private publication finds the application by exact
package ID and uses `NowledgeMem` when it must create the application.

Organization Secrets must authorize this repository. For duplicate names,
Environment overrides Repository, and Repository overrides Organization.

Generated `*.lpk`, `dist/`, and `.lazycat-action/` files are intentionally not
tracked. Download release packages from GitHub Releases.
