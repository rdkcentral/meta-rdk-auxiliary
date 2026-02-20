##########################################################################
# If not stated otherwise in this file or this component's LICENSE
# file the following copyright and licenses apply:
#
# Copyright 2026 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

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
    import stat
    import posixpath
    import shutil
    import bb.utils
    import bb.fetch2
    import re


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

    def ensure_logically_under_rootfs(dest_path):
        """Fatal if dest_path is not logically under IMAGE_ROOTFS.

        This check is safe to use before the destination exists. It does not
        resolve symlinks; symlink traversal is handled separately via lstat()
        checks on each path component and post-validation with ensure_under_rootfs().
        """
        rootfs_abs = os.path.abspath(rootfs)
        dest_abs = os.path.abspath(dest_path)
        try:
            if os.path.commonpath([rootfs_abs, dest_abs]) != rootfs_abs:
                bb.fatal(
                    f"Destination escapes IMAGE_ROOTFS: '{dest_path}' (rootfs='{rootfs_abs}')"
                )
        except ValueError:
            # Different drive letters on Windows can trigger ValueError.
            bb.fatal(
                f"Destination escapes IMAGE_ROOTFS: '{dest_path}' (rootfs='{rootfs_abs}')"
            )

    bb.note(f"Processing factory apps manifest: {json_file}")

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

    # Detect duplicate packagename entries to avoid silent overwrites.
    seen_packagenames = {}
    for idx, app in enumerate(factory_apps):
        if not isinstance(app, dict):
            continue

        pkg_name = app.get("packagename")
        if isinstance(pkg_name, str):
            pkg_name = pkg_name.strip()
        if not pkg_name:
            continue

        if pkg_name in seen_packagenames:
            first_idx = seen_packagenames[pkg_name]
            srcuri = app.get("srcuri", "")
            bb.warn(
                f"Duplicate packagename {pkg_name!r} in factory apps manifest: "
                f"first at index {first_idx}, again at index {idx}"
                f"{f', srcuri={srcuri!r}' if srcuri else ''}. "
                "This is allowed; later entries will overwrite earlier installs."
            )
        else:
            seen_packagenames[pkg_name] = idx

    def fetch_file(src_uri, sha_value, package_name):
        # Add mandatory sha256 checksum to the URI so BitBake can verify automatically
        # Parse and validate the required sha256sum
        sha_value_clean = sha_value.strip().lower()
        # Non-empty value must be a valid 64-character lowercase hex string
        if len(sha_value_clean) != 64 or any(c not in "0123456789abcdef" for c in sha_value_clean):
            bb.fatal(
                f"Invalid sha256sum for '{package_name}': must be 64 hex characters (got {sha_value!r})"
            )

        # BitBake fetcher expects checksums in SRC_URI or via params
        fetch_uri = f"{src_uri};sha256sum={sha_value_clean}"
        # Create fetcher instance and a FetchData object
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

        return local_path

    def copy_package(src_file, package_name, overwrite_expected):
        """Copy package to final destination."""
        rel_dir_posix = install_path_norm.lstrip("/")
        rel_parts = [p for p in rel_dir_posix.split("/") if p]

        # Build destination path: ${IMAGE_ROOTFS}${FACTORY_APPS_PATH}
        dest_dir = os.path.join(rootfs, *rel_parts) if rel_parts else rootfs
        dest_file = os.path.join(dest_dir, package_name)

        bb.note(f"Installing package '{package_name}' to: {dest_file}")

        # Ensure we never write outside the rootfs (works even before paths exist).
        ensure_logically_under_rootfs(dest_dir)
        ensure_logically_under_rootfs(dest_file)

        # Create destination directory path under IMAGE_ROOTFS, refusing to traverse symlinks.
        cur_dir = rootfs
        for part in rel_parts:
            next_dir = os.path.join(cur_dir, part)
            try:
                st = os.lstat(next_dir)
                if stat.S_ISLNK(st.st_mode):
                    bb.fatal(
                        f"Refusing to install into symlinked directory under IMAGE_ROOTFS: {next_dir!r}"
                    )
                if not stat.S_ISDIR(st.st_mode):
                    bb.fatal(
                        f"Refusing to install into non-directory under IMAGE_ROOTFS: {next_dir!r}"
                    )
            except FileNotFoundError:
                os.mkdir(next_dir, mode=0o755)
            cur_dir = next_dir

        # If a non-symlink file already exists, we will overwrite it.
        # Warn only when this isn't an expected overwrite (e.g. duplicate packagename).
        try:
            existing_st = os.lstat(dest_file)
            if stat.S_ISLNK(existing_st.st_mode):
                bb.fatal(
                    f"Refusing to overwrite symlink under IMAGE_ROOTFS: {dest_file!r}"
                )
            if not stat.S_ISREG(existing_st.st_mode):
                bb.fatal(
                    f"Refusing to overwrite non-regular file under IMAGE_ROOTFS: {dest_file!r}"
                )
            if not overwrite_expected:
                bb.warn(
                    f"Destination already exists and will be overwritten for '{package_name}': {dest_file}"
                )
        except FileNotFoundError:
            pass

        # Copy artifact into IMAGE_ROOTFS (intentionally overwrites when duplicates are present).
        shutil.copy2(src_file, dest_file)
        os.chmod(dest_file, 0o644)

        # Post-validate final destination (defense in depth).
        ensure_under_rootfs(dest_file)

        bb.note(f"Successfully installed '{package_name}' at {dest_file}")

    def process_app(app, idx, installed_packagenames_in_run):
        """Process a single factory app entry."""
        try:
            if not isinstance(app, dict):
                bb.warn(f"Factory app entry #{idx} is not an object/dict")
                return False

            # Extract fields
            package_name_raw = app.get("packagename")
            if package_name_raw is None:
                srcuri = app.get('srcuri', '')
                bb.warn(f"Factory app entry #{idx} missing required field 'packagename' (srcuri={srcuri!r})")
                return False
            if not isinstance(package_name_raw, str):
                srcuri = app.get('srcuri', '')
                bb.warn(
                    f"Factory app entry #{idx} invalid 'packagename' type: expected string, got {type(package_name_raw).__name__} (srcuri={srcuri!r})"
                )
                return False
            package_name = package_name_raw.strip()
            if not package_name:
                srcuri = app.get('srcuri', '')
                bb.warn(f"Factory app entry #{idx} empty/whitespace-only 'packagename' (srcuri={srcuri!r})")
                return False

            overwrite_expected = package_name in installed_packagenames_in_run

            # Validate package name early (security-critical) before any other operations.
            if ".." in package_name or "/" in package_name or "\\" in package_name:
                bb.fatal(
                    f"Invalid packagename '{package_name}': must be a plain filename (no '..', '/' or '\\') "
                    "to prevent directory traversal and ensure the artifact is installed directly under "
                    "FACTORY_APPS_PATH"
                )

            src_uri_raw = app.get("srcuri")
            if src_uri_raw is None:
                bb.warn(f"Factory app entry #{idx} ('{package_name}') missing required field 'srcuri'")
                return False
            if not isinstance(src_uri_raw, str):
                bb.warn(
                    f"Factory app entry #{idx} ('{package_name}') invalid 'srcuri' type: expected string, got {type(src_uri_raw).__name__}"
                )
                return False
            src_uri = src_uri_raw.strip()
            if not src_uri:
                bb.warn(
                    f"Factory app entry #{idx} ('{package_name}') empty/whitespace-only 'srcuri'"
                )
                return False

            # Validate sha256sum presence and type early for clearer errors
            if "sha256sum" not in app:
                bb.fatal(
                    f"Factory app entry #{idx} ('{package_name}') missing required field 'sha256sum'. "
                    f"srcuri={src_uri}"
                )
            sha_value = app["sha256sum"]
            if not isinstance(sha_value, str):
                bb.fatal(
                    f"Factory app entry #{idx} ('{package_name}') has invalid 'sha256sum' type: "
                    f"expected string (must be quoted in JSON), got {type(sha_value).__name__}. "
                    f"srcuri={src_uri}"
                )
            if not sha_value.strip():
                bb.fatal(
                    f"Factory app entry #{idx} ('{package_name}') has empty/whitespace-only 'sha256sum'. "
                    f"srcuri={src_uri}"
                )

            bb.note(f"Processing factory app [{idx}]: packagename='{package_name}', srcuri='{src_uri}'")

            # Use BitBake fetcher to handle all protocols (file://, http://, https://, ftp://, etc.)
            local_file = fetch_file(src_uri, sha_value, package_name)

            # Copy the fetched file
            copy_package(local_file, package_name, overwrite_expected=overwrite_expected)
            installed_packagenames_in_run.add(package_name)
            return True

        except Exception as e:
            # Preserve BitBake fatal errors (bb.fatal) as build-stoppers.
            # bb.fatal raises bb.BBHandledException; do not downgrade it to a warning.
            if hasattr(bb, "BBHandledException") and isinstance(e, bb.BBHandledException):
                raise

            # Raise fetch errors as fatal, not warnings
            if isinstance(e, bb.fetch2.FetchError):
                raise

            # Include index and, when available, packagename and srcuri for easier troubleshooting
            pkg_name = app.get("packagename") if isinstance(app, dict) else None
            src_uri = app.get("srcuri") if isinstance(app, dict) else None
            bb.warn(
                f"Failed to process package at index {idx}"
                f"{f', packagename={pkg_name!r}' if pkg_name else ''}"
                f"{f', srcuri={src_uri!r}' if src_uri else ''}: {e}"
            )
            return False

    # Process each factory app.
    # Note: any bb.fatal encountered during processing stops the build immediately;
    # the summary counts below only apply when processing completes without fatal.
    installed_count = 0
    skipped_count = 0
    installed_packagenames_in_run = set()
    for idx, app in enumerate(factory_apps):
        if process_app(app, idx, installed_packagenames_in_run):
            installed_count += 1
        else:
            skipped_count += 1

    if skipped_count:
        bb.warn(
            f"Factory apps installation completed with issues: installed={installed_count}, "
            f"skipped={skipped_count}, total={len(factory_apps)}"
        )
    else:
        bb.note(
            f"Factory apps installation complete: installed={installed_count}, total={len(factory_apps)}"
        )
}

python factory_apps_installer_postprocess() {
    """Rootfs postprocess hook to install factory apps."""
    bb.build.exec_func('factory_apps_installer_run', d)
}
