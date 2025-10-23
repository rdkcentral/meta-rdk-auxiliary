#Install collectd to the debug builds as required in RDK_TOOLS_PACKAGES
IMAGE_INSTALL:append = "${@bb.utils.contains('BUILD_VARIANT', 'debug', d.getVar('RDK_TOOLS_PACKAGES') or '', '', d)}"

#Install memcapture to all the builds as per RDK-59546
IMAGE_INSTALL:append = " memcapture"

IMAGE_INSTALL:append = "${@bb.utils.contains('BUILD_VARIANT', 'debug', " systemd-analyze", "", d)}" 
