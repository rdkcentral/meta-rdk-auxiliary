#extract-sha256-cve.bbclass
#
# Extracts SHA256 checksums for CVE layer feed entries at parse time.
#
# For each entry in CVE_LAYER_FEED_PATH this class:
#   1. Extracts the artifact URL (the portion after ## and before ;)
#   2. Fetches the SHA256 from the X-Checksum-Sha256 HTTP response header
#      (mirrors the curl --netrc -sI -L behaviour of generate_sha256.sh)
#   3. Sets the corresponding BitBake variable in the current datastore
#   4. Appends  VAR = "SHA"  to ${TOPDIR}/conf/dynamic_sha.inc so the
#      value is available to subsequent bitbake invocations as well
#
# Expected CVE_LAYER_FEED_PATH entry format:
#   <name>##<url>;<param>;sha256sum=${VAR_NAME}[;<more-params>]
#
# Usage:
#   inherit extract-sha256-cve   (in an image recipe or distro conf)
# or
#   INHERIT += "extract-sha256-cve"  (in local.conf)
#
# The generated include is shared by all variants in the cooker. The network
# fetch runs only when the include does not exist; subsequent parses load the
# same values into their datastores.

python () {
    import os
    import hashlib
    import re
    import urllib.request
    import urllib.parse

    # skip cve-check is not enabled 
    inherit_classes = (d.getVar("INHERIT") or"").split()
    if "cve-check" not in inherit_classes:
        bb.debug(1,"extract-sha256-cve:cve-check not enabled ,skipping")
        return

    topdir = d.getVar('TOPDIR')
    inc_file = os.path.join(topdir, 'conf', 'dynamic_sha.inc')
    cve_layer_feed_path = d.getVar('CVE_LAYER_FEED_PATH') or ''
    if not cve_layer_feed_path.strip():
        bb.debug(1, "extract-sha256-cve: CVE_LAYER_FEED_PATH is not set, nothing to do")
        return

    feed_fingerprint = hashlib.sha256(cve_layer_feed_path.encode()).hexdigest()

    def load_dynamic_sha():
        if not os.path.exists(inc_file):
            return False
        with open(inc_file, 'r') as sha_file:
            lines = sha_file.readlines()
        if not lines or lines[0].strip() != '# feed-path-sha256: %s' % feed_fingerprint:
            return False
        for line in lines[1:]:
            match = re.match(r'\s*([A-Za-z0-9_:+.-]+)\s*=\s*"([^"]+)"', line)
            if match:
                d.setVar(match.group(1), match.group(2))
        return True

    # Reuse the same values for normal and multilib variants.
    if load_dynamic_sha():
        bb.debug(1, "extract-sha256-cve: reusing dynamic_sha.inc")
        return

    bb.note("extract-sha256-cve: generating CVE feed SHA256 checksums -> %s" % inc_file)

    generated_values = ['# feed-path-sha256: %s\n' % feed_fingerprint]

    for entry in cve_layer_feed_path.split():
        entry = entry.strip()
        if not entry:
            continue

        # Extract URL: the segment after ## up to the first ;
        # e.g.  feedname##https://example.com/feed.xml;sha256sum=${FEED_SHA}
        url_match = re.search(r'##([^;]+)', entry)
        if not url_match:
            bb.warn("extract-sha256-cve: cannot parse URL from entry: %s" % entry)
            continue
        url = url_match.group(1).strip()

        # Extract the BitBake variable name from  sha256sum=${VAR_NAME}
        var_match = re.search(r'sha256sum=\$\{([^}]+)\}', entry)
        if not var_match:
            bb.warn("extract-sha256-cve: cannot parse sha256sum variable from entry: %s" % entry)
            continue
        var_name = var_match.group(1).strip()

        # Perform a HEAD request and read the X-Checksum-Sha256 header.
        # Honour ~/.netrc credentials when present (mirrors curl --netrc).
        sha = None
        try:
            req = urllib.request.Request(url, method='HEAD')

            netrc_path = os.path.expanduser('~/.netrc')
            if os.path.exists(netrc_path):
                try:
                    import netrc as netrc_module
                    import base64
                    parsed = urllib.parse.urlparse(url)
                    creds = netrc_module.netrc(netrc_path).authenticators(parsed.hostname)
                    if creds:
                        token = base64.b64encode(
                            ('%s:%s' % (creds[0], creds[2])).encode()
                        ).decode()
                        req.add_header('Authorization', 'Basic %s' % token)
                except Exception:
                    pass  # netrc parse failure is non-fatal


            with urllib.request.urlopen(req, timeout=30) as resp:
                sha = (resp.headers.get('X-Checksum-Sha256') or '').strip()

        except Exception as exc:
            bb.warn("extract-sha256-cve: failed to fetch SHA for %s (%s) - skipping entry: %s"
                    % (var_name, url, exc))
            continue

        if not sha:
            bb.warn("extract-sha256-cve: empty X-Checksum-Sha256 header for %s (%s) - skipping entry"
                    % (var_name, url))
            continue

        generated_values.append('%s = "%s"\n' % (var_name, sha))

        # Also set the value in the current datastore for immediate use
        d.setVar(var_name, sha)

        bb.debug(1, "extract-sha256-cve: %s = %s" % (var_name, sha))

    temporary_file = inc_file + '.tmp'
    with open(temporary_file, 'w') as sha_file:
        sha_file.writelines(generated_values)
    os.replace(temporary_file, inc_file)
}
