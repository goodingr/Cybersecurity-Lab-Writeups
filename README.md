
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
