# Enable CLOC report generation
USER_CLASSES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'ENABLE_CLOC', 'cloc', '', d)}"

# Generate version.txt in the rootfs
USER_CLASSES:append = " create_fw_version_file "

# Generate build data
USER_CLASSES:append = " generate-build-datastore "
