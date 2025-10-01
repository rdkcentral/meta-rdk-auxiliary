addhandler collect_component_info_eventhandler
collect_component_info_eventhandler[eventmask] = "bb.event.BuildCompleted"

python collect_component_info_eventhandler() {
    import os
    import json

    def find_package_latest(buildhistory_dir, arch, package_name):
        """Find the latest file for a package in buildhistory directories."""
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
        """Extract PV, PR, and SRC_URI from buildhistory latest file."""
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

                # Store package details
                arch_pkg_details[pkg_name] = [{"pv": pv, "pr": pr, "srcuri": srcuri}]

            # Write architecture details to file
            try:
                with open(arch_details_file, 'w') as f:
                    json.dump(arch_pkg_details, f, indent=4)
                bb.note(f"Wrote component details for arch {candidate_arch} to {arch_details_file}")
            except Exception as ex:
                bb.warn(f"Error writing {arch_details_file}: {ex}")

        bb.note("collect-component-info processing complete.")
}
