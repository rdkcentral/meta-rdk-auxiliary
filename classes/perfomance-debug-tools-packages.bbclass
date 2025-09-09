#Install performance and debug tools as required in RDK_TOOLS_PACKAGES
IMAGE_INSTALL:append = " ${@d.getVar("RDK_TOOLS_PACKAGES", True) or ""} "

IMAGE_INSTALL:append = "${@bb.utils.contains('BUILD_VARIANT', 'debug', " systemd-analyze", "", d)}" 
