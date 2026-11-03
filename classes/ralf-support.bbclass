##########################################################################
# If not stated otherwise in this file or this component's LICENSE
# file the following copyright and licenses apply:
#
# Copyright 2026 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

# RALF Support BitBake Class
#
# Provisions RALF (RDK Application Layer Format) runtime prerequisites:
# creates a dedicated ralf user and group for the container in non-root mode
# and reserves a configurable pool of additional user IDs for installed RALF
# packages.

SUMMARY = "Add RALF support: add required runtime users and group to the created image"

inherit extrausers

# Provide default fallbacks for overridable configuration variables
RALF_UID ?= "30000"
RALF_UID_COUNT ?= "100"
RALF_GID ?= "30000"
RALF_USER_PREFIX ?= "ralfuser"

python () {
    import re

    def parse_int(var_name, default):
        value = (d.getVar(var_name) or "").strip()
        if not value:
            return default
        if not re.fullmatch(r"\d+", value):
            bb.fatal(f"{var_name} must be a non-negative integer, got '{value}'")
        return int(value)

    base_uid = parse_int("RALF_UID", 30000)
    uid_count = parse_int("RALF_UID_COUNT", 100)
    base_gid = parse_int("RALF_GID", 30000)
    prefix = (d.getVar("RALF_USER_PREFIX") or "").strip() or "ralfuser"

    if uid_count < 1:
        bb.fatal("RALF_UID_COUNT must be at least 1")

    # Construct the base group and root daemon identity commands
    commands = [
        f"groupadd -g {base_gid} ralf;",
        f"useradd -u {base_uid} -g {base_gid} -s /sbin/nologin -M ralf;",
    ]

    # Dynamically scale sequential sandbox identities
    for idx in range(1, uid_count + 1):
        commands.append(f"useradd -u {base_uid + idx} -g {base_gid} -s /sbin/nologin -M {prefix}{idx};")

    # Safely append configuration directly into the image generation track
    new_params = " " + " ".join(commands)
    d.appendVar("EXTRA_USERS_PARAMS", new_params)
}
