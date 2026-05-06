# BizarreCRM Management Dashboard

Electron dashboard for local server operations, super-admin tenant management,
backup controls, logs, and update/restart workflows.

## Local Development

```bash
npm run dev --workspace=packages/management
npm run dev:electron --workspace=packages/management
```

`dev` starts the main-process TypeScript watcher and the Vite renderer server
on port 5174. `dev:electron` performs a one-shot main/preload build and opens
Electron against the current renderer/dev configuration.

## Build Targets

```bash
npm run build:main --workspace=packages/management
npm run build:preload --workspace=packages/management
npm run build:renderer --workspace=packages/management
npm run build --workspace=packages/management
```

The package has three TypeScript/runtime targets:

- `build:main` compiles Electron main-process code with `tsconfig.node.json`.
- `build:preload` compiles the secure preload bridge with `tsconfig.preload.json`
  and renames it to `index.cjs`, which Electron requires for preload loading.
- `build:renderer` builds the React dashboard with Vite.

The root `npm run build` runs this full package build, so CI catches main,
preload, and renderer failures.

## Windows Package Signing

```bash
npm run package --workspace=packages/management
```

Packaging is gated by `scripts/package-win-signed.js`. Release builds must set
one of these signing modes:

- `WIN_CERT_SUBJECT`: certificate subject name already installed in the Windows
  certificate store.
- `WIN_CERT_FILE` and `WIN_CERT_PASSWORD`: path/password for a PFX certificate.

The wrapper maps PFX credentials to electron-builder's `CSC_LINK` and
`CSC_KEY_PASSWORD` environment variables. Unsigned packaging intentionally
fails, while development Electron and the `/super-admin/` web dashboard remain
available.

## CI Expectations

Management should be covered by:

- `npm run build --workspace=packages/management`
- root `npm run build`
- any future management lint/test scripts once those TODOs land

Do not replace the full package build with `build:renderer:web`; that build is
only for serving the management UI from the server-hosted `/super-admin/` page.
