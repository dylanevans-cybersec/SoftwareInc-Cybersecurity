# Cybersecurity mod — catalog and reference notes

**Scope:** one combined code mod in `DLLMods\Cybersecurity`: the C# incident system at the top level and the data mod in `Data\` (registered by the code at startup, see docs\packaging.md). Furniture was abandoned. There is no SOC-analyst specialization from data: custom specs are rejected by the game, so the Cybersecurity specialisation is added by the code (docs\incidents.md).

## Vanilla names (extracted from `Software Inc_Data\resources.assets`, game build 2018.4.36)

**Software types:** Distribution platform, Operating System, Game, 3D Editor, Antivirus, Embedded System, Game Assets, Audio Tool, 2D Editor, Website, Office Software, Logistics Application.

**Company types (`Specialization`):** Creative tools, Computer Operating Systems, Phone Operating Systems, Console Operating Systems, Antivirus, Office, Games.
The vanilla `Antivirus` company type already makes the `Antivirus` software type, so the Antivirus override needs no new company type.

**Specs (`Spec`) used by vanilla features:** System, Hardware, 2D, 3D, Audio, Network. **Only these can be used.** The wiki says a new `Spec` name is auto-created, but the game then refuses the mod: "Software X uses the Y spec, but it is never supported by any operating systems". Every spec must be provided by a vanilla Operating System feature, and overriding the OS to add one would delete its features. So there is no custom "Security Operations" or "Cryptography" spec; those features were merged into System/Network.

**OS categories:** Computer, Console, Phone. `OSSupport` accepts a category or a list, e.g. `[ Computer; Phone ]`.

**Built-in hardware designs** (parametric models, no docs for making new ones): `Console`, `OldConsole`, `CellPhone`, `SmartPhone`, `TestJoystick`. Used as `Design "Console"` or `Design [ "CellPhone"; [ "SmartPhone"; 2000 ] ]`.

**Vanilla name generators referenced:** Antivirus, OS, Console, Phone, Joystick, Company.

## Syntax facts confirmed from vanilla data (not obvious from the wiki)

