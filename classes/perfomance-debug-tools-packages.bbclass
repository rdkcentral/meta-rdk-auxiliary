#Install collectd,systemd-analyze and other debug tools using RDK_TOOLS_PACKAGES Jenkins option
IMAGE_INSTALL:append = "${@bb.utils.contains('BUILD_VARIANT', 'debug', d.getVar('RDK_TOOLS_PACKAGES') or '', '', d)}"

#Install memcapture to all the builds as per RDK-59546
IMAGE_INSTALL:append = "${@bb.utils.contains('DISTRO_FEATURES', 'memcapture', 'memcapture', '', d)}"
