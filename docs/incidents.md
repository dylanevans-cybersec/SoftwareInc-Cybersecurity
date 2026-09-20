# Cyber incident system (Phase 4)

Code: `DLLMods\Cybersecurity\CyberMeta.cs`, `CyberBehaviour.cs` and `IncidentWork.cs`. Game-compiled `.cs`, C# 3, no enums, no `System.IO` / `System.Reflection`, no `GiveMeFreedom`, so it stays eligible for the Steam Workshop.

Check it with `tools\compile-check.ps1`. That runs the game's own compiler (`mcs.dll`, needs 32-bit PowerShell, handled by the script) against the real game assemblies at `-langversion:3` and scans for the constructs the game forbids.

## The specialisation: vanilla Support

Response speed scales with the **Support** specialisation (levels 1-3) that Service staff already hire and train with. The mod does not add a specialisation of its own (`CyberBehaviour.SpecName = "Support"`).

Why not a new one: an earlier version appended `Cybersecurity` to `Employee.ServiceSpecs`, which made it show up in hiring and education, but hiring with it threw `KeyNotFoundException` in `Employee.GetRoleSalary`. Service salaries come from a private static dictionary (`Employee.ServiceSalaryFactor`, filled in the static constructor with only Support, Marketing, Law and Accounting), and the hire window, new-employee generation (`Employee..ctor` -> `WageFromSkillBracket`) and HR hiring all look up the spec name there. Nothing public writes to that dictionary, and a game-compiled mod cannot use reflection (that would also make it ineligible for the Steam Workshop), so a new Service specialisation cannot be made hireable. `Employee.GetMaxServiceSpec` only reads the four vanilla names, so employees are safe, but the hire window is not. If a future game version exposes a way to register a salary, a dedicated specialisation can come back.

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

An incident is a real work item (`IncidentWork`, a subclass of the game's `WorkItem`, modelled on `LegalWork`). It has a progress bar and a deadline, is listed with the other work, and is worked by the Service staff of the team it is assigned to. It is a race between the bar and the deadline.

- A new incident is added with `Company.AddWorkItem` and `GameSettings.ApplyDefaultTeams(item, "IncidentTeam")`, the same way the game launches a lawsuit. The player can change the team like for any other work.
- Only Service staff can work on it (`HasWork` returns the result of `IsRoleSecondary(RoleBit.Service, ...)`). Nobody is assigned, nobody makes progress: there is no automatic baseline.
- Points per day, per employee = the Support level (1-3) for a trained employee, `IncidentWork.UntrainedRate` (0.25) for any other Service employee, scaled by their Service skill and the usual work effectiveness. The bar fills when the points reach the threat's work total.
- Filling the bar contains the incident (`IncidentContained`, then `Kill(false)`). Missing the deadline (checked by the mod's daily tick, because the game only checks its own lawsuits) calls `GameSettings.LaunchSuit(new GameSettings.Lawsuit(subject, amount, difficulty), false)`, exactly what the game's own `LaunchLawsuit` script does, and removes the item. Cancelling the item counts as missing the deadline.
- Lawsuit amount = size multiplier x clamp(users x 0.10, 15,000, 3,000,000).
- A warning popup appears 2 days before the deadline if less than 60% is done.
- `GetNeeds` is empty: HR is not told to hire or train for incidents.

Rough guide, before in-game balancing: a level-3 specialist alone should contain anything except the data breach; a level-2 specialist handles phishing and DDoS; several untrained Service staff can contain a phishing campaign or DDoS attack but need luck on the rest. The rate constants (`UntrainedRate` in `IncidentWork.cs`, `Work` per threat in `CyberBehaviour.cs`) have not been calibrated in game yet; `Utilities.PerDay` spreads its argument over a game month, so the code multiplies the per-day rate by `GameSettings.DaysPerMonth`, and the "contained after N days" popup is the way to measure the real speed.

## Options and testing

Options > Mods > Cybersecurity: enable/disable, frequency slider (0.25x-3x), and in a running game a "Trigger a test incident" button.

All tuning numbers are constants at the top of `CyberBehaviour.cs`.

The incident lifecycle is logged to the console and `output_log.txt` with a `[Cybersecurity]` prefix: `incident started`, one `day N: <threat> is X% done, deadline day D` line per open incident per day, then `contained after N day(s)`, or `missed its deadline ...: launching the lawsuit` followed by `lawsuit queued: ...`. If a deadline passes without those lines, the daily tick did not run for that incident. The game then shows the lawsuit dialog within a day of `lawsuit queued` (`GameSettings.LaunchSuit(..., false)` schedules it up to a day ahead, and the queue is drained hourly).

The deadline is judged from the mod's own list (`CyberBehaviour._incidents`), not from whether the work item is still in the company, and an `IncidentWork` found in the company that is not in that list is taken back over (`AdoptOrphans`), so an incident cannot escape its deadline.

## Saving

Open incidents, their assigned team names, the day counter and the last incident day are saved with the game as primitives (in the mod's own `Serialize` data), so removing the mod does not corrupt saves.

The work items themselves must never reach the save file. The game writes `Company.WorkItems` by type name and reads it back with `Type.GetType(name)` from its own assembly, which cannot find a type from a mod assembly, so loading would fail. What the code relies on, from the game's IL (`GameReader.CreateDictionaryData`):

- `GameSettings.Serialize` puts the live `Company` object into the save dictionary, and the file is only encoded at the end (`AltSerialize.Serializer.Serialize`), on the same thread and under `GameReader.SaveLock`.
- Each mod's `Serialize` runs after the dictionaries are built and before that encode.
- So `CyberBehaviour.Serialize` removes its `IncidentWork` items from `Company.WorkItems` (`DetachAll`), and `Update` puts them back on the next frame (`AttachAll`). Teams do not save their work items (`Team.Serialize` has no such field), so team lists need no handling.
- On load, `Deserialize` only reads the values; `OnGameReady` (after the company exists) rebuilds the items (`RestoreIncidents`) and re-assigns the saved teams by name with `WorkItem.AddDevTeams(IEnumerable<string>)`.
- Turning the mod off kills the open items (`RemoveOpenIncidents`), so nothing of the mod stays in the company.

This was derived from reading the game's code and has to be confirmed in game: save with an incident open, check `output_log.txt` for `AltSerializeException` / "Unable to GetType", reload, and repeat with the mod disabled.