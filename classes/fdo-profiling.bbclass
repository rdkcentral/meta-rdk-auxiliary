# Usage:
#   In bb or bbappend file set one of below option:
#     FDO_PROFILE_MODE = ""           → FDO disabled (default)
#     FDO_PROFILE_MODE = "generate"   → Instrumented build (generates .gcda profiles)
#     FDO_PROFILE_MODE = "use"        → Optimized build (consumes stored profiles)
#
#   In component recipe (.bb or .bbappend):
#     inherit fdo-profiling
#     Set FDO_PROFILE_MODE
#     DISTRO_FEATURES:append = " ENABLE_FDO_PROFILING "

# Defaults Values
FDO_PROFILE_MODE                     ??= ""
FDO_PROFILE_OUTPUT_TARGET_DIR        ??= "/opt"
FDO_PROFILE_INPUT_NATIVE_DIR         ??= "fdo-profiles"
FDO_PROFILE_USE_DIR                  ??= "${WORKDIR}/fdo-profiles"

# Internal: compute FDO flags
def fdo_get_flags(d, fdo_mode):
    if fdo_mode == "generate":
        return " -fprofile-generate=%s -fprofile-correction" % d.getVar('FDO_PROFILE_OUTPUT_TARGET_DIR')
    elif fdo_mode == "use":
        return " -fprofile-use=%s -fprofile-correction -Wno-error=missing-profile" % d.getVar('FDO_PROFILE_USE_DIR')
    return ""

python () {
    if 'ENABLE_FDO_PROFILING' not in (d.getVar('DISTRO_FEATURES') or '').split():
        return

    fdo_mode = (d.getVar('FDO_PROFILE_MODE') or "").strip().lower()
    if fdo_mode not in ("", "generate", "use"):
        bb.fatal("fdo-profiling.bbclass: FDO_PROFILE_MODE must be '', 'generate', or 'use'. Got: '%s'" % fdo_mode)
    if fdo_mode in ("generate", "use"):
        bb.note("fdo-profiling.bbclass: FDO_PROFILE_MODE = '%s'" % fdo_mode)
        flags = fdo_get_flags(d, fdo_mode)
        d.appendVar('CFLAGS',     flags)
        d.appendVar('CXXFLAGS',   flags)
        d.appendVar('LDCFLAGS',   flags)
        bb.note("fdo-profiling.bbclass: Appended FDO flags to CFLAGS/CXXFLAGS/LDFLAGS: %s" % flags)

    if fdo_mode == "use":
        import os, glob

        d.appendVar('SRC_URI', ' file://fdo-profiles ')
        bb.note("fdo-profiling.bbclass: Appended fdo-profiles to SRC_URI")
        file_dirname = d.getVar('FILE_DIRNAME')
        recipe_profile_dir = os.path.join(file_dirname, 'files', d.getVar('FDO_PROFILE_INPUT_NATIVE_DIR'))

        if not os.path.isdir(recipe_profile_dir):
            bb.fatal(
                "fdo-profiling.bbclass: FDO_PROFILE_MODE=use but profile directory not found: %s\n"
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

        bb.note("fdo-profiling.bbclass: Found %d profile file(s) in %s" % (len(profiles), recipe_profile_dir))
        bb.note("fdo-profiling.bbclass: fdoprofile_sanity_check passed (FDO_PROFILE_MODE=%s)" % fdo_mode)
}
