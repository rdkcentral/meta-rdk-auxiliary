# RDKE GPU Layer Configuration Documentation

## Overview

The `rdke-gpu-layer.bbclass` is a BitBake class that processes GPU layer configuration to set up GPU layer support in the rootfs for containerized applications in RDK-E. It performs two main tasks:

1. **Creates a mount configuration file** with GPU device nodes and group IDs for container runtime
2. **Creates hardlinks and symlinks** of GPU libraries in a dedicated rootfs path for container mounting

This implementation follows the RDK GPU Layer Proposal for:
- Separating vendor GPU libraries from container images
- Providing mount configuration for container runtimes
- Creating a shared GPU rootfs for multiple containers

The bbclass automates the setup of the GPU layer rootfs structure as described in the GPU layer proposal documentation.

## Usage

Add the class to your image recipe or build configuration and set `RDKE_GPU_LAYER_CONFIG_JSON` pointing to the valid GPU layer configuration JSON file.

```bitbake
INHERIT += "rdke-gpu-layer"
```

### RDKE_GPU_LAYER_CONFIG_JSON
- **Type**: File path
- **Default**: `""` (empty - must be set and should be available in all RDKE layers, preferably from vendor layer or product)
- **Description**: Path to the GPU layer configuration JSON file. This variable must be set to a valid JSON configuration file path, otherwise the build will fail with a fatal error.

## JSON Schema

The configuration JSON file must conform to the following schema:

### Top-Level Structure

```json
{
  "mount-config-file": "/usr/share/gpu-layer/config.json",
  "mount-config": {
    "vendorGpuSupport": {
      "devNodes": [<string array>],
      "groupIds": [<string array>]
    }
  },
  "mount-rootfs-path": "<string>",
  "mount-rootfs-links": {
    "mandatory": {<dictionary>},
    "optional": [<string array>]
  }
}
```

### Required Fields (Mandatory)

All of the following fields are **mandatory** and will cause a fatal error if missing:

#### 1. `mount-config-file`
- **Type**: String
- **Description**: Absolute path where the GPU configuration file will be created in the rootfs
- **Example**: `"/usr/share/gpu-layer/config.json"`

#### 2. `mount-config`
- **Type**: Object (Dictionary)
- **Description**: Contains the GPU mount configuration that will be written to the config file
- **Required Nested Fields**:
  - `vendorGpuSupport` (mandatory)

#### 3. `vendorGpuSupport`
- **Type**: Object (Dictionary)
- **Parent**: `mount-config`
- **Description**: Vendor-specific GPU support configuration
- **Required Nested Fields**:
  - `devNodes` (mandatory)
  - `groupIds` (mandatory)

#### 4. `devNodes`
- **Type**: Array of strings
- **Parent**: `vendorGpuSupport`
- **Description**: List of GPU device nodes to be made available to containers
- **Example**:
  ```json
  "devNodes": [
    "/dev/ashmem",
    "/dev/dma_heap/system",
    "/dev/dma_heap/system-uncached",
    "/dev/dri/card0"
  ]
  ```

#### 5. `groupIds`
- **Type**: Array of strings
- **Parent**: `vendorGpuSupport`
- **Description**: List of group IDs/names required for GPU access
- **Example**:
  ```json
  "groupIds": [
    "video",
    "render"
  ]
  ```

#### 6. `mount-rootfs-path`
- **Type**: String
- **Description**: Absolute path where GPU libraries will be hardlinked in the rootfs
- **Example**: `"/usr/share/gpu-layer/rootfs/usr/lib"`

#### 7. `mount-rootfs-links`
- **Type**: Object (Dictionary)
- **Description**: Defines which libraries to link into the GPU layer rootfs
- **Required Nested Fields**:
  - `mandatory` (mandatory)

#### 8. `mandatory`
- **Type**: Object (Dictionary)
- **Parent**: `mount-rootfs-links`
- **Description**: Dictionary of mandatory library mappings (key-value pairs)
- **Format**: `"<link_name>": "<source_path>"`

### Optional Fields

#### `optional`
- **Type**: Array of strings
- **Parent**: `mount-rootfs-links`
- **Description**: List of optional library paths to hardlink
- **Behavior**: Optional libraries that don't exist will be logged but won't cause a failure

## Complete Example Configuration

