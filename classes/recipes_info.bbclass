
# recipes_info.bbclass

# === Configuration knobs ===
# Output file (default under TMPDIR)
PRINT_SRC_LOG_FILE ?= "${TMPDIR}/recipes_info.txt"

# Field delimiter (default ':'). Set to ',', '|', etc. as needed.
PRINT_SRC_DELIM ?= "#"

# Optional prefix to strip from the recipe path when deriving recipe_name.
# If empty, the class will use the basename of BB_FILENAME.
PRINT_SRC_RECIPE_PATH_PREFIX ?= ""

python do_print_recipes_info() {
    import os

    # Resolve configuration
    delim = d.getVar("PRINT_SRC_DELIM", True) or ":"
    log_file = d.getVar("PRINT_SRC_LOG_FILE", True) or os.path.join(d.getVar("TMPDIR", True), "recipes_info.txt")

    # Collect metadata
    pkg_pn   = d.getVar("PN", True) or ""
    pkg_pv   = d.getVar("PV", True) or ""
    pkg_pr   = d.getVar("PR", True) or ""
    pkg_pe   = d.getVar("PE", True) or ""
    pkg_arch = d.getVar("PACKAGE_ARCH", True) or ""
    bbfn     = d.getVar("BB_FILENAME", True) or ""

    # Derive recipe_name, with optional path prefix stripping
    prefix = d.getVar("PRINT_SRC_RECIPE_PATH_PREFIX", True) or ""
    recipe_name = bbfn
    try:
        if prefix:
            # Remove everything up to and including the first occurrence of "/{prefix}/"
            marker = f"/{prefix}/"
            if marker in bbfn:
                recipe_name = bbfn.split(marker, 1)[1]
            else:
                # Fallback to basename if prefix not found
                recipe_name = bbfn
        else:
            recipe_name = bbfn
    except Exception:
        recipe_name = os.path.basename(bbfn)

    # Build a stable, deduped SRC_URI string
    srcuri = d.getVar("SRC_URI", True) or ""
    src_list = sorted(set(srcuri.split()))
    srcuri_str = " ".join(src_list)

    # Prepare the line to write/update
    # Format: PN:PV-PR-PE:PACKAGE_ARCH:recipe_name:SRC_URI:SRCREV
    line_value = delim.join([
        pkg_pn,
        f"{pkg_pv}-{pkg_pr}-{pkg_pe}",
        pkg_arch,
        recipe_name,
        srcuri_str,
    ]) + "\n"

    # Ensure log file exists
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    if not os.path.exists(log_file):
        # Create empty file
        with open(log_file, "w"):
            pass

    # Read once, update or append
    updated = False
    lines = []
    with open(log_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Replace the line that starts with "PN<delim>"
    start_token = f"{pkg_pn}{delim}"
    for idx, line in enumerate(lines):
        if line.startswith(start_token):
            if line != line_value:
                lines[idx] = line_value
                updated = True
            else:
                # Already identical: nothing to do
                updated = False
            break
    else:
        # Not found; append
        lines.append(line_value)
        updated = True

    # Write only if changed
    if updated:
        with open(log_file, "w", encoding="utf-8") as f:
            f.writelines(lines)
}

# Ensure the task runs before fetch, so SRC_URI/SRCREV are available but
# we capture info early in the pipeline.
addtask do_print_recipes_info before do_fetch

