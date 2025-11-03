
#Install collectd,systemd-analyze and other debug tools using RDK_TOOLS_PACKAGES Jenkins option
IMAGE_INSTALL:append = "${@bb.utils.contains('BUILD_VARIANT', 'debug', d.getVar('RDK_TOOLS_PACKAGES') or '', '', d)}"


