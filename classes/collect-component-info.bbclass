addhandler collect_component_info_eventhandler
collect_component_info_eventhandler[eventmask] = "bb.event.BuildCompleted"

python collect_component_info_eventhandler() {
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

    def create_component_version_md_file(candidate_arch, arch_pkg_details):
        tmpdir = e.data.getVar('TMPDIR')
        md_file = os.path.join(tmpdir, f'{candidate_arch}-PackagesAndVersions.md')

        try:
            # Extract package entries and create version strings
            all_entries = []
            for pkg_name, pkg_info_list in arch_pkg_details.items():
                if pkg_info_list and len(pkg_info_list) > 0:
                    pkg_info = pkg_info_list[0]
                    pv = pkg_info.get('pv', '')
                    pr = pkg_info.get('pr', '')
                    if pv and pr:
                        version = f"{pv}-{pr}"
                        # Keep full package name (including MLPREFIX) for display
                        display_name = pkg_name
                        all_entries.append((display_name, version))

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
                f.write(f'# {candidate_arch} - Packages and Versions\n\n')
                f.write('| Package Name | Version |\n')
                f.write('|--------------|---------|\n')

                # Write packagegroup entries first
                for pkg_name, version in pkg_group_entries:
                    f.write(f'| {pkg_name} | {version} |\n')

                # Write other entries
                for pkg_name, version in other_entries:
                    f.write(f'| {pkg_name} | {version} |\n')

            bb.note(f"Created Markdown file: {md_file} with {len(all_entries)} packages")

        except Exception as ex:
            bb.warn(f"Error creating Markdown file {md_file}: {ex}")

    if isinstance(e, bb.event.BuildCompleted):
        bb.note("BuildCompleted event received. Starting collect-component-info processing...")

        # Check if documentation generation is enabled
        generate_layer_component_doc = e.data.getVar('GENERATE_RDKE_LAYER_COMPONENT_DOC') or 'None'
        if not generate_layer_component_doc or generate_layer_component_doc == 'None':
            bb.note("GENERATE_RDKE_LAYER_COMPONENT_DOC is not set. Exiting collect-component-info handler.")
            return

        # Check if buildhistory is enabled
        inherit_val = e.data.getVar('INHERIT') or ''
        if 'buildhistory' not in inherit_val.split():
            bb.warn("Aborting since 'buildhistory' is not enabled which is required for data collection.")
            return

        # Get configuration variables
        buildhistory_dir = e.data.getVar('BUILDHISTORY_DIR')
        all_archs = e.data.getVar('ALL_MULTILIB_PACKAGE_ARCHS').split()
        layer_package_arch = e.data.getVar('RDKE_DOC_LAYER_TYPE') or e.data.getVar('MIDDLEWARE_ARCH')
        tmpdir = e.data.getVar('TMPDIR')
        bb.note(f"Specified layer_package_arch is {layer_package_arch}")
        archs = [arch for arch in all_archs if arch == layer_package_arch]
        bb.note(f"Filtered archs to layer_package_arch={layer_package_arch}: {archs}")

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
            bb.note(f"Looking for packages in {arch_pkg_dir} (arch dir: {candidate_arch})")

            if not os.path.isdir(arch_pkg_dir):
                bb.warn(f"No buildhistory package dir for candidate_arch {candidate_arch}, skipping.")
                continue

            pkgs = os.listdir(arch_pkg_dir)
            bb.note(f"Found packages for candidate_arch {candidate_arch}: {pkgs}")

            if not pkgs:
                bb.warn(f"No packages found for candidate_arch {candidate_arch}, skipping.")
                continue

            # Initialize architecture details
            arch_details_file = os.path.join(tmpdir, f"{candidate_arch}-component-details.json")
            arch_pkg_details = {}

            if os.path.exists(arch_details_file):
                try:
                    with open(arch_details_file, 'r') as f:
                        arch_pkg_details = json.load(f)
                except Exception as ex:
                    bb.warn(f"Failed to load existing {arch_details_file}: {ex}")

            # Process each package
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

            # Write architecture details to file
            try:
                with open(arch_details_file, 'w') as f:
                    json.dump(arch_pkg_details, f, indent=4)
                bb.note(f"Wrote component details for arch {candidate_arch} to {arch_details_file}")
            except Exception as ex:
                bb.warn(f"Error writing {arch_details_file}: {ex}")

            # Create an MD file based on the arch_pkg_details
            create_component_version_md_file(candidate_arch, arch_pkg_details)

        bb.note("collect-component-info processing complete.")
}
