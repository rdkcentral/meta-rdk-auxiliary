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

# Add recipe-level data collection task
python do_collect_component_data() {
    import os

    # Early architecture filtering - only collect if recipe matches target arch
    package_arch = d.getVar('PACKAGE_ARCH') or ""

    # Get target architecture from environment (check if this recipe is relevant)
    target_layer_arch = None
    priority_vars = ['RDKE_GEN_DOC_LAYER_ARCH', 'OSS_LAYER_ARCH', 'VENDOR_LAYER_EXTENSION', 'MIDDLEWARE_ARCH', 'APP_LAYER_ARCH']
    for var_name in priority_vars:
        var_value = d.getVar(var_name)
        if var_value:
            target_layer_arch = var_value
            break

    # Skip processing if this recipe doesn't match target architecture
    if target_layer_arch and target_layer_arch not in package_arch:
        return

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
        bb.warn(f"Failed to extract SRCREV via fetcher for {pkg_pn}, using fallback: {ex}")
        srcrev = d.getVar('SRCREV')
        if srcrev and srcrev != 'INVALID':
            srcrev_data['SRCREV'] = srcrev

    # Recipe data structure
    recipe_data = {
        'pv': pkg_pv,
        'pr': pkg_pr,
        'srcuri': srcuri
    }

    if srcrev_data:
        recipe_data['srcrev'] = srcrev_data

    # Use shared memory via BitBake's persistent data store (thread-safe)
    try:
        import bb.persist_data

        persist_d = bb.persist_data.persist(d.getVar('TMPDIR') + '/cache', d)
        # Store recipe data in shared cache with domain-specific namespace to avoid conflicts
        persist_d.setValue("component_cache", pkg_pn, recipe_data)

        # Ensure data is committed to shared storage immediately
        persist_d.sync()

    except Exception as ex:
        bb.warn(f"Failed to cache component data for {pkg_pn} in shared memory: {ex}")
}

# Add the task to recipe processing (isolated from main build path)
addtask do_collect_component_data after do_fetch
do_collect_component_data[nostamp] = "1"
do_collect_component_data[vardepsexclude] += "DATETIME BB_TASKHASH"
do_collect_component_data[vardepvalueexclude] = "."
# Make it completely isolated - doesn't affect other tasks
do_collect_component_data[vardepsexclude] += "do_collect_component_data"

addhandler generate_rdke_component_info_eventhandler
generate_rdke_component_info_eventhandler[eventmask] = "bb.event.BuildCompleted"

