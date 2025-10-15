# Run post-rootfs hooks based on BUILD_VARIANT
# TBD: Move these hooks to respective components

ROOTFS_POSTPROCESS_COMMAND += '${@bb.utils.contains("DISTRO_FEATURES", "debug-variant", "dev_image_hook; ", "", d)}'
ROOTFS_POSTPROCESS_COMMAND += '${@bb.utils.contains("DISTRO_FEATURES", "prod-variant", "prod_image_hook; ", "", d)}'
ROOTFS_POSTPROCESS_COMMAND += '${@bb.utils.contains("DISTRO_FEATURES", "prodlog-variant", "prodlog_image_hook; ", "", d)}'
ROOTFS_POSTPROCESS_COMMAND += " common_image_hook; "
ROOTFS_POSTPROCESS_COMMAND += " create_NM_link; "
ROOTFS_POSTPROCESS_COMMAND += " remove_hvec_asset; "

R = "${IMAGE_ROOTFS}"

python dev_image_hook(){
     bb.build.exec_func('copy_dev_sshkeys', d)
}

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
     bb.build.exec_func('cleanup_sshkeys', d)
     bb.build.exec_func('cleanup_amznsshlxybundl', d)
}

update_build_type_property() {
    if [ -f "${R}/etc/device.properties" ]; then
       sed -i 's/BUILD_TYPE=dev/BUILD_TYPE=prod/g' ${R}/etc/device.properties
    fi
}

copy_dev_sshkeys() {
     if [ -d "${R}/etc/dropbear/vbn-keys" ]; then
         install -m 0644 ${R}/etc/dropbear/vbn-keys/* ${R}/etc/dropbear
     fi
     if [ -f "${R}/etc/dropbear/id_dropbear" ]; then
         rm -rf ${R}/etc/dropbear/id_dropbear
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

cleanup_sshkeys() {
     if [ -d ${R}/etc/dropbear/dev-keys ];then
          rm -rf ${R}/etc/dropbear/dev-keys
     fi
     if [ -d ${R}/etc/dropbear/vbn-keys ];then
          rm -rf ${R}/etc/dropbear/vbn-keys
     fi
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

    if [ -f "${R}/lib/systemd/system/NetworkManager.service" ]; then
        sed -i 's/\/opt\/NetworkManager/\/opt\/secure\/NetworkManager/g' ${R}/lib/systemd/system/NetworkManager.service
    fi

    if [ -L "${R}/etc/NetworkManager/system-connections" ]; then
        rm -f ${R}/etc/NetworkManager/system-connections
        ln -s /opt/secure/NetworkManager/system-connections ${R}/etc/NetworkManager/
    fi
}

remove_hvec_asset(){
    if [ -f "${R}/var/sky/assets/Vision50V95_HEVC.mp4" ]; then
        rm -rf ${R}/var/sky/assets/Vision50V95_HEVC.mp4
    fi
}
