using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace CybersecurityMod
{
    // One kind of cyber threat. Kept as data (no enums: the game's compiler crashes on them).
    internal class ThreatDef
    {
        public string Name;
        public string SubjectKey;      // lawsuit subject, localized in Localization/English/UI.tyd
        public int MinYear;            // earliest year this threat can happen
        public float Weight;           // relative chance of being picked
        public int DeadlineDays;       // days the company has to respond
        public float Work;             // response points needed before the deadline
        public float Damage;           // multiplier on the lawsuit amount if the response fails
        public float Difficulty;       // lawsuit difficulty (0-1), passed to the game's lawsuit system
        public string Intro;

        public ThreatDef(string name, string subjectKey, int minYear, float weight, int deadlineDays, float work, float damage, float difficulty, string intro)
        {
            Name = name;
            SubjectKey = subjectKey;
            MinYear = minYear;
            Weight = weight;
            DeadlineDays = deadlineDays;
            Work = work;
            Damage = damage;
            Difficulty = difficulty;
            Intro = intro;
        }

        public static ThreatDef[] CreateAll()
        {
            return new ThreatDef[]
            {
                new ThreatDef("Ransomware", "CyberRansomware", 2005, 3f, 7, 24f, 1.5f, 0.6f,
                    "Ransomware attack! Attackers have encrypted company systems and are demanding payment."),
                new ThreatDef("Phishing campaign", "CyberPhishing", 1998, 4f, 10, 12f, 0.6f, 0.4f,
                    "Phishing campaign! Convincing fake emails are hitting staff and credentials may already be stolen."),
                new ThreatDef("Data breach", "CyberBreach", 1990, 3f, 14, 28f, 2.0f, 0.7f,
                    "Data breach! An intruder has reached customer data."),
                new ThreatDef("DDoS attack", "CyberDDoS", 1999, 2f, 4, 8f, 0.5f, 0.4f,
                    "DDoS attack! Your services are being flooded with junk traffic.")
            };
        }
    }

    // An incident read from a save, waiting for the game to finish loading before it becomes an IncidentWork again.
    internal class IncidentRecord
    {
        public int Threat;
        public int StartDay;
        public int DeadlineDay;
        public float Progress;      // 0..1
        public bool Warned;
        public List<string> Teams;

        // (created here, not in a field initializer: the game's try/catch injector mistakes a '(' at class level for a method)
        public IncidentRecord()
        {
            Teams = new List<string>();
        }
    }

    public class CyberBehaviour : ModBehaviour
    {
        // The vanilla Service specialisation that incident response scales with. A new specialisation cannot be added:
        // the game keeps a private salary table for Service specialisations and throws for any name it does not know
        // (hire window, new employees, HR hiring), and a mod cannot reach that table without reflection.
        public const string SpecName = "Support";

        // ---------------- tuning ----------------
        private const float BaseChancePerDay = 0.0012f;     // before the user/reputation factors
        private const float MaxChancePerDay = 0.02f;
        private const float UsersScale = 2000f;             // active users at which the user factor reaches log10(2)
        private const int MinDaysBetweenIncidents = 10;
        private const int MaxActiveIncidents = 3;
        private const string IncidentTeamKey = "IncidentTeam";   // key for the game's default-team setting, like "InternalLawsuitTeam"
        private const float MinDamage = 15000f;
        private const float DamagePerUser = 0.10f;
        private const float MaxDamage = 3000000f;
        private const int WarnDaysBeforeDeadline = 2;

        public static CyberBehaviour Current;

        public bool Enabled = true;
        public float Frequency = 1f;

        private static readonly ThreatDef[] Threats = ThreatDef.CreateAll();

        private List<IncidentWork> _incidents = new List<IncidentWork>();
        private List<IncidentRecord> _pending = new List<IncidentRecord>();   // read from a save, not yet in the game
        private int _dayCounter;
        private int _lastIncidentDay = -1000;
        private bool _loadedThisGame;
        private bool _detachedForSave;

        // A method, not a property: the game's try/catch injector wraps the block after the last '(' at class level
        // (here the field initializers above), and a property block there breaks the compile.
        public int GetDayCounter()
        {
            return _dayCounter;
        }

        internal static string ThreatName(int threat)
        {
            return threat >= 0 && threat < Threats.Length ? Threats[threat].Name : "Cyber incident";
        }

        internal static float ThreatWork(int threat)
        {
            return threat >= 0 && threat < Threats.Length ? Threats[threat].Work : 1f;
        }

        // ---------------- lifecycle ----------------

        public override void OnActivate()
        {
            Current = this;
            Enabled = LoadSetting("Enabled", true);
            Frequency = LoadSetting("Frequency", 1f);

            RegisterBundledData();
            SceneManager.sceneLoaded += OnSceneLoaded;

            TimeOfDay.OnDayPassed += OnDayPassed;
            GameSettings.GameReady += OnGameReady;
        }

        public override void OnDeactivate()
        {
            TimeOfDay.OnDayPassed -= OnDayPassed;
            GameSettings.GameReady -= OnGameReady;
            SceneManager.sceneLoaded -= OnSceneLoaded;
            RemoveOpenIncidents();
            UnregisterBundledData();
            if (Current == this) Current = null;
        }

        // ---------------- bundled data mod ----------------
        // This code mod carries the software types, company types and name generators in its Data folder.
        // The game only reads data mods from its own Mods folder at startup, before code mods activate, so the
        // code registers the bundled copy itself, the same way the game registers a Workshop data mod.
        //
        // Things the game does that this has to work with:
        //  - GameSettings.Start builds a game's types from the packages that are Enabled, then disables all of them.
        //    So the package is re-enabled whenever the main menu / New Game scene loads.
        //  - The New Game screen fills its mod list with a copy of GameData.ModPackages when it starts, so a package
        //    added after that has to be added to the open list too.
        //
        // Everything is reported to the log and to the in-game console, because exceptions inside mod code are
        // otherwise easy to miss.

        private const string DataFolderName = "Data";
        private ModPackage _dataPackage;

        private static void Log(string message)
        {
            string text = "[Cybersecurity] " + message;
            UnityEngine.Debug.Log(text);
            try
            {
                DevConsole.Console.Log(text);
            }
            catch (Exception)
            {
                // the console may not exist yet during startup; the log line above is enough then
            }
        }

        private void RegisterBundledData()
        {
            try
            {
                string dataPath = ParentMod.FolderPath() + "/" + DataFolderName;
                Log("bundled data folder: " + dataPath);

                _dataPackage = FindDataPackage(dataPath);
                if (_dataPackage != null)
                {
                    Log("bundled data was already registered");
                }
                else
                {
                    int before = GameData.ModPackages.Count;
                    ModPackage loaded = ModPackage.Load(dataPath);   // throws with the real message if the data is rejected
                    GameData.ModPackages.Add(loaded);
                    _dataPackage = loaded;
                    Log("loaded bundled data: " + loaded.SoftwareTypes.Count + " software types, "
                        + loaded.CompanyTypes.Count + " company types (mod packages " + before + " -> " + GameData.ModPackages.Count + ")");
                }

                EnableBundledData();
                AddToNewGameList();
            }
            catch (Exception ex)
            {
                Log("could not load bundled data: " + ex.Message);
                UnityEngine.Debug.LogWarning("Cybersecurity mod: could not load bundled data: " + ex);
            }
        }

        private static ModPackage FindDataPackage(string dataPath)
        {
            foreach (ModPackage package in GameData.ModPackages)
            {
                if (package != null && package.SameRoot(dataPath, false)) return package;
            }
            return null;
        }

        private void EnableBundledData()
        {
            if (_dataPackage != null && !_dataPackage.Enabled) _dataPackage.Enabled = true;
        }

        // If the New Game screen is already open (its list was copied before we registered), add the package to it.
        private void AddToNewGameList()
        {
            ActorCustomization screen = ActorCustomization.Instance;
            if (screen == null || screen.ModList == null || _dataPackage == null) return;

            EventList<object> items = screen.ModList.Items;
            if (items != null && !items.Contains(_dataPackage))
            {
                items.Add(_dataPackage);
                Log("added the bundled data to the open New Game mod list");
            }
        }

        // Tick the package by default on the screens where the list is built. A game scene is deliberately left
        // alone, so unticking it in the New Game list is respected for that game.
        private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
        {
            try
            {
                if (scene.name == "MainMenu" || scene.name == "Customization")
                {
                    EnableBundledData();
                    Log("scene " + scene.name + ": bundled data enabled = " + (_dataPackage != null && _dataPackage.Enabled));
                }
            }
            catch (Exception ex)
            {
                UnityEngine.Debug.LogWarning("Cybersecurity mod: scene hook: " + ex);
            }
        }

        private void UnregisterBundledData()
        {
            if (_dataPackage == null) return;
            try
            {
                ActorCustomization screen = ActorCustomization.Instance;
                if (screen != null && screen.ModList != null && screen.ModList.Items != null) screen.ModList.Items.Remove(_dataPackage);

                // same sequence the game's own RELOAD_MOD command uses
                _dataPackage.Unload();
                GameData.ModPackages.Remove(_dataPackage);
                ModWindow.RemoveMod(_dataPackage);
                Log("unloaded the bundled data");
            }
            catch (Exception ex)
            {
                UnityEngine.Debug.LogWarning("Cybersecurity mod: could not unload bundled data: " + ex);
            }
            _dataPackage = null;
        }

        public void SetEnabled(bool value)
        {
            Enabled = value;
            SaveSetting("Enabled", value);
        }

        public void SetFrequency(float value)
        {
            Frequency = value;
            SaveSetting("Frequency", value);
        }

        // ---------------- game hooks ----------------

        private void OnGameReady(object sender, EventArgs e)
        {
            try
            {
                // Whatever was open belongs to the game that just ended.
                _incidents.Clear();
                _detachedForSave = false;

                if (_loadedThisGame)
                {
                    // Deserialize ran before the company existed, so the saved incidents become work items now.
                    RestoreIncidents(GameSettings.Instance);
                }
                else
                {
                    _pending.Clear();
                    _dayCounter = 0;
                    _lastIncidentDay = -1000;
                }
                _loadedThisGame = false;
            }
            catch (Exception ex)
            {
                UnityEngine.Debug.LogWarning("Cybersecurity mod: " + ex);
            }
        }

        // Only used to put the incidents back after a save (see Serialize).
        private void Update()
        {
            if (_detachedForSave) AttachAll();
        }

        private void OnDayPassed(object sender, EventArgs e)
        {
            try
            {
                DailyTick();
            }
            catch (Exception ex)
            {
                UnityEngine.Debug.LogWarning("Cybersecurity mod: " + ex);
            }
        }

        private void DailyTick()
        {
            GameSettings gs = GameSettings.Instance;
            if (gs == null || gs.MyCompany == null || TimeOfDay.Instance == null) return;

            _dayCounter++;
            CheckIncidents(gs);
            if (Enabled) MaybeStartIncident(gs);
        }

        // ---------------- likelihood ----------------

        private static double ActiveUsers(Company company)
        {
            double total = 0;
            foreach (SoftwareProduct p in company.Products)
            {
                if (p == null || p.IsMock || p.Archived) continue;
                total += p.Userbase;
            }
            return total;
        }

        // Chance of a new incident today. Grows with the company's total active users and with its business reputation
        // (a famous company with many users is a bigger target). No users means nothing worth attacking.
        private double ChancePerDay(Company company)
        {
            double users = ActiveUsers(company);
            if (users <= 0) return 0;

            double userFactor = Math.Log10(1.0 + users / UsersScale);                 // 0 users -> 0, 200k -> ~2, 2M -> ~3
            double reputation = Mathf.Clamp01(company.BusinessReputation);            // 0..1 (stars = reputation * 6)
            double reputationFactor = 0.6 + 1.4 * reputation;                         // 0.6 (unknown) .. 2.0 (famous)

            double chance = BaseChancePerDay * Frequency * userFactor * reputationFactor;
            return Math.Min(chance, MaxChancePerDay);
        }

        private void MaybeStartIncident(GameSettings gs)
        {
            if (Frequency <= 0f) return;
            if (_incidents.Count >= MaxActiveIncidents) return;
            if (_dayCounter - _lastIncidentDay < MinDaysBetweenIncidents) return;

            double chance = ChancePerDay(gs.MyCompany);
            if (chance <= 0 || UnityEngine.Random.value >= chance) return;

            int threat = PickThreat();
            if (threat >= 0) StartIncident(gs, threat);
        }

        private int PickThreat()
        {
            int year = CurrentYear();
            float total = 0f;
            for (int i = 0; i < Threats.Length; i++)
            {
                if (year >= Threats[i].MinYear) total += Threats[i].Weight;
            }
            if (total <= 0f) return -1;

            float roll = UnityEngine.Random.value * total;
            for (int i = 0; i < Threats.Length; i++)
            {
                if (year < Threats[i].MinYear) continue;
                roll -= Threats[i].Weight;
                if (roll <= 0f) return i;
            }
            return -1;
        }

        private static int CurrentYear()
        {
            int year = TimeOfDay.Instance.Year;
            if (year < 1000) year += 1900;
            return year;
        }

        // ---------------- incidents ----------------

        private void StartIncident(GameSettings gs, int threat)
        {
            ThreatDef def = Threats[threat];
            IncidentWork incident = new IncidentWork(threat, _dayCounter, _dayCounter + def.DeadlineDays);
            gs.MyCompany.AddWorkItem(incident);
            gs.ApplyDefaultTeams(incident, IncidentTeamKey);
            _incidents.Add(incident);
            _lastIncidentDay = _dayCounter;
            Log("incident started: " + def.Name + " on day " + _dayCounter + ", deadline day " + incident.DeadlineDay + " (" + _incidents.Count + " open)");

            Popup(def.Intro + " You have " + def.DeadlineDays + " days to respond. Assign a Service team to it; staff with Support training work fastest.", PopupManager.NotificationSound.Issue, 1f);
        }

        // Once a day: fail the incidents that are past their deadline and warn about the ones running late.
        // The deadline is judged from the mod's own list, not from whether the work item is still in the company, so an
        // incident can never slip past it (for instance one that was briefly taken out of the company for a save).
        private void CheckIncidents(GameSettings gs)
        {
            AdoptOrphans(gs);

            for (int i = _incidents.Count - 1; i >= 0; i--)
            {
                IncidentWork incident = _incidents[i];
                ThreatDef def = Threats[incident.Threat];
                int percent = (int)(100f * incident.Progress);
                Log("day " + _dayCounter + ": " + def.Name + " is " + percent + "% done, deadline day " + incident.DeadlineDay);

                if (incident.Progress >= 1f)
                {
                    IncidentContained(incident);
                    RemoveWorkItem(incident);
                }
                else if (_dayCounter >= incident.DeadlineDay)
                {
                    _incidents.RemoveAt(i);
                    Log(def.Name + " missed its deadline at " + percent + "%: launching the lawsuit");
                    try
                    {
                        FailIncident(gs, def);
                    }
                    catch (Exception ex)
                    {
                        Log("could not launch the lawsuit: " + ex);
                    }
                    RemoveWorkItem(incident);
                }
                else if (!incident.Warned && incident.DeadlineDay - _dayCounter <= WarnDaysBeforeDeadline && incident.Progress < 0.6f)
                {
                    incident.Warned = true;
                    Popup(def.Name + " response is only " + percent + "% done and the deadline is close. Assign more Service staff, ideally with Support training.", PopupManager.NotificationSound.Warning, 0.8f);
                }
            }
        }

        private static void RemoveWorkItem(IncidentWork incident)
        {
            try
            {
                incident.Kill(false);
            }
            catch (Exception ex)
            {
                Log("could not remove the incident work item: " + ex);
            }
        }

        // An IncidentWork in the company that the mod is not tracking (its deadline would never be checked) is taken back over.
        private void AdoptOrphans(GameSettings gs)
        {
            List<IncidentWork> found = new List<IncidentWork>();
            lock (gs.MyCompany.WorkItems)
            {
                foreach (WorkItem item in gs.MyCompany.WorkItems)
                {
                    IncidentWork incident = item as IncidentWork;
                    if (incident != null && !_incidents.Contains(incident)) found.Add(incident);
                }
            }
            for (int i = 0; i < found.Count; i++)
            {
                _incidents.Add(found[i]);
                Log("took over an incident work item that was not being tracked: " + ThreatName(found[i].Threat));
            }
        }

        // Called by IncidentWork when its progress bar fills up.
        internal void IncidentContained(IncidentWork incident)
        {
            _incidents.Remove(incident);
            int days = _dayCounter - incident.StartDay;
            Log(ThreatName(incident.Threat) + " contained after " + days + " day(s)");
            Popup(ThreatName(incident.Threat) + " contained after " + days + " day" + (days == 1 ? "" : "s") + ". Good response.", PopupManager.NotificationSound.Good, 0.6f);
        }

        // Called by IncidentWork when the player cancels it: same outcome as running out of time.
        internal void IncidentAbandoned(IncidentWork incident)
        {
            if (!_incidents.Remove(incident)) return;
            GameSettings gs = GameSettings.Instance;
            Log(ThreatName(incident.Threat) + " was cancelled: launching the lawsuit");
            if (gs != null && gs.MyCompany != null) FailIncident(gs, Threats[incident.Threat]);
        }

        // Called by IncidentWork when the game removes it for any other reason (nothing to fail, nothing to contain).
        internal void IncidentRemoved(IncidentWork incident)
        {
            if (_incidents.Remove(incident)) Log(ThreatName(incident.Threat) + " work item was removed by the game");
        }

        // Take every open incident out of the game (mod switched off, or a script reload).
        private void RemoveOpenIncidents()
        {
            try
            {
                List<IncidentWork> open = new List<IncidentWork>(_incidents);
                _incidents.Clear();
                for (int i = 0; i < open.Count; i++) open[i].Kill(false);
            }
            catch (Exception ex)
            {
                UnityEngine.Debug.LogWarning("Cybersecurity mod: could not remove open incidents: " + ex);
            }
        }

        // Missing the deadline costs a lawsuit, using the game's own lawsuit system.
        private void FailIncident(GameSettings gs, ThreatDef def)
        {
            double users = ActiveUsers(gs.MyCompany);
            double amount = def.Damage * Math.Min(MaxDamage, Math.Max(MinDamage, users * DamagePerUser));
            gs.LaunchSuit(new GameSettings.Lawsuit(def.SubjectKey, amount, def.Difficulty), false);
            Log("lawsuit queued: " + def.SubjectKey + ", " + (int)amount + " (users " + (int)users + ")");
            Popup(def.Name + " was not contained in time. Affected customers are suing.", PopupManager.NotificationSound.Issue, 1f);
        }

        // Test helper used by the options screen: start a random incident right now.
        public void DebugStart()
        {
            GameSettings gs = GameSettings.Instance;
            if (gs == null || gs.MyCompany == null) return;
            int threat = PickThreat();
            if (threat < 0) threat = 0;
            StartIncident(gs, threat);
        }

        private static void Popup(string message, PopupManager.NotificationSound sound, float importance)
        {
            if (HUD.Instance == null) return;
            HUD.Instance.AddPopupMessage(message, "Exclamation", sound, importance, PopupManager.PopupIDs.None, 0);
        }

        // ---------------- saving ----------------

        // The game writes Company.WorkItems by type name and cannot read back a type from a mod assembly, so an
        // IncidentWork must not be in the company while the save is encoded. The game calls this after it has built
        // the company data (which holds the live company) and before it encodes the file, all in one call on the
        // main thread. So the incidents are taken out of the company here and put back on the next frame (Update).
        // Their own state is written below in plain values and rebuilt by RestoreIncidents when the game loads.
        public override void Serialize(WriteDictionary data, GameReader.LoadMode mode)
        {
            List<float> flat = new List<float>();
            List<string> teams = new List<string>();
            for (int i = 0; i < _incidents.Count; i++)
            {
                IncidentWork incident = _incidents[i];
                flat.Add(incident.Threat);
                flat.Add(incident.StartDay);
                flat.Add(incident.DeadlineDay);
                flat.Add(ThreatWork(incident.Threat));                          // kept so the layout matches older saves
                flat.Add(incident.Progress * ThreatWork(incident.Threat));      // in response points, as older saves had it
                flat.Add(incident.Warned ? 1f : 0f);

                string names = "";
                foreach (Team team in incident.GetDevTeams())
                {
                    if (team != null) names += (names.Length > 0 ? "\n" : "") + team.Name;
                }
                teams.Add(names);
            }
            data["CyberIncidents"] = flat;
            data["CyberIncidentTeams"] = teams;
            data["CyberDay"] = _dayCounter;
            data["CyberLastIncident"] = _lastIncidentDay;

            DetachAll();
        }

        public override void Deserialize(WriteDictionary data, GameReader.LoadMode mode)
        {
            _loadedThisGame = true;
            _incidents.Clear();
            _pending.Clear();

            List<float> flat = data.Get("CyberIncidents", new List<float>());
            List<string> teams = data.Get("CyberIncidentTeams", new List<string>());
            for (int i = 0; i + 5 < flat.Count; i += 6)
            {
                int threat = (int)flat[i];
                if (threat < 0 || threat >= Threats.Length) continue;

                IncidentRecord record = new IncidentRecord();
                record.Threat = threat;
                record.StartDay = (int)flat[i + 1];
                record.DeadlineDay = (int)flat[i + 2];
                float work = flat[i + 3] > 0f ? flat[i + 3] : ThreatWork(threat);
                record.Progress = Mathf.Clamp01(flat[i + 4] / work);
                record.Warned = flat[i + 5] > 0.5f;

                int index = i / 6;
                if (index < teams.Count && teams[index].Length > 0) record.Teams.AddRange(teams[index].Split('\n'));
                _pending.Add(record);
            }
            _dayCounter = data.Get("CyberDay", 0);
            _lastIncidentDay = data.Get("CyberLastIncident", -1000);
        }

        // Turn the saved incidents back into work items once the game (company and teams) has finished loading.
        private void RestoreIncidents(GameSettings gs)
        {
            if (gs == null || gs.MyCompany == null) return;

            for (int i = 0; i < _pending.Count; i++)
            {
                IncidentRecord record = _pending[i];
                IncidentWork incident = new IncidentWork(record.Threat, record.StartDay, record.DeadlineDay);
                incident.Progress = record.Progress;
                incident.Warned = record.Warned;
                gs.MyCompany.AddWorkItem(incident);
                if (record.Teams.Count > 0) incident.AddDevTeams(record.Teams);
                else gs.ApplyDefaultTeams(incident, IncidentTeamKey);
                _incidents.Add(incident);
            }
            _pending.Clear();
            Log("restored " + _incidents.Count + " open cyber incident" + (_incidents.Count == 1 ? "" : "s") + " from the save");
        }

        private void DetachAll()
        {
            GameSettings gs = GameSettings.Instance;
            if (gs == null || gs.MyCompany == null || _incidents.Count == 0) return;

            lock (gs.MyCompany.WorkItems)
            {
                for (int i = 0; i < _incidents.Count; i++) gs.MyCompany.WorkItems.Remove(_incidents[i]);
            }
            _detachedForSave = true;
        }

        private void AttachAll()
        {
            _detachedForSave = false;
            GameSettings gs = GameSettings.Instance;
            if (gs == null || gs.MyCompany == null) return;

            for (int i = 0; i < _incidents.Count; i++) gs.MyCompany.AddWorkItem(_incidents[i]);
        }
    }
}
