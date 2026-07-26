
My personal archive of CTF challenges and lab walkthroughs! 
This repository serves as a knowledge base and study guide tracking my progression across various cybersecurity training platforms. Inside, you'll find comprehensive notes and exploitation methodologies for the environments I've compromised.
### Profiles
TryHackMe https://tryhackme.com/p/bobbybojanglles

Hack the Box https://app.hackthebox.com/users/816258


## Walkthroughs

Below is an index of the environments documented in this repository:

| Platform | Target Name | Difficulty level | Overview |
|:---:|---|:---:|---|
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Watcher**](./Rooms/TryHackMe/Watcher/writeup.md) | Medium | A classic boot2root Linux scenario focusing on web exploitation flows (LFI) and chained privilege escalation techniques to gain root access. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**LazyAdmin**](./Rooms/TryHackMe/LazyAdmin/writeup.md) | Easy | Exploiting a SweetRice CMS backup leak to crack credentials, uploading a PHP reverse shell through an ads injection vulnerability, and escalating to root via a writable Perl backup script. |
| ![Hack the Box](https://img.shields.io/badge/Hack%20the%20Box-red) | [**Codify**](./Rooms/Hack%20the%20Box/Codify/writeup.md) | Easy | Exploiting a vm2 sandbox escape (CVE-2023-30547) for initial access, cracking a bcrypt hash from a SQLite database for lateral movement, and abusing a bash glob pattern bypass with pspy to leak root credentials. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Madness**](./Rooms/TryHackMe/Madness/writeup.md) | Easy | An image forensics and path brute forcing challenge that leads to SSH access via ROT13, ending in a SUID privilege escalation to root. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Net Sec Challenge**](./Rooms/TryHackMe/Net%20Sec%20Challenge/writeup.md) | Medium | A network security skills challenge using Nmap banner grabbing to find hidden flags, Hydra to brute force FTP credentials, and a stealthy Null scan to evade IDS detection. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Opacity**](./Rooms/TryHackMe/Opacity/writeup.md) | Easy | Exploiting an insecure file upload to grab a KeePass database and escalating privileges through cracked credentials and an insecure backup script. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Phishing Analysis Fundamentals**](./Rooms/TryHackMe/Phishing%20Analysis%20Fundamentals/writeup.md) | Easy | A walkthrough of email anatomy, delivery protocols, header analysis, body inspection, and common phishing attack types for SOC analysts. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Pickle Rick**](./Rooms/TryHackMe/Pickle%20Rick/writeup.md) | Easy | A Rick and Morty themed web exploitation challenge where you bypass command execution filters to find all the ingredients to turn Rick back into a human. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**The Greenholt Phish**](./Rooms/TryHackMe/The%20Greenholt%20Phish/writeup.md) | Easy | Investigating a Business Email Compromise phishing email through header analysis, SPF/DMARC validation, and malicious attachment forensics. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**UltraTech**](./Rooms/TryHackMe/UltraTech/writeup.md) | Medium | Enumerating a Node.js REST API and Apache web server, exploiting a command injection vulnerability in a ping endpoint to dump an SQLite database, cracking MD5 hashes, and escalating to root via Docker group membership. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Willow**](./Rooms/TryHackMe/Willow/writeup.md) | Medium | Decoding a hex-encoded RSA-encrypted SSH key found via NFS, cracking the key passphrase with John the Ripper, escalating to root through a sudo mount exploit, and recovering the root flag from a steganography image. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Internal**](./Rooms/TryHackMe/Internal/writeup.md) | Medium | Cracking WordPress credentials to get a shell via the theme editor, pivoting through leaked credentials to a low-privileged user, brute forcing an internal Jenkins instance over an SSH tunnel, and gaining RCE through the Jenkins Script Console. |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Cat Pictures 2**](./Rooms/TryHackMe/Cat%20Pictures%202/writeup.md) | Medium | Recovering Gitea credentials from image metadata, weaponizing an Ansible playbook triggered through an OliveTin runner for a shell as a low-privileged user, and escalating to root via the sudo Baron Samedit heap overflow (CVE-2021-3156). |
| ![TryHackMe](https://img.shields.io/badge/TryHackMe-red) | [**Super Secret Tip**](./Rooms/TryHackMe/Super%20Secret%20Tip/writeup.md) | Medium | Leaking Flask source code to find an SSTI vulnerability, recovering an XOR-encoded debug password, spoofing an IP-based access check, achieving RCE via Jinja2 sandbox escape, and chaining a writable `.profile` with a root cron job to read protected files. |
