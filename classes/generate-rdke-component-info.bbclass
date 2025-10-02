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

addhandler generate_rdke_component_info_eventhandler
generate_rdke_component_info_eventhandler[eventmask] = "bb.event.BuildCompleted"

python generate_rdke_component_info_eventhandler() {
    import os
    import json

    # Get MLPREFIX for consistency with BitBake variables
    mlprefix = e.data.getVar('MLPREFIX') or 'lib32-'

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
        md_file = os.path.join(tmpdir, f'{layer_type}-PackagesAndVersions.md')

        try:
            # Extract package entries and create version strings with hyperlinks
            all_entries = []
            for pkg_name, pkg_info_list in arch_pkg_details.items():
                if pkg_info_list and len(pkg_info_list) > 0:
                    pkg_info = pkg_info_list[0]
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

    if isinstance(e, bb.event.BuildCompleted):
        import time
        start_time = time.time()
        start_ms = int((start_time % 1) * 1000)
        bb.note(f"Starting generate-rdke-component-info processing...")

        # Check if buildhistory is enabled
        inherit_val = e.data.getVar('INHERIT') or ''
        if 'buildhistory' not in inherit_val.split():
            bb.warn("Aborting since 'buildhistory' is not enabled which is required for data collection.")
            return

        # Get configuration variables
        buildhistory_dir = e.data.getVar('BUILDHISTORY_DIR')
        all_archs = e.data.getVar('ALL_MULTILIB_PACKAGE_ARCHS').split()

        # Get layer_package_arch with priority order for different layer types
        layer_package_arch = e.data.getVar('RDKE_GEN_DOC_LAYER_ARCH')

        if not layer_package_arch:
            # These shall be available in bitbake env. Check variables in ascending priority order
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
                    # Don't break - continue to get highest priority (last found)

        if not layer_package_arch:
            bb.warn("No layer architecture variable found. Skipping component info collection.")
            return

        tmpdir = e.data.getVar('TMPDIR')
        archs = [arch for arch in all_archs if arch == layer_package_arch]

        # Find candidate architecture directories
        packages_root = os.path.join(buildhistory_dir, "packages")
        candidate_dirs = []
        if os.path.isdir(packages_root):
            for d in os.listdir(packages_root):
                for arch in archs:
                    if arch in d:
                        candidate_dirs.append(d)
                        break

        if not candidate_dirs:
            bb.warn(f"No buildhistory package dir containing archs '{archs}', skipping.")
            return

        # Process each architecture directory
        for candidate_arch in candidate_dirs:
            arch_pkg_dir = os.path.join(packages_root, candidate_arch)

            if not os.path.isdir(arch_pkg_dir):
                bb.warn(f"No buildhistory package dir for candidate_arch {candidate_arch}, skipping.")
                continue

            pkgs = os.listdir(arch_pkg_dir)

            if not pkgs:
                bb.warn(f"No packages found for candidate_arch {candidate_arch}, skipping.")
                continue

            # Extract layer type for optimized file naming
            layer_type = extract_layer_type(candidate_arch)

            # Initialize architecture details with layer-type-based naming
            arch_details_file = os.path.join(tmpdir, f"{layer_type}-component-details.json")
            arch_pkg_details = {}

            if os.path.exists(arch_details_file):
                try:
                    with open(arch_details_file, 'r') as f:
                        arch_pkg_details = json.load(f)
                except Exception as ex:
                    bb.warn(f"Failed to load existing {arch_details_file}: {ex}")

            # Process each package sequentially
            for pkg_name in pkgs:
                latest_path = find_package_latest(buildhistory_dir, candidate_arch, pkg_name)
                if not latest_path:
                    bb.warn(f"No latest file for {pkg_name} in arch {candidate_arch}, skipping.")
                    continue

                pv, pr, srcuri = read_pv_pr_srcuri(latest_path)
                if not pv or not pr:
                    bb.warn(f"PV or PR missing for {pkg_name} in arch {candidate_arch}, skipping.")
                    continue

                # Read SRCREV information from latest_srcrev file
                package_dir = os.path.dirname(latest_path)
                latest_srcrev_path = os.path.join(package_dir, "latest_srcrev")
                srcrev_data = {}
                if os.path.exists(latest_srcrev_path):
                    srcrev_data = read_srcrev_info(latest_srcrev_path)

                package_info = {"pv": pv, "pr": pr, "srcuri": srcuri}
                if srcrev_data:
                    package_info["srcrev"] = srcrev_data

                arch_pkg_details[pkg_name] = [package_info]

            # Write architecture details to file with layer type naming
            try:
                with open(arch_details_file, 'w') as f:
                    json.dump(arch_pkg_details, f, indent=4)
                #bb.note(f"Created {arch_details_file}")
            except Exception as ex:
                bb.warn(f"Error writing {arch_details_file}: {ex}")

            # Create an MD file based on the arch_pkg_details with layer type naming
            create_component_version_md_file(layer_type, arch_pkg_details)

        end_time = time.time()
        end_ms = int((end_time % 1) * 1000)
        duration = end_time - start_time
        bb.note(f"generate-rdke-component-info processing complete. Duration: {duration:.3f} seconds")
}
