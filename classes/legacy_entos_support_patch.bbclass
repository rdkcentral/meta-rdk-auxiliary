#
# Vendor provided scripts,properies file will be used as priority
# Middleware Files will be used if not supplied from Vendor Layer
# /etc/common.properties
# /lib/rdk/init-zram.sh
# /lib/rdk/imageFlasher.sh

ROOTFS_POSTPROCESS_COMMAND += ' legacy_entos_support; '

legacy_entos_support(){
    if [ -f "${IMAGE_ROOTFS}${sysconfdir}/common.properties" ]; then
        bbnote "common.properties file from Vendor Layer in rootfs"
        rm -f ${IMAGE_ROOTFS}${sysconfdir}/common-generic.properties
    else
        bbnote "Installing common.properties file from Middleware Layer"
        mv ${IMAGE_ROOTFS}/${sysconfdir}/common-generic.properties ${IMAGE_ROOTFS}/${sysconfdir}/common.properties
    fi
    
    if [ -f "${IMAGE_ROOTFS}/lib/rdk/imageFlasher.sh" ]; then
        bbnote "imageFlasher.sh script added from Vendor Layer in rootfs"
        rm -f ${IMAGE_ROOTFS}/lib/rdk/imageFlasher_generic.sh
    else
        bbnote "Installing imageFlasher.sh file from Middleware Layer"
        mv ${IMAGE_ROOTFS}/lib/rdk/imageFlasher_generic.sh ${IMAGE_ROOTFS}/lib/rdk/imageFlasher.sh
    fi

    if [ -f "${IMAGE_ROOTFS}/lib/rdk/init-zram.sh" ]; then
        bbnote "init-zram.sh Script added from Vendor Layer in rootfs"
        rm -f ${IMAGE_ROOTFS}/lib/rdk/init-zram_generic.sh
    else
        bbnote "Installing init-zram.sh file from Middleware Layer"
        mv ${IMAGE_ROOTFS}/lib/rdk/init-zram_generic.sh ${IMAGE_ROOTFS}/lib/rdk/init-zram.sh
    fi    
}
