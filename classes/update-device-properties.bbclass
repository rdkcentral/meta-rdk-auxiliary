#
# Merge device properties from all layers into a single file
# /etc/device.properties and /etc/device-middleware.properties are delivered by Middleware
# /etc/device-vendor.properties is delivered by Vendor
#
# Priority order (highest wins): vendor > middleware > application/generic
# A key is kept only once in the final file. An override with an empty
# value (e.g. KEY=) is still a valid override and wins over the lower
# priority layer's value.

ROOTFS_POSTPROCESS_COMMAND += ' update_device_properties; '

# merge_properties BASE_FILE OVERRIDE_FILE OUTPUT_FILE
# Every key in OVERRIDE_FILE replaces the same key in BASE_FILE.
# Keys only in BASE_FILE are kept as-is. Order of BASE_FILE is preserved,
# new keys introduced by OVERRIDE_FILE are appended at the end.
merge_properties() {
    base_file="$1"
    override_file="$2"
    output_file="$3"

    # an override with no records would make FNR==NR true for the base, so let's sort this out here
    if [ ! -s "${override_file}" ]; then
        cp "${base_file}" "${output_file}"
        return
    fi

    awk -F'=' '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
        FNR==NR {
            if ($0 !~ /^[[:space:]]*(#|$)/) {
                key = trim($1)
                if (!(key in override)) order[++n] = key
                override[key] = $0
            }
            next
        }
        {
            if ($0 !~ /^[[:space:]]*(#|$)/) {
                key = trim($1)
                if (key in done) next
                done[key] = 1
                print (key in override) ? override[key] : $0
                next
            }
            print $0
        }
        END {
            for (i = 1; i <= n; i++)
                if (!(order[i] in done)) print override[order[i]]
        }
    ' "${override_file}" "${base_file}" > "${output_file}"
}

update_device_properties() {
    GENERIC_DEV_PROP="/etc/device.properties"
    MIDDLEWARE_DEV_PROP="/etc/device-middleware.properties"
    VENDOR_DEV_PROP="/etc/device-vendor.properties"

    if [ -n "${IMAGE_ROOTFS}" -a -d "${IMAGE_ROOTFS}" ]; then
        echo "IMAGE_ROOTFS: ${IMAGE_ROOTFS}"

        GENERIC_DEV_PROP_FILE="${IMAGE_ROOTFS}${GENERIC_DEV_PROP}"
        MIDDLEWARE_DEV_PROP_FILE="${IMAGE_ROOTFS}${MIDDLEWARE_DEV_PROP}"
        VENDOR_DEV_PROP_FILE="${IMAGE_ROOTFS}${VENDOR_DEV_PROP}"
        TMP_DEV_PROP_FILE="${GENERIC_DEV_PROP_FILE}.tmp"

        if [ -f "${GENERIC_DEV_PROP_FILE}" ]; then
            bbnote "${GENERIC_DEV_PROP} found in rootfs"
        else
            bbnote "${GENERIC_DEV_PROP} not found in rootfs, creating it"
            touch "${GENERIC_DEV_PROP_FILE}"
        fi

       # Step 1: middleware overrides application/generic
       if [ -f "${MIDDLEWARE_DEV_PROP_FILE}" ]; then
           bbnote "Updating ${GENERIC_DEV_PROP} with ${MIDDLEWARE_DEV_PROP}"
           merge_properties "${GENERIC_DEV_PROP_FILE}" "${MIDDLEWARE_DEV_PROP_FILE}" "${TMP_DEV_PROP_FILE}"
           mv "${TMP_DEV_PROP_FILE}" "${GENERIC_DEV_PROP_FILE}"
           bbnote "Deleting ${MIDDLEWARE_DEV_PROP} from rootfs"
           rm -rf "${MIDDLEWARE_DEV_PROP_FILE}"
        fi

     # Step 2: vendor overrides the result of step 1 (highest priority)
        if [ -f "${VENDOR_DEV_PROP_FILE}" ]; then
            bbnote "Updating ${GENERIC_DEV_PROP} with ${VENDOR_DEV_PROP}"
            merge_properties "${GENERIC_DEV_PROP_FILE}" "${VENDOR_DEV_PROP_FILE}" "${TMP_DEV_PROP_FILE}"
            mv "${TMP_DEV_PROP_FILE}" "${GENERIC_DEV_PROP_FILE}"
            bbnote "Deleting ${VENDOR_DEV_PROP} from rootfs"
            rm -rf "${VENDOR_DEV_PROP_FILE}"
        fi

    else
        bbnote "IMAGE_ROOTFS not found"
    fi
}
