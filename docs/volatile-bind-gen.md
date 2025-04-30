# volatile-bind-gen.bbclass

## Overview
 This bbclass dynamically generates and installs systemd service units, based on volatile bind configurations from `VOLATILE_BINDS` variable.


## Features
This bbclass standardizes the management of volatile binds in a layered build system, allowing configurations to be handled independently across different layers.

## Functionality of volatile-bind-gen.bbclass
- Parses bind mount configurations from the `VOLATILE_BINDS` variable.
- Dynamically creates systemd service unit files during rootfs generation
- Installs and enables each generated service.
- Installs the `mount-copybind`.
- If the service or `mount-copybind` already exists, a warning is logged and reinstallation is skipped.
- All of these operations will be part of the corresponding package's postinst script, which is executed when the package's IPK is installed to the rootfs.


## Usage
- Inherit the bbclass in the desired packagegroup. Ex: packagegroup-middleware-layer.bb

