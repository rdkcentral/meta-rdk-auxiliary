# install-factoryapps.bbclass

## Overview
`install-factoryapps.bbclass` installs a set of “factory applications” into the image root filesystem during the rootfs creation phase.

Apps are described by a JSON manifest. Each entry provides a fetch URI, which is downloaded via [BitBake’s fetcher](https://docs.yoctoproject.org/bitbake/bitbake-user-manual/bitbake-user-manual-fetching.html#fetchers) and copied into `${IMAGE_ROOTFS}${FACTORY_APPS_PATH}`.

## Key Behavior
- Runs as a rootfs postprocess hook (`ROOTFS_POSTPROCESS_COMMAND`).
- Fetches via `bb.fetch2` (cached in `DL_DIR`) and installs into `${IMAGE_ROOTFS}${FACTORY_APPS_PATH}/<packagename>` with mode `0644`.
- Validates `packagename` to prevent obvious directory traversal.
- Skips invalid entries (wrong type, missing or empty fields) with a warning.
- Duplicate `packagename` entries overwrite earlier installs and missing `sha256sum` warns and proceeds without verification.

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

- `sha256sum` (required)
  - SHA-256 checksum (hex) for the artifact.
  - It is appended to the fetch URI as `;sha256sum=<sha256sum>` so BitBake can verify the download.
  - If omitted, the current class implementation logs a warning and proceeds without verification.

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
