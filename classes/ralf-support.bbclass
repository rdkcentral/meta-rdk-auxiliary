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
# creates dedicated ralf user and group with proper permissions for RALF applications.
# Usage: Inherit this class in your recipe or image file to enable RALF support.

SUMMARY = "Add RALF support: add required runtime user and group to the created image"

inherit extrausers

RALF_UID ?= "30000"
RALF_GID ?= "30000"

EXTRA_USERS_PARAMS += " \
    groupadd -g ${RALF_GID} ralf; \
    useradd -u ${RALF_UID} -g ${RALF_GID} -s /sbin/nologin -M ralf; \
    "