```json
{
  "mount-config-file": "/usr/share/gpu-layer/config.json",
  "mount-config": {
    "vendorGpuSupport": {
      "devNodes": [
        "/dev/ashmem",
        "/dev/dma_heap/system",
        "/dev/dma_heap/system-uncached",
        "/dev/dri/card0",
        "/dev/dri/card1"
      ],
      "groupIds": [
        "video"
      ]
    }
  },
  "mount-rootfs-path": "/usr/share/gpu-layer/rootfs/usr/lib",
  "mount-rootfs-links": {
    "mandatory": {
      "libEGL.so": "/usr/lib/libEGL.so",
      "libEGL.so.1": "/usr/lib/libEGL.so.1.0.0",
      "libGLESv1_CM.so": "",
      "libGLESv1_CM.so.1": "",
      "libGLESv2.so": "/usr/lib/libGLESv2.so.2.0.0",
      "libGLESv2.so.2": "/usr/lib/libGLESv2.so.2.0.0",
      "libwayland-egl.so.1": "/usr/lib/libwayland-egl.so.1.0.0"
    },
    "optional": [
      "/usr/lib/libglapi.so.0.0.0",
      "/usr/lib/libffi.so.8.1.2",
      "/usr/lib/libgbm.so.1.0.0",
      "/usr/lib/libdrm.so.2.4.0",
      "/usr/lib/libvulkan.so.1.3.204"
    ]
  }
}
```

## How the Mapping Works

### 1. Mount Config File Creation

The `mount-config` object is written directly to the file specified in `mount-config-file`:

**Input:**
```json
"mount-config-file": "/usr/share/gpu-layer/config.json",
"mount-config": {
  "vendorGpuSupport": {
    "devNodes": ["/dev/dri/card0"],
    "groupIds": ["video"]
  }
}
```

**Output:**
Creates file at `${IMAGE_ROOTFS}/usr/share/gpu-layer/config.json` with content:
```json
{
  "vendorGpuSupport": {
    "devNodes": ["/dev/dri/card0"],
    "groupIds": ["video"]
  }
}
```

### 2. Mandatory Libraries Processing

For each entry in the `mandatory` dictionary:

#### Behavior 1: When target path is specified (non-empty)

**Input:**
```json
"libEGL.so.1": "/usr/lib/libEGL.so.1.0.0"
```

**Output:**
Creates in `${IMAGE_ROOTFS}${mount-rootfs-path}`:
- **Hardlink**: `libEGL.so.1.0.0` → hardlinked from `${IMAGE_ROOTFS}/usr/lib/libEGL.so.1.0.0`
- **Symlink**: `libEGL.so.1` → points to `libEGL.so.1.0.0`

**Rationale**: Container applications expect to find `libEGL.so.1` in their rootfs. The symlink provides this expected name while pointing to the actual hardlinked library file.

#### Behavior 2: When target path is empty

**Input:**
```json
"libGLESv1_CM.so": "",
"libGLESv1_CM.so.1": ""
```

**Output:**
- Searches for library variants matching the pattern in the rootfs
- Creates hardlinks for all found variants (files and symlinks)
- Useful when you don't know the exact versioned filename

### 3. Optional Libraries Processing

For each entry in the `optional` array:

**Input:**
```json
"optional": [
  "/usr/lib/libglapi.so.0.0.0",
  "/usr/lib/libffi.so.8.1.2"
]
```

**Output:**
Creates in `${IMAGE_ROOTFS}${mount-rootfs-path}`:
- **Hardlink**: `libglapi.so.0.0.0` → hardlinked from `${IMAGE_ROOTFS}/usr/lib/libglapi.so.0.0.0`
- **Hardlink**: `libffi.so.8.1.2` → hardlinked from `${IMAGE_ROOTFS}/usr/lib/libffi.so.8.1.2`

**Note**: Only the basename (filename) is used in the destination. Full directory structure is NOT preserved.

**Behavior**: If an optional library doesn't exist:
- Reported as a warning via `bb.warn`
- Build continues (no fatal error)

## File Structure Example

Given the example configuration above, the resulting file structure would be:

```
${IMAGE_ROOTFS}/
├── usr/
│   └── share/
│       └── gpu-layer/
│           ├── config.json                    # Mount config file
│           └── rootfs/
│               └── usr/
│                   └── lib/
                       ├── libEGL.so → libEGL.so.1.0.0          # Symlink (mandatory)
                       ├── libEGL.so.1 → libEGL.so.1.0.0        # Symlink (mandatory)
                       ├── libEGL.so.1.0.0                      # Hardlink (mandatory)
                       ├── libGLESv2.so → libGLESv2.so.2.0.0    # Symlink (mandatory)
                       ├── libGLESv2.so.2 → libGLESv2.so.2.0.0  # Symlink (mandatory)
                       ├── libGLESv2.so.2.0.0                   # Hardlink (mandatory)
                       ├── libwayland-egl.so.1 → libwayland...  # Symlink (mandatory)
                       ├── libwayland-egl.so.1.0.0              # Hardlink (mandatory)
│                       ├── libglapi.so.0.0.0                    # Hardlink (optional)
│                       ├── libffi.so.8.1.2                      # Hardlink (optional)
│                       ├── libgbm.so.1.0.0                      # Hardlink (optional)
│                       ├── libdrm.so.2.4.0                      # Hardlink (optional)
│                       └── libvulkan.so.1.3.204                 # Hardlink (optional)
```
