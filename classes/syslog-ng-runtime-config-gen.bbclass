IMAGE_INSTALL:append = " syslog-ng "

ROOTFS_POSTPROCESS_COMMAND += " generate_syslog_ng_config; "

LOG_PATH = "/opt/logs"

python generate_syslog_ng_config() {
    bb.build.exec_func('update_constants',d)
}

python update_constants () {
    import os
    config_dir = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/"
    if not os.path.exists(config_dir):
        os.makedirs(config_dir)
    config_file = config_dir + "syslog-ng.conf"
    version_file = config_dir + ".version"
    log_path = d.getVar('LOG_PATH', True)
    if os.path.exists(version_file):
        with open(version_file, 'r') as config_version:
            get_version = config_version.readline()
            syslogng_version = ".".join(get_version.split(".")[:2])
            config_version.close()
    with open(config_file, 'w') as conf:
        conf.write("@version: %s\n" % (syslogng_version))
        conf.write("# Syslog-ng configuration file, created by syslog-ng configuration generator\n")
        conf.write("\n# First, set some global options.\n")
        conf.write("options { flush_lines(0);owner(\"root\"); perm(0664); stats_freq(0);use-dns(no);dns-cache(no);time-zone(\"Etc/UTC\"); };\n")
        conf.write("\n@define log_path \"%s\"\n" % (log_path))
        conf.write("\n########################\n")
        conf.write("# Sources\n")
        conf.write("########################\n")
        conf.write("\n#systemd journal entries\n")
        conf.write("source s_journald { systemd-journal(prefix(\".SDATA.journald.\")); };\n")
        conf.write("\n########################\n")
        conf.write("# Parsers and filters\n")
        conf.write("########################\n")
        conf.write("\n# Match DCM telemetry markers from the PatternDB ruleset.\n")
        conf.write("parser p_dcm_markers {\n")
        conf.write("    db-parser(\n")
        conf.write("        file(\"/opt/syslog-ng/patterndb/dcm-markers.xml\")\n")
        conf.write("        program-template(\"dcm\")\n")
        conf.write("    );\n")
        conf.write("};\n")
        conf.write("\nfilter f_dcm_marker { tags(\"dcm-marker\"); };\n")
        conf.write("\n########################\n")
        conf.write("# Templates\n")
        conf.write("########################\n")
        conf.write("template-function t_unified \"${ISODATE} ${MSGHDR} ${MSG}\\n\";\n")
        conf.write("template t_dcm_marker \"${ISODATE} header=${.dcm.header} class=${.classifier.class} rule=${.classifier.rule_id} msg=${MSG}\\n\";\n")
        conf.write("destination d_unified { file(\"%s/unified-logging.txt\" template(\"$(t_unified)\")); };\n" % (log_path))
        conf.write("destination d_dcm_marker { file(\"%s/dcm-marker-matches.log\" template(t_dcm_marker)); };\n" % (log_path))
        conf.write("log { source(s_journald); destination(d_unified); };\n")
        conf.write("log { source(s_journald); parser(p_dcm_markers); filter(f_dcm_marker); destination(d_dcm_marker); };\n")
        conf.close()
}
