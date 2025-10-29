# Run post-rootfs hooks based on BUILD_VARIANT
# TBD: Move these hooks to respective components

ROOTFS_POSTPROCESS_COMMAND += '${@bb.utils.contains("DISTRO_FEATURES", "prod-variant", "prod_image_hook; ", "", d)}'
ROOTFS_POSTPROCESS_COMMAND += '${@bb.utils.contains("DISTRO_FEATURES", "prodlog-variant", "prodlog_image_hook; ", "", d)}'
ROOTFS_POSTPROCESS_COMMAND += " common_image_hook; "
ROOTFS_POSTPROCESS_COMMAND += " create_NM_link; "
ROOTFS_POSTPROCESS_COMMAND += " remove_hvec_asset; "

R = "${IMAGE_ROOTFS}"

python common_prod_image_hook(){
     bb.build.exec_func('cleanup_stunnel_socat', d)
     bb.build.exec_func('update_noshadow', d)
     bb.build.exec_func('disable_agetty', d)
     bb.build.exec_func('update_build_type_property', d)    
}

python prod_image_hook(){
     bb.build.exec_func('common_prod_image_hook', d)
}

python prodlog_image_hook(){
     bb.build.exec_func('common_prod_image_hook', d)
}

python common_image_hook(){
     bb.build.exec_func('cleanup_amznsshlxybundl', d)
     bb.build.exec_func('add_network_dependency_for_ntp_client', d)
     bb.build.exec_func('strip_logging', d)
}

update_build_type_property() {
    if [ -f "${R}/etc/device.properties" ]; then
       sed -i 's/BUILD_TYPE=dev/BUILD_TYPE=prod/g' ${R}/etc/device.properties
    fi
}

cleanup_stunnel_socat () {
    if [ -d ${R}/lib/rdk/stunnel ];then
        rm -rf ${R}/lib/rdk/stunnel
    fi
    if [ -f "${R}/bin/filan" ]; then
        rm -rf ${R}/bin/filan
    fi
    if [ -f "${R}/bin/procan" ]; then
        rm -rf ${R}/bin/procan
    fi
}

python update_noshadow() {
    import fileinput
    import re
    import sys
    noshadow_path = d.getVar("R", True) + "/etc/shadow"
    if os.path.isfile(noshadow_path):
        for line in fileinput.input(noshadow_path, inplace=1):
            line = re.sub("root::","root:*:",line)
            sys.stdout.write(line)
}

cleanup_amznsshlxybundl() {
    if [ -d ${R}/etc/amznsshlxybundl.bz2 ];then
          rm -rf ${R}/etc/amznsshlxybundl.bz2
    fi
}

disable_agetty() {
    if [ -f "${R}/lib/systemd/system/getty@.service" ]; then
        rm -rf ${R}/lib/systemd/system/getty@.service
    fi
    if [ -f "${R}/lib/systemd/system/serial-getty@.service" ]; then
        rm -rf ${R}/lib/systemd/system/serial-getty@.service
    fi
    if [ -f "${R}/sbin/agetty" ]; then
        rm -rf ${R}/sbin/agetty
    fi
    if [ -f "${R}/bin/login" ]; then
        rm -rf ${R}/bin/login
    fi
}

# Required for NetworkManager
create_NM_link() {
    touch ${R}/etc/resolv.conf
    echo "nameserver 127.0.0.1" > ${R}/etc/resolv.conf
    echo "options timeout:1" >> ${R}/etc/resolv.conf
    echo "options attempts:2" >> ${R}/etc/resolv.conf
    ln -sf /var/run/NetworkManager/no-stub-resolv.conf ${R}/etc/resolv.dnsmasq
}

remove_hvec_asset(){
    if [ -f "${R}/var/sky/assets/Vision50V95_HEVC.mp4" ]; then
        rm -rf ${R}/var/sky/assets/Vision50V95_HEVC.mp4
    fi
}

# TODO This is temporary. Must be moved to OSS layer
# Start NTP client on network UP
add_network_dependency_for_ntp_client() {
     if [ -f "${R}/lib/systemd/system/systemd-timesyncd.service" -a -f "${R}/lib/systemd/system/network-up.target" ]; then
         sed -i -E 's/^(Before=).*/\1time-sync.target shutdown.target/' ${R}/lib/systemd/system/systemd-timesyncd.service
         sed -i -E '/^\[Install\]/,/^\[/{s/(WantedBy=).*/\1network-up.target/}' ${R}/lib/systemd/system/systemd-timesyncd.service
         if [ -f "${R}/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service" ]; then
             rm -rf ${R}/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service
         fi
     fi
}
strip_logging() {
     rm -rf ${R}/usr/sbin/logrotate
     echo "LOG.RDK.DEFAULT=NONE" > ${R}/etc/debug.ini
     sed -i 's/Storage=.*/Storage=none/g' ${R}/etc/systemd/journald.conf
     rm -rf ${R}/lib/systemd/system/syslog*
     rm -rf ${R}/lib/systemd/system/logrotate*
}
