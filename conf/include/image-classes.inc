# Enable syslog-ng runtime config generation rootfs hook
IMAGE_CLASSES += "${@bb.utils.contains('DISTRO_FEATURES', 'syslog-ng', 'syslog-ng-runtime-config-gen', '', d)}"

# Update device.properties in the rootfs
IMAGE_CLASSES += "update-device-properties"

# Enable Cloc Report
IMAGE_CLASSES += "${@bb.utils.contains('DISTRO_FEATURES', 'ENABLE_CLOC', 'cloc-report', '', d)}"

# Install performance and debug tools for Dev builds only
IMAGE_CLASSES += "${@bb.utils.contains('DISTRO_FEATURES', 'debug-variant', 'perfomance-debug-tools-packages', '', d)}"

IMAGE_CLASSES +="logrotate_inconfig"

# Rootfs Audit Report
IMAGE_CLASSES += "package_categories"

# Post-rootfs hooks based on BUILD_VARIANT
IMAGE_CLASSES += "post-rootfs-hooks"

# Post-rootfs hook for converting apparmor text profiles to binary
IMAGE_CLASSES += "${@bb.utils.contains('DISTRO_FEATURES_NATIVE', 'apparmor', 'apparmor_binprofiles', '', d)}"
