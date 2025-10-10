# -----------------------------------------------------------------------
# File: classes/generate-rdke-component-info.bbclass
# Author: RDK Management
#
# Description : Iterates through the buildhistory and creates component
#  documentation files based on layer architecture configuration.
#  Generates JSON metadata and Markdown reports with hyperlinked package
#  versions for oss, vendor, middleware, application layer; whichever is
#  specified or in the order of priority.
# -----------------------------------------------------------------------

# Cache version for component data - increment when data structure changes
# Use conditional assignment to avoid affecting task hashes when unchanged
RDKE_COMPONENT_CACHE_VERSION ??= "1.0"

def rdke_log(message, level="INFO", d=None):
    """Centralized logging function that writes to both BitBake log and dedicated debug file."""
    import os
    import datetime

    # Get TMPDIR for log file location
    if d:
        tmpdir = d.getVar('TMPDIR') or '/tmp'
    else:
        tmpdir = '/tmp'

    log_file = os.path.join(tmpdir, 'rdke-component-info-debug.log')
    timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]

    # Format log message
    log_entry = f"[{timestamp}] [{level}] {message}\n"

    # Write to dedicated log file
    try:
        with open(log_file, 'a') as f:
            f.write(log_entry)
    except Exception:
        pass  # Don't let logging failures break the build

    # Also log to BitBake with appropriate level
    import bb
    if level == "ERROR":
        bb.error(f"RDKE: {message}")
    elif level == "WARN":
        bb.warn(f"RDKE: {message}")
    elif level == "NOTE":
        bb.note(f"RDKE: {message}")
    else:  # INFO, DEBUG
        bb.debug(1, f"RDKE: {message}")

def rdke_log_init(d):
    """Initialize logging by creating/clearing the log file - only once per build."""
    import os
    import datetime

    tmpdir = d.getVar('TMPDIR') or '/tmp'
    log_file = os.path.join(tmpdir, 'rdke-component-info-debug.log')

    # Check if log file was already initialized this build
    init_marker = os.path.join(tmpdir, '.rdke-log-initialized')
    if os.path.exists(init_marker):
        return  # Already initialized, don't recreate

    try:
        # Create/clear log file only once
        with open(log_file, 'w') as f:
            f.write(f"=== RDKE Component Info Debug Log - Started: {datetime.datetime.now()} ===\n")
            f.write(f"TMPDIR: {tmpdir}\n")
            f.write(f"Log file: {log_file}\n")
            f.write("=" * 80 + "\n\n")

        # Create marker file to prevent re-initialization
        with open(init_marker, 'w') as f:
            f.write("initialized")

    except Exception as e:
        import bb
        bb.warn(f"Failed to initialize RDKE debug log file {log_file}: {e}")

def get_target_layer_arch(d):
    """Get target layer architecture from priority variables (optimized single call)."""
    priority_vars = [
        'OSS_LAYER_EXTENSION',
        'OSS_LAYER_ARCH',
        'VENDOR_LAYER_EXTENSION',
        'MIDDLEWARE_ARCH',
        'APP_LAYER_ARCH',
        'RDKE_GEN_DOC_LAYER_ARCH',  # Highest priority override
    ]

    target_layer_arch = None
    for var_name in priority_vars:
        var_value = d.getVar(var_name)
        if var_value:
            target_layer_arch = var_value
            # Continue to get highest priority (last found)

    return target_layer_arch

