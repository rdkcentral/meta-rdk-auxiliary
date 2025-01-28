python generate_build_data() {
    from oe.data import export2json
    from bb import note, warn, error

    deploy_dir = d.getVar('DEPLOY_DIR')
    topdir = d.getVar('TOPDIR')

    # Define the path for the test data JSON
    testdata_name = os.path.join(deploy_dir, "build_datastore.json")

    # Check if the file already exists and remove it if necessary
    if os.path.exists(testdata_name):
        os.remove(testdata_name)  # Remove the existing file

    # Prepare the search string for export2json
    searchString = f"{topdir}/".replace("//", "/")

    # Attempt to export test data to JSON format
    try:
        export2json(d, testdata_name, searchString=searchString, replaceString="")
    except Exception as e:
        warn(f"Failed to export JSON data: {str(e)}")
        return

}

write_image_test_data[vardepsexclude] += "TOPDIR"

# Register the event handler to trigger this function post-build
python run_generate_build_data() {
    from bb import build, event, note

    if isinstance(e, event.BuildCompleted):
        note("Running generate_test_data as part of post-build.")
        build.exec_func("generate_build_data", d)
}

# Bind the handler to the BuildCompleted event
addhandler run_generate_build_data
