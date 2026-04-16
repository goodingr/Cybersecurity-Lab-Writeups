# TryHackMe: Phishing Analysis Fundamentals Writeup

**Room Link:** [Phishing Analysis Fundamentals](https://tryhackme.com/room/phishingemails1tryoe)

---

## Introduction

This room teaches the fundamentals of email analysis — a critical skill for any SOC analyst. We'll walk through how emails work under the hood, what headers reveal about a message's origin, how to dissect an email body, and the various types of phishing attacks we should be aware of.

---

## The Email Address

Email as a technology dates back to the **1970s**. Originally designed with trust in mind, the protocol lacked the authentication and security mechanisms we rely on today, which is exactly why phishing remains such a persistent threat.

An email address is composed of two parts:
- **User Mailbox** (or username) — the part before the `@`
- **Domain** — the part after the `@` (e.g., `tryhackme.com`)

---

## Email Delivery

Emails rely on a handful of core protocols to move from sender to recipient:

| Protocol | Purpose | Standard Port | Secure Port |
|----------|---------|:------------:|:-----------:|
| **SMTP** | Sending/transferring mail | 25 | 587 (STARTTLS) |
| **POP3** | Retrieving mail (downloads to client) | 110 | 995 (SSL/TLS) |
| **IMAP** | Retrieving mail (syncs with server) | 143 | 993 (SSL/TLS) |

The journey of an email:

1. The sender composes and sends via their **Mail User Agent (MUA)** (e.g., Outlook, Thunderbird).
2. The MUA connects to the outgoing **Mail Transfer Agent (MTA)** via SMTP.
3. The MTA performs a DNS lookup to find the recipient domain's **MX record**.
4. The email is relayed to the recipient's **Mail Delivery Agent (MDA)**.
5. The recipient's MUA retrieves the message via POP3 or IMAP.

---

## Email Headers

Email headers carry metadata about every message. They're the first place we look when investigating a suspicious email. Key headers include:

- **From** — The displayed sender (easily spoofed).
- **To** — The recipient.
- **Date** — Timestamp of when the email was sent.
- **Subject** — The email's subject line.
- **X-Originating-IP** — The IP address of the sender's machine. This is invaluable for attribution.
- **Reply-To / Return-Path** — Where replies are directed. The **Return-Path** header is the same as "Reply-to" and can reveal redirection attempts by attackers.
- **Message-ID** — A unique identifier assigned by the MTA.
- **MIME-Version** — Indicates the email uses MIME (Multipurpose Internet Mail Extensions) formatting.
- **Content-Type** — Specifies the format of the email body (e.g., `text/html`, `multipart/mixed`).
- **Received** — Added by every mail server the email passes through. Reading these bottom-to-top reconstructs the email's path.

Once we find the sender's IP address, we can retrieve more information about it using a WHOIS lookup service such as **http://www.arin.net**.

---

## Email Body

The email body is the actual content the recipient sees. It can contain:

- **Plain text** or **HTML** content
- **Hyperlinks** (which may be masked to appear legitimate)
- **Attachments** (which may carry malware)

### Analyzing Embedded Content

When analyzing phishing emails, we should always check:

1. **Image URIs** — Blocked or externally hosted images may contain tracking pixels or lead to malicious domains. One example URI of a blocked image from the room's screenshots: `https://i.imgur.com/LSWOtDI.png`.
2. **Attachment names** — Suspicious naming conventions can be a giveaway. In the room's example, the PDF attachment is named `Payment-updateid.pdf`.
3. **Base64-encoded attachments** — Emails often carry attachments as Base64 data within the raw source. We can decode these to reconstruct the original file.

### Reconstructing a PDF from Base64

In the room's VM, we open `email2.txt` and find a Base64-encoded block. To reconstruct the PDF:

1. Copy the Base64 string from the email source.
2. Use **CyberChef** (or the command line) to decode it:

```
cat email2.txt | grep -A 9999 'Content-Transfer-Encoding: base64' | base64 -d > attachment.pdf
```

3. Open the resulting PDF to find the hidden text: **THM{BENIGN_PDF_ATTACHMENT}**.

---

## Types of Phishing

Phishing is not one-size-fits-all. Understanding the different variants helps us identify and categorize threats:

| Type | Description |
|------|-------------|
| **Spam (Malspam)** | Bulk unsolicited email, often carrying malware or malicious links |
| **Phishing** | Broad-target attacks impersonating trusted entities to steal credentials |
| **Spear Phishing** | Targeted attacks aimed at specific individuals or organizations |
| **Whaling** | Spear phishing directed at senior executives (C-suite) |
| **Smishing** | Phishing via SMS text messages |
| **Vishing** | Phishing via voice calls |

---

## Conclusion

**BEC** stands for **Business Email Compromise** — a sophisticated attack where adversaries impersonate executives or trusted partners to trick employees into transferring funds or divulging sensitive information.

### Key Takeaways

- Always inspect email headers before trusting the displayed "From" address.
- Use tools like **ARIN**, **VirusTotal**, and **CyberChef** to investigate suspicious indicators.
- Defang URLs and IPs when documenting findings (e.g., `hxxp[://]` instead of `http://`).
- Treat every unexpected attachment with suspicion — reconstruct and analyze in a sandbox.
- Understanding the email delivery pipeline (SMTP → MTA → MDA → MUA) helps us trace exactly where a message originated and how it was modified in transit.