- `Server` per feature is tiny: vanilla uses `0.0001`–`0.0005`; MMO uses `0.002`. Values like `0.05` need absurd server capacity. `lint-tyd.ps1` warns above `0.005`.
- Level-3 script pattern (vanilla "Datamining"): check `Product.GetVar("x", true)`, pay with `Product.DevCompany.MakeTransaction(extra, Sales, "Label")`, chart it with `Product.AddToCashflow(0, 0, 0, extra, 0, Time)`, get caught with `Random() * Product.Userbase > N`, then `LaunchLawsuit("Key", Product.Sum, 1)`, `Product.DevCompany.AddFans(-x, Product.Category)`, `Product.ChangeUserbase(...)`, `Product.KillAwareness()`, `Product.PutVar("x", false)`, `AddPopup(Localize("Key", Product.Name), 1, "Exclamation", Issue)`.
- Descriptions can embed `{Currency:0.25}` so amounts show in the player's currency.
- Level-3 features can be gated by category: `SoftwareCategories [ Computer; Phone ]`, or with a year: `[ Computer; [ Console; 1990 ] ]`.
- A spec feature with `Forced [ Computer; Console ]` is mandatory for those categories, and `Optional True` makes it deselectable elsewhere.
- Hardware types carry `Hardware True` plus `Manufacturing`. `Design` is optional: vanilla Operating System (Console/Phone) and Joystick set it, vanilla Embedded System (also `Hardware True`) does not, so the Firewall and Security Key omit it.
- A manufacturing component's `DependsOn` feature must exist in **every** category that uses that `Manufacturing` block, otherwise the game refuses the mod ("depends on a feature that has an incompatible category"). If categories differ (NFC, fingerprint), give each category its own `Manufacturing`, as Security Key does. `lint-tyd.ps1` checks this.
- Only spec features (top-level entries in `Features`) document `Dependencies`; sub-features do not. Only one spec feature per `Spec` per type.
- A `SoftwareCategories` restriction on a spec feature also overrides its sub-features' own restrictions (wiki).
- Data-mod parse errors are **not** written to `output_log.txt` (verified by planting a broken file): check the in-game console after `RELOAD_MOD Cybersecurity`.
- `SoftwareProduct.ChangeUserbase(newValue)` sets the absolute value (checked in IL), so scripts use `Product.ChangeUserbase(Product.Userbase * 0.4)` to keep 40%.
- Add-ons: `Categories "Console"`, `Forced 0.4`, `PerUser 2`, `BaseFeature { Spec; DevTime; CodeArt; Submarkets }`, features with `MaxFactor` and `AmountScript`.
- Overrides (`SoftwareTypeOverride`, read from the game's IL): `Override True` edits an existing type, `Override Delete` removes it. If any override supplies `Categories`, `Features` or `AddOns`, the base type's list is **cleared and replaced** (not merged). So a mod cannot add one category or one feature to a vanilla type such as Operating System without restating everything the type already has.
- `TimeScale` is documented as 0..1 (vanilla never exceeds 1); the largest variant of each type uses 1.
- `OptimalDevTime` is per type, but what matters is the ratio to the total feature `DevTime` each **category** sees (features restricted with `SoftwareCategories` don't count for other categories). `lint-tyd.ps1` prints this per category and warns above 0.8.
- **Variants must differ in features, not only in price and market share.** Each variant gets its own feature set through `SoftwareCategories` on sub-features (only works when the parent spec feature has no restriction of its own). Variant names must not repeat the type name.

## Mod catalog (status)

All types are lint-clean. Phase 1 types loaded in game before the consolidation; everything from Phase 2 on and the consolidation itself are **untested in game**.

**Variant rule:** a type only gets variants when they are genuinely different products (roughly under 60% feature overlap, measured with the per-variant feature sets). Tier-style chains (each variant contains the smaller one) are a single product instead: features unlock by year, so the time progression comes for free. A type with no variants keeps its price, retention and market values at the type level (like vanilla Embedded System).

| # | Type | Variants |
|---|---|---|
| 1 | Endpoint Protection (replaces vanilla Antivirus, deleted with `Override Delete` + `CompanyTypes\delete.txt`) | Antivirus, EDR / XDR |
| 2 | Firewall OS | none |
| 3 | SIEM | none |
| 4 | Certificate Authority | Issuing CA, Lifecycle Management |
| 5 | Threat Intelligence Platform | none |
| 6 | Identity & Access | Password Manager, Access Management |
| 7 | Network Security Suite | Secure Access, Web & Email Security |
| 8 | Security Testing & Forensics | Vulnerability Testing, Digital Forensics |
| 9 | Data Protection | Backup & Recovery, Encryption & DLP |
| H1 | Firewall (hardware, needs a Firewall OS) | SMB Firewall, Enterprise Firewall |
| H2 | Security Key (hardware) | none (NFC and fingerprint parts follow the chosen features) |
| H3 | HSM (hardware) | none (network interface and redundant power follow the chosen features) |

19 variants in total, down from 36. The Intrusion Detection variant was dropped; its four IDS-only features (Protocol Decoders, Anomaly Detection, Passive Span Monitoring, Alert Triage View) went with it.
Firewall OS stays its own type: making it a variant of the vanilla Operating System would mean redefining the whole OS (see Overrides above).

## Furniture (abandoned)

Four racks were written and then dropped: the game rejected them with "Furniture needs at least one mesh" (an inherited `Base` model is not enough; the loader wants a mesh from `Models`). The files are kept in `archive\furniture\` and are not linked. The finding that would matter if this is revisited: `Base` does clone the vanilla object, but the loader clears its renderer list, so a furniture needs its own `.obj` in `Models`.