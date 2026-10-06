# Cybersecurity for Software Inc.

A mod for [Software Inc.](https://store.steampowered.com/app/362620/Software_Inc/) that adds a full security industry: nine new software types, three hardware products, twelve new company specialisations, and cyber incidents that hit successful companies.

Tested in game and working. This is a passion project and will not be updated regularly.

## What it adds

### Software

| Type | Available from | Variants |
|---|---|---|
| Endpoint Protection (replaces vanilla Antivirus) | 1988 | Antivirus, EDR / XDR |
| Data Protection | 1990 | Backup & Recovery, Encryption & DLP |
| Firewall OS | 1992 | none |
| Certificate Authority | 1995 | Issuing CA, Lifecycle Management |
| Network Security Suite | 1996 | Secure Access, Web & Email Security |
| Identity & Access | 1998 | Password Manager, Access Management |
| Security Testing & Forensics | 1998 | Vulnerability Testing, Digital Forensics |
| SIEM | 2000 | none |
| Threat Intelligence Platform | 2006 | none |

Variants are genuinely different products with their own feature sets, not the same product at a different price.

### Hardware

| Product | Available from | Notes |
|---|---|---|
| Firewall | 1995 | SMB Firewall and Enterprise Firewall. Needs a Firewall OS to run on. |
| HSM | 1998 | Hardware Security Module for cryptographic keys. |
| Security Key | 2005 | Small authentication token. |

### Company specialisations

Twelve new company types to start a game with: Authentication Hardware, Cryptographic Hardware, Data Protection, Endpoint Security, Identity Security, Network Defense, Network Security, Security Analytics, Security Assessment, Security Suite, Threat Intelligence and Trust Services.

The vanilla Antivirus software type and company type are removed. Endpoint Protection takes their place.

## Cyber incidents

Once your company has users, attackers start to notice.

| Threat | Appears from | Time to respond |
|---|---|---|
| Data breach | 1990 | 14 days |
| Phishing campaign | 1998 | 10 days |
| DDoS attack | 1999 | 4 days |
| Ransomware | 2005 | 7 days |

**How often.** More users and a better business reputation make you a bigger target. The chance is rolled once per in-game day, incidents are always at least 10 days apart and no more than 3 can be open at once. As a guide, a company with 200,000 users and a middling reputation can expect an incident roughly every 300 in-game days. That is about once a year with 25 or more days per month, but only once every 25 years or so at the default of 1 day per month.

**How to respond.** Each incident is a work item with a progress bar and a deadline, listed with your other work like a lawsuit. Assign a team to it: only the team's **Service staff** work on it, and nobody makes progress unless someone is assigned. Staff trained in the vanilla **Support** specialisation are much faster (the higher their level, the faster), while untrained Service staff only chip away at it. A warning pops up 2 days before the deadline if the response is less than 60% done. Miss the deadline, or cancel the work item, and your customers sue. The more users you have, the bigger the lawsuit.

**Harder attacks on bigger names.** A company with a strong business reputation and lots of fans draws harder attacks: an incident needs up to 5 times the usual response work, while the deadline stays the same. The lawsuit also gets harder with more users, so losing it costs more reputation.

**Options.** Open Options > Mods > Cybersecurity to turn incidents off (incidents already open still run their course), or scale how often they happen from 0.25x to 3x. In a running game there is also a "Trigger a test incident" button.

Incident state is saved with your game, and it only uses basic values, so removing the mod will not corrupt your saves.

## Installation

Subscribe on the Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3814485977

Then enable the mod in the game's Mods window. When you start a new game, **Cybersecurity** is ticked by default in the mod list on the New Game screen. Leave it ticked. The new software and company types apply to new games, not to saves you already have.

## Compatibility

- Removes the vanilla Antivirus software and company types, so other mods that build on them may not work alongside this one.
- Incident response uses the vanilla Support specialisation. The mod does not add or change any specialisations.

## Credits

Made by Decksy.

License: not yet chosen.
