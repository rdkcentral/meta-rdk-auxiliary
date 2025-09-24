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
        bb.note(f"Looking for latest file for package {package_name} in arch {arch}")
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
        # buildhistory will be following the recipe specified PN but same recipe
        # may be providing more packages. Remove mlprefix from pkg_name if present
        search_pkg_name = pkg_name
        if mlprefix and pkg_name.startswith(mlprefix):
            search_pkg_name = pkg_name[len(mlprefix):]
        # Collect new entries in a global list attached to e.data
        if not hasattr(e.data, 'new_md_entries'):
            e.data.new_md_entries = []
        # Only add entry if pkg_name is not already present in md_file
        already_present = False
        if os.path.exists(md_file):
            with open(md_file, 'r') as f:
                for line in f:
                    if search_pkg_name in line:
                        already_present = True
                        break
        entry = f"| {pkg_name} | {pkg_version} |\n"
        if not already_present:
            with open(md_file, 'a') as wf:
                wf.write(entry)
                e.data.new_md_entries.append((md_file, entry))
                wf.close()
        else:
            bb.note(f"Entry for {pkg_name} already exists in {md_file}, skipping.")

    if isinstance(e, bb.event.BuildCompleted):
        bb.note("BuildCompleted event received. Starting collect-component-info processing...")
        buildhistory_dir = e.data.getVar('BUILDHISTORY_DIR')
        all_archs = e.data.getVar('ALL_MULTILIB_PACKAGE_ARCHS').split()
        package_arch = 'raspberrypi4-64-rdke-middleware'
        archs = [arch for arch in all_archs if arch == package_arch]
        bb.note(f"Filtered archs to PACKAGE_ARCH={package_arch}: {archs}")
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
                arch_details_path = os.path.join(tmpdir, f"{arch}-component-details.conf")
                arch_details = {}
                if os.path.exists(arch_details_path):
                    with open(arch_details_path, 'r') as f:
                        try:
                            arch_details = json.load(f)
                        except Exception as ex:
                            bb.warn(f"Failed to load existing {arch_details_path}: {ex}")
                for pkg_name in pkgs:
                    bb.note(f"Processing package {pkg_name} for arch {arch}, MLPREFIX: {mlprefix}")
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
        # After all packages processed, append all new entries to the MD file
        if hasattr(e.data, 'new_md_entries') and e.data.new_md_entries:
            md_file_entries = {}
            for md_file, entry in e.data.new_md_entries:
                md_file_entries.setdefault(md_file, []).append(entry)
            # Write all new_md_entries to a debug file in tmpdir for verification
            tmpdir = e.data.getVar('TMPDIR')
            debug_new_entries_path = os.path.join(tmpdir, 'collect-component-info-new-entries.txt')
            with open(debug_new_entries_path, 'w') as debug_f:
                for entries in md_file_entries.values():
                    for entry in entries:
                        debug_f.write(entry)
                debug_f.write("\n")
                debug_f.close()
            bb.note(f"Wrote new_md_entries to debug file: {debug_new_entries_path}")
            for md_file, entries in md_file_entries.items():
                if not os.path.exists(md_file):
                    bb.warn(f"MD file does not exist: {md_file}")
                    continue
                if not os.access(md_file, os.W_OK):
                    bb.warn(f"MD file is not writable: {md_file}")
                    continue
                with open(md_file, 'r') as f:
                    lines = f.readlines()
                # Find header
                insert_index = None
                for i, line in enumerate(lines):
                    if line.startswith('|--------------|'):
                        insert_index = i + 1
                        break
                if insert_index is not None:
                    lines[insert_index:insert_index] = entries
                    with open(md_file, 'w') as f:
                        f.writelines(lines)
                    bb.note(f"Appended {len(entries)} new entries to {md_file} after header.")
        bb.note("collect-component-info processing complete.")
}
