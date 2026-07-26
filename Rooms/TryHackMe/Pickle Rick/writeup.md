# TryHackMe: Pickle Rick Writeup

**Room Link:** [Pickle Rick](https://tryhackme.com/room/picklerick)

---

## Initial Enumeration

We kick things off with an Nmap scan to reveal open ports:

```bash
nmap -sC 10.10.119.47
```

**Results:**
```text
PORT   STATE SERVICE
22/tcp open  ssh
80/tcp open  http
```

Visiting the web page on port 80 reveals a title: `Rick is sup4r cool`.

Checking the page's source code, we hit our first lucky break—a hidden HTML comment:
```html
<!--
  Note to self, remember username!
  Username: R1ckRul3s
-->
```

**Username obtained:** `R1ckRul3s`

To see if there are any low-hanging fruits, we check `http://10.10.119.47/robots.txt`. The file contains a single string:
`Wubbalubbadubdub`

This feels like a password. Let's try to log into SSH using the discovered username and password.

```bash
ssh R1ckRul3s@10.10.119.47
R1ckRul3s@10.10.119.47: Permission denied (publickey).
```
SSH requires public key authentication, so we can't get in immediately.

## Web Exploitation

Since SSH failed, let's explore the web application further using `gobuster` to find hidden directories and PHP files:
```bash
gobuster dir -u http://10.10.119.47 -w /usr/share/wordlists/dirb/common.txt -x php
```

This scan uncovers:
- `/assets` (Directory)
- `/login.php`
- `/portal.php`

Navigating to `login.php`, we are greeted with a login portal. Using our discovered credentials (`R1ckRul3s` : `Wubbalubbadubdub`), we successfully log in and are redirected to `/portal.php`.

The portal has several tabs, but clicking anywhere else leads to `/denied.php`. We need to gain more privileges, but there is a command execution panel right in front of us.

## Command Execution & Filter Bypass

Typing `ls` into the prompt and executing it gives us our directory contents! 
However, trying to read a file with `cat <file>` triggers a warning message indicating that the command is disabled to make the challenge harder. Let's dig into the source code of the portal page.

Inside the page source, we find another hidden comment containing what looks like Base64:
`Vm1wR1UxTnRWa2RUV0d4VFlrZFNjRlV3V2t0alJsWnlWbXQwVkUxV1duaFZNakExVkcxS1NHVkliRmhoTVhCb1ZsWmFWMVpWTVVWaGVqQT0==`

Base64 decoding this string several times iteratively eventually yields:
`rabbit hole`

It seems this was just a distraction. Let's return to the command execution portal. Since `cat` is blacklisted, we need an alternative way to read files. We know `ls` works, so we can see what's in the current directory:
- `Sup3rS3cretPickl3Ingred.txt`
- `clue.txt`
- `portal.php`

Instead of bypassing the command line to read `.txt` files in the web root, we can just access them via the browser!
Appending `/Sup3rS3cretPickl3Ingred.txt` to our URL reveals the **first ingredient** (redacted — solve the room to get the exact value).

Appending `/clue.txt` reveals:
`Look around the file system for the other ingredient.`

Back on the command panel, we can use `tac` (which reads files backwards) since `cat`, `head`, `more`, `tail`, `nano`, `vim`, and `vi` are blocked. Let's see if we can read the restricted command list from `portal.php`:
```bash
tac portal.php
```
It returns the source code, confirming `tac` works!

## Escalation and Finding the Ingredients

Using our `ls` command, let's inspect the `/home` directory.
```bash
ls /home
```
This reveals the user `rick`. Let's inspect Rick's folder:
```bash
ls /home/rick
```
Rick's directory contains a file called `second ingredients`. We can read it using `tac` (remember to wrap the filename in quotes since it contains a space):
```bash
tac "/home/rick/second ingredients"
```

**Second ingredient:** obtained (redacted — solve the room to get the exact value).

To get to the final ingredient, we'll likely need root access. Let's check our `sudo` privileges:
```bash
sudo -l
```
This reveals the user mapping for `www-data` lets us run *all* commands implicitly as root without needing a password. (The web portal interface's blacklists still apply to our shell execution, though).

Using `sudo ls /root`, we find two files inside the root directory:
- `3rd.txt`
- `snap`

We use `sudo tac` to read the final file while bypassing the `cat` restriction:
```bash
sudo tac /root/3rd.txt
```

**Third ingredient:** obtained (redacted — solve the room to get the exact value).

