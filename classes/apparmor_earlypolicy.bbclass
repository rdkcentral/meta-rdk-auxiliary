SUMMARY = "AppArmor Global Profile Configurations"
DEPENDS += "apparmor-cache-native"
ROOTFS_POSTPROCESS_COMMAND:append = " execute_list_services;"
execute_list_services() {
    mkdir -p ${R}/etc/apparmor/aa_profiles/
    # Check if the exclusion file exists and read it
    if [ -f ${R}/etc/apparmor/Apparmor_exclude_systemdservice.inc ]; then
        exclude_services=$(cat ${R}/etc/apparmor/Apparmor_exclude_systemdservice.inc)
    else
        exclude_services=""
    fi
    find ${R}/lib/systemd/system/*.service | while read line; do
        if [ -f "$line" ]; then
            bname=$(basename $line)
            if echo "$exclude_services" | grep -q "$bname"; then
                echo "$bname is in the exclusion list, skipping"
                continue
            fi
            pname="$bname.sp"
            sed -i '/^AppArmorProfile/d' $line
            val="AppArmorProfile=-$pname"
            sed "/\[Service\]/a $val" $line > $line.tmp
            mv $line.tmp $line
            profile_path="${R}/etc/apparmor/aa_profiles/$pname"
            if [ ! -f "$profile_path" ]; then
                echo "profile $pname flags=(complain, attach_disconnected, mediate_deleted) {" > "$profile_path"
                cat ${R}/etc/apparmor/global_system_wide >> "$profile_path"
                echo "}" >> "$profile_path"
            fi
        else
            echo "$line not found, skipping"
        fi
    done
    install -d ${R}/etc/apparmor/service_profiles/
    install -d ${R}/etc/tmp_cache/
    install -d ${R}/lib/apparmor_cache
    install -d ${R}/var/
    install -d ${R}/var/tmp/
    ${STAGING_DIR_NATIVE}/sbin/apparmor_parser -aQTW -M ${STAGING_DIR_NATIVE}/usr/lib/features -L ${STAGING_DIR_NATIVE}/${libdir}/apparmor_cache/ ${R}/etc/apparmor/aa_profiles/*
    find ${STAGING_DIR_NATIVE}/${libdir}/apparmor_cache/ -type f -exec cp {} ${R}/etc/apparmor/service_profiles/ \;
    cp -r ${STAGING_DIR_NATIVE}/usr/lib/features ${R}/var/tmp/features
    rm -rf ${R}/etc/apparmor/earlyload_apparmor_profile.sh
    rm -rf ${R}/lib/systemd/system/earlyload-apparmor.service
}
FILES_${PN} += "/etc/apparmor/aa_profiles/"
FILES_${PN} += "/etc/apparmor/service_profiles/*"
FILES_${PN} += "/etc/tmp_cache/*"
