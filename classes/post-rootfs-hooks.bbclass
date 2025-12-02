# Run post-rootfs hooks based on BUILD_VARIANT
# TBD: Move these hooks to respective components

ROOTFS_POSTPROCESS_COMMAND += '${@bb.utils.contains("DISTRO_FEATURES", "debug-variant", "dev_image_hook; ", "", d)}'
ROOTFS_POSTPROCESS_COMMAND += '${@bb.utils.contains("DISTRO_FEATURES", "prod-variant", "prod_image_hook; ", "", d)}'
ROOTFS_POSTPROCESS_COMMAND += '${@bb.utils.contains("DISTRO_FEATURES", "prodlog-variant", "prodlog_image_hook; ", "", d)}'
ROOTFS_POSTPROCESS_COMMAND += " common_image_hook; "
ROOTFS_POSTPROCESS_COMMAND += " create_NM_link; "
ROOTFS_POSTPROCESS_COMMAND += " remove_hvec_asset; "
ROOTFS_POSTPROCESS_COMMAND += " rdm_package; "

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
     bb.build.exec_func('add_network_dependency_for_ntp_client', d)
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

python rdm_package(){
     bb.build.exec_func('package_deployment', d)
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

package_deployment() {
   VER="ver.txt"
   FIL="fil.txt"
   NAM="nam.txt"
   RDM_FLOCK="${TMPDIR}/.rdmpkg.lock"
   RDM_DIR=${TMPDIR}/deploy/
   RDM_DEPLOYDIR=${TMPDIR}/deploy/rdm-pkgs
   rootfs_path=${R}
   RDM_MANIFEST=${rootfs_path}/etc/rdm/rdm-manifest.json
   TEMP_MANIFEST=./temp-manifest.json
   package_type="${@d.getVar('PACKAGE_TYPE', True)}"
   if [ `echo ${IMAGE_NAME} | grep -c sdy ` -eq 1 ];then
       package_type_dir=${package_type}-sdy
   fi
   if [ `echo ${IMAGE_NAME} | grep -c sey ` -eq 1 ];then
       package_type_dir=${package_type}-sey
   fi
   if [ ! -d $RDM_DEPLOYDIR ];then
         mkdir -p $RDM_DEPLOYDIR
   fi
   touch $RDM_DEPLOYDIR/deploy_image.list
   touch $RDM_DEPLOYDIR/deploy_versioned_image.list
   bbnote "[RDM] image list file: `ls -l $RDM_DEPLOYDIR/deploy_image.list`"
   machine_dir="${@d.getVar('MACHINE', True)}"
   for deploy_dir in `find ${RDM_DIR} -type d -name deploy-snapshots | grep ${machine_dir}`
   do
       if [ ! ${deploy_dir} ];then return ; fi
       for pkg_dir in `find ${deploy_dir}/* -maxdepth 1 -type d`
       do
          if [ ! "$pkg_dir" ];then
             bbnote "[RDM] Nothing to deploy..!"
             break
          fi
          type=${PACKAGE_TYPE}
          bbnote "[RDM] Build Package Type: package_type is $type"
          pkg_done_flag=".pkg_${type}_done"
          pkg_inprogress_flag="$HOME/package_deploy.lck"
          exec 8>$pkg_inprogress_flag
          # Acquired the lock
          # keep other process in waiting state till lock released
          flock -x 8
          bbnote "[RDM] Lock acquired Successfully"
          bbnote "[RDM] Package Directory [Full Path]: $pkg_dir"
          folder="$(basename $pkg_dir)"
          pkg_versioning_done_flag="${pkg_dir}/.${folder}_versioning_done"
          if [ -f "${pkg_versioning_done_flag}" ]; then
             bbnote "[RDM] Versioned package for ${folder} already available. Hence skipping"
             continue
          fi

          if [ -f ${pkg_dir}/${pkg_done_flag} ];then
             bbnote "[RDM] Already packaged Module"
             cd ${pkg_dir}
             if [ -f $RDM_MANIFEST ];then
                   if [ -f $TEMP_MANIFEST ]; then
                        regex=`sed -n '1p' $TEMP_MANIFEST | sed s/[\:\"\{]//g`
                        if [ "x`cat $RDM_MANIFEST | grep $regex`" = "x" ]; then
                            sed -i '/"packages":/r'$TEMP_MANIFEST $RDM_MANIFEST
                        fi
                   else
                        bbnote "[RDM] Previous manifest not found ..!"
                   fi
                   bbnote "[RDM] META Manifest file `cat $RDM_MANIFEST`"
             else
                  bbnote "[RDM] rdm-manifest.json not present in {rootfs_path} !!!"
             fi
             if [ ! -f ${rootfs_path}/etc/rdm/${folder}_cpemanifest ];then
                  if [ -f $RDM_DEPLOYDIR/${folder}_${package_type}_cpemanifest ];then
                       bbnote "[RDM] Copying $RDM_DEPLOYDIR/${folder}_${package_type}_cpemanifest"
                       cp $RDM_DEPLOYDIR/${folder}_${package_type}_cpemanifest ${rootfs_path}/etc/rdm/${folder}_cpemanifest
                  else
                       bbnote "[RDM] Missing $RDM_DEPLOYDIR/${folder}_${package_type}_cpemanifest"
                  fi
             fi
             continue
          fi
          bbnote "[RDM] Working Directory [Application Name]: ${folder}"
          CURRENT_PATH=`pwd`
          if [ ! -d ${TOPDIR}/${package_type_dir} ];then
               bbnote "[RDM] The current Path is ${TOPDIR}/${package_type_dir}"
               mkdir -p ${TOPDIR}/${package_type_dir}
          else
               rm -rf ${TOPDIR}/${package_type_dir}/*
               bbnote "[RDM] Cleaning the Path ${TOPDIR}/${package_type_dir}"
          fi
          cd ${TOPDIR}/${package_type_dir}
          #cd ${TOPDIR}
          image_name=${IMAGE_NAME}
          # Generating packing name
          if [ "$type" ];then
            bbnote "[RDM] Build Package Type: package_type is $type"
            bbnote "[RDM] Current Build Name: ${IMAGE_NAME}"
                 replace_string="$type""_";
                 bbnote "[RDM] Replacing the build type variable: ${replace_string}"
                 pkg_image_name=`echo ${IMAGE_NAME} | sed -e 's/'${replace_string}'//g;s/sey//g;s/sdy//g'`
                 bbnote "[RDM] Deploy Package Prefix (without appln): ${pkg_image_name}"
                 final_pkg_name="$pkg_image_name""_${folder}-signed.tar"
          fi
          bbnote "[RDM] Final Deploy Package Name: ${final_pkg_name}"
          files_list=`find ${pkg_dir}/*.ipk -maxdepth 1 -type f`
          bbnote "[RDM] Files Needed for Appln ${folder}:"
          bbnote "${files_list}"
          cat /dev/null > ./packages.list
          bbnote "[RDM] Starting creating: packages.list"
          for pkg in ${files_list}
          do
              bbnote "[RDM] PKG: $pkg"
              filename=`echo ${pkg##*/}`
              p_name=`echo "${filename}" | tr -d /`
              bbnote "[RDM] PKG - Package file Name: $p_name"
              echo ${p_name} >> ./packages.list
              if [ -f ${pkg} ];then
                   if [ -f ./${p_name} ];then
                       bbnote "[RDM] Removing the file ./${p_name}"
                       rm -rf ./${p_name}
                   fi
                   cp ${pkg} .
                   bbnote "[RDM] File check inside current path (`ls ./${p_name}`)"
             else
                   bbnote "[RDM] Missing Package ${pkg}"
             fi
          done
          bbnote "[RDM] End creating: packages.list"
          # Intermediate PKG name ( $pkg_dir + -pkg.tar)
          PKG_TEMP_NAME="${folder}-pkg.tar"
          bbnote "[RDM] Intermediate PKG: $PKG_TEMP_NAME"
          # Signature File Name
          prefix="${PKG_TEMP_NAME%.*}"
          bbnote "[RDM] Signature File Name Prefix: $prefix"
          SIGN=${folder}-pkg.sig
          bbnote "[RDM] Signature File Name: $SIGN"
          # Version Name
          echo -e "cpex 2.0\n" > ./$VER
          # File Name
          echo -e "$PKG_TEMP_NAME \n" > ./$FIL
          bbnote "[RDM] Creating NAM File"
          touch ./${NAM}
          bbnote "[RDM] Completed NAM File creation"
          bbnote "[RDM] Files Inside Working Path ->`pwd;ls -l .`"
          bbnote "[RDM] Packages List for ${final_pkg_name}: `cat ./packages.list`"
          if [ ! -f $RDM_DEPLOYDIR/${PKG_TEMP_NAME} ];then
               tar -cvf $RDM_DEPLOYDIR/${PKG_TEMP_NAME} ./*.ipk $VER $NAM $FIL ./packages.list
               if [ $? -ne 0 ];then
                    bbnote "[RDM] Error in tar file Generation"
                    break
               fi
          else
              bbnote "[RDM] Multi Arch Platform and same package from both core side"
              bbnote "[RDM] Destination Package is Already there"
              # break
          fi

          bbnote "[RDM] Successfully generated `ls -l $RDM_DEPLOYDIR/${PKG_TEMP_NAME}`"
              if [ -f $RDM_DEPLOYDIR/${PKG_TEMP_NAME} ];then
                     mkdir -p $RDM_DEPLOYDIR/${package_type_dir}/work_temp/size_pool
                     bbnote "[RDM] Uncompressing $RDM_DEPLOYDIR/${PKG_TEMP_NAME} for size"
                     tar -xvf $RDM_DEPLOYDIR/${PKG_TEMP_NAME} --no-same-owner -C $RDM_DEPLOYDIR/${package_type_dir}/work_temp/
                     if [ $? -ne 0 ];then
                           bbnote "[RDM] Error in tar extraction during size check"
                     fi
                     bbnote "[RDM] Files after $RDM_DEPLOYDIR/${PKG_TEMP_NAME} extraction `ls -lh $RDM_DEPLOYDIR/${package_type_dir}/work_temp/`"
                     while read line
                     do
                         if [ -f $RDM_DEPLOYDIR/${package_type_dir}/work_temp/$line ];then
                               bbnote "[RDM] Uncompressing ipk $line"
                               TEMP_WORK=`pwd`
                               cd $RDM_DEPLOYDIR/${package_type_dir}/work_temp/
                               ar -x $line
                               #default compression method in opkg is gz for daisy/morty and xz for dunfell
                               data_file=`ls data.tar.* | tail -n1`
                               cd $TEMP_WORK
                               bbnote "[RDM] Files after $line extraction `ls -lh $RDM_DEPLOYDIR/${package_type_dir}/work_temp/`"

                               if [ -f $RDM_DEPLOYDIR/${package_type_dir}/work_temp/$data_file ];then
                                     bbnote "[RDM] Uncompressing Final $data_file file $RDM_DEPLOYDIR/${package_type_dir}/work_temp/$data_file"
                                     tar --skip-old-files -xvf  $RDM_DEPLOYDIR/${package_type_dir}/work_temp/$data_file --no-same-owner -C $RDM_DEPLOYDIR/${package_type_dir}/work_temp/size_pool/
                                     bbnote "[RDM] Files after $data_file extraction `ls -lh $RDM_DEPLOYDIR/${package_type_dir}/work_temp/size_pool/`"
                                     TEMP_WORK=`pwd`
                                     cd $RDM_DEPLOYDIR/${package_type_dir}/work_temp/size_pool
                                     find .  -type f | cut -c 3- > $RDM_DEPLOYDIR/${folder}_${package_type}_cpemanifest
                                     cat $RDM_DEPLOYDIR/${folder}_${package_type}_cpemanifest | xargs cat > $RDM_DEPLOYDIR/${folder}_${package_type}_packagecat
                                     if [ -f ${rootfs_path}/etc/rdm/${folder}_cpemanifest ];then
                                         sleep 2
                                     fi
                                     bbnote "[RDM] Copying the Final meta data file: $RDM_DEPLOYDIR/${folder}_${package_type}_cpemanifest ${rootfs_path}/etc/rdm/${folder}_cpemanifest"
                                     if [ -f $RDM_DEPLOYDIR/${folder}_${package_type}_cpemanifest ];then
                                          cp $RDM_DEPLOYDIR/${folder}_${package_type}_cpemanifest ${rootfs_path}/etc/rdm/${folder}_cpemanifest
                                          ls -l ${rootfs_path}/etc/rdm/${folder}_cpemanifest
                                     else
                                          bbnote "[RDM] Missing Intermediate ${folder}_${package_type}_cpemanifest file"
                                     fi
                                     bbnote "[RDM] Updated the cpemanifest File"
                                     cd $TEMP_WORK
                                     rm -rf $RDM_DEPLOYDIR/${package_type_dir}/work_temp/$data_file
                                     if [ -f $RDM_DEPLOYDIR/${folder}_packagecat ];then
                                          sleep 5
                                     fi
                                     bbnote "[RDM] Copying the Final Package cat file $RDM_DEPLOYDIR/${folder}_${package_type}_packagecat $RDM_DEPLOYDIR/${folder}_packagecat"
                                     if [ -f $RDM_DEPLOYDIR/${folder}_${package_type}_packagecat ];then
                                          mv $RDM_DEPLOYDIR/${folder}_${package_type}_packagecat $RDM_DEPLOYDIR/${folder}_packagecat
                                          ls -l $RDM_DEPLOYDIR/${folder}_packagecat
                                     else
                                         bbnote "[RDM] Missing package cat file"
                                     fi
                               fi
                               bbnote "[RDM] Size after $line $data_file extraction: `du -sh $RDM_DEPLOYDIR/${package_type_dir}/work_temp/size_pool`"
                         fi
                     done<./packages.list
                     pkg_size=`du -sh $RDM_DEPLOYDIR/${package_type_dir}/work_temp/size_pool | cut -f1`
              fi
              rdm_versioning="false"
              decoupled_app="false"
              rdm_bundle_name=""
              rdm_bundle_version=""
              ondemand_val="no"
              dwld_method_ctrl_val="None"
              rdm_pkg_type_val="None"
              rdm_config_flag="${pkg_dir}/config"
              if [ -f $rdm_config_flag ];then
                        ondemand_val=`cat $rdm_config_flag | grep -i 'DOWNLOAD_ON_DEMAND' | awk '{print $3}'`
                        dwld_method_ctrl_val=`cat $rdm_config_flag | grep -i 'DOWNLOAD_METHOD_CONTROLLER' | awk '{print $3}'`
                        rdm_pkg_type_val=`cat $rdm_config_flag | grep -i 'RDM_PACKAGE_TYPE' | awk '{print $3}'`
                        rdm_versioning=`cat $rdm_config_flag | grep -i 'ENABLE_RDM_VERSIONING' | awk '{print $3}' | xargs`
                        decoupled_app=`cat $rdm_config_flag | grep -i 'PKG_FIRMWARE_DECOUPLED' | awk '{print $3}' | xargs`
                        rdm_bundle_name=`cat $rdm_config_flag | grep -i 'PKG_BUNDLE_NAME' | awk '{print $3}' | xargs`
                        rdm_bundle_version=`cat $rdm_config_flag | grep -i 'PKG_BUNDLE_VERSION' | awk '{print $3}' | xargs`
              fi

              if [ -z "${rdm_pkg_type_val}" ]; then
                  pkg_type="None"
              else
                  pkg_type="${rdm_pkg_type_val}"
              fi

              if [ -z "${decoupled_app}" ]; then
                  is_decoupledApp="false"
              else
                  is_decoupledApp="${decoupled_app}"
              fi

              if [ "${rdm_versioning}" = "true" -a "${is_decoupledApp}" = "true" ]; then
                        bbnote "[RDM] RDM Versioning is enabled for ${folder} package"
                        deploy_image_list="${RDM_DEPLOYDIR}/deploy_versioned_image.list"

                        pkg_tar_filename="${rdm_bundle_name}"
                        versioned_tar_filename="${rdm_bundle_name}_${rdm_bundle_version}"
                        final_signed_tar_file="${versioned_tar_filename}-signed.tar"
                        final_tar_file="${versioned_tar_filename}.tar"
                        final_sig_file="${versioned_tar_filename}.sig"
                        final_cpemanifest_file="pkg_cpemanifest"
                        matchFlag=0
                        # pkg info file
                        while read line
                        do
                                deploy_pkg_name=`echo $line | cut -d " " -f1`
                                if [ "$deploy_pkg_name" = "${final_signed_tar_file}" ];then
                                        bbnote "[RDM] Found Matching Entry for ${final_signed_tar_file} in ${deploy_image_list}"
                                        matchFlag=1
                                        break
                                fi
                        done < "$deploy_image_list"
                        if [ $matchFlag -eq 0 ];then
                                bbnote "[RDM] Adding image details to $(basename ${deploy_image_list})"
                                echo "${final_signed_tar_file} ${final_tar_file} ${final_sig_file} ${final_cpemanifest_file}" >> "$deploy_image_list"
                        fi
                        pkg_metadata="${rdm_bundle_name}_package.json"
                        pkg_metadata_ipk="$(find "${RDM_DEPLOYDIR}/${package_type_dir}/work_temp/size_pool" -type f -name "${pkg_metadata}")"
                        [ -z "${pkg_metadata_ipk}" -o ! -f "${pkg_metadata_ipk}" ] && bbfatal_log "[RDM] ${pkg_metadata} not found in the package"
                        temp_work_dir="${RDM_DEPLOYDIR}/bundle"
                        image_dir="${@d.getVar("DEPLOY_DIR_IMAGE", True)}"
                        [ -d "${temp_work_dir}" ] && rm -rf ${temp_work_dir}
                        mkdir -p ${temp_work_dir}
                        grep -q "name" ${pkg_metadata_ipk}
                        j_name=$?
                        grep -q "description" ${pkg_metadata_ipk}
                        j_des=$?
                        grep -q "version" ${pkg_metadata_ipk}
                        j_ver=$?
                        grep -q "contents" ${pkg_metadata_ipk}
                        j_cont=$?
                        grep -q "size" ${pkg_metadata_ipk}
                        j_size=$?
                        grep -q "installScript" ${pkg_metadata_ipk}
                        j_inst=$?
                        if [ $j_name -ne 0 -o $j_des -ne 0 -o $j_ver -ne 0 -o $j_cont -ne 0 -o $j_size -ne 0 -o $j_inst -ne 0 ]; then
                                bbfatal_log "[RDM] ${pkg_metadata} missing critical fields. Mandatory fields - name, description, version, contents, size, installScript"
                        fi
                        ## Update package.json with missing details
                        bbnote "[RDM] Updating ${pkg_metadata}"
                        sed -i "/name/c\  \"name\": \"${rdm_bundle_name}\"," "${pkg_metadata_ipk}"
                        sed -i "/version/c\  \"version\": \"${rdm_bundle_version}\"," "${pkg_metadata_ipk}"
                        sed -i "/size/c\  \"size\": \"${pkg_size}\"," "${pkg_metadata_ipk}"
                        sed -i "/contents/c\  \"contents\": [\"${pkg_tar_filename}.tar\"]," "${pkg_metadata_ipk}"
                        cp "${pkg_metadata_ipk}" "${temp_work_dir}/package.json"
                        bbnote "[RDM] Updated ${pkg_metadata}. Contents below"
                        cat "${temp_work_dir}/package.json"
                        ## Update package.json in rootfs too if present
                        pkg_metadata_rootfs="$(find "${rootfs_path}" -type f -name "${pkg_metadata}")"
                        [ -n "${pkg_metadata_rootfs}" -o -f "${pkg_metadata_rootfs}" ] && cp "${pkg_metadata_ipk}" "${pkg_metadata_rootfs}"
                        ## Generate the tar files
                        curpwd=$(pwd)
                        cd "${RDM_DEPLOYDIR}/${package_type_dir}/work_temp/size_pool"
                        bbnote "[RDM] Generating ${pkg_tar_filename}.tar"
                        tar -cf "${temp_work_dir}/${pkg_tar_filename}.tar" *
                        cd "${temp_work_dir}"
                        bbnote "[RDM] Generating ${final_tar_file}"
                        tar -cf "${RDM_DEPLOYDIR}/${final_tar_file}" *
                        cd "${curpwd}"
                        bbnote "[RDM] Versioned RDM package ${final_tar_file} generated and deployed to DEPLOY_DIR_IMAGE"
                        [ ! -d "${image_dir}" ] && mkdir -p ${image_dir}
                        cp "${RDM_DEPLOYDIR}/${final_tar_file}" "${image_dir}"
                        bbnote "[RDM] ls -l ${image_dir}/${final_tar_file}"
                        ls -l "${image_dir}/${final_tar_file}"
                        bbnote "[RDM] Creating versioning done flag for ${folder} package"
                        touch "${pkg_versioning_done_flag}"

                        [ -f "${rootfs_path}/etc/rdm/${folder}_cpemanifest" ] && rm -rf ${rootfs_path}/etc/rdm/${folder}_cpemanifest
                        [ -d "${temp_work_dir}" ] && rm -rf "${temp_work_dir}"
              else
                        matchFlag=0
                        # pkg info file
                        while read line
                        do
                                deploy_pkg_name=`echo $line | cut -d " " -f1`
                                if [ "$deploy_pkg_name" = "${final_pkg_name}" ];then
                                        bbnote "[RDM] Found Matching Entry for ${final_pkg_name} in $RDM_DEPLOYDIR/deploy_image.list"
                                        matchFlag=1
                                        break
                                fi
                        done <$RDM_DEPLOYDIR/deploy_image.list
                        if [ $matchFlag -eq 0 ];then
                                echo "${final_pkg_name} ${PKG_TEMP_NAME} ${SIGN} ${folder}_packagecat" >> $RDM_DEPLOYDIR/deploy_image.list
                        fi
                        # Application meta data info
                        #pkg_size=`du -smh $RDM_DEPLOYDIR/${PKG_TEMP_NAME}| cut -f1`
                        bbnote "[RDM]: ondemand file path=$rdm_config_flag"
                        bbnote "[RDM]: Contents of ${PKG_TEMP_NAME}: `tar -tvf $RDM_DEPLOYDIR/${PKG_TEMP_NAME}`"
                        bbnote "[RDM]: Size of ${PKG_TEMP_NAME}: $pkg_size"
                        echo "{\"$folder\":{" > $TEMP_MANIFEST
                        echo "  \"app_name\": \"$folder\"," >> $TEMP_MANIFEST
                        echo "  \"pkg_name\": \"${final_pkg_name}\"," >> $TEMP_MANIFEST
                        echo "  \"app_size\": \"${pkg_size}\"," >> $TEMP_MANIFEST
                        echo "  \"pkg_type\": \"${rdm_pkg_type_val}\"," >> $TEMP_MANIFEST
                        echo "  \"dwld_on_demand\": \"${ondemand_val}\"," >> $TEMP_MANIFEST
                        echo "  \"dwld_method_controller\": \"${dwld_method_ctrl_val}\"" >> $TEMP_MANIFEST
                        echo " }}" >> $TEMP_MANIFEST
                        bbnote "[RDM] Temporary Manifest file `cat $TEMP_MANIFEST`"
                        # Update RDM metadata to rootfs
                        bbnote "[RDM] ROOTFS PATH: ${rootfs_path}"
                        if [ -f $RDM_MANIFEST ];then
                                if [ "x`cat $RDM_MANIFEST | grep app_name`" != "x" ]; then
                                        echo "," >> $TEMP_MANIFEST
                                fi
                                regex=`sed -n '1p' $TEMP_MANIFEST | sed s/[\:\"\{]//g`
                                if [ "x`cat $RDM_MANIFEST | grep $regex`" = "x" ]; then
                                        sed -i '/"packages":/r'$TEMP_MANIFEST $RDM_MANIFEST
                                fi
                        fi
                        bbnote "[RDM] META Manifest file `cat $RDM_MANIFEST`"
                        cp $TEMP_MANIFEST ${pkg_dir}/
              fi
              if [ -d $RDM_DEPLOYDIR/${package_type_dir}/work_temp ];then
                        rm -rf $RDM_DEPLOYDIR/${package_type_dir}/work_temp
              fi
              touch ${pkg_dir}/${pkg_done_flag}
              # Releasing the lock
              flock -u 8
              rm -f $pkg_inprogress_flag
              bbnote "[RDM] lock released successfully"
              cd $CURRENT_PATH
              cd $CURRENT_PATH
       done
   done

   if [ -f "${RDM_FLOCK}" ]; then
      bbnote "[RDM] Cleaning up RDM lock"
      rm -f "${RDM_FLOCK}"
   fi

   if [ -f $RDM_DEPLOYDIR/deploy_image.list ];then
      bbnote "[RDM] Packages List for Jenkins Job: `cat $RDM_DEPLOYDIR/deploy_image.list `"
   fi
}
