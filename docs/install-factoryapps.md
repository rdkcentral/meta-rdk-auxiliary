# install-factoryapps.bbclass

## Overview
`install-factoryapps.bbclass` installs a set of “factory applications” into the image root filesystem during the rootfs creation phase.

Apps are described by a JSON manifest. Each entry provides a fetch URI, which is downloaded via [BitBake’s fetcher](https://docs.yoctoproject.org/bitbake/bitbake-user-manual/bitbake-user-manual-fetching.html#fetchers) and copied into `${IMAGE_ROOTFS}${FACTORY_APPS_PATH}`.

## Key Behavior
- Runs as a rootfs postprocess hook (`ROOTFS_POSTPROCESS_COMMAND`).
- Fetches via `bb.fetch2` (cached in `DL_DIR`) and installs into `${IMAGE_ROOTFS}${FACTORY_APPS_PATH}/<packagename>` with mode `0644`.
- Validates `packagename` to prevent obvious directory traversal.
- The class warns and skips an entry when it is malformed (wrong entry type, missing/empty fields), except for `sha256sum` which is always required and strictly validated.
- The class fails the build (`bb.fatal`) for security- or correctness-critical errors such as invalid `packagename`, fetch failures, missing or invalid `sha256sum`, or fetched-file validation failures (because the requested artifact cannot be reliably installed).
- Configuration/manifest problems are fatal and fail the build. This includes `FACTORY_APPS_PATH` not set when installation is enabled, an unreadable/unparseable manifest, a manifest that is not a JSON list, or an invalid `FACTORY_APPS_PATH`.
- Duplicate `packagename` entries overwrite earlier installs (a warning is logged).

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
  - Must be a plain filename (no `/` or `\\` allowed anywhere) and must not contain `..`.

- `srcuri` (required)
  - Fetch URI for the app artifact (must resolve to a single file, not a directory).
  - Examples: `https://example.com/app.bolt`, `file:///path/to/app.bolt`.

- `sha256sum` (required)
  - SHA-256 checksum (64 hex chars, hex-encoded) for the artifact.
  - Must be a JSON string (quoted); non-string types are rejected.
  - The value must be exactly 64 hexadecimal characters (0-9, a-f, A-F). Input is case-insensitive and will be normalized to lowercase internally. Any missing, empty, or invalid value will cause the build to fail.
  - It is appended to the fetch URI as `;sha256sum=<sha256sum>` so BitBake can verify the download.

### Example
```json
[
  {
    "packagename": "app.bolt",
    "srcuri": "https://example.com/app.bolt",
    "sha256sum": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
]
```
