# Usage:
#   In local.conf or distro.conf set:
#     FDO_PROFILE_MODE = ""           → FDO disabled (default)
#     FDO_PROFILE_MODE = "generate"   → Instrumented build (generates .gcda profiles)
#     FDO_PROFILE_MODE = "use"        → Optimized build (consumes stored profiles)
#
#   In component recipe (.bb or .bbappend):
#     inherit fdo-profiling

# ── Defaults ───────────────────────────────────────────────────────────
FDO_PROFILE_MODE               ??= ""
FDO_PROFILE_OUTPUT_TARGET_DIR        ??= "/opt"
FDO_PROFILE_INPUT_NATIVE_DIR ??= "${FILE_DIRNAME}/files/fdo-profiles"

# ── Internal: compute FDO flags (empty string when FDO disabled) ──────────────
def fdo_get_flags(d):
    if 'ENABLE_FDO_PROFILING' not in (d.getVar('DISTRO_FEATURES') or '').split():
        return ""
    fdo_mode = (d.getVar('FDO_PROFILE_MODE') or "").strip().lower()
    if fdo_mode == "generate":
        return " -fprofile-generate=%s -fprofile-correction" % d.getVar('FDO_PROFILE_OUTPUT_TARGET_DIR')
    elif fdo_mode == "use":
        return " -fprofile-use=%s -fprofile-correction -Wno-error=missing-profile" % d.getVar('FDO_PROFILE_INPUT_NATIVE_DIR')
        #return " -fprofile-use=%s -fprofile-correction" % d.getVar('FDO_PROFILE_INPUT_NATIVE_DIR')
    return ""

# ── Conditionally register the task only when FDO is active ───────────────────
python () {
    if 'ENABLE_FDO_PROFILING' not in (d.getVar('DISTRO_FEATURES') or '').split():
        return

    fdo_mode = (d.getVar('FDO_PROFILE_MODE') or "").strip().lower()
    if fdo_mode not in ("", "generate", "use"):
        bb.fatal("fdo-profiling.bbclass: FDO_PROFILE_MODE must be '', 'generate', or 'use'. Got: '%s'" % fdo_mode)
    if fdo_mode:
        bb.note("fdo-profiling.bbclass: FDO_PROFILE_MODE = '%s'" % fdo_mode)

    if fdo_mode == "use":
        import os, glob

        recipe_profile_dir = d.getVar('FDO_PROFILE_INPUT_NATIVE_DIR')

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

# ── SAFE FLAG APPEND — uses :append, never overwrites existing flags ────────
# :append is evaluated AFTER all other flag assignments by BitBake,
# so this safely adds FDO flags on top of toolchain/distro/machine flags.
CFLAGS:append   = " ${@fdo_get_flags(d)} "
CXXFLAGS:append = " ${@fdo_get_flags(d)} "
LDFLAGS:append = " ${@fdo_get_flags(d)} "
