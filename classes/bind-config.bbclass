VOLATILE_BINDS ?= "\
    /var/volatile/lib /var/lib\n\
"

pkg_postinst:${PN}:append () {
SERVICES=""
printf "${VOLATILE_BINDS}" | while IFS= read -r line
do
    [ -z "$line" ] && continue
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

SERVICE_PATH="$D${systemd_unitdir}/system/${service}"
if [ -f "$SERVICE_PATH" ]; then
    echo "Service ${service} already exists. Skipping creation."
    continue
fi
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

echo "inside loop:${SERVICES}"

if command -v systemctl >/dev/null 2>&1; then
                OPTS=""
                echo "systemctl command found"
        if [ -n "$D" ]; then
                OPTS="--root=$D"
        fi
        echo "Enabling the services in bind-config"
        systemctl ${OPTS} enable "$service"
        SERVICE_LINK="$D/etc/systemd/system/local-fs.target.wants/${service}"
        if [ ! -L "$SERVICE_LINK" ]; then
            echo "Symlink not created by systemctl, creating manually"
            mkdir -p "$D/etc/systemd/system/local-fs.target.wants"
            ln -sf "/lib/systemd/system/${service}" "$D/etc/systemd/system/local-fs.target.wants/${service}"
        fi
        echo "SYMLink created by systemctl"
else
        echo "systemctl Not Found. Enabling the service Manually"
        mkdir -p "$D/etc/systemd/system/local-fs.target.wants"
        ln -sf "/lib/systemd/system/${service}" "$D/etc/systemd/system/local-fs.target.wants/${service}"
fi

#systemctl enable "$D${systemd_unitdir}/system/${service}" - enable failed
 #    SYSTEMD_SERVICE:${PN} += "${service}" - inside postinst : systemd not available. outside postinst service not available
 #   FILES:${PN} += "${service}"
done

echo "list of services: ${SERVICES}"
echo "CREATING mount-copybind"
if [ -f "$D${base_sbindir}/mount-copybind" ]; then
    echo "mount-copybind already exists. Skipping creation."
    exit 0
fi
cat << EOF > "$D${base_sbindir}/mount-copybind"
#!/bin/sh
#
# Perform a bind mount, copying existing files as we do so to ensure the
# overlaid path has the necessary content.

if [ $# -lt 2 ]; then
    echo >&2 "Usage: $0 spec mountpoint [OPTIONS]"
    exit 1
fi

spec=$1
mountpoint=$2

if [ $# -gt 2 ]; then
    options=$3
else
    options=
fi

[ -n "$options" ] && options=",$options"

mkdir -p "${spec%/*}"
if [ -d "$mountpoint" ]; then
    if [ ! -d "$spec" ]; then
        mkdir "$spec"
        cp -pPR "$mountpoint"/. "$spec/"
    fi
elif [ -f "$mountpoint" ]; then
    if [ ! -f "$spec" ]; then
        cp -pP "$mountpoint" "$spec"
    fi
fi

mount -o "bind$options" "$spec" "$mountpoint"
EOF
}
