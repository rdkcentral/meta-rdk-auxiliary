# By default, cve_check.bbclass enables CVE report generation only when an image or a specific recipe is explicitly built as a target.
# This class extends that behavior to support CVE checks for packagegroup targets.
# It is particularly useful in RDKE-based stacks, where releases are typically driven by packagegroup recipes.

# Note: This class should be inherited **only** by packagegroup recipes as needed.
# Prerequisite: The cve_check.bbclass must be inherited globally (e.g., via USER_CLASSES or INHERIT) for this feature to function correctly.

# Enable CVE check for packagegroup target
#do_build[recrdeptask] += "${@'do_cve_check' if d.getVar('CVE_CHECK_CREATE_MANIFEST') == '1' else ''}"

python __anonymous() {
    import bb

    pn = d.getVar("PN")

    # Apply only if this is a packagegroup recipe
    if not pn.startswith("packagegroup"):
        bb.debug(1, "Skipping CVE check extension: %s is not a packagegroup recipe." %pn)
        return

    # Enable CVE check only if manifest generation is requested
    if d.getVar("CVE_CHECK_CREATE_MANIFEST") == "1":
        bb.note("Enabling do_cve_check for packagegroup target: %s" %pn)
        d.appendVarFlag("do_build", "recrdeptask", " do_cve_check")
}

