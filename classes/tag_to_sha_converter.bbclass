# This class implementation enables the configuration of tag names in SRCREV for Git repositories,
# satisfying the developer requirement for RDK. The class method is executed after the recipe is parsed
# and the datastore is populated. It updates the SRCREV by obtaining the SHA value of the configured tag name
# through a git ls-remote query with the remote server. This implementation assumes that the necessary rules are configured
# in Git repositories to ensure the immutability of tags.

# Please note that the option to configure tag names in SRCREV is restricted in Yocto version kirkstone
# due to the mutable nature of tags in Git and the necessity for bitbake to generate consistent binaries
# from the precise source specified in the recipe at any given point in time.
# (Reference: https://github.com/yoctoproject/poky/commit/ebfa1700f41b3411aec040144605166c35b8dd14)

def get_protocol(parm):
    protocol = None
    if "protocol" in parm:
        protocol = parm.get("protocol")
    elif "proto" in parm:
        protocol = parm.get("proto")
    else:
        protocol = "https"
    #if host == "github.com" or protocol == "git":
    #    protocol = "https"
    return protocol


def get_commit_sha_for_tag(url, tag_name):
    import subprocess
    try:
        cmd = "git ls-remote --tags %s" %(url)
        output = subprocess.check_output(cmd.split(), stderr=subprocess.STDOUT).decode("utf-8")
        for n in ["refs/tags/" + tag_name + "^{}", "refs/tags/" + tag_name]:
            for line in output.split('\n'):
                if line:
                    sha, ref = line.split('\t')
                    if ref == n:
                        return sha
        # If no valid tag found
        bb.fatal("ERROR: The tag name '%s' does not exist for url '%s'" %(tag_name, url))
    except subprocess.CalledProcessError as e:
        bb.fatal("ERROR: cmd - %s failed with %s" %(cmd, e.output))


def get_srcrev(d, name):
    pn = d.getVar('PN')
    attempts = []
    if name != '' and pn:
        attempts.append("SRCREV_%s:pn-%s" % (name, pn))
    if name != '':
        attempts.append("SRCREV_%s" % name)
    if pn:
        attempts.append("SRCREV:pn-%s" % pn)
    attempts.append("SRCREV")

    for att in attempts:
        srcrev = d.getVar(att)
        if srcrev and srcrev != "INVALID":
            return att, srcrev
    return None


python convert_tag_to_sha() {
    pn = d.getVar('PN')
    srcuri = d.getVar('SRC_URI')
    urls = srcuri.split()

    for url in urls:
        (type, host, path, user, pswd, parm) =  bb.fetch2.decodeurl(url)
        if "git" in type:
            if not  user and "user" in parm:
                user = param[user]
            name = parm.get("name",'default')
            protocol = get_protocol(parm)
            if not protocol in ["git", "http", "https", "ssh"]:
                bb.fatal("ERROR: The URL '%s' for %s uses an invalid git protocol: '%s'" % (url, pn, protocol))
            srcrev_var, srcrev =  get_srcrev(d, name) or (None, None)
            # Check if the srcrev is a tag
            if srcrev and srcrev != "AUTOINC":
                # Anything that doesn't look like a sha256 checksum/revision is considered as tag
                if len(srcrev) != 40 or (False in [c in "abcdef0123456789" for c in srcrev.lower()]):
                   if user:
                       username = user + '@'
                   else:
                       username = ""
                   tag_name = srcrev
                   repo_url = "%s://%s%s%s" % (protocol, username, host, path)
                   tag_srcrev = get_commit_sha_for_tag(repo_url, tag_name)
                   if tag_srcrev:
                       bb.note("Updating tag name '%s' to commit SHA '%s' in SRCREV for %s" %(tag_name, tag_srcrev, pn))
                       d.setVar(srcrev_var, tag_srcrev)
}


addhandler convert_tag_to_sha
convert_tag_to_sha[eventmask] = "bb.event.RecipeParsed"
