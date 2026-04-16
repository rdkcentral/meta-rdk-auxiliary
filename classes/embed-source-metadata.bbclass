# embed-source-metadata.bbclass
#
# PURPOSE
#   Embeds the primary SRC_URI and SRCREV of every recipe as custom fields
#   ("Source-URI" and "Source-Rev") into the IPK control file for each
#   sub-package the recipe produces.
#
#   These fields survive through the build pipeline into:
#     - The feed's Packages.gz index
#     - Each individual .ipk file's CONTROL/control archive member
#     - ${IMAGE_ROOTFS}/var/lib/opkg/status on the assembled target
#
#   This makes the source provenance available to assembler builds that
#   consume pre-built IPKs from remote layer feeds and do not have access
#   to the original recipe files or PKGDATA_DIR.
#
# COUNTERPART
#   The assembler layer's manifest-srcuri.bbclass reads these fields from
#   the opkg status file to produce an enriched rootfs.manifest.
#
# USAGE
#   Add to the building layer's distro conf or local.conf:
#       INHERIT += "embed-source-metadata"
#
#   This must be active in every layer that builds IPKs destined for the
#   assembler feed.
#
# FIELD FORMAT IN IPK CONTROL
#   Source-URI: git://github.com/rdkcentral/rdk-generic.git
#   Source-Rev: a3b399c3deadbeef1234567890abcdef12345678
#
#   For tarball-only recipes (no SCM), Source-Rev will be "INVALID".
#   For recipes whose only SRC_URI entries are local patch/diff files,
#   Source-URI will be "unknown".
#
# SPDX-License-Identifier: Apache-2.0

# ---------------------------------------------------------------------------
#
# Normalisation rules applied per URI:
#   1. Skip all file:// entries (patches, diffs, config files, service units
#      etc.) -- none of these are remote source provenance.
#   2. If ;protocol=https (or ;protocol=http) is present, replace the
#      scheme in the URL with that protocol.  This handles the common
#      BitBake pattern:  git://github.com/...;protocol=https
#      which actually fetches over HTTPS.
#   3. Strip all remaining ;param=value fetch parameters.
#   4. Strip a trailing .git suffix for github.com / gitlab.com /
#      bitbucket.org URLs, matching the canonical web URL form.
#
# Example input SRC_URI:
#   git://github.com/rdkcentral/aamp.git;branch=main;protocol=https
#   git://github.com/foo/sub.git;branch=main;name=sub
#   file://0001-fix.patch
#   file://my-service.conf
#
# Example output:
#   https://github.com/rdkcentral/aamp https://github.com/foo/sub
#
# All file:// entries (patches, configs, service units, etc.) are skipped.
# ---------------------------------------------------------------------------
def _embed_all_src_uris(d):
    import re
    WEB_HOSTS = ('github.com', 'gitlab.com', 'bitbucket.org')
    uris = []
    for entry in (d.getVar('SRC_URI') or '').split():
        # Skip all local file:// entries – config files, service units, patches
        # etc. are not remote source provenance and must not appear in the
        # Source-URI field that flows into the Packages index / manifest.
        if entry.startswith('file://'):
            continue
        parts = entry.split(';')
        url   = parts[0]
        params = {p.split('=')[0]: p.split('=', 1)[1]
                  for p in parts[1:] if '=' in p}

        # Apply ;protocol= to the URL scheme when present
        protocol = params.get('protocol', '')
        if protocol in ('https', 'http'):
            url = re.sub(r'^[a-z+]+://', protocol + '://', url)

        # Strip trailing .git for well-known web hosting services
        # and force https:// since git:// is not web-browsable on these hosts.
        try:
            host = url.split('://')[1].split('/')[0]
        except IndexError:
            host = ''
        if any(host.endswith(h) for h in WEB_HOSTS):
            url = re.sub(r'^[a-z+]+://', 'https://', url)
            url = re.sub(r'\.git$', '', url)

        uris.append(url)
    return ' '.join(uris) if uris else 'unknown'

# ---------------------------------------------------------------------------
# Helper: return all SCM revisions in a compact, parseable form.
#
# Three cases handled:
#
# 1. Single unnamed repo  (SRCREV = "abc123")
#    Output:  abc123
#
# 2. Single named repo    (SRCREV_main = "abc123", SRCREV_FORMAT = "main")
#    Output:  main=abc123
#
# 3. Multiple named repos (SRCREV_main = "abc123", SRCREV_sub = "def456",
#                          SRCREV_FORMAT = "main_sub")
#    Output:  main=abc123 sub=def456
#
# The name= pairs format is directly readable by humans and parsers alike.
# The manifest-srcuri.bbclass on the assembler side stores this verbatim.
# ---------------------------------------------------------------------------
def _embed_all_srcrevs(d):
    src_uris = (d.getVar('SRC_URI') or '').split()

    # Collect all name= values from SRC_URI fetch parameters
    names = []
    for uri in src_uris:
        for param in uri.split(';')[1:]:
            if param.startswith('name='):
                name = param[5:]
                if name and name not in names:
                    names.append(name)

    if names:
        # Named SRCREVs - emit as "name=rev" pairs
        pairs = []
        for name in names:
            rev = d.getVar('SRCREV_%s' % name) or 'INVALID'
            pairs.append('%s=%s' % (name, rev))
        return ' '.join(pairs)
    else:
        # Single unnamed SRCREV (or tarball-only recipe)
        return d.getVar('SRCREV') or 'INVALID'

# ---------------------------------------------------------------------------
# Append two custom fields to every IPK control file.
# PACKAGE_ADD_METADATA_IPK accepts newline-separated "Key: value" strings
# (see package.bbclass -> get_package_additional_metadata).
# Using :append so we do not overwrite any existing custom metadata.
#
# Fields added to each IPK CONTROL/control:
#   Source-URI: <space-separated list of all non-patch source URLs>
#   Source-Rev: <rev>  |  <name1=rev1 name2=rev2 ...>
# ---------------------------------------------------------------------------
PACKAGE_ADD_METADATA_IPK:append = "\nSource-URI: ${@_embed_all_src_uris(d)}\nSource-Rev: ${@_embed_all_srcrevs(d)}"
