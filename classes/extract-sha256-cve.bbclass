#extract-sha256-cve.bbclass
#
# Extracts SHA256 checksums for CVE layer feed entries at parse time.
#
# For each entry in CVE_LAYER_FEED_PATH this class:
#   1. Extracts the artifact URL (the portion after ## and before ;)
#   2. Fetches the SHA256 from the X-Checksum-Sha256 using Wget's --spider option
#   3. Sets the corresponding BitBake variable in the current datastore
#   4. Appends  VAR = "SHA"  to ${TOPDIR}/conf/dynamic_sha.inc so the
#      value is available to subsequent bitbake invocations as well
#
# Expected CVE_LAYER_FEED_PATH entry format:
#   <name>##<url>;<param>;sha256sum=${VAR_NAME}[;<more-params>]
#
# Usage:
#   inherit extract-sha256-cve   (in an image recipe or distro conf)
#
# The generated include is shared by all variants in the cooker. The network
# fetch runs only when the include does not exist; subsequent parses load the
# same values into their datastores.

python () {
    import os
    import re
    import shlex
    import bb
    import bb.fetch2

    # Skip if cve-check is not enabled
    inherit_classes = (d.getVar("INHERIT") or "").split()
    if "cve-check" not in inherit_classes:
        bb.debug(
            1,
            "extract-sha256-cve: cve-check not enabled, skipping"
        )
        return
    topdir = d.getVar("TOPDIR")
    inc_file = os.path.join(topdir, "conf", "dynamic_sha.inc")

    def load_dynamic_sha():
        if not os.path.exists(inc_file):
            return False
        with open(inc_file, "r") as sha_file:
            for line in sha_file:
                match = re.match(r'\s*([A-Za-z0-9_:+.-]+)\s*=\s*"([^"]+)"', line)
                if match:
                    d.setVar(match.group(1), match.group(2))
        return True

    # Reuse the same values for normal and multilib variants.
    if load_dynamic_sha():
        bb.debug(1, "extract-sha256-cve: reusing dynamic_sha.inc")
        return

    #
    # Get CVE feed path
    #
    cve_layer_feed_path = d.getVar("CVE_LAYER_FEED_PATH")
 
    if not cve_layer_feed_path or not cve_layer_feed_path.strip():
        bb.debug(
            1,
            "extract-sha256-cve: CVE_LAYER_FEED_PATH is not set, "
            "nothing to do"
        )
        return
 
    bb.note(
        "extract-sha256-cve: generating CVE feed SHA256 checksums -> %s"
        % inc_file
    )
 
    generated_values = []

    def get_sha256_from_artifact(url):
 
        #
        # Use BitBake's configured wget command if available.
        #
        wget_cmd = d.getVar("FETCHCMD_wget")
        if not wget_cmd:
            wget_cmd = "/usr/bin/env wget"
 
        # Quote URL so special characters in the URL cannot affect
        # the shell command.
        #
        quoted_url = shlex.quote(url)
 
        cmd = (
            "%s --spider --server-response %s 2>&1"
            % (wget_cmd, quoted_url)
        )
 
        bb.debug(
            1,
            "extract-sha256-cve: executing: %s"
            % cmd
        )
 
        try:
            #
            # Execute through BitBake's fetch command infrastructure.
            #
            output = bb.fetch2.runfetchcmd(
                cmd,
                d,
                quiet=True
            )
 
        except Exception as exc:
            bb.warn(
                "extract-sha256-cve: failed to access URL %s: %s"
                % (url, exc)
            )
            return None
 
        #
        # Look for:
        #
        # X-Checksum-Sha256: <64 hexadecimal characters>
        #
        sha_match = re.search(
            r'X-Checksum-Sha256:\s*([0-9a-fA-F]{64})',
            output,
            re.IGNORECASE
        )
 
        if not sha_match:
            bb.warn(
                "extract-sha256-cve: X-Checksum-Sha256 header "
                "not found for URL: %s"
                % url
            )
            return None
 
        sha = sha_match.group(1).lower()
 
        bb.debug(
            1,
            "extract-sha256-cve: SHA256 for %s = %s"
            % (url, sha)
        )
 
        return sha

    # Process every CVE feed entry
    #
    for entry in cve_layer_feed_path.split():
 
        entry = entry.strip()
 
        if not entry:
            continue
 
        #
        # Expected format:
        #
        # feedname##https://example.com/foo.xml;sha256sum=${FEED_SHA}
        #
        # Extract URL between ## and ;
        #
        url_match = re.search(
            r'##([^;]+)',
            entry
        )
 
        if not url_match:
            bb.warn(
                "extract-sha256-cve: cannot parse URL from entry: %s"
                % entry
            )
            continue
 
        url = url_match.group(1).strip()
 
        #
        # Extract variable name from:
        #
        # sha256sum=${VAR_NAME}
        #
        var_match = re.search(
            r'sha256sum=\$\{([^}]+)\}',
            entry
        )
 
        if not var_match:
            bb.warn(
                "extract-sha256-cve: cannot parse sha256sum variable "
                "from entry: %s"
                % entry
            )
            continue
 
        var_name = var_match.group(1).strip()
 
        bb.debug(
            1,
            "extract-sha256-cve: processing %s -> %s"
            % (var_name, url)
        )
 
        #
        # Get SHA256 from Artifactory response header.
        #
        sha = get_sha256_from_artifact(url)
 
        if not sha:
            bb.warn(
                "extract-sha256-cve: failed to obtain SHA for "
                "%s (%s) - skipping entry"
                % (var_name, url)
            )
            continue
        generated_values.append('%s = "%s"\n' % (var_name, sha))
 
        #
        # Set the variable in the current datastore as well.
        #
        d.setVar(var_name, sha)
 
        bb.debug(
            1,
            "extract-sha256-cve: %s = %s"
            % (var_name, sha)
        )

    temporary_file = inc_file + ".tmp"
    with open(temporary_file, "w") as sha_file:
        sha_file.writelines(generated_values)
    os.replace(temporary_file, inc_file)
}