# Ledger

A one-box money ledger for iPhone. Type what happened, in English or Hinglish. The app works out the amount, type, category, payment method and person:

```
1500 spent on snacks
5000 rupees lent through credit card to Rahul
got 2000 back from Rahul
salary 50000 credited
```

- **AI:** Apple's on-device model (iPhone 15 Pro or newer with Apple Intelligence on). It's free, works offline and nothing leaves the phone. A keyword parser runs first and is the fallback.
- **Needs input:** if something is unclear (no amount, a loan with no name, an unknown category), the entry is flagged with a question. Tap it, answer, and the app reads it again.
- **Statement:** a plain-English monthly statement with totals, a breakdown by category and by payment method, and who owes whom. Copy or share it.
- **Several entries at once:** put one entry per line.
- **Split a bill later:** type it in the same box. The app finds the expense and shows a confirm sheet before changing anything:
  - `split the outing with 3 people`: finds the "outing" expense. Your share becomes the expense, and each person gets a Lent entry (names asked for in Needs input).
  - `3 logo ne contribute kar diya outing ka`: they already paid, so only your share stays.
  - `split 1200 dinner with Rahul, Amit and Neha`: no ₹1,200 expense yet, so it adds the bill and splits it.
- **Delete several at once:** tap **⋯**, then **Select Entries**, tick them, and tap **Delete**. Or type it: `all entries were test entries please delete`, `delete today's entries`, `delete the snacks entry`, `sab entries hata do`. Typed deletes only *select* the entries; nothing is deleted until you confirm.
- **English output:** if you type or dictate in Hindi script, the list and statement show an English version (needs the on-device AI). What you typed is kept too.
  - Splitting the same expense again replaces the old split. Long-press any expense and choose **Split…** to do it by hand.

## Where your data lives

| Place | What |
|---|---|
| `ledger.json` in the app (Files app, On My iPhone, Ledger) | The main copy. It stays on the phone. |
| Your backup folder (iCloud Drive or Google Drive) | `ledger-backup.csv`, rewritten after every change. Opens in Google Sheets, Numbers or Excel. |

**If you miss the 7-day re-sign:** the app stops opening, but **your data is not deleted**. Run Sideloadly again with the same Apple ID and the app opens with everything intact. Data is lost only if you *delete* the app. Even then, your backup CSV is in iCloud or Google Drive; use Import CSV to bring it back.

Set up the backup once: tap **⋯**, then **Choose backup folder**. Pick a folder in iCloud Drive, or in Google Drive (install the Google Drive app first and it appears in the picker).

## Install on your iPhone (free, from Windows)

One-time setup:
1. On the PC: **iTunes**, **iCloud** and **Sideloadly** (already installed by `winget`). Open iTunes once, plug in the iPhone and tap **Trust** on the phone.
2. On the iPhone: Settings, Privacy & Security, **Developer Mode**, turn it on. The phone restarts.
3. Make sure Apple Intelligence is on: Settings, Apple Intelligence & Siri.

Each install:
1. Download the newest `Ledger-ipa` from GitHub: repo, **Actions**, latest green run, **Artifacts**. Or run:
   `gh run download --repo vanshwason/ledger-ios -n Ledger-ipa`
2. Open Sideloadly, drag in `Ledger.ipa`, enter your Apple ID, click **Start**.
3. First time only: on the iPhone go to Settings, General, VPN & Device Management, tap your Apple ID, then **Trust**.
4. Repeat steps 2 and 3 every 7 days, before the app expires. Sideloadly can do it over Wi-Fi if you enable "Sync over Wi-Fi" in iTunes.

Free Apple ID limits: 3 sideloaded apps at a time, and the app is re-signed every 7 days.

## WhatsApp → Ledger (one-time Shortcut)

iPhone apps can't read WhatsApp chats, but WhatsApp can *share* a message to a Shortcut:

1. Open **Shortcuts**, tap **+**, and name it **Add to Ledger**.
2. Tap the **(i)** button and turn on **Show in Share Sheet**. Set the input to **Text**.
3. Add the action **URL Encode** (input: Shortcut Input).
4. Add the action **Open URLs** with the URL `ledger://add?text=` followed by the *URL Encoded Text* variable.

Now in WhatsApp: long-press a message, tap **Forward**, then the **Share** icon, then **Add to Ledger**. It also works from Notes, Messages, or anywhere you can share text. Tip: send yourself "1500 snacks" on WhatsApp during the day and share those messages to Ledger later.

Reading WhatsApp automatically would need an always-on server with the WhatsApp Business API (see PotBot or n8n's WhatsApp expense template). That isn't free or simple, so it isn't included.

## Building

Builds run on GitHub's free macOS runners (`.github/workflows/build.yml`) on every push: core tests, XcodeGen, unsigned build, then `Ledger.ipa`. Core logic (`LedgerCore/`) is a Swift package with tests: `swift test --package-path LedgerCore`.