# Create SimpleCache instance for component caching and conditionally add task - optimized to run only once per build
python __anonymous() {
    # Import bb module for BitBake functionality
    import bb.data
    import bb.cache
    import bb.build
    import os

    # Early exit checks to minimize processing for most recipes
    pn = d.getVar('PN')
    if not pn:
        return

    # Skip native and nativesdk recipes immediately
    if bb.data.inherits_class('native', d) or bb.data.inherits_class('nativesdk', d):
        return

    # Check if we need component collection at all
    target_layer_arch = get_target_layer_arch(d)
    if not target_layer_arch:
        return

    # Early package architecture check
    package_arch = d.getVar('PACKAGE_ARCH') or ""
    if target_layer_arch not in package_arch:
        return  # Skip recipes that don't match target architecture

    # Check if RDKE setup was already completed this build
    tmpdir = d.getVar('TMPDIR') or '/tmp'
    rdke_setup_marker = os.path.join(tmpdir, '.rdke-setup-completed')

    # Only do the full setup once per build
    if not os.path.exists(rdke_setup_marker):
        # Initialize logging only once per build
        rdke_log_init(d)
        rdke_log(f"RDKE setup starting - first qualifying recipe: {pn}", "INFO", d)

        # Initialize SimpleCache using BitBake's standard infrastructure
        component_cache = bb.cache.SimpleCache(d.getVar("RDKE_COMPONENT_CACHE_VERSION") or "1.0")

        # Initialize cache with default data structure for component collection
        default_data = {
            'components': {},  # Architecture namespace -> component data
            'architectures': set(),
            'last_updated': None
        }

        # Use deterministic cache file name to avoid taskhash issues
        cache_data = component_cache.init_cache(d, "rdke_component_data.dat", default_data)

        rdke_log(f"RDKE cache initialized for target architecture: '{target_layer_arch}'", "INFO", d)

        # Store cache references and target_layer_arch in datastore for task access
        # Note: These variables are excluded from vardeps to maintain deterministic taskhash
        d.setVar("_RDKE_COMPONENT_CACHE", component_cache)
        d.setVar("_RDKE_CACHE_DATA", cache_data)
        d.setVar("_RDKE_TARGET_LAYER_ARCH", target_layer_arch or "")

        # Create marker file to prevent re-setup
        try:
            with open(rdke_setup_marker, 'w') as f:
                f.write(f"RDKE setup completed by {pn} for target_layer_arch: {target_layer_arch}")
            rdke_log(f"RDKE setup completed - marker created", "INFO", d)
        except Exception as e:
            rdke_log(f"Failed to create RDKE setup marker: {e}", "WARN", d)

    rdke_log(f"RDKE configured for qualifying recipe: {pn}", "DEBUG", d)
}

