#Install performance and debug tools as required in RDK_TOOLS_PACKAGES
IMAGE_INSTALL:append = " ${@d.getVar("RDK_TOOLS_PACKAGES", True) or ""} "
