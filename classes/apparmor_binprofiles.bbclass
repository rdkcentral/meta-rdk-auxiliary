SUMMARY = "AppArmor profile compilation"

#
# This recipe compiles AppArmor text profiles in /etc/apparmor.d/
# into binary form in the same directory. This results in
# the removal of text-based profiles on device, reducing space
# and improving load times
#
DEPENDS:append = " apparmor-native "

ROOTFS_POSTPROCESS_COMMAND:append = " execute_aa_compile_std_profiles;"

execute_aa_compile_std_profiles() {
    install -d ${R}/etc/apparmor.d/
    install -d ${R}/etc/apparmor/binprofiles/
    install -d ${R}/etc/apparmor/txttmp/

    SRCDIR="${R}/etc/apparmor.d"
    OUTDIR="${R}/etc/apparmor/txttmp"

    # The parser's file search functionality considers any #include without < >'s an
    # absolute path that is immutable, which means -I and -b are not resolved. See
    # parser/parser_lex.l, line 314 - only #includes in < > are searched for. Since
    # we don't use that, we need to mutate existing includes to move from " " or no
    # special chars to using < > then pass -I to apparmor_parser
    for f in "${SRCDIR}"/*; do
        [ -f "${f}" ] || continue

        out="${OUTDIR}/$(basename "${f}")"

        while IFS= read -r line || [ -n "$line" ]; do
          line="${line#"${line%%[![:space:]]*}"}"
          case "$line" in
          # Handle #include if exists entries
            \#include\ if\ exists\ \"*\"|\#include\ if\ exists\ *)
              file=${line#\#include if exists }
              file=${file#\"}
              file=${file%\"}
              echo "#include if exists <${file}>"
              ;;
          # Handle #include entries
            \#include\ \"*\"|\#include\ *)
              file=${line#\#include }
              file=${file#\"}
              file=${file%\"}
              echo "#include <${file}>"
              ;;

            *)
              echo "$line"
              ;;
          esac
        done < "$f" > "$out"
    done
    if [ "$(find "${R}/etc/apparmor/txttmp/" -mindepth 1 -print -quit)" ]; then
          ${STAGING_DIR_NATIVE}/sbin/apparmor_parser -aQTW -I ${R}/ -M ${STAGING_DIR_NATIVE}/usr/lib/features -L ${R}/etc/apparmor/binprofiles/ ${R}/etc/apparmor/txttmp/*
          rm -fr ${R}/etc/apparmor.d/*
          mv ${R}/etc/apparmor/txttmp/* ${R}/etc/apparmor.d/
          rm -rf ${R}/etc/apparmor/txttmp
    fi
}
FILES:${PN} += "/etc/apparmor/binprofiles/"
