SUMMARY = "Merge the JSON files from Generic and Device Specific RemoteDebugger profile"

ROOTFS_POSTPROCESS_COMMAND += " do_merge_json_files; "

python do_merge_json_files() {
    import json
    import os

    workdir = d.expand('${IMAGE_ROOTFS}${sysconfdir}/rrd')
    workdir = os.path.normpath(workdir) 
    
    remote_debugger_oem_exists = False       
    json_files = []

    if os.path.exists(workdir):
     for filename in os.listdir(workdir):
        if filename.endswith(".json"):  # Check for .json extension
            filepath = os.path.join(workdir, filename)
            json_files.append(filepath)
            
            if filename == "remote_debugger_oem.json":
                remote_debugger_oem_exists = True
    else:
        bb.warn("Directory does not exist!")
   
    output_file = os.path.join(workdir, "remote_debugger.json")

    
    merged_data = {}

    def merge_dicts(dict1, dict2):
        for key, value in dict2.items():
            if key in dict1:
                if isinstance(dict1[key], str) and isinstance(value, str):
                    dict1[key] += ";" + value
                elif isinstance(dict1[key], dict) and isinstance(value, dict):
                    merge_dicts(dict1[key], value)
                elif isinstance(dict1[key], list) and isinstance(value, list):
                    dict1[key].extend(value)
                else:
                    dict1[key] = value
            else:
                dict1[key] = value


    if os.path.exists(workdir) and remote_debugger_oem_exists:
        for json_file in json_files:
        
            if not os.path.exists(json_file):
                bb.warn("JSON files does not exist!")
        
            with open(json_file, 'r') as f:
                data = json.load(f)

            merge_dicts(merged_data, data)

    if os.path.exists(workdir) and remote_debugger_oem_exists:
        with open(output_file, 'w') as output:
            json.dump(merged_data, output, indent=4)


    if remote_debugger_oem_exists:
        filepath = os.path.join(workdir, "remote_debugger_oem.json")
        if os.path.exists(filepath):
            os.remove(filepath) 

}
