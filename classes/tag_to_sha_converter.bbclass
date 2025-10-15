# This class implementation enables the configuration of tag names in SRCREV for Git repositories,
# satisfying the developer requirement for RDK. The class method is executed after the recipe is parsed
# and the datastore is populated. It updates the SRCREV by obtaining the SHA value of the configured tag name
# through a git ls-remote query with the remote server. This implementation assumes that the necessary rules are configured
# in Git repositories to ensure the immutability of tags.

# Please note that the option to configure tag names in SRCREV is restricted in Yocto version kirkstone
# due to the mutable nature of tags in Git and the necessity for bitbake to generate consistent binaries
# from the precise source specified in the recipe at any given point in time.
# (Reference: https://github.com/yoctoproject/poky/commit/ebfa1700f41b3411aec040144605166c35b8dd14)

python () {
    import fcntl
    import json
    import sqlite3
    import concurrent.futures
    from typing import Optional
    class ShaCache:
        def __init__(self, cache_dir: str):
            self.cache_dir = os.path.join(cache_dir, "git_revision_cache")
            os.makedirs(self.cache_dir, exist_ok=True)

        def get_cache_file(self, host: str, path: str) -> str:
            cache_filename = '%s%s' % (host.replace(':', '.'), path.replace('/', '.').replace('*', '.').replace(' ','_'))
            return os.path.join(self.cache_dir, cache_filename)

        def get_sha_value(self, host: str, path: str, tag_name: str) -> Optional[str]:
            file_path = self.get_cache_file(host, path)
            lock_path = f"{file_path}.lock"

            if not os.path.exists(file_path):
                return None

            with open(lock_path, 'w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                try:
                    with open(file_path, 'r') as f:
                        data = json.load(f)
                        sha_val = data.get(tag_name)
                        if sha_val and isinstance(sha_val, str) and len(sha_val) == 40:
                            return sha_val
                except (json.JSONDecodeError, IOError):
                    # Corrupted file, remove it
                    os.remove(file_path)
                    return None
                finally:
                    fcntl.flock(lock, fcntl.LOCK_UN)
                    lock.close()

            return None

        def store_sha_value(self, host: str, path: str, tag_name: str, sha_value: str) -> None:
            if not isinstance(sha_value, str) or len(sha_value) != 40:
                raise ValueError("Invalid SHA value")

            file_path = self.get_cache_file(host, path)
            lock_path = f"{file_path}.lock"

            with open(lock_path, 'w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                try:
                    data = {}
                    if os.path.exists(file_path):
                        try:
                            with open(file_path, 'r') as f:
                                data = json.load(f)
                        except (json.JSONDecodeError, IOError):
                            # Start fresh if file is corrupted
                            data = {}

                    data[tag_name] = sha_value
                    with open(file_path, 'w') as f:
                        json.dump(data, f, indent=2)
                finally:
                    fcntl.flock(lock, fcntl.LOCK_UN)
                    lock.close()

    def get_protocol(parm):
        protocol = None
        if "protocol" in parm:
            protocol = parm.get("protocol")
        elif "proto" in parm:
            protocol = parm.get("proto")
        else:
            protocol = "https"
        return protocol

    def get_commit_sha_for_tag(url, tag_name):
        import subprocess
        try:
            commit_tag_name = "refs/tags/" + tag_name
            annotated_tag_name = "refs/tags/" + tag_name + "^{}"
            cmd = "git ls-remote --tags %s %s %s" %(url, annotated_tag_name, commit_tag_name)
            output = subprocess.check_output(cmd.split(), stderr=subprocess.STDOUT).decode("utf-8")
            for ref_name in [annotated_tag_name, commit_tag_name]:
                for line in output.split('\n'):
                    if line:
                        if line.startswith('Warning:') or not line.strip():
                            continue
                        parts = line.split('\t')
                        if len(parts) == 2:
                            sha, ref = parts
                            if ref == ref_name and len(sha.strip()) == 40:
                                return sha
            # If no valid tag found
            bb.fatal("ERROR: The tag name '%s' not found in repository '%s'" %(tag_name, url))
        except subprocess.CalledProcessError as e:
            bb.fatal("ERROR: cmd - %s failed with return code - %d\n Output:%s" %(cmd, e.returncode, e.output))
        except subprocess.TimeoutExpired as e:
            bb.fatal("ERROR: cmd - %s timed out after %s seconds" %(cmd, e.timeout))
        except Exception as e:
            bb.fatal("ERROR: cmd - %s failed with unexpected error: %s" % (cmd, str(e)))
            

    def get_srcrev(d, name, url_index):
        pn = d.getVar('PN')
        attempts = []
        if name != '' and pn:
            attempts.append('SRCREV_%s:pn-%s' % (name, pn))
        if name != '':
            attempts.append('SRCREV_%s' % name)
        if name == 'default' or url_index == 1:
            if pn:
                attempts.append('SRCREV:pn-%s' % pn)
            attempts.append('SRCREV')


        attempts_override =[]
        overrides = d.getVar('OVERRIDES').split(":") or []
        overrides = list(set(overrides))
        overrides = [x.strip() for x in overrides if x.strip()]
        for att in attempts:
            for var in overrides:
                attempts_override.append('%s:%s' %(att, var))
        attempts.extend(attempts_override)
        final_attempts = list(set(attempts))
        srcrev_dct = {}
        for att in final_attempts:
            srcrev = d.getVar(att)
            if srcrev and srcrev != "INVALID":
                srcrev_dct[att] = srcrev
        return srcrev_dct


    def process_url(type, host, path, user, pswd, parm, url_index):
        if not  user and "user" in parm:
            user = parm[user]
        name = parm.get("name",'default')
        protocol = get_protocol(parm)
        if not protocol in ["git", "http", "https", "ssh"]:
            bb.fatal("ERROR: The %s uses an invalid git protocol: '%s'" % (pn, protocol))
        srcrevs =  get_srcrev(d, name, url_index)
        for srcrev_var, srcrev in sorted(srcrevs.items()):
            # Check if the srcrev is a tag
            if srcrev and srcrev != "AUTOINC":
                # Anything that doesn't look like a sha256 checksum/revision is considered as tag
                if len(srcrev) != 40 or (False in [c in "abcdef0123456789" for c in srcrev.lower()]):
                    tag_name = srcrev
                    if user:
                        username = user + '@'
                    else:
                        username = ""
                    repo_url = "%s://%s%s%s" % (protocol, username, host, path)
                    tag_srcrev = cache.get_sha_value(host, path, tag_name)
                    if tag_srcrev is not None:
                        #bb.note("Updating tag name from cache '%s' to commit SHA '%s' in SRCREV for %s with %s" %(tag_name, tag_srcrev, pn, srcrev_var))
                        d.setVar(srcrev_var, tag_srcrev)
                    else:
                        tag_srcrev = get_commit_sha_for_tag(repo_url, tag_name)
                        if tag_srcrev:
                            #bb.note("Updating tag name '%s' to commit SHA '%s' in SRCREV for %s with %s" %(tag_name, tag_srcrev, pn, srcrev_var))
                            d.setVar(srcrev_var, tag_srcrev)
                            cache.store_sha_value(host, path, tag_name, tag_srcrev)

    def process_urls(urls):
        import bb.utils as utils
        with concurrent.futures.ThreadPoolExecutor(max_workers=utils.cpu_count()) as executor:
            futures = []
            url_index = 0;
            for url in urls:
                type, host, path, user, pswd, parm =  bb.fetch2.decodeurl(url)
                if "git" in type:
                    url_index += 1
                    futures.append(executor.submit(process_url, type, host, path, user, pswd, parm, url_index))
            for future in concurrent.futures.as_completed(futures):
                future.result()

    cache = ShaCache(d.getVar('DL_DIR'))
    pn = d.getVar('PN')
    srcuri = d.getVar('SRC_URI')
    urls = srcuri.split()

    process_urls(urls)
}

