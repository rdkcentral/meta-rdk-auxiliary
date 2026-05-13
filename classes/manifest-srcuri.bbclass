# manifest-srcuri.bbclass
#
# Enriches rootfs.manifest with Recipe, Source-URI, and Source-Rev for each
# installed package.  Reads source metadata from two complementary sources:
#
#   - Assembler builds: ${TMPDIR}/ipk_pkgdata/feed_info/index/<feed-name>
#     (Packages indexes downloaded from remote opkg feeds)
#   - Local builds:     ${WORKDIR}/oe-rootfs-repo/<arch>/Packages
#     (repo assembled by poky inside do_rootfs, indexed with -f)
#
# Both sources are merged; where a package appears in both, the local
# oe-rootfs-repo entry wins so the most-recently-built metadata takes
# precedence.
#
# Output columns in rootfs.manifest:
#   Package  Arch  Version  Recipe  Source-URI  Source-Rev
#
# Source-URI / Source-Rev are populated only when the building layer
# inherits embed-source-metadata.bbclass.  For git-based packages whose
# version string embeds a short hash (e.g. 1.0+git0+7c6608d0db-r1) the
# hash is extracted automatically as a partial fallback.
#
# Usage:
#   INHERIT += "manifest-srcuri"  (in local.conf or image conf)
#
# Author: Arjun <arjun_daasuramdass@comcast.com>

# ---------------------------------------------------------------------------
# Helper -- parse all feed index files and return a dict keyed by
# (Package, Version, Architecture) 3-tuple.
# Each value is a dict of the fields from that package's stanza.
#
# Two sources are scanned so both build modes are covered:
#
#   1. Assembler mode (remote IPK feeds):
#        ${TMPDIR}/ipk_pkgdata/feed_info/index/<feed-name>
#      These are the Packages indexes downloaded from remote opkg feeds
#      (Artifactory).  Present in assembler builds; absent in local builds.
#
#   2. Local build mode (oe-rootfs-repo):
#        ${WORKDIR}/oe-rootfs-repo/<arch>/Packages
#      Poky assembles this temporary repo inside do_rootfs from the locally
#      built IPKs before installing them.  It is always present when
#      manifest_srcuri_enrich runs (DEPLOY_DIR_IPK/Packages may not exist
#      yet because do_package_index can run after do_rootfs).
#
# Both sources are merged into one dict.  Where a package appears in both
# (e.g. a remote sstate hit plus a local override), the oe-rootfs-repo entry
# wins (scanned last) so the most-recently-built metadata takes precedence.
# ---------------------------------------------------------------------------
def _parse_feed_indexes(tmpdir, oe_rootfs_repo):
    import os
    import glob

    pkg_meta = {}

    def _parse_file(index_file):
        current = {}
        with open(index_file, 'r', errors='replace') as f:
            for line in f:
                line = line.rstrip('\n')
                if line == '':
                    if 'Package' in current and 'Version' in current and 'Architecture' in current:
                        key = (current['Package'], current['Version'], current['Architecture'])
                        pkg_meta[key] = current
                    current = {}
                elif ': ' in line:
                    key, _, val = line.partition(': ')
                    current[key.strip()] = val.strip()
        if 'Package' in current and 'Version' in current and 'Architecture' in current:
            key = (current['Package'], current['Version'], current['Architecture'])
            pkg_meta[key] = current

    # Source 1: remote feed indexes (assembler pattern)
    index_dir = os.path.join(tmpdir, 'ipk_pkgdata', 'feed_info', 'index')
    for index_file in glob.glob(os.path.join(index_dir, '*')):
        if os.path.isfile(index_file):
            _parse_file(index_file)

    # Source 2: oe-rootfs-repo Packages indexes (local build pattern).
    # Poky assembles this repo inside do_rootfs and indexes it with -f,
    # so Source-URI / Source-Rev fields are preserved.  Always available
    # when manifest_srcuri_enrich runs, unlike DEPLOY_DIR_IPK which may
    # not be indexed yet (do_package_index can run after do_rootfs).
    if oe_rootfs_repo and os.path.isdir(oe_rootfs_repo):
        for packages_file in glob.glob(os.path.join(oe_rootfs_repo, '*', 'Packages')):
            if os.path.isfile(packages_file):
                _parse_file(packages_file)

    return pkg_meta

