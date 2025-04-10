pkg_postinst:${PN} () {
BIND_CONFIGURATIONS="${@d.getVar('BIND_CONFIGURATIONS', True) or ""}"
echo "${BIND_CONFIGURATIONS}"

echo "${BIND_CONFIGURATIONS}" | while IFS= read -r line
do
    [ -z "$line" ] && continue
echo ${line}
    what=$(echo "${line}" | awk '{print $1}')
    echo "DBG:WHAT:$what"

    where=$(echo "${line}" | awk '{print $2}')
    echo "DBG:WHERE:$where"

    service=$(echo "${what}" | sed 's|^/||; s|/|-|g').service
    echo "DBG:SERVICE:$service"

    services="${services} ${service}"

    echo "Creating service file ${service}"

    sed -e "s#@what@#${what}#g; s#@where@#${where}#g" \
        -e "s#@whatparent@#${what%/*}#g; s#@whereparent@#${where%/*}#g" \
        $D${sysconfdir}/volatile-binds.service.in > $D${systemd_unitdir}/system/${service}

done

echo "DBG:${services}"

SYSTEMD_SERVICE:${PN} += "${services}"
FILES:${PN} += "${services}"
}