python generate_rdke_component_info_eventhandler() {
    import os
    import json

    # Get MLPREFIX for consistency with BitBake variables
    mlprefix = e.data.getVar('MLPREFIX') or 'lib32-'

    def process_cached_recipe_data():
        # Process cached recipe data from shared memory at build completion
        tmpdir = e.data.getVar('TMPDIR')

        # Get layer_package_arch with priority order for different layer types
        layer_package_arch = e.data.getVar('RDKE_GEN_DOC_LAYER_ARCH')

        if not layer_package_arch:
            priority_vars = [
                'OSS_LAYER_EXTENSION',
                'OSS_LAYER_ARCH',
                'VENDOR_LAYER_EXTENSION',
                'MIDDLEWARE_ARCH',
                'APP_LAYER_ARCH'
            ]

            for var_name in priority_vars:
                var_value = e.data.getVar(var_name)
                if var_value:
                    layer_package_arch = var_value

        if not layer_package_arch:
            bb.warn("No layer architecture variable found. Skipping component info collection.")
            return

        # Load all cached recipe data from shared memory
        try:
            import bb.persist_data

            # Access the same persistent data store used during recipe collection
            persist_d = bb.persist_data.persist(tmpdir + '/cache', e.data)

            # Get all component cache entries
            arch_pkg_details = {}
            try:
                # Get all keys in the component_cache domain
                cache_keys = persist_d.getKeyValues("component_cache")
                for pkg_name, recipe_data in cache_keys.items():
                    arch_pkg_details[pkg_name] = recipe_data
            except Exception as ex:
                bb.warn(f"Failed to retrieve component cache from shared memory: {ex}")
                return

            # Extract layer type and create output files
            if arch_pkg_details:
                layer_type = extract_layer_type(layer_package_arch)

                # Write JSON details
                arch_details_file = os.path.join(tmpdir, f"{layer_type}-component-details.json")
                try:
                    import json
                    with open(arch_details_file, 'w') as f:
                        json.dump(arch_pkg_details, f, indent=4)
                    bb.note(f"Created {arch_details_file} with {len(arch_pkg_details)} packages")
                except Exception as ex:
                    bb.warn(f"Error writing {arch_details_file}: {ex}")

                # Create Markdown file
                create_component_version_md_file(layer_type, arch_pkg_details)

                # Clean up shared memory cache after processing
                try:
                    for pkg_name in arch_pkg_details.keys():
                        persist_d.delValue("component_cache", pkg_name)
                    persist_d.sync()
                except Exception as ex:
                    bb.warn(f"Failed to cleanup shared memory cache: {ex}")

        except Exception as ex:
            bb.warn(f"Failed to process shared memory cache: {ex}")

    def find_package_latest(buildhistory_dir, arch, package_name):
        # Find the latest file for a package in buildhistory directories.
        packages_root = os.path.join(buildhistory_dir, "packages")
        candidate_dirs = []
        if os.path.isdir(packages_root):
            for d in os.listdir(packages_root):
                if arch in d:
                    candidate_dirs.append(d)

        for candidate_arch in candidate_dirs:
            package_dir = os.path.join(packages_root, candidate_arch, package_name)
            latest_path = os.path.join(package_dir, "latest")
            if os.path.exists(latest_path):
                return latest_path

        # Fallback to direct arch match
        package_dir = os.path.join(packages_root, arch, package_name)
        latest_path = os.path.join(package_dir, "latest")
        if os.path.exists(latest_path):
            return latest_path

        bb.warn(f"Latest file not found for {package_name} in any arch dir containing '{arch}'")
        return None

    def read_pv_pr_srcuri(latest_path):
        # Extract PV, PR, and SRC_URI from buildhistory latest file.
        pv = pr = srcuri = None
        try:
            with open(latest_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('PV ='):
                        pv = line.split('=', 1)[1].strip()
                    elif line.startswith('PR ='):
                        pr = line.split('=', 1)[1].strip()
                    elif line.startswith('SRC_URI ='):
                        srcuri = line.split('=', 1)[1].strip()
        except Exception as ex:
            bb.warn(f"Error reading {latest_path}: {ex}")
        return pv, pr, srcuri

    def read_srcrev_info(latest_srcrev_path):
        # Extract SRCREV information from buildhistory latest_srcrev file.
        srcrev_data = {}
        try:
            with open(latest_srcrev_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    # Skip commented lines and empty lines
                    if line and not line.startswith('#'):
                        if line.startswith('SRCREV'):
                            # Parse SRCREV lines like: SRCREV_firebolt = "7b01285cd..."
                            if '=' in line:
                                key, value = line.split('=', 1)
                                key = key.strip()
                                value = value.strip().strip('"')
                                srcrev_data[key] = value
        except Exception as ex:
            bb.warn(f"Error reading {latest_srcrev_path}: {ex}")
        return srcrev_data

    def extract_git_repo_info(srcuri):
        # Extract Git repository information from SRC_URI.
        try:
            import bb.fetch2
            # Parse URLs from SRC_URI (handle git://, gitsm://, git+)
            urls = srcuri.split() if srcuri else []
            for url in urls:
                if any(protocol in url for protocol in ['git://', 'gitsm://', 'git+']):
                    type, host, path, user, pswd, parm = bb.fetch2.decodeurl(url)
                    if ('git' in type or type == 'gitsm') and host:
                        # Get protocol (default to https for web links)
                        protocol = 'https'
                        if 'protocol' in parm:
                            protocol = parm['protocol']
                        elif 'proto' in parm:
                            protocol = parm['proto']

                        # Build base repo URL for web interface
                        if protocol in ['git', 'ssh']:
                            protocol = 'https'  # Convert to web-accessible protocol
                        elif protocol == 'http' and 'github.com' in host:
                            protocol = 'https'  # GitHub requires HTTPS for web interface

                        base_url = f"{protocol}://{host}{path}"
                        # Remove .git extension if present
                        if base_url.endswith('.git'):
                            base_url = base_url[:-4]

                        return base_url
        except Exception as ex:
            bb.warn(f"Error parsing SRC_URI: {ex}")
        return None

    def analyze_srcuri_type(srcuri):
        # Analyze SRC_URI to determine if it's git, artifact, or layer-hosted.
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
            bb.warn(f"Error analyzing SRC_URI type: {ex}")
            return 'unknown', None

    def create_version_hyperlink(pkg_info, srcuri_type, artifact_url=None):
        # Create hyperlinked version with preference: release > tag > sha, or artifact/layer-hosted.
        pv = pkg_info.get('pv', '')
        pr = pkg_info.get('pr', '')
        srcrev_data = pkg_info.get('srcrev', {})
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

            # Only create hyperlinks based on actual SRCREV data, not assumptions
            # 1. Check for tag in SRCREV data (look for tag-like patterns)
            for srcrev_key, srcrev_value in srcrev_data.items():
                if srcrev_value and len(srcrev_value) != 40:  # Not a SHA, likely a tag
                    # Check if it looks like a version tag
                    if any(char.isdigit() for char in srcrev_value):
                        tag_url = f"{base_repo_url}/releases/tag/{srcrev_value}"
                        return f"[{version}]({tag_url})"

            # 2. Use SHA if available (prefer main SRCREV)
            sha_value = None
            if 'SRCREV' in srcrev_data:
                sha_value = srcrev_data['SRCREV']
            elif srcrev_data:
                # Use first available SRCREV
                sha_value = next(iter(srcrev_data.values()))

            if sha_value and len(sha_value) == 40:
                commit_url = f"{base_repo_url}/commit/{sha_value}"
                return f"[{version}]({commit_url})"

            # 3. If no SRCREV data but is git repo, just link to the repository
            if base_repo_url:
                return f"[{version}]({base_repo_url})"

                # Fallback to plain version if no linkable info
        return version

    def extract_layer_type(arch_name):
        # Extract layer type (oss, vendor, middleware, application) from architecture name.
        layer_types = ['oss', 'vendor', 'middleware', 'application']
        for layer_type in layer_types:
            if arch_name.endswith(f'-{layer_type}'):
                return layer_type
        # Fallback - try to find it anywhere in the name
        for layer_type in layer_types:
            if layer_type in arch_name:
                return layer_type
        return 'unknown'

    def create_component_version_md_file(layer_type, arch_pkg_details):
        # Create a Markdown file with package names and hyperlinked versions.
        tmpdir = e.data.getVar('TMPDIR')
        md_file = os.path.join(tmpdir, f'{layer_type.title()}-PackagesAndVersions.md')

        try:
            # Extract package entries and create version strings with hyperlinks
            all_entries = []
            for pkg_name, pkg_info in arch_pkg_details.items():
                if pkg_info:
                    pv = pkg_info.get('pv', '')
                    pr = pkg_info.get('pr', '')
                    if pv and pr:
                        # Analyze SRC_URI type for appropriate linking
                        srcuri = pkg_info.get('srcuri', '')
                        srcuri_type, artifact_url = analyze_srcuri_type(srcuri)

                        # Create hyperlinked version based on source type
                        version_link = create_version_hyperlink(pkg_info, srcuri_type, artifact_url)

                        # Keep full package name (including MLPREFIX) for display
                        display_name = pkg_name
                        all_entries.append((display_name, version_link))

            # Sorting logic for packages
            pkg_group_entries = []
            other_entries = []

            for name, version in all_entries:
                base_name = name.replace(mlprefix, '') if name.startswith(mlprefix) else name
                if base_name.startswith('packagegroup-'):
                    pkg_group_entries.append((name, version))
                else:
                    other_entries.append((name, version))

            pkg_group_entries.sort()
            other_entries.sort()

            # Write Markdown file
            with open(md_file, 'w') as f:
                f.write(f'# {layer_type.title()} Layer - Packages and Versions\n\n')
                f.write('| Package Name | Version |\n')
                f.write('|--------------|---------|\n')

                # Write packagegroup entries first
                for pkg_name, version in pkg_group_entries:
                    f.write(f'| {pkg_name} | {version} |\n')

                # Write other entries
                for pkg_name, version in other_entries:
                    f.write(f'| {pkg_name} | {version} |\n')

            #bb.note(f"Created Markdown file: {md_file} with {len(all_entries)} packages")

        except Exception as ex:
            bb.warn(f"Error creating Markdown file {md_file}: {ex}")

    # This function should wait until any of these happens:
    # Wait for buildhistory tasks to finish. we should only start after "Writing buildhistory took: %s seconds" or "No commit since BUILDHISTORY_COMMIT != '1'"
    def wait_for_buildhistory_completion():
        import time
        import os

        buildhistory_dir = e.data.getVar('BUILDHISTORY_DIR')
        buildhistory_commit = e.data.getVar('BUILDHISTORY_COMMIT')

        if not buildhistory_dir or not os.path.exists(buildhistory_dir):
            bb.warn("BUILDHISTORY_DIR not found, skipping wait")
            return

        check_interval = 0.5  # Check every 500ms

        bb.note("Waiting for buildhistory completion...")

        while True:
            # Check if buildhistory has completed by looking for git completion or file stability

            if buildhistory_commit == "1":
                # If git commit is enabled, check for git repository completion
                git_dir = os.path.join(buildhistory_dir, '.git')
                if os.path.exists(git_dir):
                    # Check if git operations are complete by testing git status
                    try:
                        import subprocess
                        result = subprocess.run(['git', 'status', '--porcelain'],
                                              cwd=buildhistory_dir,
                                              capture_output=True,
                                              timeout=5,
                                              text=True)
                        if result.returncode == 0:
                            # Git status worked, buildhistory git operations are likely complete
                            bb.note("Buildhistory git operations completed")
                            time.sleep(0.1)  # Small buffer to ensure all files are flushed
                            return
                    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
                        # Git command failed or timed out, continue waiting
                        pass
            else:
                # If no git commit, check for file system stability
                # Look for metadata-revs file which is one of the last files written
                metadata_revs_file = os.path.join(buildhistory_dir, 'metadata-revs')
                if os.path.exists(metadata_revs_file):
                    # Check file modification time stability (no changes for at least 200ms)
                    try:
                        stat1 = os.stat(metadata_revs_file)
                        time.sleep(0.2)
                        stat2 = os.stat(metadata_revs_file)
                        if stat1.st_mtime == stat2.st_mtime:
                            bb.note("Buildhistory file operations completed")
                            return
                    except OSError:
                        # File might be being written, continue waiting
                        pass

            time.sleep(check_interval)

    if isinstance(e, bb.event.BuildCompleted):
        import time
        start_time = time.time()
        bb.note(f"Starting generate-rdke-component-info processing (direct collection method)...")

        # Process cached recipe data instead of buildhistory
        process_cached_recipe_data()

        end_time = time.time()
        duration = end_time - start_time
        bb.note(f"generate-rdke-component-info processing complete. Duration: {duration:.3f} seconds")
}
