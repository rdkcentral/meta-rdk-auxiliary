#==============================================================================
#  host_locked_sstate.bbclass
#
#  Purpose:
#    This class enables the use of a pre-populated, locked sstate cache
#    from the host machine or Docker container for native and target components.
#    By leveraging an existing sstate cache, it avoids rebuilding native tools
#    repeatedly, significantly reducing overall build time.
#
#  Key Features:
#    - Generic: Can be applied to locked sstate of any component (native or target).
#    - Configurable: The locked sstate path can be set via HOST_LOCKED_SSTATE_PATH.
#      Default path: /opt/locked_sstate
#
#  Prerequisites:
#    - The uninative feature must be enabled to ensure compatibility of native tools.
#
#  How It Works:
#    - Determines the appropriate locked sigs file based on DEFAULTTUNE and MULTILIBS.
#    - Includes the locked sigs file from the host sstate directory.
#    - Updates SSTATE_MIRRORS to point to the host locked sstate path.
#
#  Variables:
#    HOST_LOCKED_SSTATE_PATH ?= "/opt/locked_sstate"
#      Path to the locked sstate cache on the host or Docker container.
#
#  Notes:
#    - If the expected locked sigs file is missing, the build will fail with an error.
#    - SIGGEN_LOCKEDSIGS_TASKSIG_CHECK is set to "warn" to allow flexibility.
#
#==============================================================================

HOST_LOCKED_SSTATE_PATH ?= "/opt/locked_sstate"

def get_locked_sig_file(d):
    default_sigs_file = "locked-sigs.inc"
    host_locked_sstate_path = d.expand('${HOST_LOCKED_SSTATE_PATH}')

    default_tune = d.getVar('DEFAULTTUNE')
    # need to fix: Workaround to check for 64bit machine with multilib configuration
    multilib_support = d.getVar('MULTILIBS') or ""

    # Determine the correct sigs_file based on the configuration
    if multilib_support:
        sigs_file = "locked-sigs_rdk-arm64.inc"
    elif "armv7athf-neon" in default_tune:
        sigs_file = "locked-sigs_rdk-arm7a.inc"
    elif "armv7vethf-neon" in default_tune :
        sigs_file = "locked-sigs_rdk-arm7ve.inc"
    else:
        sigs_file = default_sigs_file
    sigs_file_path = os.path.join(host_locked_sstate_path, sigs_file)
    if os.path.exists(sigs_file_path):
        return sigs_file_path
    else:
        bb.fatal("ERROR: The expected locked sigs file(%s) is not found" %sigs_file_path)

SIG_FILE = "${@get_locked_sig_file(d)}"
include ${SIG_FILE}
SSTATE_MIRRORS += "file://.* file:///${HOST_LOCKED_SSTATE_PATH}/PATH"
SIGGEN_LOCKEDSIGS_TASKSIG_CHECK = "warn"
