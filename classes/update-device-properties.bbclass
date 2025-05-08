#
# Merge device properties from all layers into a single file
# /etc/device.properties and /etc/device-middleware.properties are delivered by Middleware
# /etc/device-vendor.properties is delivered by Vendor
#

ROOTFS_POSTPROCESS_COMMAND += ' update_device_properties; '

# Function to merge properties with handling duplicates and sort alphabetically
merge_properties() {
    local source_file=$1
    local target_file=$2
    local source_label=$3
    local temp_merged="${target_file}.merged"
    local temp_sorted="${target_file}.sorted"
    
    if [ -f "${source_file}" ]; then
        bbnote "Updating ${target_file} with ${source_label}"
        
        # Extract all comments from target file
        grep "^#" "${target_file}" > "${temp_merged}" 2>/dev/null || true
        
        # Add source file label as comment
        echo "# ${source_label}" >> "${temp_merged}"
        
        # Create a temporary associative array (implemented as a file)
        # to store the properties and their values
        local props_file="${target_file}.props"
        > "${props_file}"
        
        # Process target file properties first (base properties)
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
                continue
            fi
            
            # Extract variable name and value
            if [[ "$line" =~ ^([^=]*)=(.*) ]]; then
                var_name="${BASH_REMATCH[1]}"
                var_value="${BASH_REMATCH[2]}"
                echo "${var_name}=${var_value}" >> "${props_file}"
            fi
        done < "${target_file}"
        
        # Process source file properties (overriding existing ones)
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
                continue
            fi
            
            # Extract variable name and value
            if [[ "$line" =~ ^([^=]*)=(.*) ]]; then
                var_name="${BASH_REMATCH[1]}"
                var_value="${BASH_REMATCH[2]}"
                
                # Check if property already exists
                if grep -q "^${var_name}=" "${props_file}"; then
                    # Replace the existing property
                    sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "${props_file}"
                    bbnote "Replacing existing property: ${var_name}"
                else
                    # Add new property
                    echo "${var_name}=${var_value}" >> "${props_file}"
                fi
            fi
        done < "${source_file}"
        
        # Sort properties alphabetically and append to merged file
        sort "${props_file}" >> "${temp_merged}"
        
        # Replace original file with merged and sorted one
        mv "${temp_merged}" "${target_file}"
        
        # Clean up temporary files
        rm -f "${props_file}"
        
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
