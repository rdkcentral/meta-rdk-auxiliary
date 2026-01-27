# RDKE GPU Layer Configuration Class
#
# This class processes the RDKE GPU layer configuration JSON to:
# 1. Create the mount config file with GPU configuration
# 2. Create hardlinks of libraries in the mount rootfs path for container mounting
#
# Usage: Add 'INHERIT += "rdke-gpu-layer"' to your image recipe or configuration

# Path to the GPU layer configuration JSON file
RDKE_GPU_LAYER_CONFIG_JSON ?= "${VENDOR_LAYER_DIR}/conf/machine/include/rdke-gpu-layer-conf.json"

# Enable verbose logging (set to "1" for detailed output)
RDKE_GPU_LAYER_VERBOSE ?= "0"

python rdke_gpu_layer_setup() {
    import json
    import os
    from pathlib import Path

    config_file = d.getVar('RDKE_GPU_LAYER_CONFIG_JSON')
    rootfs = d.getVar('IMAGE_ROOTFS')
    verbose = d.getVar('RDKE_GPU_LAYER_VERBOSE') == "1"

    def validate_json_schema(config):
        """Validate the JSON configuration has required fields."""
        required_fields = ['mount-config-file', 'mount-config', 'mount-rootfs-path', 'mount-rootfs-links']
        missing_fields = [field for field in required_fields if field not in config]

        if missing_fields:
            bb.fatal(f"Invalid JSON schema. Missing required fields: {', '.join(missing_fields)}")

        # Validate mount-rootfs-links structure
        if not isinstance(config['mount-rootfs-links'], dict):
            bb.fatal("'mount-rootfs-links' must be a dictionary")

        for package, libs in config['mount-rootfs-links'].items():
            if not isinstance(libs, list):
                bb.fatal(f"Libraries for package '{package}' must be a list")

        return True

    def find_library_variants(lib_path, rootfs_path):
        """Find all variants of a library including versioned files and symlinks."""
        source_file = Path(rootfs_path + lib_path)
        lib_dir = source_file.parent
        lib_name = source_file.name

        # Extract base library name without version
        if '.so' in lib_name:
            base_name = lib_name.split('.so')[0] + '.so'
        else:
            base_name = lib_name

        variants = []

        if not lib_dir.exists():
            return variants

        # Find all matching files
        pattern = f"{base_name}*"
        for file_path in lib_dir.glob(pattern):
            if file_path.is_file() or file_path.is_symlink():
                relative_to_dir = str(file_path.relative_to(Path(rootfs_path)))
                full_path = '/' + relative_to_dir
                variants.append(full_path)

        return sorted(variants)

    # Check if config file exists
    if not os.path.exists(config_file):
        bb.fatal(f"RDKE GPU layer config JSON file not found: {config_file}")
        return

    try:
        # Read and validate configuration JSON
        with open(config_file, 'r') as f:
            config = json.load(f)

        if not validate_json_schema(config):
            return

        # Extract configuration elements
        mount_config_file = config['mount-config-file']
        mount_config = config['mount-config']
        mount_rootfs_path = config['mount-rootfs-path']
        mount_rootfs_links = config['mount-rootfs-links']

        # ===== Step 1: Create mount config file =====
        config_file_path = Path(rootfs + mount_config_file)
        config_file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(config_file_path, 'w') as f:
            json.dump(mount_config, f, indent=2)

        if verbose:
            bb.note(f"Created mount config file: {mount_config_file}")

        # ===== Step 2: Create hardlinks in mount rootfs path =====
        mount_rootfs_dir = Path(rootfs + mount_rootfs_path)
        mount_rootfs_dir.mkdir(parents=True, exist_ok=True)

        created_count = 0
        skipped_count = 0
        processed_files = set()
        missing_libraries = []

        # Process each package's libraries
        for package, libraries in mount_rootfs_links.items():
            if verbose:
                bb.note(f"Processing package: {package}")

            for lib_path in libraries:
                # Find all variants of this library
                variants = find_library_variants(lib_path, rootfs)

                if not variants:
                    missing_libraries.append(lib_path)
                    skipped_count += 1
                    continue

                if verbose:
                    bb.note(f"  Found {len(variants)} variant(s) for {lib_path}")

                # Create hardlinks for each variant
                for variant_path in variants:
                    if variant_path in processed_files:
                        continue

                    source_file = Path(rootfs + variant_path)
                    relative_path = variant_path.lstrip('/')
                    target_file = mount_rootfs_dir / relative_path

                    target_file.parent.mkdir(parents=True, exist_ok=True)

                    if not source_file.exists():
                        bb.warn(f"Source file not found: {variant_path}")
                        skipped_count += 1
                        continue

                    # Handle symlinks
                    if source_file.is_symlink():
                        if target_file.exists() or target_file.is_symlink():
                            target_file.unlink()

                        try:
                            link_target = os.readlink(source_file)
                            os.symlink(link_target, target_file)
                            if verbose:
                                bb.note(f"    Created symlink: {variant_path} -> {link_target}")
                            created_count += 1
                            processed_files.add(variant_path)
                        except Exception as e:
                            bb.error(f"Failed to create symlink for {variant_path}: {e}")
                            skipped_count += 1
                    else:
                        if target_file.exists():
                            target_file.unlink()

                        try:
                            os.link(source_file, target_file)
                            if verbose:
                                bb.note(f"    Created hardlink: {variant_path}")
                            created_count += 1
                            processed_files.add(variant_path)
                        except Exception as e:
                            bb.error(f"Failed to create hardlink for {variant_path}: {e}")
                            skipped_count += 1

        # Summary output
        bb.note(f"RDKE GPU Layer: Created {created_count} hardlinks/symlinks in {mount_rootfs_path}")

        if skipped_count > 0:
            bb.warn(f"RDKE GPU Layer: {skipped_count} files were not found or failed to process")

        # Log missing libraries to file for debugging
        if missing_libraries:
            log_file = Path(rootfs + "/tmp/rdke-gpu-layer-missing-libs.log")
            log_file.parent.mkdir(parents=True, exist_ok=True)
            with open(log_file, 'w') as f:
                f.write("Missing libraries during RDKE GPU layer setup:\n")
                for lib in missing_libraries:
                    f.write(f"  {lib}\n")
            bb.error(f"Missing libraries logged to {log_file}. Missing libraries: {', '.join(missing_libraries)}")

    except json.JSONDecodeError as e:
        bb.fatal(f"Invalid JSON in {config_file}: {e}")
    except Exception as e:
        import traceback
        bb.fatal(f"Failed to process RDKE GPU layer configuration: {e}\n{traceback.format_exc()}")
}

# Add the function to rootfs post-process commands
ROOTFS_POSTPROCESS_COMMAND += " rdke_gpu_layer_setup; "

# Ensure dependencies are tracked
do_rootfs[vardeps] += "RDKE_GPU_LAYER_CONFIG_JSON RDKE_GPU_LAYER_VERBOSE"
