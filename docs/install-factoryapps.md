# install-factoryapps.bbclass

## Overview
`install-factoryapps.bbclass` installs a set of "factory applications" into the image root filesystem during the `rootfs` creation phase.

Apps are described by a JSON manifest. For each entry, the class fetches a remote artifact via BitBake's fetcher, validates its checksum, and copies it to a specified location within the image's root filesystem (`IMAGE_ROOTFS`).

## Key Behavior
- Runs as a `rootfs` post-process hook (`ROOTFS_POSTPROCESS_COMMAND`).
- Fetches artifacts using `bb.fetch2`, which ensures downloads are cached in `DL_DIR`.
- Installs artifacts with file mode `0644`.
- **Security**: Implements robust checks to prevent directory traversal and other filesystem-based attacks.
  - Validates `packagename` to ensure it is a plain filename.
  - Validates all installation paths to ensure they are absolute and do not contain `..`.
  - Refuses to create directories or write files through symbolic links.
  - Verifies that all final installation paths are located safely within `${IMAGE_ROOTFS}`.
- The class **warns and skips** an entry for recoverable issues, such as a malformed entry type or missing/empty `packagename` or `srcuri`.
- The class **fails the build** (`bb.fatal`) for security-critical or unrecoverable errors. This includes:
  - Invalid `packagename` (e.g., containing `/`, `\`, or `..`).
  - An invalid, missing, or empty `sha256sum`.
  - Failure to fetch an artifact.
  - Checksum validation failure for a fetched artifact.
  - An invalid `install_path` or `FACTORY_APPS_PATH`.
  - An attempt to write outside of `${IMAGE_ROOTFS}` or overwrite a symlink.
- **Duplicate `packagename` entries**: The class detects and warns about duplicate `packagename` entries in the manifest. The build proceeds, and later entries in the list will overwrite artifacts installed by earlier entries with the same `packagename`.

## Configuration
Set the following variables in your image, distro config, or `local.conf`:

- `FACTORY_APPS_JSON_FILE`
  - **Required**: Path on the build host to the JSON manifest file.
  - If this variable is unset or the file does not exist, the installation process is skipped with a warning.

- `FACTORY_APPS_PATH`
  - **Optional**: The default absolute installation directory inside the target `rootfs` (e.g., `/opt/factoryapps`).
  - If this is not set, **every entry** in the JSON manifest must specify its own `install_path`. If an entry is missing `install_path` and `FACTORY_APPS_PATH` is also unset, the build will fail.

## JSON Manifest Format
The manifest must be a JSON array (list) of objects.

Each entry supports:
- `packagename` (required)
  - The destination filename for the artifact.
  - **Validation**: Must be a plain filename. It cannot contain `/`, `\`, or `..`.

- `srcuri` (required)
  - The fetch URI for the artifact (e.g., `https://...`, `file://...`). This must resolve to a single file.

- `sha256sum` (required)
  - The SHA-256 checksum of the artifact file.
  - **Validation**: This field is security-critical and strictly enforced.
    - It must be a JSON string (quoted).
    - The value must be exactly 64 hexadecimal characters (`0-9`, `a-f`, `A-F`).
    - The build will fail (`bb.fatal`) if the value is missing, empty, not a string, or not a valid 64-character hex string.

- `install_path` (string, optional)
  - An absolute path within the target `rootfs` where this specific artifact should be installed.
  - This value, if provided, overrides the global `FACTORY_APPS_PATH` for this entry.
  - **Validation**: Must be an absolute path (start with `/`) and must not contain `..` or `\`.

### Example Manifest
```json

[
  {
    "packagename": "app.bolt",
    "srcuri": "https://example.com/app.bolt",
    "sha256sum": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    "install_path": "/opt/apps/specific"
  },
 {
        "packagename": "app2.bolt",
        "srcuri": "file:///path/to/local/app2.bolt",
        "sha256sum": "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
 }
]

*In this example, `app1.bolt` will be installed to `/opt/apps/specific/app1.bolt`. `app2.bolt` will be installed to the directory specified by the global `FACTORY_APPS_PATH`.*