# Add recipe-level data collection task
python do_collect_component_data() {
    import os
    import bb
    import copy

    pn = d.getVar('PN')

    # Skip native and nativesdk recipes
    if bb.data.inherits_class('native', d) or bb.data.inherits_class('nativesdk', d):
        return

    # Check if we need component collection at all
    target_layer_arch = get_target_layer_arch(d)
    if not target_layer_arch:
        return

    # Early package architecture check
    package_arch = d.getVar('PACKAGE_ARCH') or ""
    if target_layer_arch not in package_arch:
        return  # Skip recipes that don't match target architecture

    rdke_log(f"Component data collection task executing for recipe: {pn}", "INFO", d)

    # Initialize our own cache objects (not relying on anonymous function setup)
    component_cache = bb.cache.SimpleCache(d.getVar("RDKE_COMPONENT_CACHE_VERSION") or "1.0")

    # Initialize with proper default structure
    default_cache_structure = {
        'components': {},  # Architecture namespace -> component data
        'architectures': set(),
        'last_updated': None
    }

    cache_data = component_cache.init_cache(d, "rdke_component_data.dat", default_cache_structure)

    # Debug: Check cache file location
    tmpdir = d.getVar('TMPDIR') or '/tmp'
    expected_cache_path = os.path.join(tmpdir, "cache", "rdke_component_data.dat")
    rdke_log(f"Expected cache file location: {expected_cache_path}", "DEBUG", d)
    rdke_log(f"Cache file exists before operations: {os.path.exists(expected_cache_path)}", "DEBUG", d)
    rdke_log(f"PACKAGE_ARCH for recipe {pn} is: {package_arch}", "DEBUG", d)
    rdke_log(f"Using target_layer_arch='{target_layer_arch}' for recipe {pn}", "DEBUG", d)

    # Extract recipe data (same pattern as do_print_src)
    pkg_pn = d.getVar("PN")
    pkg_pv = d.getVar("PV")
    pkg_pr = d.getVar("PR")
    pkg_pe = d.getVar("PE") or "0"
    srcuri = d.getVar('SRC_URI') or ""

    # Extract SRCREV information (using buildhistory approach)
    srcrev_data = {}

    try:
        import bb.fetch2
        fetcher = bb.fetch2.Fetch(d.getVar('SRC_URI').split(), d)
        urldata = fetcher.ud

        scms = []
        for u in urldata:
            if urldata[u].method.supports_srcrev():
                scms.append(u)

        for scm in scms:
            ud = urldata[scm]
            for name in ud.names:
                autoinc, rev = ud.method.sortable_revision(ud, d, name)
                if name == "default":
                    srcrev_data['SRCREV'] = rev
                else:
                    srcrev_data[f'SRCREV_{name}'] = rev

    except Exception as ex:
        rdke_log(f"Failed to extract SRCREV via fetcher for {pkg_pn}, using fallback: {ex}", "WARN", d)
        srcrev = d.getVar('SRCREV')
        if srcrev and srcrev != 'INVALID':
            srcrev_data['SRCREV'] = srcrev

    rdke_log(f"Extracted recipe data for {pkg_pn}: PV={pkg_pv}, PR={pkg_pr}, SRCREV_count={len(srcrev_data)}", "DEBUG", d)

    # Recipe data structure for MD file generation (keeping original fields)
    recipe_data = {
        'pv': pkg_pv,
        'pr': pkg_pr,
        'srcuri': srcuri,
        'package_arch': package_arch
    }

    if srcrev_data:
        recipe_data['srcrev'] = srcrev_data

    # Use SimpleCache to store component data
    try:
        # Make a copy of cache data to modify
        updated_data = copy.deepcopy(cache_data)

        # Use target_layer_arch as namespace (keeping same logic as original)
        arch_namespace = target_layer_arch or 'default'

        # Ensure components key exists
        if 'components' not in updated_data:
            updated_data['components'] = {}

        # Initialize namespace if needed
        if arch_namespace not in updated_data['components']:
            updated_data['components'][arch_namespace] = {}

        # Store recipe data in structured format
        updated_data['components'][arch_namespace][pkg_pn] = recipe_data

        # Update metadata
        if 'architectures' not in updated_data:
            updated_data['architectures'] = set()

        updated_data['architectures'].add(package_arch)
        updated_data['last_updated'] = bb.utils.time.time()

        # Save updated data back to cache
        tmpdir = d.getVar('TMPDIR') or '/tmp'
        cache_dir = os.path.join(tmpdir, "cache")
        expected_cache_path = os.path.join(cache_dir, "rdke_component_data.dat")

        rdke_log(f"About to save cache data. Cache dir exists: {os.path.exists(cache_dir)}", "DEBUG", d)
        rdke_log(f"Cache dir permissions: {oct(os.stat(cache_dir).st_mode) if os.path.exists(cache_dir) else 'N/A'}", "DEBUG", d)

        try:
            # Ensure cache directory exists
            if not os.path.exists(cache_dir):
                rdke_log(f"Creating cache directory: {cache_dir}", "DEBUG", d)
                os.makedirs(cache_dir, exist_ok=True)

            component_cache.save(updated_data)
            rdke_log(f"Cache save() completed without exception", "DEBUG", d)
        except Exception as save_ex:
            rdke_log(f"Cache save failed with exception: {save_ex}", "ERROR", d)
            raise save_ex

        # Debug: Verify cache file was created
        rdke_log(f"Cache file exists after save: {os.path.exists(expected_cache_path)}", "DEBUG", d)
        if os.path.exists(expected_cache_path):
            rdke_log(f"Cache file size: {os.path.getsize(expected_cache_path)} bytes", "DEBUG", d)
        else:
            # List what's actually in the cache directory
            if os.path.exists(cache_dir):
                cache_contents = os.listdir(cache_dir)
                rdke_log(f"Cache directory contents: {cache_contents}", "DEBUG", d)
            else:
                rdke_log(f"Cache directory does not exist: {cache_dir}", "ERROR", d)

        rdke_log(f"Successfully cached component data for {pkg_pn} in namespace '{arch_namespace}': version={pkg_pv}, srcrev_count={len(srcrev_data)}", "INFO", d)

    except Exception as ex:
        import traceback
        rdke_log(f"Failed to cache component data for {pkg_pn} using SimpleCache: {ex}", "ERROR", d)
        rdke_log(f"Exception traceback: {traceback.format_exc()}", "ERROR", d)
}

# Add the task globally - it will only execute for qualifying recipes due to early returns
addtask do_collect_component_data after do_prepare_recipe_sysroot before do_compile

