#Install performance and debug tools as required in RDK_TOOLS_PACKAGES
IMAGE_INSTALL_append = " ${@d.getVar("RDK_TOOLS_PACKAGES", True) or ""} "
