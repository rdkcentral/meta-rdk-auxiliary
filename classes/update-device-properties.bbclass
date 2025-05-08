#
# Merge device properties from all layers into a single file
# /etc/device.properties and /etc/device-middleware.properties are delivered by Middleware
# /etc/device-vendor.properties is delivered by Vendor
#

ROOTFS_POSTPROCESS_COMMAND += ' update_device_properties; '

# Function to merge properties with handling duplicates
merge_properties() {
    local source_file=$1
    local target_file=$2
    local source_label=$3
    
    if [ -f "${source_file}" ]; then
        bbnote "Updating ${target_file} with ${source_label}"
        echo "# ${source_label}" >> "${target_file}.new"
        
        # Process each line from source file
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
                echo "$line" >> "${target_file}.new"
                continue
            fi
            
            # Extract variable name
            var_name=$(echo "$line" | sed -n 's/^\([^=]*\)=.*/\1/p')
            
            if [ -n "$var_name" ]; then
                # Check if variable already exists in the original file
                if grep -q "^${var_name}=" "${target_file}"; then
                    bbnote "Replacing existing property: ${var_name}"
                else
                    # Variable doesn't exist in target, add it
                    echo "$line" >> "${target_file}.new"
                fi
            else
                # Not a variable line, just add it
                echo "$line" >> "${target_file}.new"
            fi
        done < "${source_file}"
        
        # Now handle the replacements by processing the original target file
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
                continue
            fi
            
            var_name=$(echo "$line" | sed -n 's/^\([^=]*\)=.*/\1/p')
            
            if [ -n "$var_name" ]; then
                # Check if this variable should be replaced
                if grep -q "^${var_name}=" "${source_file}"; then
                    # Replace with the value from source file
                    grep "^${var_name}=" "${source_file}" >> "${target_file}.new"
                else
                    # Keep original value
                    echo "$line" >> "${target_file}.new"
                fi
            else
                # Not a variable line, keep it
                echo "$line" >> "${target_file}.new"
            fi
        done < "${target_file}"
        
        # Replace original file with new one
        mv "${target_file}.new" "${target_file}"
        bbnote "Deleting ${source_label} from rootfs"
        rm -rf "${source_file}"
    fi
}

update_device_properties() {
    GENERIC_DEV_PROP="/etc/device.properties"
    MIDDLEWARE_DEV_PROP="/etc/device-middleware.properties"
    VENDOR_DEV_PROP="/etc/device-vendor.properties"
    
    if [ -n "${IMAGE_ROOTFS}" -a -d "${IMAGE_ROOTFS}" ]; then
        echo "IMAGE_ROOTFS: ${IMAGE_ROOTFS}"
        
        # Create generic properties file if it doesn't exist
        if [ -f "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}" ]; then
            bbnote "${GENERIC_DEV_PROP} found in rootfs"
        else
            bbnote "${GENERIC_DEV_PROP} not found in rootfs, creating it"
            touch "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}"
        fi
        
        # Merge middleware properties
        if [ -f "${IMAGE_ROOTFS}${MIDDLEWARE_DEV_PROP}" ]; then
            merge_properties "${IMAGE_ROOTFS}${MIDDLEWARE_DEV_PROP}" "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}" "${MIDDLEWARE_DEV_PROP}"
        fi
        
        # Merge vendor properties
        if [ -f "${IMAGE_ROOTFS}${VENDOR_DEV_PROP}" ]; then
            merge_properties "${IMAGE_ROOTFS}${VENDOR_DEV_PROP}" "${IMAGE_ROOTFS}${GENERIC_DEV_PROP}" "${VENDOR_DEV_PROP}"
        fi
    else
        bbnote "IMAGE_ROOTFS not found"
    fi
}