# ---------------------------------------------------------------------------
# Helper -- try to extract a short SRCREV hash from a BitBake version string.
# Handles AUTOINC / git fetcher patterns, e.g.:
#   1.0+git0+7c6608d0db-r1         -> 7c6608d0db
#   20211102.0+git0+7c6608d0db-r1  -> 7c6608d0db
#   1.10+git+0+0f1b43536d-r0       -> 0f1b43536d
#   1.2.1gitr+0+18c4c982a5-r0      -> 18c4c982a5
#   1.2.3+gitAUTOINC+18c4c982a5-r0 -> 18c4c982a5
#   25.lts+git0+abc123_def456-r30  -> abc123_def456 (multi-SRCREV, hex only)
# Returns None when no hash is found (plain version or bare git-r0).
# ---------------------------------------------------------------------------
def _srcrev_from_version(ver):
    import re
    # Match git/gitr marker with optional AUTOINC, +N, or bare digit suffix,
    # followed by + and the hex hash.  Negative lookbehind prevents matching
    # 'git' inside longer words (e.g. 'digital').
    m = re.search(r'(?<![a-zA-Z])git[rR]?(?:AUTOINC|\+[0-9]+|[0-9]*)?\+([0-9a-f][0-9a-f_]+)', ver)
    if m:
        return m.group(1)
    return None

# ---------------------------------------------------------------------------
# Enrich the rootfs manifest with source metadata.
#
# Hooked via ROOTFS_POSTUNINSTALL_COMMAND:append so it runs AFTER poky's
# write_image_manifest (from rootfs-postcommands.bbclass).  Defining the
# function as a plain "python write_image_manifest()" would be silently
# overridden by poky's version because image recipe inherits
# rootfs-postcommands.bbclass AFTER the global INHERIT is processed, so
# poky's definition always wins the last-parsed-wins rule.
#
# By appending our own uniquely-named function to the post-uninstall
# command list we avoid the naming conflict entirely.  Our function runs
# after poky has written the basic 3-column manifest and overwrites it
# with the enriched 6-column version.
# ---------------------------------------------------------------------------

ROOTFS_POSTUNINSTALL_COMMAND:append = " manifest_srcuri_enrich ; "

