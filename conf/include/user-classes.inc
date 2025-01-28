# Enable CLOC report generation
USER_CLASSES_append = " ${@bb.utils.contains('DISTRO_FEATURES', 'ENABLE_CLOC', 'cloc', '', d)}"

# Generate version.txt in the rootfs
USER_CLASSES_append = " create_fw_version_file "

# Generate build data
USER_CLASSES_append = " generate-build-datastore "
