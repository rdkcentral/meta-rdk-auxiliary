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

# Defaults Values
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
    if not bb.utils.contains('DISTRO_FEATURES', 'enable-fdo-profiling', True, False, d)
        bb.fatal("[FDO-PROFILING]: Distro feature 'enable-fdo-profiling' not enabled)
        return

    fdo_mode = (d.getVar('FDO_PROFILE_MODE') or "").strip().lower()
    if fdo_mode not in ("", "generate", "use"):
        bb.fatal("[FDO-PROFILING]: FDO_PROFILE_MODE not set)

    if fdo_mode == "use":
        import os, glob

        prof_src_dir = d.getVar('FDO_PROFILE_LOCAL_DIR')
        d.appendVar('SRC_URI', ' file://%s ' % prof_src_dir)
        file_dirname = d.getVar('FILE_DIRNAME')
#        recipe_profile_dir = os.path.join(file_dirname, 'files', d.getVar('FDO_PROFILE_LOCAL_DIR'))
#
#        if not os.path.isdir(recipe_profile_dir):
#            bb.fatal(
#                "[FDO-PROFILING]: FDO_PROFILE_MODE=use but profile directory not found: %s\n"
#                "Run a FDO_PROFILE_MODE=generate build first and collect profiles."
#             )
#
#        profiles = glob.glob(os.path.join(recipe_profile_dir, "**", "*.gcda"), recursive=True)
#        if not profiles:
#            bb.fatal(
#                "[FDO-PROFILING]: FDO_PROFILE_MODE=use but no .gcda files found in: %s\n"
#                "Run a FDO_PROFILE_MODE=generate build first and collect profiles."
#                % recipe_profile_dir
#            )

    if fdo_mode in ("generate", "use"):
        bb.note("[FDO-PROFILING]: FDO_PROFILE_MODE set to '%s'" % fdo_mode)
        flags = fdo_get_flags(d, fdo_mode)
        d.appendVar('CFLAGS', flags)
        d.appendVar('CXXFLAGS', flags)
        d.appendVar('LDFLAGS', flags)
}
