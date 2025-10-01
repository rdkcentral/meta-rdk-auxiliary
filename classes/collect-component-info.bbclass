addhandler collect_component_info_eventhandler
collect_component_info_eventhandler[eventmask] = "bb.event.BuildCompleted"

python collect_component_info_eventhandler() {
    import os
    import time

    # MLPREFIX may not be set in the event environment since this is triggered at the very end.
    mlprefix = e.data.getVar('MLPREFIX') or 'lib32-'

    def wait_for_md_files(md_files, timeout=30):
        bb.note(f"Waiting for MD files: {md_files} with timeout {timeout}s")
        start = time.time()
        while time.time() - start < timeout:
            missing = [f for f in md_files if not os.path.exists(f)]
            if not missing:
                bb.note(f"All MD files found: {md_files}")
                return True
            bb.note(f"Still waiting for: {missing}")
            time.sleep(1)
        bb.warn(f"Timeout waiting for MD files: {md_files}")
        return False

    def get_md_files(d):
        bb.note("Getting list of PackagesAndVersions.md files for all arches...")
        deploy_dir_ipk = d.getVar('DEPLOY_DIR_IPK')
        archs = d.getVar("ALL_MULTILIB_PACKAGE_ARCHS").split()
        md_files = []
        for arch in archs:
            target_dir = os.path.join(deploy_dir_ipk, arch)
            output_file = os.path.join(target_dir, "PackagesAndVersions.md")
            md_files.append(output_file)
            #bb.note(f"Expecting MD file for arch {arch}: {output_file}")
        return md_files

    def find_package_latest(buildhistory_dir, arch, package_name):
        #bb.note(f"Looking for latest file for package {package_name} in arch {arch}")
        # Enhanced: find any directory under buildhistory_dir/packages that contains arch in its name
        packages_root = os.path.join(buildhistory_dir, "packages")
        candidate_dirs = []
        if os.path.isdir(packages_root):
            for d in os.listdir(packages_root):
                if arch in d:
                    candidate_dirs.append(d)
        found = False
        for candidate_arch in candidate_dirs:
            package_dir = os.path.join(packages_root, candidate_arch, package_name)
            latest_path = os.path.join(package_dir, "latest")
            if os.path.exists(latest_path):
                #bb.note(f"Found latest file: {latest_path} (arch dir: {candidate_arch})")
                return latest_path
        # Fallback to original logic if nothing found
        package_dir = os.path.join(packages_root, arch, package_name)
        latest_path = os.path.join(package_dir, "latest")
        if os.path.exists(latest_path):
            #bb.note(f"Found latest file: {latest_path} (direct arch match)")
            return latest_path
        bb.warn(f"Latest file not found for {package_name} in any arch dir containing '{arch}'")
        return None
        latest_path = os.path.join(package_dir, "latest")
        if os.path.exists(latest_path):
            #bb.note(f"Found latest file: {latest_path}")
            return latest_path
        else:
            bb.warn(f"Latest file not found: {latest_path}")
            return None

    def read_pv_pr_srcuri(latest_path):
        bb.note(f"Reading PV/PR/SRC_URI from: {latest_path}")
        pv = pr = srcuri = None
        with open(latest_path, 'r') as f:
            for line in f:
                if line.startswith('PV ='):
                    pv = line.split('=', 1)[1].strip()
                elif line.startswith('PR ='):
                    pr = line.split('=', 1)[1].strip()
                elif line.startswith('SRC_URI ='):
                    srcuri = line.split('=', 1)[1].strip()
        #bb.note(f"Extracted PV={pv}, PR={pr}, SRC_URI={srcuri} from {latest_path}")
        return pv, pr, srcuri

    def update_md_table(md_file, pkg_name, pkg_version):
        # Collect package info in a dict attached to e.data
        if not hasattr(e.data, 'pkg_version_dict'):
            e.data.pkg_version_dict = {}
        search_pkg_name = pkg_name
        if mlprefix and pkg_name.startswith(mlprefix):
            search_pkg_name = pkg_name[len(mlprefix):]
        # Update dict if exists, else add new
        if search_pkg_name in e.data.pkg_version_dict:
            e.data.pkg_version_dict[search_pkg_name] = pkg_version
            bb.note(f"Updated entry for {search_pkg_name}: {pkg_version}")
        else:
            e.data.pkg_version_dict[search_pkg_name] = pkg_version
            bb.note(f"Added entry for {search_pkg_name}: {pkg_version}")

    if isinstance(e, bb.event.BuildCompleted):
        bb.note("BuildCompleted event received. Starting collect-component-info processing...")
        machine_name = e.data.getVar('MACHINE')
        deploy_ipk_feed = e.data.getVar('DEPLOY_IPK_FEED') or 'None'
        generate_ipk_version_doc = e.data.getVar('GENERATE_IPK_VERSION_DOC') or 'None'
        generate_layer_component_doc = e.data.getVar('GENERATE_RDKE_LAYER_COMPONENT_DOC') or 'None'
        bb.note(f"DEPLOY_IPK_FEED: {deploy_ipk_feed}")
        bb.note(f"GENERATE_IPK_VERSION_DOC: {generate_ipk_version_doc}")
        # exit if generate_ipk_version_doc is None
        if not generate_layer_component_doc or generate_layer_component_doc == 'None':
            bb.note("GENERATE_RDKE_LAYER_COMPONENT_DOC is not set. Exiting collect-component-info handler.")
            return
        buildhistory_dir = e.data.getVar('BUILDHISTORY_DIR')
        all_archs = e.data.getVar('ALL_MULTILIB_PACKAGE_ARCHS').split()
        package_arch = e.data.getVar('RDKE_DOC_LAYER_TYPE') or e.data.getVar('MIDDLEWARE_ARCH')
        bb.note(f"Specified package_arch is {package_arch}")
        archs = [arch for arch in all_archs if arch == package_arch]
        bb.note(f"Filtered archs to PACKAGE_ARCH={package_arch}: {archs}")
        # check if INHERIT contain 'buildhistory' word because it is needed for proceeding further.
        inherit_val = e.data.getVar('INHERIT') or ''
        if 'buildhistory' not in inherit_val.split():
            bb.warn("Aborting since 'buildhistory' is not enabled.")
            return
        md_files = get_md_files(e.data)
        md_file_map = {arch: md_file for arch, md_file in zip(all_archs, md_files) if arch in archs and os.path.exists(md_file)}
        bb.note(f"Found MD files for PACKAGE_ARCH: {list(md_file_map.keys())}")
        if not md_file_map:
            bb.warn("No PackagesAndVersions.md files found for PACKAGE_ARCH.")
            return
        for arch, md_file in md_file_map.items():
            bb.note(f"Processing arch {arch} with MD file {md_file}")
            packages_root = os.path.join(buildhistory_dir, "packages")
            candidate_dirs = []
            if os.path.isdir(packages_root):
                for d in os.listdir(packages_root):
                    if arch in d:
                        candidate_dirs.append(d)
            if not candidate_dirs:
                bb.warn(f"No buildhistory package dir containing arch '{arch}', skipping.")
                continue
            for candidate_arch in candidate_dirs:
                arch_pkg_dir = os.path.join(packages_root, candidate_arch)
                bb.note(f"Looking for packages in {arch_pkg_dir} (arch dir: {candidate_arch})")
                if not os.path.isdir(arch_pkg_dir):
                    bb.warn(f"No buildhistory package dir for arch {arch} (candidate: {candidate_arch}), skipping.")
                    continue
                pkgs = os.listdir(arch_pkg_dir)
                bb.note(f"Found packages for arch {arch} (candidate: {candidate_arch}): {pkgs}")
                if not pkgs:
                    bb.warn(f"No packages found for arch {arch} (candidate: {candidate_arch}), skipping.")
                    continue
                import json
                tmpdir = e.data.getVar('TMPDIR')
                arch_details_path = os.path.join(tmpdir, f"{arch}-component-details.json")
                arch_details = {}
                if os.path.exists(arch_details_path):
                    with open(arch_details_path, 'r') as f:
                        try:
                            arch_details = json.load(f)
                        except Exception as ex:
                            bb.warn(f"Failed to load existing {arch_details_path}: {ex}")
                for pkg_name in pkgs:
                    #bb.note(f"Processing package {pkg_name} for arch {arch}, MLPREFIX: {mlprefix}")
                    latest_path = find_package_latest(buildhistory_dir, arch, pkg_name)
                    if not latest_path:
                        bb.warn(f"No latest file for {pkg_name} in arch {arch}, skipping.")
                        continue
                    pv, pr, srcuri = read_pv_pr_srcuri(latest_path)
                    if not pv or not pr:
                        bb.warn(f"PV or PR missing for {pkg_name} in arch {arch}, skipping.")
                        continue
                    pkg_version = f"{pv}-{pr}"
                    bb.note(f"updating md file for {pkg_name} and {pkg_version}")
                    update_md_table(md_file, pkg_name, pkg_version)
                    # Write details to arch-details file
                    arch_details[pkg_name] = [{"pv": pv, "pr": pr, "srcuri": srcuri}]
                with open(arch_details_path, 'w') as f:
                    json.dump(arch_details, f, indent=4)
                    f.close()
                bb.note(f"Wrote component details for arch {arch} to {arch_details_path}")
        # After all packages processed, batch write all entries to a new sorted MD file
        if hasattr(e.data, 'pkg_version_dict') and e.data.pkg_version_dict:
            tmpdir = e.data.getVar('TMPDIR')
            new_md_file = os.path.join(tmpdir, 'CompleteMiddlewarePackagesAndVersions.md')
            all_entries = list(e.data.pkg_version_dict.items())
            # Separate packagegroup-* entries
            pkg_group_entries = [(pkg_name, pkg_version) for pkg_name, pkg_version in all_entries if pkg_name.startswith('packagegroup-')]
            other_entries = [(pkg_name, pkg_version) for pkg_name, pkg_version in all_entries if not pkg_name.startswith('packagegroup-')]
            # Sort both lists alphabetically
            pkg_group_entries.sort()
            other_entries.sort()
            with open(new_md_file, 'w') as f:
                f.write('| Package Name | Version |\n')
                f.write('|--------------|---------|\n')
                for pkg_name, pkg_version in pkg_group_entries + other_entries:
                    f.write(f'| {pkg_name} | {pkg_version} |\n')
            bb.note(f"Wrote sorted package/version entries to new MD file: {new_md_file}")
        bb.note("collect-component-info processing complete.")
}