do_collect_component_data[network] = "1"
do_collect_component_data[nostamp] = "1"
do_collect_component_data[vardepsexclude] += "DATETIME BB_TASKHASH BUILDNAME BB_UNIHASH BB_HASHFILENAME"
do_collect_component_data[vardepsexclude] += "_RDKE_COMPONENT_CACHE _RDKE_CACHE_DATA _RDKE_TARGET_LAYER_ARCH"
do_collect_component_data[vardepsexclude] += "RDKE_COMPONENT_CACHE_VERSION TMPDIR"
do_collect_component_data[vardepsexclude] += "OSS_LAYER_EXTENSION OSS_LAYER_ARCH VENDOR_LAYER_EXTENSION MIDDLEWARE_ARCH APP_LAYER_ARCH RDKE_GEN_DOC_LAYER_ARCH"
do_collect_component_data[vardepvalueexclude] = "."
do_collect_component_data[doc] = "Collect RDK component metadata for MD file generation"

def extract_layer_type(arch_name):
    """Extract layer type (oss, vendor, middleware, application) from architecture name."""
    layer_types = ['oss', 'vendor', 'middleware', 'application']
    for layer_type in layer_types:
        if arch_name.endswith(f'-{layer_type}'):
            return layer_type
    # Fallback - try to find it anywhere in the name
    for layer_type in layer_types:
        if layer_type in arch_name:
            return layer_type
    return 'unknown'

def analyze_srcuri_type(srcuri):
    """Analyze SRC_URI to determine if it's git, artifact, or layer-hosted."""
    if not srcuri:
        return 'unknown', None

    try:
        import bb.fetch2
        urls = srcuri.split()

        for url in urls:
            type, host, path, user, pswd, parm = bb.fetch2.decodeurl(url)

            # Check for file:// protocol (layer hosted)
            if type == 'file':
                return 'layer-hosted', None

            # Check for git repositories (including gitsm)
            if 'git' in type or type == 'gitsm':
                return 'git', None

            # Check for artifacts (http/https with downloadable files)
            if type in ['http', 'https', 'ftp']:
                # Common artifact extensions
                artifact_extensions = ['.tar.gz', '.tar.xz', '.tar.bz2', '.zip', '.tgz',
                                     '.ipk', '.deb', '.rpm', '.jar', '.war', '.tar']

                if any(path.endswith(ext) for ext in artifact_extensions):
                    full_url = f"{type}://{host}{path}"
                    return 'artifact', full_url
                else:
                    # Generic HTTP URL without clear artifact extension
                    full_url = f"{type}://{host}{path}"
                    return 'artifact', full_url

        return 'unknown', None

    except Exception as ex:
        import bb
        rdke_log(f"Error analyzing SRC_URI type: {ex}", "WARN")
        return 'unknown', None

def extract_git_repo_info(srcuri):
    """Extract base repository URL from git SRC_URI."""
    if not srcuri:
        return None

    try:
        import bb.fetch2
        urls = srcuri.split()

        for url in urls:
            type, host, path, user, pswd, parm = bb.fetch2.decodeurl(url)
            if 'git' in type or type == 'gitsm':
                # Build base repo URL for GitHub/GitLab style repos
                if host and path:
                    # Remove .git extension if present
                    if path.endswith('.git'):
                        path = path[:-4]
                    return f"https://{host}{path}"

        return None
    except Exception:
        return None

