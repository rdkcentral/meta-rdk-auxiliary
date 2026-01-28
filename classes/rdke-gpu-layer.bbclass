# RDKE GPU Layer Configuration Class
#
# This class processes the RDKE GPU layer configuration JSON to:
# 1. Create the mount config file with GPU configuration
# 2. Create hardlinks of libraries in the mount rootfs path for container mounting
#
# Usage: Add 'INHERIT += "rdke-gpu-layer"' to your image recipe or configuration

# Path to the GPU layer configuration JSON file
RDKE_GPU_LAYER_CONFIG_JSON ?= ""

# Enable verbose logging (set to "1" for detailed output)
RDKE_GPU_LAYER_VERBOSE ?= "0"

# Log prefix for all messages from this class
RDKE_GPU_LAYER_LOG_PREFIX = "[rdke-gpu-layer]"

# Required mandatory library keys that must be present in the 'madatory' section
RDKE_GPU_LAYER_REQUIRED_LIBS = "libEGL.so libEGL.so.1 libGLESv1_CM.so libGLESv1_CM.so.1 libGLESv2.so libGLESv2.so.2 libwayland-egl.so.1"

python rdke_gpu_layer_setup() {
    import json
    import os
    from pathlib import Path

    config_file = d.getVar('RDKE_GPU_LAYER_CONFIG_JSON')
    rootfs = d.getVar('IMAGE_ROOTFS')
    verbose = d.getVar('RDKE_GPU_LAYER_VERBOSE') == "1"
    log_prefix = d.getVar('RDKE_GPU_LAYER_LOG_PREFIX') or "[rdke-gpu-layer]"
    required_libs = (d.getVar('RDKE_GPU_LAYER_REQUIRED_LIBS') or "").split()

    def validate_json_schema(config):
        """Validate the JSON configuration has required fields."""
        required_fields = ['mount-config-file', 'mount-config', 'mount-rootfs-path', 'mount-rootfs-links']
        missing_fields = [field for field in required_fields if field not in config]

        if missing_fields:
            bb.fatal(f"{log_prefix} Invalid JSON schema. Missing required fields: {', '.join(missing_fields)}")

        # Validate mount-config structure
        if 'mount-config' not in config or not isinstance(config['mount-config'], dict):
            bb.fatal(f"{log_prefix} 'mount-config' must be a dictionary")

        # Validate vendorGpuSupport
        mount_config = config['mount-config']
        if 'vendorGpuSupport' not in mount_config:
            bb.fatal(f"{log_prefix} 'vendorGpuSupport' is mandatory in 'mount-config'")

        vendor_gpu = mount_config['vendorGpuSupport']
        if not isinstance(vendor_gpu, dict):
            bb.fatal(f"{log_prefix} 'vendorGpuSupport' must be a dictionary")

        # Validate devNodes
        if 'devNodes' not in vendor_gpu:
            bb.fatal(f"{log_prefix} 'devNodes' is mandatory in 'vendorGpuSupport'")
        if not isinstance(vendor_gpu['devNodes'], list):
            bb.fatal(f"{log_prefix} 'devNodes' must be a list")

        # Validate groupIds
        if 'groupIds' not in vendor_gpu:
            bb.fatal(f"{log_prefix} 'groupIds' is mandatory in 'vendorGpuSupport'")
        if not isinstance(vendor_gpu['groupIds'], list):
            bb.fatal(f"{log_prefix} 'groupIds' must be a list")

        # Validate mount-rootfs-links structure
        if not isinstance(config['mount-rootfs-links'], dict):
            bb.fatal(f"{log_prefix} 'mount-rootfs-links' must be a dictionary")

        rootfs_links = config['mount-rootfs-links']

        # Validate mandatory key
        if 'madatory' not in rootfs_links:
            bb.fatal(f"{log_prefix} 'madatory' is mandatory in 'mount-rootfs-links'")
        if not isinstance(rootfs_links['madatory'], dict):
            bb.fatal(f"{log_prefix} 'madatory' must be a dictionary")

        # Validate required library keys are present in madatory
        madatory_libs = rootfs_links['madatory']
        missing_required_libs = [lib for lib in required_libs if lib not in madatory_libs]
        if missing_required_libs:
            bb.fatal(f"{log_prefix} Missing required library keys in 'madatory': {', '.join(missing_required_libs)}")

        # Validate optional key (if present)
        if 'optional' in rootfs_links and not isinstance(rootfs_links['optional'], list):
            bb.fatal(f"{log_prefix} 'optional' must be a list")

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

    def create_library_link(source_file, target_file, filename, log_prefix, verbose):
        """Create hardlink or symlink for a library file.

        Returns: (success, is_error) tuple
        - success: True if link was created successfully
        - is_error: True if failure should be treated as error (vs warning)
        """
        # Handle symlinks
        if source_file.is_symlink():
            if target_file.exists() or target_file.is_symlink():
                target_file.unlink()

            try:
                link_target = os.readlink(source_file)
                os.symlink(link_target, target_file)
                if verbose:
                    bb.note(f"{log_prefix}     Created symlink: {filename} -> {link_target}")
                return (True, False)
            except Exception as e:
                bb.error(f"{log_prefix} Failed to create symlink for {filename}: {e}")
                return (False, True)
        else:
            if target_file.exists():
                target_file.unlink()

            try:
                os.link(source_file, target_file)
                if verbose:
                    bb.note(f"{log_prefix}     Created hardlink: {filename}")
                return (True, False)
            except Exception as e:
                bb.error(f"{log_prefix} Failed to create hardlink for {filename}: {e}")
                return (False, True)

    # Check if config file is specified
    if not config_file or config_file == "":
        bb.fatal(f"{log_prefix} RDKE_GPU_LAYER_CONFIG_JSON is not set. Please set it to a valid JSON configuration file path.")

    # Check if config file exists
    if not os.path.exists(config_file):
        bb.fatal(f"{log_prefix} RDKE GPU layer config JSON file not found: {config_file}")

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
            bb.note(f"{log_prefix} Created mount config file: {mount_config_file}")

        # ===== Step 2: Create hardlinks in mount rootfs path =====
        mount_rootfs_dir = Path(rootfs + mount_rootfs_path)
        mount_rootfs_dir.mkdir(parents=True, exist_ok=True)

        created_count = 0
        skipped_count = 0
        processed_files = set()
        missing_mandatory_libraries = set()
        missing_optional_libraries = set()

        # Process mandatory libraries (dict with link_name: target_path mapping)
        if 'madatory' in mount_rootfs_links:
            if verbose:
                bb.note(f"{log_prefix} Processing mandatory libraries")

            madatory_libs = mount_rootfs_links['madatory']
            for link_name, target_path in madatory_libs.items():
                # If target_path is empty, find library variants automatically
                if not target_path or target_path == "":
                    lib_path = f"/usr/lib/{link_name}"
                    variants = find_library_variants(lib_path, rootfs)

                    if not variants:
                        missing_mandatory_libraries.add(lib_path)
                        skipped_count += 1
                        continue

                    if verbose:
                        bb.note(f"{log_prefix}   Found {len(variants)} variant(s) for {lib_path}")

                    # Determine the primary target file (first variant found)
                    primary_variant = variants[0]
                    primary_basename = os.path.basename(primary_variant)

                    # Process all variants
                    for variant_path in variants:
                        # Use only basename to avoid nested directory structure
                        variant_basename = os.path.basename(variant_path)

                        if variant_basename in processed_files:
                            continue

                        source_file = Path(rootfs + variant_path)
                        target_file = mount_rootfs_dir / variant_basename

                        if not source_file.exists():
                            bb.warn(f"{log_prefix} Source file not found: {variant_path}")
                            skipped_count += 1
                            continue

                        success, is_error = create_library_link(source_file, target_file, variant_basename, log_prefix, verbose)
                        if success:
                            created_count += 1
                            processed_files.add(variant_basename)
                        else:
                            skipped_count += 1

                    # Create symlink from link_name to primary target if they differ
                    if link_name != primary_basename and primary_basename in processed_files:
                        link_file = mount_rootfs_dir / link_name

                        if link_file.exists() or link_file.is_symlink():
                            link_file.unlink()

                        try:
                            os.symlink(primary_basename, link_file)
                            if verbose:
                                bb.note(f"{log_prefix}     Created symlink: {link_name} -> {primary_basename}")
                            created_count += 1
                        except Exception as e:
                            bb.error(f"{log_prefix} Failed to create symlink for {link_name}: {e}")
                            skipped_count += 1
                else:
                    # Use specified target_path
                    source_file = Path(rootfs + target_path)
                    if not source_file.exists():
                        missing_mandatory_libraries.add(target_path)
                        skipped_count += 1
                        continue

                    # Extract just the filename from target_path for hardlink
                    target_filename = os.path.basename(target_path)

                    # Create hardlink for the actual target file if not already processed
                    target_file = mount_rootfs_dir / target_filename
                    if target_filename not in processed_files:
                        success, is_error = create_library_link(source_file, target_file, target_filename, log_prefix, verbose)
                        if success:
                            created_count += 1
                            processed_files.add(target_filename)
                        else:
                            skipped_count += 1
                            continue

                    # Create symlink with the specified link_name pointing to target_filename
                    if link_name != target_filename:
                        link_file = mount_rootfs_dir / link_name

                        if link_file.exists() or link_file.is_symlink():
                            link_file.unlink()

                        try:
                            os.symlink(target_filename, link_file)
                            if verbose:
                                bb.note(f"{log_prefix}     Created symlink: {link_name} -> {target_filename}")
                            created_count += 1
                        except Exception as e:
                            bb.error(f"{log_prefix} Failed to create symlink for {link_name}: {e}")
                            skipped_count += 1

        # Process optional libraries (list of paths)
        if 'optional' in mount_rootfs_links:
            if verbose:
                bb.note(f"{log_prefix} Processing optional libraries")

            optional_libs = mount_rootfs_links['optional']
            for lib_path in optional_libs:
                source_file = Path(rootfs + lib_path)

                if not source_file.exists():
                    if verbose:
                        bb.note(f"{log_prefix}   Optional library not found (skipping): {lib_path}")
                    missing_optional_libraries.add(lib_path)
                    skipped_count += 1
                    continue

                # Extract just the filename for hardlink
                lib_filename = os.path.basename(lib_path)

                if lib_filename in processed_files:
                    continue

                target_file = mount_rootfs_dir / lib_filename

                success, is_error = create_library_link(source_file, target_file, lib_filename, log_prefix, verbose)
                if success:
                    created_count += 1
                    processed_files.add(lib_filename)
                else:
                    skipped_count += 1

        # Summary output
        bb.note(f"{log_prefix} Created {created_count} hardlinks/symlinks in {mount_rootfs_path}")

        if skipped_count > 0:
            bb.warn(f"{log_prefix} {skipped_count} files were not found or failed to process")

        # Report missing mandatory libraries as error (will fail build)
        if missing_mandatory_libraries:
            bb.fatal(f"{log_prefix} Missing mandatory libraries: {', '.join(sorted(missing_mandatory_libraries))}")

        # Report missing optional libraries as error (logged only, build continues)
        if missing_optional_libraries:
            bb.error(f"{log_prefix} Missing optional libraries: {', '.join(sorted(missing_optional_libraries))}")

    except json.JSONDecodeError as e:
        bb.fatal(f"{log_prefix} Invalid JSON in {config_file}: {e}")
    except Exception as e:
        import traceback
        bb.fatal(f"{log_prefix} Failed to process RDKE GPU layer configuration: {e}\n{traceback.format_exc()}")
}

# Add the function to rootfs post-process commands
ROOTFS_POSTPROCESS_COMMAND += " rdke_gpu_layer_setup; "

# Ensure dependencies are tracked
do_rootfs[vardeps] += "RDKE_GPU_LAYER_CONFIG_JSON RDKE_GPU_LAYER_VERBOSE"
