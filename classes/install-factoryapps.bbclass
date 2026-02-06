inherit python3native

# Hook into rootfs creation
ROOTFS_POSTPROCESS_COMMAND += " factory_apps_installer_postprocess; "

python factory_apps_installer_run() {
    import json
    import os
    import shutil
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
        bb.fatal("factoryapp 'installpath' not set!")

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
            
            bb.note(f"Successfully fetched to: {local_path}")

            return local_path
            
        except bb.fetch2.FetchError as e:
            bb.fatal(f"Failed to fetch {src_uri}: {e}")
        except Exception as e:
            bb.fatal(f"Unexpected error fetching {src_uri}: {e}")

    def copy_package(src_file, package_name):
        """Copy package to final destination."""
        # Build destination path: ${IMAGE_ROOTFS}${installpath}
        dest_dir = os.path.join(rootfs, install_path.lstrip("/"))
        dest_file = os.path.join(dest_dir, package_name)
        
        bb.note(f"Installing package '{package_name}' to: {dest_file}")
        
        # Create destination directory
        os.makedirs(dest_dir, exist_ok=True)
        
        # Copy and rename the file
        import shutil
        shutil.copy2(src_file, dest_file)
        
        # Set appropriate permissions (readable by all, writable by owner)
        os.chmod(dest_file, 0o644)
        
        bb.note(f"Successfully installed '{package_name}' -> {dest_file}")

    def process_app(app, idx):
        """Process a single factory app entry."""
        if not isinstance(app, dict):
            bb.fatal(f"Factory app entry #{idx} is not an object/dict")

        # Extract fields
        package_name = app.get("packagename", "")
        src_path = app.get("srcpath", "")
        sha_value = app.get("sha", "")

        if not package_name:
            bb.fatal(f"Factory app entry #{idx} missing 'packagename': {app}")
        
        if not src_path:
            bb.fatal(f"Factory app entry #{idx} ('{package_name}') missing 'srcpath' or 'sourcepath': {app}")

        # Validate package name - prevent directory traversal
        if ".." in package_name or package_name.startswith("/") or package_name.startswith("\\"):
            bb.fatal(f"Invalid packagename '{package_name}': potential directory traversal detected")

        bb.note(f"Processing factory app [{idx}]: packagename='{package_name}', srcpath='{src_path}'")

        # Use BitBake fetcher to handle all protocols (file://, http://, https://, ftp://, etc.)
        local_file = fetch_file(src_path, sha_value, package_name)
        
        # Copy the fetched file
        copy_package(local_file, package_name)

    # Process each factory app
    for idx, app in enumerate(factory_apps):
        process_app(app, idx)
    

    bb.note(f"Factory apps installation complete: {len(factory_apps)} app(s) processed")
}

python factory_apps_installer_postprocess() {
    """Rootfs postprocess hook to install factory apps."""
    bb.build.exec_func('factory_apps_installer_run', d)
}