python manifest_srcuri_enrich() {
    import os
    from oe.rootfs import image_list_installed_packages

    deploy_dir    = d.getVar('IMGDEPLOYDIR')
    link_name     = d.getVar('IMAGE_LINK_NAME')
    manifest_name = d.getVar('IMAGE_MANIFEST')
    tmpdir        = d.getVar('TMPDIR')
    workdir       = d.getVar('WORKDIR')

    if not manifest_name:
        return

    # oe-rootfs-repo is the temporary IPK repo that poky assembles inside
    # do_rootfs from locally-built packages before installing them.  It is
    # always present when manifest_srcuri_enrich runs.  DEPLOY_DIR_IPK, by
    # contrast, may not have its Packages indexes yet -- do_package_index
    # can execute after do_rootfs in the BitBake task graph, so its Packages
    # files may not exist at this point.
    #
    # Poky now calls opkg-make-index with -f, so Source-URI / Source-Rev
    # fields are already preserved in the oe-rootfs-repo Packages indexes.
    # No re-indexing is needed here.
    oe_rootfs_repo = os.path.join(workdir, 'oe-rootfs-repo') if workdir else ''

    # Build package -> metadata lookup from all feed index files.
    # Scans remote feed_info/index/ (assembler) and oe-rootfs-repo (local builds).
    pkg_meta = _parse_feed_indexes(tmpdir, oe_rootfs_repo)
    if not pkg_meta:
        bb.warn("manifest-srcuri: no feed index files found under "
                "%s/ipk_pkgdata/feed_info/index/ or %s -- "
                "Source-URI / Source-Rev columns will be empty." % (tmpdir, oe_rootfs_repo))

    # Get the installed package list (arch + version) -- same call used
    # by poky's standard write_image_manifest.
    pkgs = image_list_installed_packages(d)

    # Build all rows first so we can compute column widths for pretty-printing.
    # Columns 1-4 (Package, Arch, Version, Recipe) have bounded widths and are
    # padded so the file is readable with plain `cat`.  Columns 5-6 (Source-URI,
    # Source-Rev) can be arbitrarily long and are left unpadded.
    import re as _re
    def _version_lookup_candidates(ver):
        # Build a deduplicated ordered list of version strings to try.
        # Strip only the trailing -rN Yocto revision suffix (not "-rc1" etc.).
        # Also try epoch-stripped variants (epoch is the "N:" prefix in ver).
        ver_plain = _re.sub(r'-r\d+$', '', ver)
        if ':' in ver:
            no_epoch = ver.split(':', 1)[1]
            no_epoch_plain = _re.sub(r'-r\d+$', '', no_epoch)
            raw = [ver, ver_plain, no_epoch, no_epoch_plain]
        else:
            raw = [ver, ver_plain]
        return list(dict.fromkeys(v for v in raw if v))

    rows = []
    for pkg in sorted(pkgs):
        arch = pkgs[pkg].get('arch', 'unknown')
        ver  = pkgs[pkg].get('ver',  'unknown')
        meta = {}
        for lookup_ver in _version_lookup_candidates(ver):
            meta = pkg_meta.get((pkg, lookup_ver, arch)) or {}
            if meta:
                break

        recipe = meta.get('OE', 'unknown')

        # Source-URI: prefer field from embed-source-metadata.bbclass.
        # Only fall back to Source: when it looks like a real URL (contains
        # ://) -- in opkg Packages stanzas the Source: field is typically a
        # recipe/source identifier (.bb filename), not a URL.
        # If neither is available, or all tokens are file:// local paths,
        # mark as N/A -- the recipe .bb name is already in the Recipe column.
        src_uri = meta.get('Source-URI', '')
        if not src_uri:
            source_fallback = meta.get('Source', '')
            if '://' in source_fallback:
                src_uri = source_fallback

        # Strip any file:// tokens and the 'unknown' sentinel emitted by
        # embed-source-metadata.bbclass when no remote URIs exist.
        # After filtering, keep all remaining remote URLs.
        remote_uris = [t for t in src_uri.split()
                       if not t.startswith('file://') and t != 'unknown']
        src_uri = ' '.join(remote_uris) if remote_uris else 'N/A'

        src_rev = meta.get('Source-Rev', '')
        if not src_rev or src_rev in ('INVALID', 'unknown'):
            # Fall back to hash extracted from the version string (git fetcher
            # encodes SRCREV as +git0+<hash>).  If no hash is found (tarball
            # recipes, suppressed SRCREV), use N/A rather than the Yocto-internal
            # sentinel "INVALID" which has no meaning to manifest consumers.
            src_rev = _srcrev_from_version(ver) or 'N/A'

        rows.append((pkg, arch, ver, recipe, src_uri, src_rev))

    # Column widths for the four bounded columns (pad to at least the header width).
    col_w = [
        max(len('Package'),  max(len(r[0]) for r in rows) if rows else 0),
        max(len('Arch'),     max(len(r[1]) for r in rows) if rows else 0),
        max(len('Version'),  max(len(r[2]) for r in rows) if rows else 0),
        max(len('Recipe'),   max(len(r[3]) for r in rows) if rows else 0),
    ]

    def _fmt(row, comment=False):
        line = '  '.join([
            row[0].ljust(col_w[0]),
            row[1].ljust(col_w[1]),
            row[2].ljust(col_w[2]),
            row[3].ljust(col_w[3]),
            row[4],
            row[5],
        ])
        if comment:
            line = '# ' + line
        return line + '\n'

    with open(manifest_name, 'w+') as mf:
        # Header line is commented so plain package-list parsers can skip it.
        mf.write(_fmt(('Package', 'Arch', 'Version', 'Recipe', 'Source-URI', 'Source-Rev'), comment=True))
        for row in rows:
            mf.write(_fmt(row))

    # Maintain the IMAGE_LINK_NAME.manifest symlink (same as poky)
    if os.path.exists(manifest_name) and link_name:
        manifest_link = deploy_dir + "/" + link_name + ".manifest"
        if manifest_link != manifest_name:
            if os.path.lexists(manifest_link):
                os.remove(manifest_link)
            os.symlink(os.path.basename(manifest_name), manifest_link)
}
