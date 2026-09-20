# Cyber incident system (Phase 4)

Code: `DLLMods\Cybersecurity\CyberMeta.cs` and `CyberBehaviour.cs`. Game-compiled `.cs`, C# 3, no enums, no `System.IO` / `System.Reflection`, no `GiveMeFreedom`, so it stays eligible for the Steam Workshop.

Check it with `tools\compile-check.ps1`. That runs the game's own compiler (`mcs.dll`, needs 32-bit PowerShell, handled by the script) against the real game assemblies at `-langversion:3` and scans for the constructs the game forbids.

## The Cybersecurity specialisation

The Service role's specialisations are a compiled static list (`Employee.ServiceSpecs` = Support, Marketing, Law, Accounting). On activation the mod appends `Cybersecurity` to it (and removes it again on deactivation). That makes it appear in hiring and education for Service staff. The salary table is private and the mod cannot use reflection, so a Cybersecurity specialist is paid like the employee's best vanilla Service specialisation.

The name is localized by the `Cybersecurity` key in `DLLMods\Cybersecurity\Data\Localization\English\UI.tyd`. The per-level tooltip lines (`SpecDesc > Service > ...`) are not provided, because a mod file with a `SpecDesc` table might replace the vanilla one.

## Threats

| Threat | From | Deadline | Work | Lawsuit size | Lawsuit difficulty |
|---|---|---|---|---|---|
| Ransomware | 2005 | 7 days | 24 | x1.5 | 0.6 |
| Phishing campaign | 1998 | 10 days | 12 | x0.6 | 0.4 |
| Data breach | 1990 | 14 days | 28 | x2.0 | 0.7 |
| DDoS attack | 1999 | 4 days | 8 | x0.5 | 0.4 |

## Likelihood

Each in-game day, when the company has active users:

```
chance = 0.0012 x frequency x log10(1 + users / 2000) x (0.6 + 1.4 x businessReputation)
```

- `users` = sum of `Userbase` over the player's products (mock and archived products excluded).
- `businessReputation` is `Company.BusinessReputation`, 0 to 1 (the game's star rating is `floor(rep x 6)`).
- Capped at 2% per day, at least 10 days between incidents, at most 3 open at once.
- Example: 200k users at reputation 0.5 is about 0.3% per day (roughly one incident a year); 2M users at reputation 0.8 is about 0.6% per day.

## Response

An incident is a race between response points and a deadline.

- Points per day = 0.5 (what the company manages alone) + the Cybersecurity level of every available Service employee (sick employees do not count).
- Reaching the work total before the deadline contains it. Missing the deadline calls `GameSettings.LaunchSuit(new GameSettings.Lawsuit(subject, amount, difficulty), false)`, exactly what the game's own `LaunchLawsuit` script does.
- Lawsuit amount = size multiplier x clamp(users x 0.10, 15,000, 3,000,000).
- A warning popup appears 2 days before the deadline if less than 60% is done.
- No specialists at all means every incident is lost (0.5 points x deadline is always below the work needed).

Rough guide (level 3 is the top of a specialisation): a level-3 specialist alone contains anything except the data breach; a level-2 specialist handles phishing, DDoS and the breach; ransomware wants two people.

## Options and testing

Options > Mods > Cybersecurity: enable/disable, frequency slider (0.25x-3x), and in a running game a "Trigger a test incident" button.

All tuning numbers are constants at the top of `CyberBehaviour.cs`.

## Saving

Open incidents, the day counter and the last incident day are saved with the game (primitives only, so removing the mod does not corrupt saves).