# Usage:
#   Enable FDO:
#     DISTRO_FEATURES += "enable-fdo-profiling"
#     inherit fdo-profiling
#
#   Set FDO_PROFILE_MODE:
#     FDO_PROFILE_MODE = ""           → FDO disabled (default)
#     FDO_PROFILE_MODE = "generate"   → Instrumented build (generates .gcda profiles)
#     FDO_PROFILE_MODE = "use"        → Optimized build (consumes stored profiles)
#

# Default Values
FDO_PROFILE_MODE                     ??= ""
FDO_PROFILE_LOCAL_DIR                ??= "fdo-profiles"
FDO_PROFILE_OUTPUT_TARGET_DIR        ??= "/opt"
FDO_PROFILE_INPUT_NATIVE_DIR         ??= "${WORKDIR}/fdo-profiles"

def fdo_get_flags(d, fdo_mode):
    if fdo_mode == "generate":
        return " -fprofile-generate=%s -fprofile-correction" % d.getVar('FDO_PROFILE_OUTPUT_TARGET_DIR')
    elif fdo_mode == "use":
        return " -fprofile-use=%s -fprofile-correction -Wno-error=missing-profile" % d.getVar('FDO_PROFILE_INPUT_NATIVE_DIR')
    return ""

python () {
    if not bb.utils.contains('DISTRO_FEATURES', 'enable-fdo-profiling', True, False, d):
        bb.fatal("[FDO-PROFILING]: Distro feature 'enable-fdo-profiling' not enabled")
        return

    fdo_mode = (d.getVar('FDO_PROFILE_MODE') or "").strip().lower()
    if fdo_mode not in ("", "generate", "use"):
        bb.fatal("[FDO-PROFILING]: FDO_PROFILE_MODE not set")

    if fdo_mode == "use":
        prof_src_dir = d.getVar('FDO_PROFILE_LOCAL_DIR')
        d.appendVar('SRC_URI', ' file://%s ' % prof_src_dir)
        bb.build.addtask('do_fdoprofile_sanity_check', 'do_configure', 'do_unpack', d)

    if fdo_mode in ("generate", "use"):
        bb.note("[FDO-PROFILING]: FDO_PROFILE_MODE set to '%s'" % fdo_mode)
        flags = fdo_get_flags(d, fdo_mode)
        d.appendVar('CFLAGS', flags)
        d.appendVar('CXXFLAGS', flags)
        d.appendVar('LDFLAGS', flags)
}

python do_fdoprofile_sanity_check() {
    import os, glob

    #fdo_mode = (d.getVar('FDO_PROFILE_MODE') or "").strip().lower()
    #if fdo_mode != "use":
    #    return

    recipe_profile_dir = d.getVar('FDO_PROFILE_INPUT_NATIVE_DIR')

    if not os.path.isdir(recipe_profile_dir):
        bb.fatal(
            "fdo.bbclass: FDO_PROFILE_MODE=use but profile directory not found: %s\n"
            "Run a FDO_PROFILE_MODE=generate build first and collect profiles."
            % recipe_profile_dir
        )

    profiles = glob.glob(os.path.join(recipe_profile_dir, "**", "*.gcda"), recursive=True)
    if not profiles:
        bb.fatal(
            "fdo-profiling.bbclass: FDO_PROFILE_MODE=use but no .gcda files found in: %s\n"
            "Run a FDO_PROFILE_MODE=generate build first and collect profiles."
            % recipe_profile_dir
        )

    bb.note("fdo.bbclass: Found %d profile file(s) in %s" % (len(profiles), recipe_profile_dir))
}
