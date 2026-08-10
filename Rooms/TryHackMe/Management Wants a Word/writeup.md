# TryHackMe: Management Wants a Word Writeup

**Room Link:** [Management Wants a Word](https://tryhackme.com/room/hh-managementwantsaword-6bf3cc41)

---

## Scenario

Housekeeping found a guest's laptop left behind after an early checkout — Room 214, registered to "Vera." IT pulled a full forensic triage before wiping it for the next guest. The objective is to work through the artifacts on disk, recover a password Vera never meant to leave behind, and follow it to something she was keeping quiet.

## Profile Discovery

Enumerating user profiles on the mounted disk image:

```bash
find . -type f -iname "NTUSER.DAT" -print
```

```text
./Users/Default/NTUSER.DAT
./Users/vera/NTUSER.DAT
./Windows/ServiceProfiles/LocalService/NTUSER.DAT
./Windows/ServiceProfiles/NetworkService/NTUSER.DAT
```

`./Users/vera/NTUSER.DAT` confirms a real logged-on profile for Vera. A lookup of `ProfileList` in the `SOFTWARE` hive didn't return anything useful, so profile enumeration moved on to Vera's `AppData` directly.

## Recovering the Windows Password from Registry Hives

With the local `SYSTEM`, `SAM`, and `SECURITY` hives extracted from the KAPE collection, `pypykatz registry` parses them offline — no live LSASS access required:

```bash
pypykatz registry Windows/System32/config/SYSTEM \
  --sam Windows/System32/config/SAM \
  --security Windows/System32/config/SECURITY \
  --software Windows/System32/config/SOFTWARE \
  -o ~/vera-registry.txt
```

Alongside the local SAM account hashes, this dumps the machine's **LSA secrets** — the registry-protected store (`HKLM\SECURITY\Policy\Secrets`) Windows uses for things like service-account credentials and autologon passwords:

```text
LSA Default Password:
Password: minivera
```

The `DefaultPassword` LSA secret exists specifically to support Windows autologon — for the OS to log a user in automatically at boot, it has to keep that account's password recoverable, not just hashed, in a location protected only by SYSTEM-level registry access. Since offline hive extraction grants exactly that access, the password falls out directly, with no cracking required.

## Recovering the DPAPI Master Key

Windows DPAPI protects secrets like saved browser passwords with a per-user master key, which is itself encrypted using a key derived from the user's logon password. Checking Vera's DPAPI directory:

```bash
find "./Users/vera/AppData/Roaming/Microsoft/Protect" -type f -print
```

```text
./Users/vera/AppData/Roaming/Microsoft/Protect/S-1-5-21-2529683458-431225740-1723070931-1000/c90719ef-5b98-474e-b934-136d606a702a
./Users/vera/AppData/Roaming/Microsoft/Protect/S-1-5-21-2529683458-431225740-1723070931-1000/Preferred
```

Vera's SID is read directly from the `Protect\<SID>` folder name. The `Preferred` file identifies which master key GUID is active:

```bash
pypykatz dpapi preferredkey \
  "./Users/vera/AppData/Roaming/Microsoft/Protect/S-1-5-21-2529683458-431225740-1723070931-1000/Preferred"
# [GUID] c90719ef-5b98-474e-b934-136d606a702a
```

With `minivera` recovered from LSA secrets, prekeys can be derived for that SID:

```bash
pypykatz dpapi prekey password \
  "S-1-5-21-2529683458-431225740-1723070931-1000" \
  "minivera" \
  -o ~/vera-password-prekeys.txt
```

These candidate keys successfully decrypt the master key file:

```bash
pypykatz dpapi masterkey \
  "./Users/vera/AppData/Roaming/Microsoft/Protect/S-1-5-21-2529683458-431225740-1723070931-1000/c90719ef-5b98-474e-b934-136d606a702a" \
  ~/vera-password-prekeys.txt \
  -o ~/vera-masterkey.txt
```

## Decrypting Chrome Credentials

With the DPAPI master key in hand, Chrome's encrypted credential store can be decrypted:

```bash
pypykatz dpapi chrome \
  ~/vera-masterkey.txt \
  "./Users/vera/AppData/Local/Google/Chrome For Testing/User Data/Local State" \
  --logindata "./Users/vera/AppData/Local/Google/Chrome For Testing/User Data/Default/Login Data"
```

This recovers a saved credential:

```text
user: VeraSecretVault
pass: Wh4t1sV3raD0inG0nTh1sH0st
url:  http://bytelotus.thm:8080/login
```

## Browser History

Querying Chrome's history database corroborates the finding:

```bash
sqlite3 "./Users/vera/AppData/Local/Google/Chrome For Testing/User Data/Default/History" \
  "SELECT datetime(last_visit_time/1000000-11644473600,'unixepoch'), url, title FROM urls ORDER BY last_visit_time DESC;"
```

```text
2026-07-19 22:58:50 | Google search: tryhackme
2026-07-19 22:58:47 | Google search: how to exfiltrate data red teaming
2026-07-19 22:58:09 | Google search: chrome cves
2026-07-19 22:53:45 | http://bytelotus.thm:8080/         | SecureVault Portal
2026-07-19 22:53:30 | http://bytelotus.thm:8080/login    | Error
```

## Finding the Hidden Container

Searching for suspicious backup/container files:

```bash
find . -type f \( -iname "*backup*" -o -iname "*.hc" -o -iname "*.vhd*" -o -iname "*.img" \) -ls
```

```text
./Users/vera/Documents/backup   (104857600 bytes)
```

The file has no extension, and `file` only reports it as generic `data` — expected, since VeraCrypt/TrueCrypt containers are designed to be indistinguishable from random data without the passphrase. Checking its structure:

```bash
sudo cryptsetup tcryptDump "./Users/vera/Documents/backup"
```

```text
VERACRYPT header information for ./Users/vera/Documents/backup
Version:        5
Driver req.:    1.b
Sector size:    512
MK offset:      131072
PBKDF2 hash:    sha512
Cipher chain:   aes
Cipher mode:    xts-plain64
MK bits:        512
```

Readable header output confirms the passphrase (from the recovered Chrome credential) successfully decrypts it. Mounting the volume:

```bash
sudo mkdir -p /mnt/vera_backup
sudo cryptsetup open --type tcrypt --veracrypt \
  "./Users/vera/Documents/backup" vera_backup
sudo mount /dev/mapper/vera_backup /mnt/vera_backup
```

## Inside the Vault

```bash
find /mnt/vera_backup -maxdepth 4 -type f -ls
```

```text
/mnt/vera_backup/secret_financial_documents/important_invoice_byte_lotus.pdf
/mnt/vera_backup/secret_financial_documents/transactions_q3.csv
```

The CSV contains routine transactions, plus one outlier:

```text
2026-07-12,TXN-10531,Internal Adjustment,Image asset correction,0.00,Archived
```

A $0.00 line item referencing "image" is a clear pointer toward the PDF being the next artifact of interest.

## The Trick Invoice

```bash
pdfinfo important_invoice_byte_lotus.pdf
# no metadata, no JavaScript, not encrypted, 1 page
pdftotext important_invoice_byte_lotus.pdf /tmp/invoice.txt
cat /tmp/invoice.txt
# (empty)
```

Empty text extraction means the invoice isn't a real text layer — checking for embedded objects:

```bash
pdfimages -list important_invoice_byte_lotus.pdf
```

```text
page num type   width height color comp bpc  enc     interp object ID
1    0   image  636   724   icc   3    8    image   no      3
1    1   smask  636   724   gray  1    1    ccitt   no      3
```

Raw object inspection confirms `/Type/XObject/Subtype/Image`, with the image stream itself header-tagged `%JP2` (JPEG 2000). The "invoice" is really just a picture pasted into a one-page PDF generated by MuPDF.

## Extracting the Flag

```bash
mkdir -p /tmp/invoice_extract
pdfimages -all important_invoice_byte_lotus.pdf /tmp/invoice_extract/img
ls -lh /tmp/invoice_extract
file /tmp/invoice_extract/*
```

Extracting and inspecting the embedded image directly reveals the flag hidden inside it, rather than anywhere in the PDF's text or metadata layers.

## Key Takeaways

- **Offline registry hive extraction beats live-system credential access.** Pulling `SYSTEM`/`SAM`/`SECURITY` off a disk image and parsing them with `pypykatz registry` exposes LSA secrets — including an autologon `DefaultPassword` — without ever touching a running LSASS process.
- **Local-account DPAPI security reduces to the strength of the logon password.** No domain backup key exists for local accounts, so recovering the master key is entirely gated on recovering the password.
- **A VeraCrypt/TrueCrypt container with no extension is intentional, not an oversight.** `file` reporting `data` is expected — the format is designed to be indistinguishable from random noise without the key.
- **`pdftotext` returning nothing is a signal, not a dead end.** Rasterized/scanned content defeats naive text search; `pdfimages -list` is the next step.
- **Contextual clues in unrelated artifacts matter.** The `$0.00 "Image asset correction"` CSV entry was the pointer that made the trick invoice worth investigating further.

Flag recovered (redacted here — solve the room yourself to get the exact value).
