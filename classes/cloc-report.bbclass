python do_cloc_report() {
    import os
    import csv

    def process_component_report(component_report, final_report_path):
        with open(component_report, 'r') as f:
            lines = f.readlines()
            if len(lines) >= 4:  # Check if the file has at least 4 lines
                filename = os.path.splitext(os.path.basename(component_report))[0]
                with open(final_report_path, 'a', newline='') as final_report:
                    csv_writer = csv.writer(final_report)
                    final_report.write("ComponentName:{}\n".format(filename))
                    header_skipped = False
                    for line in lines[1:-3]:
                        if not header_skipped:
                            header_skipped = True
                            continue
                        if not line.strip():  # Skip empty lines
                            continue
                        parts = line.strip().split()
                        if len(parts) >= 3 and parts[0].isalpha() and (parts[1].isalpha() and parts[2].isalpha()):
                            parts[0] = ' '.join(parts[:3])
                            del parts[1:3]
                        if len(parts) >= 2 and parts[0] in ['Fortran']:
                            parts[0] = ' '.join(parts[:2])
                            del parts[1]
                        if len(parts) >= 2 and (parts[0].isalpha() or parts[0] in ['C/C++']) and (parts[1].isalpha() or parts[1] in ['C++'] or parts[1] in ['PL/SQL']):
                            parts[0] = ' '.join(parts[:2])
                            del parts[1]
                        csv_writer.writerow(parts)
            else:
                bb.warn("Skipping component report file with insufficient lines: %s" % component_report)

    def generate_final_report(report_dir, final_report_path):
        with open(final_report_path, 'w', newline='') as final_report:
            csv_writer = csv.writer(final_report)
            csv_writer.writerow(["Language", "Files", "Blank", "Comment", "Code"])
        with open(final_report_path, 'w', newline='') as final_report:
            for filename in os.listdir(report_dir):
                if filename.endswith('.txt'):
                    component_report = os.path.join(report_dir, filename)
                    bb.note("Processing file: %s" % filename)
                    process_component_report(component_report, final_report_path)

    def count_language_stats(final_report_path):
        language_data = {}
        with open(final_report_path, 'r') as final_report:
            csv_reader = csv.reader(final_report)
            next(csv_reader)  # Skip header
            for row in csv_reader:
                if len(row) < 5:
                    bb.warn("Skipping invalid row: %s" % row)
                    continue
                language = row[0]
                if language == "ComponentName":
                    continue
                files, blank, comment, code = map(int, row[1:])
                if language not in language_data:
                    language_data[language] = {'Files': files, 'Blank': blank, 'Comment': comment, 'Code': code}
                else:
                    language_data[language]['Files'] += files
                    language_data[language]['Blank'] += blank
                    language_data[language]['Comment'] += comment
                    language_data[language]['Code'] += code
        return language_data

    def generate_language_stats_report(language_data, output_path):
        with open(output_path, 'w', newline='') as output_file:
            csv_writer = csv.writer(output_file)
            csv_writer.writerow(["Language", "Files", "Blank", "Comment", "Code"])
            for language, data in language_data.items():
                csv_writer.writerow([language, data['Files'], data['Blank'], data['Comment'], data['Code']])
        bb.note("Language stats report generated: %s" % output_path)

    report_dir = d.getVar('TMPDIR') + '/deploy/cloc_reports'
    final_report_path = os.path.join(report_dir, "FinalClocReport.csv")
    generate_final_report(report_dir, final_report_path)
    bb.note("Final report generated as: %s" % final_report_path)
    if not os.path.isfile(final_report_path):
        bb.warn("FinalClocReport.csv not found in the specified directory!")
        return
    language_data = count_language_stats(final_report_path)
    output_path = os.path.join(report_dir, "LanguageStatsReport.csv")
    generate_language_stats_report(language_data, output_path)
}

python do_cloc_final_report() {
    bb.build.exec_func('do_cloc_report', d)
}

ROOTFS_POSTPROCESS_COMMAND += "${@bb.utils.contains('DISTRO_FEATURES', 'ENABLE_CLOC', 'do_cloc_final_report;', '', d)}"
