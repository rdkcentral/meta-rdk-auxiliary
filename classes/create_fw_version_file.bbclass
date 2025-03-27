ROOTFS_POSTPROCESS_COMMAND += ' create_version_file; '

def extract_layer_versions_from_file(d, file_path):
    import re
    # Define a regular expression pattern to match the version number
    pattern = r'(\d+(\.\d+)*)'

    # Initialize a dictionary to store version numbers
    versions = {}

    # Open the file and read its contents
    with open(file_path, 'r') as file:
        for line in file:
            # Split the line by '=' to separate the package group and version
            package_group, version_str = line.strip().split('=')

            # Extract the layer name from the package group and add "_VERSION"
            prefix = d.getVar('MLPREFIX') or ""
            if prefix and package_group.startswith(prefix):
                package_group = package_group[len(prefix):]
            layer_name = package_group.split('-')[1].upper() + "_VERSION"

            # Use regex to find the version number in the version string
            match = re.search(pattern, version_str)

            # If a match is found, extract the version number
            if match:
                version_number = match.group(1)
                versions[layer_name] = version_number

    return versions


python create_version_file() {
    version_file = os.path.join(d.getVar("IMAGE_ROOTFS", True), 'version.txt')
    image_name = d.getVar("IMAGE_NAME",True)
    distro_codename = d.getVar("DISTRO_CODENAME",True) or ""
    stamp = d.getVar("DATETIME", True)
    t = time.strptime(stamp, '%Y%m%d%H%M%S')
    build_time = time.strftime('"%Y-%m-%d %H:%M:%S"', t)
    sdk_version = d.getVar("SDKVERSION",True) or "UNKNOWN"
    oss_layer_version = d.getVar('OSS_LAYER_VERSION', True) or '0.0.0'
    build_number = d.getVar('BUILD_NUMBER', True) or '0'
    job_name = d.getVar('JOB_NAME', True) or 'Default'
    branch = d.getVar("PROJECT_BRANCH", True) or 'Develop'

    if "-" in sdk_version:
        sdk_version=sdk_version.split("-")[-1]

    layer_info_path = d.getVar("RELEASE_LAYER_VERSIONS", True)

    with open(version_file, 'w') as fw:
        fw.write('imagename:{0}\n'.format(image_name))
        fw.write('OSS_VERSION={0}\n'.format(oss_layer_version))
        if os.path.exists(layer_info_path):
            layer_versions = extract_layer_versions_from_file(d, layer_info_path)
            for layer_name, version in layer_versions.items():
                fw.write(f"{layer_name}={version}\n")
        fw.write('YOCTO_VERSION={0}\n'.format(distro_codename))
        fw.write('SDK_VERSION={0}\n'.format(sdk_version))
        fw.write('VERSION=1.1.1.1\n')
        fw.write('FW_CLASS=rdke\n')
        fw.write('JENKINS_JOB={0}\n'.format(job_name))
        fw.write('JENKINS_BUILD_NUMBER={0}\n'.format(build_number))
        fw.write('BRANCH={0}\n'.format(branch))
        fw.write('BUILD_TIME={0}\n'.format(build_time))
        fw.close()
}

create_version_file[vardepsexclude] += "DATETIME"
