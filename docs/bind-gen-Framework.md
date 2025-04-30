# Volatile-bind-gen.bbclass

## Overview
`volatile-bind-gen.bbclass` dynamically generates and installs systemd service units, based on volatile bind mount configurations provided in a recipe or layer.

This bbclass is specifically designed to be inherited in a **packagegroup** recipe.


## Features
This bbclass standardizes the management of volatile binds in RDK-E by providing reusable build framework.
It eliminates redundant builds and simplifies the integration of volatile bind configurations across all projects.


## Functionality of volatile-bind-gen.bbclass
- Parses bind mount configurations from the `VOLATILE_BINDS` variable.
- Dynamically creates systemd service unit files during build process. 
- Installs and enables each generated service.
- Installs the `mount-copybind`.
- If the service or `mount-copybind` already exists, a warning is logged and reinstallation is skipped.
- All of these operations are implemented inside a `pkg_postinst` script, which becomes part of the packagegroup's `.ipk` metadata.
- This postinst script is executed when the `.ipk` is installed.


## Usage

1. Inherit the bbclass in the desired packagegroup. Ex: packagegroup-middleware-layer.bb
   inherit volatile-bind-gen
2. Remove the dependency of volatile-binds recipe from the corresponding project
