# install-factoryapps.bbclass

## Overview
`install-factoryapps.bbclass` installs a set of “factory applications” into the image root filesystem during the rootfs creation phase.

The apps to install are described by a JSON manifest file. Each manifest entry points to a fetchable URI (e.g., `https://…` or `file://…`). The class downloads each app using BitBake’s fetcher and then copies it into the configured install directory inside `${IMAGE_ROOTFS}`.

## Key Behavior
- Runs as a rootfs postprocess hook via `ROOTFS_POSTPROCESS_COMMAND`.
- Uses `bb.fetch2.Fetch(...)` so downloads are cached in `DL_DIR` (standard BitBake download cache).
- Copies each fetched artifact into `${IMAGE_ROOTFS}${FACTORY_APPS_PATH}` with mode `0644`.
- Prevents obvious directory traversal via `packagename` validation.
- If the manifest is missing or empty, it logs a warning and skips installation.

## Configuration
Set the following variables in your image, distro config, or `local.conf`:

- `FACTORY_APPS_JSON_FILE`
  - Path (on the build host) to the JSON manifest file.
  - If unset or the file does not exist, installation is skipped (warning only).

- `FACTORY_APPS_PATH`
  - Absolute install directory inside the target rootfs (e.g., `/opt/factoryapps`).
  - If `FACTORY_APPS_JSON_FILE` is set but `FACTORY_APPS_PATH` is not set, the build fails (`bb.fatal`).

## JSON Manifest Format
The manifest must be a JSON array (list) of objects.

Each entry supports:
- `packagename` (required)
  - Destination filename within `${FACTORY_APPS_PATH}`.
  - Must not contain `..` and must not start with `/` or `\`.

- `srcpath` (required)
  - Fetch URI for the app artifact.
  - Examples: `https://example.com/app.bolt`, `file:///path/to/app.bolt`.

- `sha256sum` (optional)
  - SHA-256 checksum (hex) for the artifact.
  - If provided, it is passed to the BitBake fetcher as `;sha256sum=<sha>`.
  - If omitted, the class logs a warning and proceeds without verification.

### Example
```json
[
  {
    "packagename": "app.bolt",
    "srcpath": "https://example.com/app.bolt",
    "sha256sum": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
]
```
