CLOCDEPENDENCY ?= "cloc-native"
CLOC_REQUIRED = "${@bb.utils.contains('DISTRO_FEATURES', 'ENABLE_CLOC', '1', '0', d)}"
CLOC_DIR ?= "cloc_reports"
DEPENDS:append:class-target = " ${CLOCDEPENDENCY} "

PACKAGE_PREPROCESS_FUNCS += "do_cloc_report_comp"

BLOCK_LIST_FILE="ClocBlockList.log"
CLOC_REPORT_FILE="ClocReportList.log"
get_cloc_vars() {
    cloc_blocklist_env="${@d.getVar('CLOC_BLOCKLIST_PATH', True)}"
    cloc_report_env="${@d.getVar('CLOC_COMPONENT_REPORT', True)}"
    pn="${@d.getVar('PN', True)}"
    cloc_blocklist_env=`echo "$cloc_blocklist_env" | tr "|" " " | tr "\t" " " | tr -s " "`
    cloc_report_env=`echo "$cloc_report_env" |  tr "|" " " | tr "\t" " " | tr -s " "`
    [ "$cloc_blocklist_env" = "None" ] && cloc_blocklist_env=""
    [ "$cloc_report_env" = "None" ] && cloc_cmplist_env=""
    file="${@d.getVar('FILE',True)}"
    workdir="${@d.getVar('WORKDIR', True)}"

    cv_blocklist="$cloc_blocklist_env"
    cv_genreport="$cloc_report_env"
    cv_exclude="\-native \-cross"
}

do_generate_cloc_report () {
    get_cloc_vars
    cloc=1
    for i in $cv_exclude; do
      if [ "x`echo $pn | grep "$i" `" != "x" ]; then
          cloc=0
          break
      fi
    done
    for i in $cv_blocklist; do
        if [ "x`echo $file | grep "$i" `" != "x" ]; then
            cloc=0
            break
        fi
    done
    if [ "$cloc" = "1" ] ; then
      if [ "x$cv_genreport" != "x" ]; then
         for i in $cv_genreport; do
              if [ "x`echo $file | grep "$i" `" != "x" ]; then
                   cloc=1
                   break
              fi
         done
      fi
    fi

    if [ "$cloc" = "0" ] ;then
        echo "##### CLOC Blocklist Path : $file -  ${PN}. Skipping cloc report." >> ${TMPDIR}/deploy/${CLOC_DIR}/${BLOCK_LIST_FILE}
    fi

    if [ "$cloc" = "1" ] ;then
        if [ -e "${WORKDIR}/recipe-sysroot-native/usr/bin/cloc" ]; then
            bbnote "Generating cloc report for ${PN}"
            if [ "$(ls -A ${S})" ]; then
                ${WORKDIR}/recipe-sysroot-native/usr/bin/cloc ${S} | tail -n +7 > ${TMPDIR}/deploy/${CLOC_DIR}/${PN}.txt
            else
                echo "Source code not found for ${PN}. Skipping cloc report." >> ${TMPDIR}/deploy/${CLOC_DIR}/${CLOC_REPORT_FILE}
            fi
        else
            echo "cloc binary not found in sysroot-native for ${PN}. Skipping cloc report." >> ${TMPDIR}/deploy/${CLOC_DIR}/${CLOC_REPORT_FILE}
        fi
    fi
}

python do_cloc_report_comp() {
    REPORT_DIR = os.path.join(d.getVar('TMPDIR'), 'deploy', d.getVar('CLOC_DIR'))
    os.makedirs(REPORT_DIR, exist_ok=True)

    component_name = d.getVar('PN')

    if d.getVar('CLOC_REQUIRED', True) == '1':
        with open(os.path.join(d.getVar('TMPDIR'), 'deploy', d.getVar('CLOC_DIR'), d.getVar('CLOC_REPORT_FILE')), 'a') as log_file:
            log_file.write("CLOC distro feature is enabled.\n")
        bb.build.exec_func('do_generate_cloc_report', d)
    else:
        with open(os.path.join(d.getVar('TMPDIR'), 'deploy', d.getVar('CLOC_DIR'), d.getVar('CLOC_REPORT_FILE')), 'a') as log_file:
            log_file.write("CLOC distro feature is disabled.\n")
}

# Ignore Opensource compoments
CLOC_BLOCKLIST_PATH += "openembedded-core | meta-openembedded | meta-rdk-ext"
# Ignore linux kernel Build
CLOC_BLOCKLIST_PATH += "linux-yocto-cougarmountain | linux-avalanche | linux-yocto-custom | stblinux | rglinux | display-linux-kernel | tsout-linux-kernel"
# Ignore driver componenent
CLOC_BLOCKLIST_PATH += "bbu-kdriver | docsis-headers | docsis | broadcom-refsw | broadcom-moca | broadcom-wifi-src"
# Ignore problematic components
CLOC_BLOCKLIST_PATH += "avro-c | graphite2 | zilker | wdmp-c | ctrlm-testapp | wpeframework | mkimage"
CLOC_BLOCKLIST_PATH += "netflix-src | dtcpmgr | qtbase | syslog-helper | linux-meson | mediarite | quilt-native"
CLOC_BLOCKLIST_PATH += "wave-api | meta-wave | meta-sky-qt5"
CLOC_BLOCKLIST_PATH += "asappsserviced-debug | asappsserviced-release | asappsserviced"

addtask do_cloc_report_comp after do_build
