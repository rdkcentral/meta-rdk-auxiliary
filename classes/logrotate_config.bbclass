SUMMARY = "Generate a information to build logrotate data configuration for the recipe"

fakeroot python do_write_metadata_logrotate() {

    import os
    log_path = "/opt/logs"
    metadata_dir = d.expand('${D}${sysconfdir}')  + "/logrotate/"

    def write_rotation_hook(conf, log_name, rotation):
        safe_name = log_name.replace("/", "_").replace("*", "_")
        counter_file = "/opt/logs/.rotcount_%s" % safe_name
        log_pathname = "%s/%s" % (log_path, log_name)
        conf.write("postrotate\n")
        conf.write("    f=\"%s\"; d=$(date +%%F); [ \"$(head -1 \"$f\" 2>/dev/null)\" = \"$d\" ] || printf '%%s\\n0\\n' \"$d\" > \"$f\"; c=$(( $(sed -n 2p \"$f\") + 1 )); sed -i \"2s/.*/$c/\" \"$f\"; echo \"actual rotations today for %s: $c (configured limit: %s rotations)\" >> /opt/logs/logrotate.log\n" % (counter_file, log_pathname, rotation))
        conf.write("    syslog-ng-ctl reopen --control=/tmp/syslog-ng/syslog-ng.ctl\n")
        conf.write("endscript\n")

    if not os.path.exists(metadata_dir):
        bb.utils.mkdirhier(metadata_dir)
        os.chown(metadata_dir, 0, 0)
    if d.getVar('LOGROTATE_NAME', True) != None:
        name_list = d.getVar('LOGROTATE_NAME', True).split()
        for fname in name_list:
            config_file = metadata_dir + d.getVar('PN', True) + fname + "_orig.metadata"
            mem_config_file = metadata_dir + d.getVar('PN', True) + fname + "_mem.metadata"
            with open(config_file, 'w') as conf:
                with open(mem_config_file, 'w') as memconf:
                    logname_tag = 'LOGROTATE_LOGNAME_' + fname
                    if d.getVar(logname_tag, True) != None:
                        name = d.getVar(logname_tag, True)
                        conf.write("%s/%s {\n" % (log_path,name))
                        memconf.write("%s/%s {\n" % (log_path,name))
                        size_tag = 'LOGROTATE_SIZE_' + fname
                        if d.getVar(size_tag, True) != None:
                            size = d.getVar(size_tag, True)
                            conf.write("size %s\n" % (size))
                        rotate_tag =  'LOGROTATE_ROTATION_' + fname
                        if d.getVar(rotate_tag, True) != None:
                            rotate = d.getVar(rotate_tag, True)
                            conf.write("rotate %s\n" % (rotate))
                        mem_size_tag = 'LOGROTATE_SIZE_MEM_' + fname
                        if d.getVar(mem_size_tag, True) != None:
                            mem_size = d.getVar(mem_size_tag, True)
                            memconf.write("size %s\n" % (mem_size))
                        mem_rotate_tag =  'LOGROTATE_ROTATION_MEM_' + fname
                        if d.getVar(mem_rotate_tag, True) != None:
                            mem_rotate = d.getVar(mem_rotate_tag, True)
                            memconf.write("rotate %s\n" % (mem_rotate))
                    conf.write("missingok\n")
                    conf.write("ignoreduplicates\n")
                    conf.write("create\n")
                    write_rotation_hook(conf, name, d.getVar(rotate_tag, True) or "unknown")
                    conf.write("}\n")
                    memconf.write("create\n")
                    memconf.write("missingok\n")
                    memconf.write("ignoreduplicates\n")
                    write_rotation_hook(memconf, name, d.getVar(mem_rotate_tag, True) or "unknown")
                    memconf.write("}\n")
                    conf.close()
                    memconf.close()
}

python() {
    if bb.utils.contains('DISTRO_FEATURES', 'systemd', True, False, d):
        bb.build.addtask("write_metadata_logrotate", "do_package", "do_install", d)
}

FILES:${PN} += "${@bb.utils.contains('DISTRO_FEATURES','systemd',' ${sysconfdir}/* ','',d)}"
