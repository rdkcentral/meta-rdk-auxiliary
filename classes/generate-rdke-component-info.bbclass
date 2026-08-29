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
    else:
        rdke_log(f"RDKE configured for qualifying recipe: {pn}", "DEBUG", d)

    #rdke_log(f"RDKE configured for qualifying recipe: {pn}", "DEBUG", d)
}

# Add recipe-level data collection task
python do_collect_component_data() {
    import os
    import bb
    import copy

    pn = d.getVar('PN')

    # Skip native and nativesdk recipes
    if bb.data.inherits_class('native', d) or bb.data.inherits_class('nativesdk', d):
        rdke_log(f"do_collect_component_data skipping {pn} since it inherits native.", "DEBUG", d)
        return

    # Check if we need component collection at all
    target_layer_arch = get_target_layer_arch(d)
    if not target_layer_arch:
        return

    # Early package architecture check
    package_arch = d.getVar('PACKAGE_ARCH') or ""
    if target_layer_arch not in package_arch:
        rdke_log(f"do_collect_component_data skipping {pn} due to ARCH mismatch.", "DEBUG", d)
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

    # Only try to extract SRCREV if SRC_URI is not empty
    if srcuri:
        try:
            import bb.fetch2
            fetcher = bb.fetch2.Fetch(srcuri.split(), d)
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
    else:
        # For packages with empty SRC_URI (like packagegroups), check if SRCREV exists
        srcrev = d.getVar('SRCREV')
        if srcrev and srcrev != 'INVALID':
            srcrev_data['SRCREV'] = srcrev
        # Note: packagegroups typically have no SRCREV at all, which is normal

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
        rdke_log(f"Starting cache storage for {pkg_pn} with target_layer_arch='{target_layer_arch}'", "INFO", d)

        # Make a copy of cache data to modify
        updated_data = copy.deepcopy(cache_data)
        rdke_log(f"Cache data copied, current components count: {len(updated_data.get('components', {}))}", "DEBUG", d)

        # Use target_layer_arch as namespace (keeping same logic as original)
        arch_namespace = target_layer_arch or 'default'
        rdke_log(f"Using arch_namespace: '{arch_namespace}' for {pkg_pn}", "DEBUG", d)

        # Ensure components key exists
        if 'components' not in updated_data:
            updated_data['components'] = {}
            rdke_log(f"Initialized components key in cache data", "DEBUG", d)

        # Initialize namespace if needed
        if arch_namespace not in updated_data['components']:
            updated_data['components'][arch_namespace] = {}
            rdke_log(f"Initialized namespace '{arch_namespace}' in cache", "DEBUG", d)
        else:
            existing_count = len(updated_data['components'][arch_namespace])
            rdke_log(f"Namespace '{arch_namespace}' already exists with {existing_count} components", "DEBUG", d)

        # Store recipe data in structured format
        updated_data['components'][arch_namespace][pkg_pn] = recipe_data
        new_count = len(updated_data['components'][arch_namespace])
        rdke_log(f"Added {pkg_pn} to namespace '{arch_namespace}', new count: {new_count}", "INFO", d)

        # Update metadata
        if 'architectures' not in updated_data:
            updated_data['architectures'] = set()

        updated_data['architectures'].add(package_arch)
        updated_data['last_updated'] = bb.utils.time.time()

        # Save updated data back to cache
        tmpdir = d.getVar('TMPDIR') or '/tmp'
        cache_dir = os.path.join(tmpdir, "cache")
        expected_cache_path = os.path.join(cache_dir, "rdke_component_data.dat")

        rdke_log(f"About to save cache data for {pkg_pn}. Cache dir exists: {os.path.exists(cache_dir)}", "DEBUG", d)
        rdke_log(f"Cache dir permissions: {oct(os.stat(cache_dir).st_mode) if os.path.exists(cache_dir) else 'N/A'}", "DEBUG", d)
        rdke_log(f"Total components to save: {sum(len(arch_data) for arch_data in updated_data['components'].values())}", "INFO", d)

        try:
            # Ensure cache directory exists
            if not os.path.exists(cache_dir):
                rdke_log(f"Creating cache directory: {cache_dir}", "DEBUG", d)
                os.makedirs(cache_dir, exist_ok=True)

            # Log cache state before save
            cache_state = {arch: list(arch_data.keys()) for arch, arch_data in updated_data['components'].items()}
            rdke_log(f"Cache state before save: {cache_state}", "DEBUG", d)

            component_cache.save(updated_data)
            rdke_log(f"Cache save() completed successfully for {pkg_pn}", "INFO", d)
        except Exception as save_ex:
            rdke_log(f"Cache save failed for {pkg_pn} with exception: {save_ex}", "ERROR", d)
            import traceback
            rdke_log(f"Save exception traceback: {traceback.format_exc()}", "ERROR", d)
            raise save_ex

        # Debug: Verify cache file was created and verify contents
        rdke_log(f"Cache file exists after save: {os.path.exists(expected_cache_path)}", "DEBUG", d)
        if os.path.exists(expected_cache_path):
            file_size = os.path.getsize(expected_cache_path)
            rdke_log(f"Cache file size: {file_size} bytes", "DEBUG", d)

            # Verify cache contents by re-reading
            try:
                verify_cache = bb.cache.SimpleCache(d.getVar("RDKE_COMPONENT_CACHE_VERSION") or "1.0")
                verify_data = verify_cache.init_cache(d, "rdke_component_data.dat", {})
                verify_components = verify_data.get('components', {})
                verify_total = sum(len(arch_data) for arch_data in verify_components.values())
                rdke_log(f"Cache verification: {verify_total} total components after save", "INFO", d)

                # Check if our specific package was saved
                if arch_namespace in verify_components and pkg_pn in verify_components[arch_namespace]:
                    rdke_log(f"VERIFIED: {pkg_pn} successfully stored in cache under '{arch_namespace}'", "INFO", d)
                else:
                    rdke_log(f"WARNING: {pkg_pn} NOT found in cache after save!", "WARN", d)

            except Exception as verify_ex:
                rdke_log(f"Cache verification failed: {verify_ex}", "WARN", d)
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
addtask do_collect_component_data after do_package

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

def extract_git_repo_info_for_name(srcuri, repo_name=None):
    """Extract repository URL for a specific named repository from git SRC_URI."""
    if not srcuri:
        return None

    try:
        import bb.fetch2
        # Split the SRC_URI into individual URLs (space-separated)
        urls = srcuri.split()

        for url in urls:
            # Skip file:// URLs (patches)
            if url.startswith('file://'):
                continue

            try:
                type, host, path, user, pswd, parm = bb.fetch2.decodeurl(url)
                rdke_log(f"Decoded URL: type={type}, host={host}, path={path}, parm={parm}", "DEBUG")

                if 'git' in type or type == 'gitsm':
                    # Check if this URL matches the requested repo name
                    url_name = parm.get('name', 'default')
                    rdke_log(f"URL name: {url_name}, looking for: {repo_name}", "DEBUG")

                    if repo_name is None or url_name == repo_name:
                        # Build base repo URL
                        if host and path:
                            # Remove .git extension if present
                            if path.endswith('.git'):
                                path = path[:-4]

                            # Build the repository URL
                            repo_url = f"https://{host}{path}"
                            rdke_log(f"Built repository URL: {repo_url}", "DEBUG")
                            return repo_url
            except Exception as e:
                rdke_log(f"Error decoding URL {url}: {e}", "DEBUG")
                continue

        rdke_log(f"No matching URL found for repo_name: {repo_name}", "DEBUG")
        return None
    except Exception as e:
        rdke_log(f"Exception in extract_git_repo_info_for_name: {e}", "DEBUG")
        return None

def should_expand_package_rows(pkg_info):
    """Determine if a package should be expanded into multiple rows based on named SRCREVs."""
    srcrev_data = pkg_info.get('srcrev', {}) or pkg_info.get('srcrevs', {})

    if not srcrev_data or len(srcrev_data) <= 1:
        return False

    # Check if we have multiple named SRCREVs (SRCREV_name pattern)
    named_srcrevs = [key for key in srcrev_data.keys() if key.startswith('SRCREV_') and key != 'SRCREV']

    # Expand if we have 2 or more named SRCREVs
    return len(named_srcrevs) >= 2

def create_package_rows(pkg_info, srcuri_type, artifact_url=None, d=None):
    """Create one or more table rows for a package, expanding multi-repo packages."""
    pkg_name = pkg_info.get('package-name', '')
    srcrev_data = pkg_info.get('srcrev', {}) or pkg_info.get('srcrevs', {})

    rows = []

    if should_expand_package_rows(pkg_info):
        # Multi-repo package - create single row with combined version information
        named_srcrevs = [(key, value) for key, value in srcrev_data.items()
                        if key.startswith('SRCREV_') and key != 'SRCREV']

        # Sort for consistent ordering
        named_srcrevs.sort(key=lambda x: x[0])

        version_parts = []

        for i, (srcrev_key, srcrev_value) in enumerate(named_srcrevs):
            repo_name = srcrev_key.replace('SRCREV_', '')

            rdke_log(f"Creating hyperlink for {pkg_name} repo {repo_name}: srcrev_value={srcrev_value}", "INFO", d)

            # Create version hyperlink for this specific repo
            hyperlinked_version = create_version_hyperlink_for_repo(
                pkg_info, srcuri_type, repo_name, srcrev_value, artifact_url
            )

            rdke_log(f"Generated hyperlinked_version for {repo_name}: {hyperlinked_version}", "INFO", d)

            # Add repo name annotation
            if srcuri_type == 'git' and '[' in hyperlinked_version and '](' in hyperlinked_version:
                # This is a markdown link [text](url) - add repo name after it
                hyperlinked_version += f" ({repo_name})"
            else:
                # Add repo name for non-linked versions
                hyperlinked_version += f" ({repo_name})"

            version_parts.append(hyperlinked_version)

        # Combine all version parts with a separator
        combined_version = " • ".join(version_parts)
        rdke_log(f"Combined version for {pkg_name}: {combined_version}", "INFO", d)
        rows.append((pkg_name, combined_version))
    else:
        # Single repo package - use existing logic
        hyperlinked_version = create_version_hyperlink(pkg_info, srcuri_type, artifact_url)
        rows.append((pkg_name, hyperlinked_version))

    return rows

def create_version_hyperlink_for_repo(pkg_info, srcuri_type, repo_name, srcrev_value, artifact_url=None):
    """Create hyperlinked version for a specific repository in multi-repo packages."""
    pv = pkg_info.get('pv', '')
    pr = pkg_info.get('pr', '')
    srcuri = pkg_info.get('srcuri', '')

    rdke_log(f"create_version_hyperlink_for_repo called with: repo_name={repo_name}, srcrev_value={srcrev_value}, srcuri_type={srcuri_type}", "INFO")
    rdke_log(f"pv={pv}, pr={pr}, srcuri={srcuri[:100]}...", "INFO")

    if not pv or not pr:
        return pv or 'unknown'

    version = f"{pv}-{pr}"

    # Handle layer-hosted packages
    if srcuri_type == 'layer-hosted':
        return f"{version} (layer hosted)"

    # Handle artifacts
    if srcuri_type == 'artifact' and artifact_url:
        return f"[{version} (artifact)]({artifact_url})"

    # Handle unknown/empty SRC_URI (packagegroups, virtual packages)
    if srcuri_type == 'unknown':
        return version

    # Handle Git repositories
    if srcuri_type == 'git':
        # Get repository URL for this specific named repo
        base_repo_url = extract_git_repo_info_for_name(srcuri, repo_name)
        rdke_log(f"Extracted base_repo_url for {repo_name}: {base_repo_url}", "DEBUG")

        if not base_repo_url:
            # No repository URL could be extracted
            rdke_log(f"No repository URL found for repo_name: {repo_name}", "DEBUG")
            return version

        rdke_log(f"Using base_repo_url: {base_repo_url}", "DEBUG")

        if not srcrev_value or srcrev_value == 'INVALID':
            # No SRCREV data, link to repository root
            rdke_log(f"No valid SRCREV, linking to repo root", "DEBUG")
            return f"[{version}]({base_repo_url})"

        rdke_log(f"Processing SRCREV value: {srcrev_value} (length: {len(srcrev_value)})", "DEBUG")

        # Try to extract actual commit hash from version if SRCREV doesn't look like a commit
        actual_commit = srcrev_value
        if not (len(srcrev_value) == 40 and srcrev_value.isalnum()):
            # SRCREV doesn't look like a commit hash, try to extract from version
            if "+git" in version and "_" in version:
                parts = version.split("_")
                for part in reversed(parts):
                    if len(part) >= 8 and part.isalnum():
                        actual_commit = part
                        rdke_log(f"Extracted commit from version: {actual_commit}", "DEBUG")
                        break

        # Determine link type based on commit value
        if len(actual_commit) >= 8 and actual_commit.isalnum():
            # SHA commit (full or abbreviated)
            commit_url = f"{base_repo_url}/commit/{actual_commit}"
            rdke_log(f"Generated commit URL: {commit_url}", "DEBUG")
            return f"[{version}]({commit_url})"
        elif any(char.isdigit() for char in srcrev_value):
            # Tag-like
            tag_url = f"{base_repo_url}/releases/tag/{srcrev_value}"
            rdke_log(f"Generated tag URL: {tag_url}", "DEBUG")
            return f"[{version}]({tag_url})"
        else:
            # Branch or other - link to repository
            rdke_log(f"Fallback to repo root link", "DEBUG")
            return f"[{version}]({base_repo_url})"

    # Fallback to plain version if no linkable info
    rdke_log(f"Returning plain version: {version}", "DEBUG")
    return version

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

    # Handle unknown/empty SRC_URI (packagegroups, virtual packages)
    if srcuri_type == 'unknown':
        return version

    # Handle Git repositories
    if srcuri_type == 'git':
        base_repo_url = extract_git_repo_info_for_name(srcuri)
        if not base_repo_url:
            return version

        if not srcrev_data:
            # No SRCREV data, link to repository root
            return f"[{version}]({base_repo_url})"

        # Handle single vs multiple SRCREVs
        if len(srcrev_data) == 1:
            # Single SRCREV - use original logic
            srcrev_key, srcrev_value = next(iter(srcrev_data.items()))

            if len(srcrev_value) == 40 and srcrev_value.isalnum():
                # SHA commit
                commit_url = f"{base_repo_url}/commit/{srcrev_value}"
                return f"[{version}]({commit_url})"
            elif any(char.isdigit() for char in srcrev_value):
                # Tag-like
                tag_url = f"{base_repo_url}/releases/tag/{srcrev_value}"
                return f"[{version}]({tag_url})"
            else:
                # Branch or other - link to repository
                return f"[{version}]({base_repo_url})"
        else:
            # Multiple SRCREVs - prioritize and add annotation
            default_srcrev = srcrev_data.get('SRCREV')
            if default_srcrev:
                # Use default SRCREV
                if len(default_srcrev) == 40 and default_srcrev.isalnum():
                    commit_url = f"{base_repo_url}/commit/{default_srcrev}"
                    return f"[{version}]({commit_url})"
                elif any(char.isdigit() for char in default_srcrev):
                    tag_url = f"{base_repo_url}/releases/tag/{default_srcrev}"
                    return f"[{version}]({tag_url})"
                else:
                    return f"[{version}]({base_repo_url})"
            else:
                # Use first named SRCREV
                first_key, first_value = next(iter(srcrev_data.items()))
                repo_name = first_key.replace('SRCREV_', '') if first_key.startswith('SRCREV_') else 'default'

                if len(first_value) == 40 and first_value.isalnum():
                    commit_url = f"{base_repo_url}/commit/{first_value}"
                    return f"[{version}]({commit_url}) (primary: {first_key})"
                elif any(char.isdigit() for char in first_value):
                    tag_url = f"{base_repo_url}/releases/tag/{first_value}"
                    return f"[{version}]({tag_url}) (primary: {first_key})"
                else:
                    return f"[{version}]({base_repo_url}) (primary: {first_key})"

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
                        srcrev_data = pkg.get('srcrev', {}) or pkg.get('srcrevs', {})

                        # Log details for packages with multiple SRCREVs
                        if len(srcrev_data) > 1:
                            rdke_log(f"Processing {pkg_name} with {len(srcrev_data)} SRCREVs: {list(srcrev_data.keys())}", "DEBUG", d)

                        # Analyze SRC_URI type
                        srcuri_type, artifact_url = analyze_srcuri_type(srcuri)

                        # Create one or more rows for this package
                        package_rows = create_package_rows(pkg, srcuri_type, artifact_url, d)

                        # Log expansion details
                        if len(package_rows) > 1:
                            rdke_log(f"Expanded {pkg_name} into {len(package_rows)} rows for multi-repo documentation", "INFO", d)

                        # Add all rows to the markdown content
                        for row_pkg_name, hyperlinked_version in package_rows:
                            md_content.append(f"| {row_pkg_name} | {hyperlinked_version} |")

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
