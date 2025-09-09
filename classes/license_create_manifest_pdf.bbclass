# Copyright 2024 Comcast Cable Communications Management, LLC
# SPDX-License-Identifier: GPL-2.0-only
# Populates image specific license_manifest.pdf from license.manifest
# functionality is almost similar to "license_create_manifest"
# instead of writing license name, write license text
# Some material is taken from the Yocto Project and is:
# Copyright The Yocto Project
# Licensed under the GPLv2 License
copy_license_text() {
    if [ ! -f ${LICENSE_DIRECTORY}/${IMAGE_NAME}/package.manifest ];then
        bbwarn "package.manifest does not exist exiting!"
        exit 0
    fi

    # Get the whitelist packages and bad licenses (note: adding space at both ends for better grep)
    WHITELIST=" ${WHITELIST_GPLv3} ${LGPLv2_WHITELIST_GPLv3} ${LICENSE_FLAGS_WHITELIST} ${LICENSE_FLAGS_ACCEPTED} "
    BAD_LICENSE=" ${INCOMPATIBLE_LICENSE} "

    INSTALLED_PKGS=`cat ${LICENSE_DIRECTORY}/${IMAGE_NAME}/package.manifest`
    #create a directory for copying licenses
    LICENSE_TEXT_DIRECTORY="${LICENSE_DIRECTORY}/${IMAGE_NAME}/licensetext"
    if [ ! -d ${LICENSE_TEXT_DIRECTORY} ];then
        mkdir ${LICENSE_TEXT_DIRECTORY}
    fi
    for pkg in ${INSTALLED_PKGS}; do
        bbnote "copying licenses for $pkg"
        if echo "${WHITELIST}" | grep -q "[[:space:]]${pkg}[[:space:]]" 2>/dev/null; then
            bbnote "skipping ${pkg} form copying licenses"
            continue
        fi
        
        if ! [ -e "${PKGDATA_DIR}/runtime-reverse/${pkg}" ];then
            bbnote "skipping ${pkg} form copying licenses"
            continue
        fi

        filename=`ls ${PKGDATA_DIR}/runtime-reverse/${pkg}| head -1`
        pkged_pn="$(sed -n 's/^PN: //p' ${filename})"
        pkged_name="$(basename $(readlink ${filename}))"
        pkged_lic="$(sed -n "/^LICENSE_${pkged_name}: /{ s/^LICENSE_${pkged_name}: //; s/[|&()*]/ /g; s/  */ /g; p }" ${filename})"
        if [ -z ${pkged_lic} ]; then
            # fallback checking value of LICENSE
            pkged_lic="$(sed -n "/^LICENSE: /{ s/^LICENSE: //; s/[|&()*]/ /g; s/  */ /g; p }" ${filename})"
        fi
        for lic in ${pkged_lic}; do
            bbnote "license = $lic"
            if echo "${BAD_LICENSE}" | grep -q "[[:space:]]${lic}[[:space:]]" 2>/dev/null; then
                bbnote "skipping ${lic} form getting copied"
                continue
            fi
            #to reference a license file trim trailing + symbol
            if ! [ -e "${LICENSE_DIRECTORY}/${pkged_pn}/generic_${lic%+}" ];then
                bbwarn "The license listed ${lic} was not in the licenses collected for ${pkged_pn}"
            else
                if [ ! -f ${LICENSE_TEXT_DIRECTORY}/generic_${lic%+} ];then
                    cp ${LICENSE_DIRECTORY}/${pkged_pn}/generic_${lic%+} ${LICENSE_TEXT_DIRECTORY}/.
                fi
            fi
        done
    done
}


def remove_duplicate_license(d):
    import oe.license

    # recipe use different license name some uses GPLv2 and some GPL-2.0
    # this results in having duplicate licenses in licenses directory
    # SPDXLICENSEMAP (from licenses.conf) maintains map of different license strings and actual license
    license_list = []
    license_text_dir = os.path.join(d.expand('${LICENSE_DIRECTORY}/${IMAGE_NAME}'), 'licensetext')
    bb.note("Working on %s" % license_text_dir)
    for root, dirs, files in os.walk(license_text_dir):
        for fl in files:
            lic = fl.replace("generic_", "")
            spdx_lic = d.getVarFlag('SPDXLICENSEMAP', lic, True)
            if spdx_lic == None:
                if lic not in license_list:
                    license_list.append(lic)
                else:
                    bb.note("removing license file: %s" % os.path.join(root, fl))
                    os.remove(os.path.join(root, fl))
            elif spdx_lic not in license_list:
                license_list.append(spdx_lic)
                print('adding spdx %s to list' % spdx_lic)
            else:
                bb.note("removing license file: %s" % os.path.join(root, fl))
                os.remove(os.path.join(root, fl))


python create_license_manifest() {

    remove_duplicate_license(d)
    import sys
    sys.path.append(d.expand('${STAGING_DIR_NATIVE}/${PYTHON_SITEPACKAGES_DIR}/'))

    try:
        from reportlab.pdfgen import canvas
    except ImportError:
        bb.warn("Need to install PiPy from ReportLab")
        license_create_txt(d)
    else:
        license_create_pdf(d)
}

pull_license_frm_artifactory() {

    cd ${LICENSE_DIRECTORY}/${IMAGE_NAME}
    artifactory_paths="${@d.getVar('IPK_FEED_URIS')}"
    machine="${@d.getVar('MACHINE')}"
    echo "Machine: $machine"
    echo $artifactory_paths
    # From below path variable "artifactory_paths" we removed some sensitive strings about IPK server path which need to be reworked or reconstructed after open-sourcing.
    artifactory_paths=$(echo $artifactory_paths | tr ' ' '\n' | grep -o -e 'http[s]*://[^ ]*' -e 'file*:[/][^ ]*')
    echo "Final artifactory paths: $artifactory_paths"
    for artifactory_path in $artifactory_paths; do
        set +e
        echo "Downloading licenses from $artifactory_path"
        if [[ "$artifactory_path" == *"http"* ]]
        then
            wget -r -np -nd --cut-dirs=3 --reject="index.html*" $artifactory_path/$machine/licenses/
        elif [[ "$artifactory_path" == "file://"* ]]
        then
            # Remove the file prefix. cp does not need it.
            copy_path=${artifactory_path#"file://"}
            cp $copy_path/licenses/* .
        fi
        set -e
    done
    ls -la
    for tar_file in ./*.tar;
    do
        if [ -e "$tar_file" ];
        then
            echo "Extracting $tar_file"
            tar -xvf "$tar_file" --no-same-owner 
        else
            echo "No .tar files found in the current directory"
            break
        fi
    done
}

python assemble_license_manifest() {

    bb.note("Assembling License Manifest")
    remove_duplicate_license(d)
    import sys
    sys.path.append(d.expand('${STAGING_DIR_NATIVE}/${PYTHON_SITEPACKAGES_DIR}/'))

    try:
        from reportlab.pdfgen import canvas
    except ImportError:
        bb.warn("Need to install PiPy from ReportLab")
        license_create_txt(d)
    else:
        license_create_pdf(d)
}


def license_create_pdf(d):
    #Closed opensource licenses
    ClosedOpenSourceLicenses = "Adobe MIT MIT-style BSD-3-Clause GFDL-1.2 GFDL-1.3"

    #Proprietary Licenses
    ProprietaryLicenses = "Broadcom CableLabs CLOSED Comcast RDK SeaChange PioneerDigital GreenPeak"


    license_text_dir = os.path.join(d.expand('${LICENSE_DIRECTORY}/${IMAGE_NAME}'), 'licensetext')
    license_manifest_pdf = os.path.join(d.expand('${LICENSE_DIRECTORY}'), d.expand('${IMAGE_NAME}')+'_license_manifest.pdf')
    #Adapted from ReportLab Inc.:
    #Copyright (c) 2000-2004, ReportLab Inc.
    #Licensed under the BSD-3 license

    import datetime
    import codecs
    from reportlab.lib.styles import ParagraphStyle as PS
    from reportlab.platypus import PageBreak
    from reportlab.platypus.paragraph import Paragraph
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.platypus.doctemplate import PageTemplate, BaseDocTemplate
    from reportlab.platypus.tableofcontents import TableOfContents
    from reportlab.platypus.frames import Frame
    from reportlab.lib.units import cm
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.enums import TA_CENTER

    styleSheet = getSampleStyleSheet()

    class LicenseManifestTemplate(BaseDocTemplate):

        def __init__(self, filename, **kw):
            self.allowSplitting = 0
            BaseDocTemplate.__init__(self, filename, **kw)
            frameT = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id='normal')
            template = PageTemplate('normal', frames=frameT)
            self.addPageTemplates(template)

        def beforePage(self):
            self.canv.setFont('Times-Italic',12)
            self.canv.drawString(self.leftMargin, self.height+4*cm, d.getVar('IMAGE_NAME', True))
            self.canv.line(self.leftMargin, self.height+4*cm-3, self.width+self.rightMargin, self.height+4*cm-3)

        def afterPage(self):
            self.canv.line(self.leftMargin, 1 * cm, self.width+self.rightMargin, 1 * cm)
            self.canv.drawCentredString(0.5*letter[0], 0.5 * cm, "Page %d" % self.canv.getPageNumber())

        def afterFlowable(self, flowable):
            "Registers TOC entries."
            if flowable.__class__.__name__ == 'Paragraph':
                text = flowable.getPlainText().replace('generic_', '')
                style = flowable.style.name
                key = 'ch%s' % self.seq.nextf('chapter')
                self.canv.bookmarkPage(key)
                if style == 'Heading1':
                    self.notify('TOCEntry', (0, text, self.page, key))

    h1 = PS(name = 'Heading1',
           fontSize = 14,
           leading = 16)


    # Build story.
    story = []
    story.append(Paragraph('Opensource License Manifest', styleSheet['Title']))
    story.append(Paragraph(d.getVar('MACHINE_ARCH', True), styleSheet['Title']))
    myDateFormat = datetime.datetime.strptime(d.getVar('DATE', True), '%Y%m%d')
    story.append(Paragraph(myDateFormat.strftime('%b %d %Y'), styleSheet['Title']))
    story.append(PageBreak())
    story.append(Paragraph('Licenses', styleSheet['Title']))
    toc = TableOfContents()
    # For conciseness we use the same styles for headings and TOC entries
    toc.levelStyles = [h1]
    story.append(toc)
    story.append(PageBreak())
    for root, dirs, files in os.walk(license_text_dir):
        for fl in files:
            licString=fl.replace('generic_', '')
            if licString in ClosedOpenSourceLicenses.split() or licString in ProprietaryLicenses.split():
                continue
            story.append(Paragraph(licString, styleSheet['Heading1']))
            story.append(Paragraph('\n\n\n', PS('body')))
            licFile=codecs.open(os.path.join(root, fl), 'r', encoding='utf8', errors='ignore')
            licTextList=licFile.readlines()
            for li in licTextList:
                # GPL-*-exception licenses in openembedded-core does not have the parent license text
                # following is added to update pdf with parent license text
                if li.strip() in ['insert GPL v2 license text here', 'insert GPL v2 text here']:
                    gplv2File=os.path.join(d.getVar('COREBASE', True), 'meta/files/common-licenses/GPL-2.0')
                    if os.path.isfile(gplv2File):
                        gplv2FileOpen=codecs.open(gplv2File, 'r', encoding='utf8', errors='ignore')
                        gplv2text=gplv2FileOpen.readlines()
                        for gplv2line in gplv2text:
                            story.append(Paragraph(gplv2line, styleSheet['BodyText']))
                        gplv2FileOpen.close()
                elif li.strip() in ['insert GPL v3 text here']:
                    gplv3File=os.path.join(d.getVar('COREBASE', True), 'meta/files/common-licenses/GPL-3.0')
                    if os.path.isfile(gplv3File):
                        gplv3FileOpen=codecs.open(gplv3File, 'r', encoding='utf8')
                        gplv3text=gplv3FileOpen.readlines()
                        for gplv3line in gplv3text:
                            story.append(Paragraph(gplv3line, styleSheet['BodyText']))
                        gplv3FileOpen.close()
                else:
                    story.append(Paragraph(li, styleSheet['BodyText']))
            licFile.close()
            story.append(PageBreak())

    doc = LicenseManifestTemplate(license_manifest_pdf, pagesize=letter)
    doc.title = "Opensource License Manifest"
    doc.multiBuild(story)


def license_create_txt(d):
    #Closed opensource licenses
    ClosedOpenSourceLicenses = "Adobe MIT MIT-style BSD-3-Clause GFDL-1.2 GFDL-1.3 PD"

    #Proprietary Licenses
    ProprietaryLicenses = "Broadcom CableLabs CLOSED Comcast RDK SeaChange PioneerDigital GreenPeak"

    license_text_dir = os.path.join(d.expand('${LICENSE_DIRECTORY}/${IMAGE_NAME}'), 'licensetext')
    license_manifest_txt = os.path.join(license_text_dir, 'license_manifest.txt')

    with open (license_manifest_txt, 'w') as lic_txt:
        for root, dirs, files in os.walk(license_text_dir):
            for fl in files:
                licString=fl.replace("generic", "")
                if licString in ClosedOpenSourceLicenses.split() or licString in ProprietaryLicenses.split():
                    continue
                licFile = open(os.path.join(root, fl))
                txt = licFile.read()
                lic_txt.write (licString);
                lic_txt.write(txt)
                licFile.close()

#create license manifest without closed and proprietary licenses
create_custom_license_manifest() {
    # Test if BUILD_IMAGES_FROM_FEEDS is defined in env
    if [ -n "${BUILD_IMAGES_FROM_FEEDS}" ]; then
        exit 0
    fi

    #Closed opensource licenses
    ClosedOpenSourceLicenses="Adobe MIT MIT-style BSD-3-Clause GFDL-1.2 GFDL-1.3"

    #Proprietary Licenses
    ProprietaryLicenses="Broadcom CableLabs CLOSED Comcast RDK SeaChange PioneerDigital GreenPeak"

    INSTALLED_PKGS=`cat ${LICENSE_DIRECTORY}/${IMAGE_NAME}/package.manifest`
    LICENSE_MANIFEST="${LICENSE_DIRECTORY}/${IMAGE_NAME}_license.manifest"

    # remove existing license.manifest file
    if [ -f ${LICENSE_MANIFEST} ]; then
        rm ${LICENSE_MANIFEST}
    fi

    touch ${LICENSE_MANIFEST}

    for pkg in ${INSTALLED_PKGS}; do
        filename=`ls ${PKGDATA_DIR}/runtime-reverse/${pkg}| head -1`
        pkged_pn="$(sed -n 's/^PN: //p' ${filename})"

        # check to see if the package name exists in the manifest. if so, bail.
        if grep -q "^PACKAGE NAME: ${pkg}" ${LICENSE_MANIFEST}; then
            continue
        fi

        pkged_pv="$(sed -n 's/^PV: //p' ${filename})"
        pkged_name="$(basename $(readlink ${filename}))"
        pkged_lic="$(sed -n "/^LICENSE_${pkged_name}: /{ s/^LICENSE_${pkged_name}: //; s/[|&()*]/ /g; s/  */ /g; p }" ${filename})"
        if [ -z ${pkged_lic} ]; then
            # fallback checking value of LICENSE
            pkged_lic="$(sed -n "/^LICENSE: /{ s/^LICENSE: //; s/[|&()*]/ /g; s/  */ /g; p }" ${filename})"
        fi

        #checking closed or prop license in the package license
        ignoreLIC=0
        for lic in ${pkged_lic}; do
           for closed in ${ClosedOpenSourceLicenses}; do
                if [ "${lic}" = "${closed}" ]; then
                    ignoreLIC=1
                fi
            done
            for prop in ${ProprietaryLicenses}; do
                if [ "${lic}" = "${prop}" ]; then
                    ignoreLIC=1
                fi
            done
        done
        #if any of the license is closed or prop, do not add the package in license manifest
        if [ ${ignoreLIC} -eq 1 ]; then
            continue
        fi

        echo "PACKAGE NAME:" ${pkg} >> ${LICENSE_MANIFEST}
        echo "PACKAGE VERSION:" ${pkged_pv} >> ${LICENSE_MANIFEST}
        echo "RECIPE NAME:" ${pkged_pn} >> ${LICENSE_MANIFEST}
        printf "LICENSE:" >> ${LICENSE_MANIFEST}
        for lic in ${pkged_lic}; do
            #to reference a license file trim trailing + symbol
            if ! [ -e "${LICENSE_DIRECTORY}/${pkged_pn}/generic_${lic%+}" ]; then
                bbwarn "The license listed ${lic} was not in the licenses collected for ${pkged_pn}"
            fi
            printf " ${lic}" >> ${LICENSE_MANIFEST}
        done
        printf "\n\n" >> ${LICENSE_MANIFEST}
    done
}


#append below task to ROOTFS_POSTPROCESS_COMMAND
ROOTFS_POSTPROCESS_COMMAND += "copy_license_text ; "
ROOTFS_POSTPROCESS_COMMAND += "${@ 'create_custom_license_manifest ; create_license_manifest ;' if d.getVar('LAYER_NAME') else 'pull_license_frm_artifactory ; assemble_license_manifest ; '}"