def create_version_hyperlink(pkg_info, srcuri_type, artifact_url=None):
    """Create hyperlinked version with preference: release > tag > sha, or artifact/layer-hosted."""
    pv = pkg_info.get('pv', '')
    pr = pkg_info.get('pr', '')
    # Handle both 'srcrev' (from cache) and 'srcrevs' (from JSON) keys
    srcrev_data = pkg_info.get('srcrev', {}) or pkg_info.get('srcrevs', {})
    srcuri = pkg_info.get('srcuri', '')

    if not pv or not pr:
        return pv or 'unknown'

    version = f"{pv}-{pr}"

    # Handle layer-hosted packages
    if srcuri_type == 'layer-hosted':
        return f"{version} (layer hosted)"

    # Handle artifacts
    if srcuri_type == 'artifact' and artifact_url:
        return f"[{version} (artifact)]({artifact_url})"

    # Handle Git repositories
    if srcuri_type == 'git':
        base_repo_url = extract_git_repo_info(srcuri)
        if not base_repo_url:
            return version

        if not srcrev_data:
            # No SRCREV data, link to repository root
            return f"[{version}]({base_repo_url})"

        # Handle multiple SRCREVs - prioritize in this order:
        # 1. Default SRCREV
        # 2. First tag-like SRCREV (non-40-char with digits)
        # 3. First SHA-like SRCREV (40-char)
        # 4. Any other SRCREV

        default_srcrev = None
        tag_like_srcrevs = []
        sha_like_srcrevs = []
        other_srcrevs = []

        for srcrev_key, srcrev_value in srcrev_data.items():
            if not srcrev_value:
                continue

            if srcrev_key == 'SRCREV':
                default_srcrev = srcrev_value
            elif len(srcrev_value) == 40 and srcrev_value.isalnum():
                # Looks like a SHA commit hash
                sha_like_srcrevs.append((srcrev_key, srcrev_value))
            elif len(srcrev_value) != 40 and any(char.isdigit() for char in srcrev_value):
                # Looks like a tag (not 40 chars and contains digits)
                tag_like_srcrevs.append((srcrev_key, srcrev_value))
            else:
                # Other types (branch names, etc.)
                other_srcrevs.append((srcrev_key, srcrev_value))

        # Priority 1: Use default SRCREV if available
        if default_srcrev:
            if len(default_srcrev) == 40 and default_srcrev.isalnum():
                # SHA commit
                commit_url = f"{base_repo_url}/commit/{default_srcrev}"
                return f"[{version}]({commit_url})"
            elif any(char.isdigit() for char in default_srcrev):
                # Tag-like
                tag_url = f"{base_repo_url}/releases/tag/{default_srcrev}"
                return f"[{version}]({tag_url})"
            else:
                # Branch or other - link to repository
                return f"[{version}]({base_repo_url})"

        # Priority 2: Use first tag-like SRCREV
        if tag_like_srcrevs:
            srcrev_key, srcrev_value = tag_like_srcrevs[0]
            tag_url = f"{base_repo_url}/releases/tag/{srcrev_value}"
            if len(tag_like_srcrevs) > 1:
                # Multiple tags, add annotation
                return f"[{version}]({tag_url}) (primary: {srcrev_key})"
            else:
                return f"[{version}]({tag_url})"

        # Priority 3: Use first SHA-like SRCREV
        if sha_like_srcrevs:
            srcrev_key, srcrev_value = sha_like_srcrevs[0]
            commit_url = f"{base_repo_url}/commit/{srcrev_value}"
            if len(sha_like_srcrevs) > 1:
                # Multiple SHAs, add annotation
                return f"[{version}]({commit_url}) (primary: {srcrev_key})"
            else:
                return f"[{version}]({commit_url})"

        # Priority 4: Use any other SRCREV or fallback to repo
        if other_srcrevs:
            # Non-linkable SRCREV (like branch name), link to repository
            return f"[{version}]({base_repo_url})"

        # Fallback: link to repository root
        return f"[{version}]({base_repo_url})"

    # Fallback to plain version if no linkable info
    return version

