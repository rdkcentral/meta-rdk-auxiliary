inherit systemd

VOLATILE_BINDS[type]= "list"
VOLATILE_BINDS[separator]= "\n"

pkg_postinst:${PN} () {
VOLATILE_BINDS="${@d.getVar('VOLATILE_BINDS', True) or ""}"
echo "${VOLATILE_BINDS}"

SERVICES=""
printf "${VOLATILE_BINDS}" | while IFS= read -r line
do
    [ -z "$line" ] && continue
echo ${line}
    what=$(echo "${line}" | awk '{print $1}')
    echo "DBG:WHAT:$what"

    whatparent=${what%/*}
    echo "WHAT PARENT:$whatparent"

    where=$(echo "${line}" | awk '{print $2}')
    echo "DBG:WHERE:$where"

    whereparent=${where%/*}
    echo "WHERE PARENT:$whereparent"

    service=$(echo "${what}" | sed 's|^/||; s|/|-|g').service
    echo "DBG:SERVICE:$service"

    SERVICES="$SERVICES $service"
    echo "Creating service file ${service}"

        cat << EOF > "$D${systemd_unitdir}/system/${service}"
[Unit]
Description=Bind mount volatile $where
DefaultDependencies=false
Before=local-fs.target
RequiresMountsFor=$whatparent $whereparent
ConditionPathIsReadWrite=$whatparent
ConditionPathExists=$where
ConditionPathIsReadWrite=!$where

[Service]
Type=oneshot
RemainAfterExit=Yes
StandardOutput=syslog
TimeoutSec=0
ExecStart=/sbin/mount-copybind $what $where
ExecStop=/bin/umount $where

[Install]
WantedBy=local-fs.target
EOF


echo "$SERVICES"

#ls "$D/etc/systemd/system/local-fs.target.wants"

#ln -sf "/lib/systemd/system/${service}" "$D/etc/systemd/system/local-fs.target.wants/${service}"

mkdir -p "$D/etc/systemd/system/local-fs.target.wants"
ln -sf "/lib/systemd/system/${service}" "$D/etc/systemd/system/local-fs.target.wants/${service}"

#systemctl enable "$D${systemd_unitdir}/system/${service}" - Needs runtime target
#    SYSTEMD_SERVICE:${PN} += "${service}" - systemd inherit
#   FILES:${PN} += "${service}"
done


}
