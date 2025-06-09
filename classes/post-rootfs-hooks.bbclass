# Run post-rootfs hooks based on BUILD_VARIANT
# TBD: Move these hooks to respective components


ROOTFS_POSTPROCESS_COMMAND += " create_NM_link; "
ROOTFS_POSTPROCESS_COMMAND += " remove_hvec_asset; "
ROOTFS_POSTPROCESS_COMMAND += " modify_NM; "

R = "${IMAGE_ROOTFS}"

# Required for NetworkManager
create_NM_link() {
    ln -sf /var/run/NetworkManager/no-stub-resolv.conf ${R}/etc/resolv.dnsmasq
    ln -sf /var/run/NetworkManager/resolv.conf ${R}/etc/resolv.conf
}

remove_hvec_asset(){
    if [ -f "${R}/var/sky/assets/Vision50V95_HEVC.mp4" ]; then
        rm -rf ${R}/var/sky/assets/Vision50V95_HEVC.mp4
    fi
}

# Required for NetworkManager
modify_NM() {
    if [ -f "${R}/etc/NetworkManager/dispatcher.d/nlmon-script.sh" ]; then
        rm -f ${R}/etc/NetworkManager/dispatcher.d/nlmon-script.sh
    fi
    if [ -f "${R}/etc/NetworkManager/NetworkManager.conf" ]; then
        sed -i "s/dns=dnsmasq//g" ${R}/etc/NetworkManager/NetworkManager.conf
    fi
}
