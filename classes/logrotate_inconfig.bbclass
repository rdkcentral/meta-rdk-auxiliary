ROOTFS_POSTPROCESS_COMMAND += "${@bb.utils.contains('DISTRO_FEATURES','systemd',' generate_logrotate_config; ',' ',d)}"

python generate_logrotate_config() {
    bb.build.exec_func('update_conf',d)
    bb.build.exec_func('clear_meta',d)
}

update_conf(){

    logrotate_dir="${IMAGE_ROOTFS}/${sysconfdir}/logrotate/"
    config_dir="${IMAGE_ROOTFS}/${sysconfdir}/"
    device_properties_file="${IMAGE_ROOTFS}/${sysconfdir}/device.properties"
    mem_enabled="HDD_ENABLED=false"
    mem_disabled="HDD_ENABLED=true"

    if grep "$mem_enabled" $device_properties_file; then
        for file in `find $logrotate_dir -type f -iname "*mem.metadata"`
        do
            cat $file >> $config_dir/logrotatedata.conf
        done
    elif grep "$mem_disabled" $device_properties_file; then
        for file in `find $logrotate_dir -type f -iname "*orig.metadata"`
        do
            cat $file >> $config_dir/logrotatedata.conf
        done
    fi
}

clear_meta(){

    logrotate_dir="${IMAGE_ROOTFS}/${sysconfdir}/logrotate/"

    rm -rf ${logrotate_dir}
}
