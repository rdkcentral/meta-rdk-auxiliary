#
# Merge device properties from all layers into a single file
# /etc/device.properties and /etc/device-middleware.properties are delivered by Middleware
# /etc/device-vendor.properties is delivered by Vendor
#

ROOTFS_POSTPROCESS_COMMAND += ' update_device_properties; '

update_device_properties() {
    GENERIC_DEV_PROP="/etc/device.properties"
    MIDDLEWARE_DEV_PROP="/etc/device-middleware.properties"
    VENDOR_DEV_PROP="/etc/device-vendor.properties"

    if [ -n "${IMAGE_ROOTFS}" -a -d "${IMAGE_ROOTFS}" ]; then
        echo "IMAGE_ROOTFS: ${IMAGE_ROOTFS}"



        if [ -f "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}" ]; then
            bbnote "${GENERIC_DEV_PROP} found in rootfs"

        else
            bbnote "${GENERIC_DEV_PROP} not found in rootfs, creating it"
            touch "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}"
        fi

        if [ -f "${IMAGE_ROOTFS}${MIDDLEWARE_DEV_PROP}" ]; then
           bbnote "Updating ${GENERIC_DEV_PROP} with ${MIDDLEWARE_DEV_PROP}"
           echo "# ${MIDDLEWARE_DEV_PROP}" >> "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}"
           cat "${IMAGE_ROOTFS}${MIDDLEWARE_DEV_PROP}" >> "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}"
           bbnote "Deleting ${MIDDLEWARE_DEV_PROP} from rootfs"
           rm -rf "${IMAGE_ROOTFS}${MIDDLEWARE_DEV_PROP}"
        fi

        if [ -f "${IMAGE_ROOTFS}${VENDOR_DEV_PROP}" ]; then
           bbnote "Updating ${GENERIC_DEV_PROP} with ${VENDOR_DEV_PROP}"
           echo "# ${VENDOR_DEV_PROP}" >> "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}"
           cat "${IMAGE_ROOTFS}${VENDOR_DEV_PROP}" >> "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}"
           bbnote "Deleting ${VENDOR_DEV_PROP} from rootfs"
           rm -rf "${IMAGE_ROOTFS}${VENDOR_DEV_PROP}"
        fi

        # Check and replace AUTHORIZED_USB_DEVICES value only at the end in the final merged file
        if grep -q 'AUTHORIZED_USB_DEVICES="0bda:c82b"' "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}"; then
            bbnote "Replacing AUTHORIZED_USB_DEVICES value in final properties file"
            sed -i 's/AUTHORIZED_USB_DEVICES="0bda:c82b"/AUTHORIZED_USB_DEVICES="abcd:efgh"/' "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}"
        fi


    else
        bbnote "IMAGE_ROOTFS not found"
    fi
}
