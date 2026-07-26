# TryHackMe: The Greenholt Phish Writeup

**Room Link:** [The Greenholt Phish](https://tryhackme.com/room/phishingemails5fgjlzxc)

---

## Scenario

A sales executive at Greenholt has reported a suspicious email from a known customer. The message raised several red flags: a generic greeting, an unexpected request for a money transfer, and an unsolicited attachment. This behavior doesn't align with the customer's usual communication style, so the message has been escalated to the SOC for investigation.

Our goal is to analyze the provided `.eml` file and determine whether the email is legitimate or part of a phishing attempt.

---

## Analyzing the Email Content

We start by opening `challenge.eml` on the deployed VM. The email body claims to be a SWIFT payment notification from "Mr. James Jackson" at SEC Marine Services.

The **Transfer Reference Number** listed in the email's subject line is `09674321`.

The email body contains transaction details:

```
Interbank Transfer Reference Number: 09674321
Transaction Status: Successful
Transaction Date / Time: 10-06-2020 09:18:55
Transaction Description: Balance / Final Payment
From Account: 3105234819
Amount: 149,650
Currency: USD
Bank Charges: $146.05
```

This is textbook Business Email Compromise (BEC) — impersonating a known contact and referencing a financial transaction to create urgency.

---

## Investigating the Email Headers

Next, we examine the email headers to identify the true origin.

**Display name of the sender:** `Mr. James Jackson`

**Sender's email address:** `info@mutawamarine.com`

**Reply-To address:** `info.mutawamarine@mail.com` — Notice that the Reply-To uses a completely different domain (`mail.com`) than the sender address (`mutawamarine.com`). This is a major red flag; replies would be redirected to an attacker-controlled inbox.

**Originating IP address:** `192.119.71.157`

We look up this IP using WHOIS. The owner of the originating IP is `Hostwinds LLC` — a hosting provider, not a legitimate marine services company.

---

## Validating Email Authentication Records

### SPF Record Check

We run an SPF record check on the Return-Path domain to see if the sending server was authorized:

```
v=spf1 include:spf.protection.outlook.com -all
```

The SPF record says only Microsoft Outlook servers (`spf.protection.outlook.com`) are authorized to send mail for this domain. The `-all` directive means all other sources should fail. Since the email originated from a Hostwinds IP, it fails SPF validation.

### DMARC Lookup

We perform a DMARC lookup on the same domain:

```
v=DMARC1; p=quarantine; fo=1
```

The DMARC policy is set to `quarantine`, meaning emails that fail authentication should be quarantined. The `fo=1` flag requests failure reports for any authentication mechanism that fails.

---

## Analyzing the Attachment

The email includes a suspicious attachment. The file name is `SWT_#09674321____PDF__.CAB`.

The naming convention is designed to trick the recipient — it includes "PDF" in the name to suggest it's a harmless document, but the actual extension is `.CAB` (a Windows cabinet archive format).

### Hashing the File

We calculate the SHA256 hash of the attachment:

```
sha256sum SWT_#09674321____PDF__.CAB
```

**SHA256:** `2e91c533615a9bb8929ac4bb76707b2444597ce063d84a4b33525e25074fff3f`

### VirusTotal Analysis

We search this hash on VirusTotal. The results:

- **File size:** `400.26 KB`
- **Actual file type:** `RAR` — The file is disguised as a `.CAB` archive but is actually a `RAR` archive. This is a classic technique to bypass basic file-type filters.

Multiple antivirus engines flag this file as malicious.

---

## Conclusion

This email is a **phishing attempt** leveraging Business Email Compromise (BEC) techniques. The key indicators:

- **Mismatched Reply-To** — Replies go to `mail.com`, not the sender's domain
- **Hosting provider IP** — The email originated from Hostwinds, not a corporate mail server
- **SPF failure** — The sending IP is not authorized by the domain's SPF record
- **Disguised attachment** — A RAR file masquerading as a CAB file with "PDF" in the filename
- **VirusTotal hits** — Multiple engines flag the attachment as malicious

This is exactly the kind of email a SOC analyst would flag, quarantine, and use to generate IOCs for blocking similar future attempts.
