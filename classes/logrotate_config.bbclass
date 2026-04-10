SUMMARY = "Generate logrotate data configuration for unified-logging.txt only"

python do_write_metadata_logrotate() {
    import os
    log_path = "/opt/logs"
    metadata_dir = d.expand('${D}${sysconfdir}')  + "/logrotate/"
    if not os.path.exists(metadata_dir):
        os.makedirs(metadata_dir)
    config_file = metadata_dir + "unified-logging_orig.metadata"
    mem_config_file = metadata_dir + "unified-logging_mem.metadata"
    with open(config_file, 'w') as conf:
        conf.write("/opt/logs/unified-logging.txt {\n")
        conf.write("size 4194304\n")
        conf.write("rotate 5\n")
        conf.write("missingok\n")
        conf.write("notifempty\n")
        conf.write("copytruncate\n")
        conf.write("}\n")
    with open(mem_config_file, 'w') as memconf:
        memconf.write("/opt/logs/unified-logging.txt {\n")
        memconf.write("size 4194304\n")
        memconf.write("rotate 5\n")
        memconf.write("missingok\n")
        memconf.write("notifempty\n")
        memconf.write("copytruncate\n")
        memconf.write("}\n")
}

python() {
    if bb.utils.contains('DISTRO_FEATURES', 'systemd', True, False, d):
        bb.build.addtask("write_metadata_logrotate", "do_package", "do_install", d)
}

FILES:${PN} += "${@bb.utils.contains('DISTRO_FEATURES','systemd',' ${sysconfdir}/* ','',d)}"
