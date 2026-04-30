# embed-source-metadata.bbclass
#
# Embeds source provenance fields (Source-URI, Source-Rev) into the IPK
# control file for every sub-package a recipe produces.  These fields
# are preserved through the build pipeline into the feed's Packages index
# and each .ipk's CONTROL/control member, making source metadata available
# to assembler builds that consume pre-built IPKs without access to the
# original recipe files.
#
# Source-URI: all non-file:// SRC_URI entries, normalised to HTTPS URLs
#   where possible (web-hosting services and ;protocol=https URIs).
# Source-Rev: SRCREV value(s), including named SRCREVs where present.
#
# Counterpart: manifest-srcuri.bbclass (assembler layer) consumes these
# fields from the feed Packages index to produce an enriched rootfs.manifest.
#
# Usage:
#   INHERIT += "embed-source-metadata"  (in the building layer's conf)
#
# Author: Arjun <arjun_daasuramdass@comcast.com>

# ---------------------------------------------------------------------------
# Helper: return all non-file:// source URIs, space-separated,
# normalised to web-browsable HTTPS URLs.
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
    from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
    WEB_HOSTS = ('github.com', 'gitlab.com', 'bitbucket.org')
    SECRET_QUERY_KEYS = {
        'access_token', 'api_key', 'apikey', 'auth', 'awsaccesskeyid',
        'key', 'password', 'passwd', 'signature', 'sig', 'token',
        'x-amz-credential', 'x-amz-security-token', 'x-amz-signature',
    }
    def _sanitize_url(url):
        parsed = urlsplit(url)
        # Remove any embedded userinfo (username[:password]@) from the URL.
        netloc = parsed.hostname or ''
        if parsed.port is not None:
            netloc = '%s:%s' % (netloc, parsed.port)
        # Remove common secret-bearing query parameters.
        query = urlencode(
            [(k, v) for (k, v) in parse_qsl(parsed.query, keep_blank_values=True)
             if k.lower() not in SECRET_QUERY_KEYS],
            doseq=True,
        )
        return urlunsplit((parsed.scheme, netloc, parsed.path, query, ''))
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
        # Use urlsplit().hostname to correctly handle userinfo (e.g.
        # ssh://git@github.com/...) without misidentifying git@github.com
        # as the hostname when splitting on ://.
        host = urlsplit(url).hostname or ''
        if any(host == h or host.endswith('.' + h) for h in WEB_HOSTS):
            url = re.sub(r'^[a-z+]+://', 'https://', url)
            url = re.sub(r'\.git$', '', url)

        uris.append(_sanitize_url(url))
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
            rev = d.getVar('SRCREV_%s' % name) or ''
            pairs.append('%s=%s' % (name, rev))
        return ' '.join(pairs)
    else:
        # Single unnamed SRCREV (or tarball-only recipe)
        return d.getVar('SRCREV') or ''

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