# Generate JSON and MD files when build completes
python generate_rdke_component_info_eventhandler() {
    import os
    import json
    import bb.cache

    if isinstance(e, bb.event.BuildCompleted):
        rdke_log("Starting generate-rdke-component-info processing...", "INFO", d)

        try:
            # Get the TMPDIR for output file location
            tmpdir = d.getVar('TMPDIR')
            if not tmpdir:
                rdke_log("TMPDIR not found, cannot generate component files", "ERROR", d)
                return

            rdke_log(f"Using TMPDIR: {tmpdir}", "DEBUG", d)

            # Initialize SimpleCache to read collected component data
            component_cache = bb.cache.SimpleCache(d.getVar("RDKE_COMPONENT_CACHE_VERSION") or "1.0")
            cache_data = component_cache.init_cache(d, "rdke_component_data.dat", {})

            components = cache_data.get('components', {})

            if not components:
                rdke_log("No component data found in cache, skipping file generation", "WARN", d)
                return

            rdke_log(f"Found component data for {len(components)} architecture namespaces", "INFO", d)

            # Group all components by layer type
            grouped_json_output = {}

            # Process each architecture namespace and group by layer type
            for arch_namespace, arch_components in components.items():
                if not arch_components:
                    rdke_log(f"No components found for architecture namespace: {arch_namespace}", "DEBUG", d)
                    continue

                rdke_log(f"Processing {len(arch_components)} components for arch namespace: {arch_namespace}", "DEBUG", d)

                # Extract layer type from architecture name
                layer_type = extract_layer_type(arch_namespace)

                # Initialize layer type array if it doesn't exist
                if layer_type not in grouped_json_output:
                    grouped_json_output[layer_type] = []

                # Transform component data to requested JSON format
                for pkg_name, comp_data in arch_components.items():
                    # Build the package entry in requested format
                    package_entry = {
                        "package-name": pkg_name,
                        "pv": comp_data.get('pv', ''),
                        "pr": comp_data.get('pr', ''),
                        "srcuri": comp_data.get('srcuri', '')
                    }

                    # Add srcrevs section if SRCREV data exists
                    srcrev_data = comp_data.get('srcrev', {})
                    if srcrev_data:
                        package_entry["srcrevs"] = srcrev_data
                    else:
                        package_entry["srcrevs"] = {}

                    # Add to the layer type array
                    grouped_json_output[layer_type].append(package_entry)

            # Create separate JSON files for each layer type
            total_components = 0
            layer_summary = {}

            for layer_type, packages in grouped_json_output.items():
                if not packages:
                    continue

                try:
                    # Create JSON filename based on layer type
                    json_filename = f"{layer_type}-component-details.json"
                    json_filepath = os.path.join(tmpdir, json_filename)

                    # Write JSON file for this layer type
                    with open(json_filepath, 'w') as f:
                        json.dump(packages, f, indent=2, sort_keys=True)

                    layer_summary[layer_type] = len(packages)
                    total_components += len(packages)

                    rdke_log(f"Generated {json_filename} with {len(packages)} components for layer type '{layer_type}'", "INFO", d)
                    rdke_log(f"JSON file saved to: {json_filepath}", "NOTE", d)

                except Exception as write_ex:
                    rdke_log(f"Failed to write JSON file for layer type '{layer_type}': {write_ex}", "ERROR", d)

            rdke_log(f"Generated {len(grouped_json_output)} JSON files with {total_components} total components", "INFO", d)
            rdke_log(f"Layer type breakdown: {layer_summary}", "INFO", d)

            # Generate MD files for each layer type
            for layer_type, packages in grouped_json_output.items():
                if not packages:
                    continue

                try:
                    # Create MD filename based on layer type
                    md_filename = f"{layer_type.title()}-ComponentVersionInfo.md"
                    md_filepath = os.path.join(tmpdir, md_filename)

                    # Sort packages: packagegroup entries first, then alphabetically
                    def sort_key(pkg):
                        pkg_name = pkg.get('package-name', '')
                        # Put packagegroup entries first
                        if pkg_name.startswith('packagegroup-'):
                            return (0, pkg_name)
                        else:
                            return (1, pkg_name)

                    sorted_packages = sorted(packages, key=sort_key)

                    # Generate MD content
                    md_content = []
                    md_content.append(f"# {layer_type.title()} Component Version Information")
                    md_content.append("")
                    md_content.append("| Package Name | Version |")
                    md_content.append("|--------------|---------|")

                    for pkg in sorted_packages:
                        pkg_name = pkg.get('package-name', '')
                        srcuri = pkg.get('srcuri', '')

                        # Analyze SRC_URI type and create hyperlinked version
                        srcuri_type, artifact_url = analyze_srcuri_type(srcuri)
                        hyperlinked_version = create_version_hyperlink(pkg, srcuri_type, artifact_url)

                        md_content.append(f"| {pkg_name} | {hyperlinked_version} |")

                    # Write MD file
                    with open(md_filepath, 'w') as f:
                        f.write('\n'.join(md_content))

                    rdke_log(f"Generated {md_filename} with {len(sorted_packages)} components for layer type '{layer_type}'", "INFO", d)
                    rdke_log(f"MD file saved to: {md_filepath}", "NOTE", d)

                except Exception as md_ex:
                    rdke_log(f"Failed to write MD file for layer type '{layer_type}': {md_ex}", "ERROR", d)

            rdke_log("Completed generate-rdke-component-info processing", "INFO", d)

        except Exception as ex:
            rdke_log(f"Error in generate_rdke_component_info_eventhandler: {ex}", "ERROR", d)
}

addhandler generate_rdke_component_info_eventhandler
generate_rdke_component_info_eventhandler[eventmask] = "bb.event.BuildCompleted"
