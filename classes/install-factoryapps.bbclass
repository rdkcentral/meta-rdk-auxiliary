# Factory Apps Installer BBClass
#
# Installs factory applications into rootfs during image creation.
#
# Configuration:
#   FACTORY_APPS_JSON_FILE - Path to JSON manifest
#   FACTORY_APPS_PATH      - Installation directory
#
# Detailed documentation:
# See: docs/install-factoryapps.md

inherit python3native

# Hook into rootfs creation
ROOTFS_POSTPROCESS_COMMAND += " factory_apps_installer_postprocess; "

python factory_apps_installer_run() {
    import json
    import os
    import posixpath
    import shutil
    import bb.utils
    import bb.fetch2

    json_file = d.getVar("FACTORY_APPS_JSON_FILE")
    rootfs = d.getVar("IMAGE_ROOTFS")
    install_path = d.getVar("FACTORY_APPS_PATH")

    if not json_file:
        bb.warn("FACTORY_APPS_JSON_FILE not set; skipping factory apps install")
        return

    if not os.path.exists(json_file):
        bb.warn(f"Factory apps JSON manifest not found: {json_file} (skipping)")
        return

    if not install_path:
        bb.fatal("FACTORY_APPS_PATH not set; please set FACTORY_APPS_PATH to the factory apps install directory")

    def normalize_and_validate_install_path(path_value):
        """Validate FACTORY_APPS_PATH and return a normalized POSIX path.

        The path is expected to be an absolute POSIX path within the target rootfs.
        """
        if not isinstance(path_value, str) or not path_value.strip():
            bb.fatal("FACTORY_APPS_PATH is empty")

        raw = path_value.strip()

        # Treat FACTORY_APPS_PATH as a target (POSIX) path; reject Windows separators.
        if "\\" in raw:
            bb.fatal(f"Invalid FACTORY_APPS_PATH '{raw}': backslashes are not allowed")

        if not raw.startswith("/"):
            bb.fatal(f"Invalid FACTORY_APPS_PATH '{raw}': must be an absolute path (start with '/')")

        # Reject any '..' path elements to avoid escapes when combined with IMAGE_ROOTFS.
        parts = [p for p in raw.split("/") if p]
        if any(p == ".." for p in parts):
            bb.fatal(f"Invalid FACTORY_APPS_PATH '{raw}': '..' is not allowed")

        normalized = posixpath.normpath(raw)
        # normpath can remove trailing slashes; ensure it remains absolute
        if not normalized.startswith("/"):
            bb.fatal(f"Invalid FACTORY_APPS_PATH '{raw}': normalization produced a non-absolute path")

        return normalized

    install_path_norm = normalize_and_validate_install_path(install_path)

    def ensure_under_rootfs(dest_path):
        """Fatal if dest_path resolves outside IMAGE_ROOTFS."""
        rootfs_real = os.path.realpath(rootfs)
        dest_real = os.path.realpath(dest_path)
        if dest_real != rootfs_real and not dest_real.startswith(rootfs_real + os.sep):
            bb.fatal(f"Destination escapes IMAGE_ROOTFS: '{dest_path}' -> '{dest_real}' (rootfs='{rootfs_real}')")

    bb.note(f"Reading factory apps manifest: {json_file}")

    try:
        with open(json_file, "r", encoding="utf-8") as f:
            factory_apps = json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        bb.fatal(f"Failed to read or parse JSON manifest {json_file}: {e}")

    if not isinstance(factory_apps, list):
        bb.fatal(f"Expected JSON to be a list of apps, got: {type(factory_apps).__name__}")

    if not factory_apps:
        bb.warn("No factory apps found in JSON manifest")
        return

    def fetch_file(src_uri, sha_value, package_name):
        try:
            # Create a fetch data object
            # SRC_URI format: "protocol://path;param=value"
            fetch_uri = src_uri

            # Add checksum to URI if provided (BitBake can verify automatically)
            if sha_value:
                sha_value_clean = sha_value.strip().lower()
                # BitBake fetcher expects checksums in SRC_URI or via params
                fetch_uri = f"{src_uri};sha256sum={sha_value_clean}"
            else:
                bb.warn(f"No sha256sum provided for '{package_name}' - skipping verification")

            bb.note(f"Fetching: {fetch_uri}")

            # Create fetcher instance
            # We need to create a FetchData object
            fetcher = bb.fetch2.Fetch([fetch_uri], d)

            # Download the file (uses DL_DIR for caching)
            fetcher.download()

            # Get the local file path
            local_path = fetcher.localpath(fetch_uri)

            # Verify the file exists
            if not os.path.exists(local_path):
                bb.fatal(f"Fetched file not found: {local_path}")

            # Ensure the fetched path is a regular file, not a directory or other type
            if not os.path.isfile(local_path):
                bb.fatal(f"Fetched path is not a regular file: {local_path}")

            bb.note(f"Successfully fetched to: {local_path}")

            return local_path

        except bb.fetch2.FetchError as e:
            bb.fatal(f"Failed to fetch {src_uri}: {e}")
        except Exception as e:
            bb.fatal(f"Unexpected error fetching {src_uri}: {e}")

    def copy_package(src_file, package_name):
        """Copy package to final destination."""
        # Build destination path: ${IMAGE_ROOTFS}${FACTORY_APPS_PATH}
        dest_dir = os.path.join(rootfs, install_path_norm.lstrip("/"))
        dest_file = os.path.join(dest_dir, package_name)

        # Ensure we never write outside the rootfs (including via symlinks).
        ensure_under_rootfs(dest_dir)
        ensure_under_rootfs(dest_file)

        bb.note(f"Installing package '{package_name}' to: {dest_file}")

        # Create destination directory
        bb.utils.mkdirhier(dest_dir)

        # Copy and rename the file
        shutil.copy2(src_file, dest_file)

        # Set appropriate permissions (readable by all, writable by owner)
        os.chmod(dest_file, 0o644)

        bb.note(f"Successfully installed '{package_name}' -> {dest_file}")

    def process_app(app, idx):
        """Process a single factory app entry."""
        try:
            if not isinstance(app, dict):
                bb.warn(f"Factory app entry #{idx} is not an object/dict")
                return False

            # Extract fields
            package_name = app.get("packagename", "")
            src_path = app.get("srcpath", "")
            sha_value = app.get("sha256sum", "")

            if not package_name:
                bb.warn(f"Factory app entry #{idx} missing 'packagename': {app}")
                return False
            if not src_path:
                bb.warn(f"Factory app entry #{idx} ('{package_name}') missing source path field: {app}")
                return False

            # Validate package name - prevent directory traversal
            if ".." in package_name or package_name.startswith("/") or package_name.startswith("\\"):
                bb.fatal(f"Invalid packagename '{package_name}': potential directory traversal detected")

            # Enforce plain filename to avoid nested paths and traversal complexity
            if "/" in package_name or "\\" in package_name:
                bb.fatal(f"Invalid packagename '{package_name}': must be a plain filename (no '/' or '\\')")

            bb.note(f"Processing factory app [{idx}]: packagename='{package_name}', srcpath='{src_path}'")

            # Use BitBake fetcher to handle all protocols (file://, http://, https://, ftp://, etc.)
            local_file = fetch_file(src_path, sha_value, package_name)

            # Copy the fetched file
            copy_package(local_file, package_name)
            return True

        except Exception as e:
            # Include index and, when available, packagename and srcpath for easier troubleshooting
            pkg_name = app.get("packagename") if isinstance(app, dict) else None
            src_path = app.get("srcpath") if isinstance(app, dict) else None
            bb.warn(
                f"Failed to process package at index {idx}"
                f"{f\", packagename='{pkg_name}'\" if pkg_name else ''}"
                f"{f\", srcpath='{src_path}'\" if src_path else ''}: {e}"
            )
            return False

    # Process each factory app
    for idx, app in enumerate(factory_apps):
        process_app(app, idx)

    bb.note(f"Factory apps installation complete: {len(factory_apps)} app(s) processed")
}

python factory_apps_installer_postprocess() {
    """Rootfs postprocess hook to install factory apps."""
    bb.build.exec_func('factory_apps_installer_run', d)
}
