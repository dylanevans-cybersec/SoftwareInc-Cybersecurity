# Packaging: one code mod containing data and code

## Layout

```
DLLMods\Cybersecurity\            <- the whole mod; linked into <game>\DLLMods\Cybersecurity
  CyberMeta.cs                    code: mod entry point and options screen
  CyberBehaviour.cs               code: specialisation, incident lifecycle, registering the bundled data
  IncidentWork.cs                 code: the incident work item (progress bar, team work)
  meta.tyd                        name, author, description
  Data\                           the data mod
    SoftwareTypes\  CompanyTypes\  NameGenerators\  Localization\  meta.tyd
```

`Cybersecurity.dcache` and `CybersecurityH.bin` next to the code are compile-cache files the game generates. The game leaves them out of uploads.

A previous project layout (data in `Mods\Cybersecurity`, code in `DLLMods\Cybersecurity`) is kept in `archive\pre-single-mod\`.

## How it works, and what the game does that matters

The game reads data mods only from `<game>\Mods` at startup, before any code mod is activated, so the code registers the bundled data itself (`CyberBehaviour.RegisterBundledData`): `ModPackage.Load("<mod folder>/Data")` then `GameData.ModPackages.Add(...)`. That is what `GameData.LoadSteamMod` does for a Workshop data mod, but done directly so a failure produces the real exception text instead of being swallowed. `ModPackage`'s constructor also loads the package's `Localization` folder.

Facts found in the game's code that shape the design:

- `GameSettings.Start` builds a game's software, company and name-generator types from the packages whose `Enabled` is true, **then sets `Enabled = false` on every package**. A package therefore has to be re-enabled before each game. The code sets `Enabled = true` when it registers the package and whenever the `MainMenu` or `Customization` (New Game) scene loads. Game scenes are left alone, so unticking it in the New Game list is respected.
- The New Game screen (scene `Customization`) fills its mod list with a **copy** of `GameData.ModPackages` when it starts. If the package was registered after that, the code also adds it to the open list (`ActorCustomization.Instance.ModList.Items`).
- Code mods activate after data loading (`MainMenuController.Start` -> `ModController.Initialize`), so the package always arrives late. That is fine for new games and applies from the next one, like `RELOAD_MOD`.
- Code-mod verification hashes only `*.cs` files, so editing data files inside the mod folder does not force a recompile or a re-verification.
- The game injects try/catch into mod methods. Errors inside mod code may show only in the in-game console, so the loader writes everything to both `output_log.txt` and the console, prefixed `[Cybersecurity]`.
- Do not also link anything into `<game>\Mods`, or the data would load twice. `tools\link.ps1` only links `DLLMods\Cybersecurity`.
- Mod code may not use `System.IO` or `System.Reflection`, which is why paths are built by string concatenation.
- **The try/catch injector is a text scanner, not a parser** (`ModController.InjectTryBlocks`). Inside a class, at brace depth 0, every `(` makes it assume the next `{` is a method body and wrap it in `try { ... }`. Consequences for how the code has to be written:
  - A field initializer with a call (`= new List<T>()`, `= Foo()`) must not be followed by a property or the end of the class; the next block after it has to be a method or constructor. Safest: create such objects in a constructor or `OnActivate`, and use methods instead of properties (a `get { }` block right after those fields produced `CS1519 Unexpected symbol 'try'`). Overriding a game property (`BackColor`) is fine when no such field comes before it.
  - No `\"` inside strings and no `'{'`, `'}'`, `'('`, `')'` or `'"'` character literals (the scanner only understands `"` to end a string).
  - The error line numbers refer to the injected source, not the file, so they do not match the editor.
  - `tools\compile-check.ps1` repeats this scan (`INJECT` lines). `-DisableModErrors` turns the injection off in the game, but the check exists so Workshop builds are not affected.

## Workshop

The game types a Workshop item as "Data mod" or "Code mod". A code mod may upload `.cs`, `.tyd`, `.txt`, `.png`, `.obj` and audio files, so the data travels with it as one Code mod. The upload itself is done from the game's Mods window (it writes the type file and the Steam id) and has not been tried.

## What to look for when testing

Console (or `output_log.txt`) after starting the game:

```
[Cybersecurity] bundled data folder: <...>/DLLMods/Cybersecurity/Data
[Cybersecurity] loaded bundled data: N software types, M company types (mod packages a -> a+1)
[Cybersecurity] scene MainMenu: bundled data enabled = True
[Cybersecurity] scene Customization: bundled data enabled = True
```

If the first load line is replaced by `could not load bundled data: <message>`, that message is the cause.

## Day-to-day

| Task | Command |
|---|---|
| Check the data files | `powershell -File tools\lint-tyd.ps1` |
| Check the code with the game's own compiler (C# 3) | `powershell -File tools\compile-check.ps1` |
| Link into the game (game must be closed) | `powershell -File tools\link.ps1` |
| Unlink | `powershell -File tools\unlink.ps1` |
| Reload code and data in a running game | console: `RECOMPILE_DLL_MOD Cybersecurity`, then start a new game |