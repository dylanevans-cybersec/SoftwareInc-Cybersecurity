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

    // An incident currently being handled.
    internal class Incident
    {
        public int Threat;
        public int StartDay;
        public int DeadlineDay;
        public float Work;
        public float Progress;
        public bool Warned;
    }

    public class CyberBehaviour : ModBehaviour
    {
        // The Service-role specialisation this mod adds. Staff with levels in it respond faster.
        public const string SpecName = "Cybersecurity";

        // ---------------- tuning ----------------
        private const float BaseChancePerDay = 0.0012f;     // before the user/reputation factors
        private const float MaxChancePerDay = 0.02f;
        private const float UsersScale = 2000f;             // active users at which the user factor reaches log10(2)
        private const int MinDaysBetweenIncidents = 10;
        private const int MaxActiveIncidents = 3;
        private const float BaseResponsePerDay = 0.5f;      // what an untrained company manages on its own
        private const float MinDamage = 15000f;
        private const float DamagePerUser = 0.10f;
        private const float MaxDamage = 3000000f;
        private const int WarnDaysBeforeDeadline = 2;

        public static CyberBehaviour Current;

        public bool Enabled = true;
        public float Frequency = 1f;

        private static readonly ThreatDef[] Threats = ThreatDef.CreateAll();

        private List<Incident> _incidents = new List<Incident>();
        private int _dayCounter;
        private int _lastIncidentDay = -1000;
        private bool _loadedThisGame;

        // ---------------- lifecycle ----------------

        public override void OnActivate()
        {
            Current = this;
            Enabled = LoadSetting("Enabled", true);
            Frequency = LoadSetting("Frequency", 1f);

            RegisterBundledData();
            SceneManager.sceneLoaded += OnSceneLoaded;

            AddSpecialisation();
            TimeOfDay.OnDayPassed += OnDayPassed;
            GameSettings.GameReady += OnGameReady;
        }

        public override void OnDeactivate()
        {
            TimeOfDay.OnDayPassed -= OnDayPassed;
            GameSettings.GameReady -= OnGameReady;
            SceneManager.sceneLoaded -= OnSceneLoaded;
            RemoveSpecialisation();
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

        // ---------------- the Cybersecurity specialisation ----------------

        // Service staff specialisations are a compiled list (Support, Marketing, Law, Accounting).
        // Adding a name to it makes the specialisation appear in hiring and education.
        private static void AddSpecialisation()
        {
            string[] specs = Employee.ServiceSpecs;
            if (specs == null) return;
            for (int i = 0; i < specs.Length; i++)
            {
                if (specs[i] == SpecName) return;
            }
            string[] extended = new string[specs.Length + 1];
            specs.CopyTo(extended, 0);
            extended[specs.Length] = SpecName;
            Employee.ServiceSpecs = extended;
        }

        private static void RemoveSpecialisation()
        {
            string[] specs = Employee.ServiceSpecs;
            if (specs == null) return;
            List<string> kept = new List<string>();
            for (int i = 0; i < specs.Length; i++)
            {
                if (specs[i] != SpecName) kept.Add(specs[i]);
            }
            if (kept.Count != specs.Length) Employee.ServiceSpecs = kept.ToArray();
        }

        // ---------------- game hooks ----------------

        private void OnGameReady(object sender, EventArgs e)
        {
            // A save that had incidents restored them in Deserialize before this point; a new game starts clean.
            if (!_loadedThisGame)
            {
                _incidents.Clear();
                _dayCounter = 0;
                _lastIncidentDay = -1000;
            }
            _loadedThisGame = false;
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
            ResolveIncidents(gs);
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
            Incident incident = new Incident();
            incident.Threat = threat;
            incident.StartDay = _dayCounter;
            incident.DeadlineDay = _dayCounter + def.DeadlineDays;
            incident.Work = def.Work;
            incident.Progress = 0f;
            incident.Warned = false;
            _incidents.Add(incident);
            _lastIncidentDay = _dayCounter;

            int specialists;
            ResponseCapacity(gs, out specialists);
            string team;
            if (specialists > 0)
            {
                team = "Your " + specialists + " Cybersecurity specialist" + (specialists == 1 ? "" : "s") + " are on it.";
            }
            else
            {
                team = "You have no Cybersecurity specialists. Train Service staff in Cybersecurity!";
            }

            Popup(def.Intro + " You have " + def.DeadlineDays + " days to respond. " + team, PopupManager.NotificationSound.Issue, 1f);
        }

        // Response points per day: what the company manages alone, plus the level of every available Cybersecurity specialist.
        private float ResponseCapacity(GameSettings gs, out int specialists)
        {
            specialists = 0;
            float capacity = BaseResponsePerDay;
            if (gs.sActorManager == null) return capacity;

            foreach (Actor actor in gs.sActorManager.Actors)
            {
                if (actor == null || !actor.IsEmployee() || actor.employee == null) continue;
                if (actor.SickDays > 0) continue;

                int level = actor.employee.GetSpecialization(Employee.EmployeeRole.Service, SpecName, actor);
                if (level > 0)
                {
                    capacity += level;
                    specialists++;
                }
            }
            return capacity;
        }

        private void ResolveIncidents(GameSettings gs)
        {
            if (_incidents.Count == 0) return;

            int specialists;
            float capacity = ResponseCapacity(gs, out specialists);

            for (int i = _incidents.Count - 1; i >= 0; i--)
            {
                Incident incident = _incidents[i];
                ThreatDef def = Threats[incident.Threat];
                incident.Progress += capacity;

                if (incident.Progress >= incident.Work)
                {
                    int days = _dayCounter - incident.StartDay;
                    Popup(def.Name + " contained after " + days + " day" + (days == 1 ? "" : "s") + ". Good response.", PopupManager.NotificationSound.Good, 0.6f);
                    _incidents.RemoveAt(i);
                }
                else if (_dayCounter >= incident.DeadlineDay)
                {
                    FailIncident(gs, def);
                    _incidents.RemoveAt(i);
                }
                else if (!incident.Warned && incident.DeadlineDay - _dayCounter <= WarnDaysBeforeDeadline && incident.Progress < incident.Work * 0.6f)
                {
                    incident.Warned = true;
                    int percent = (int)(100f * incident.Progress / incident.Work);
                    Popup(def.Name + " response is only " + percent + "% done and the deadline is close. More Cybersecurity staff would speed it up.", PopupManager.NotificationSound.Warning, 0.8f);
                }
            }
        }

        // Missing the deadline costs a lawsuit, using the game's own lawsuit system.
        private void FailIncident(GameSettings gs, ThreatDef def)
        {
            double users = ActiveUsers(gs.MyCompany);
            double amount = def.Damage * Math.Min(MaxDamage, Math.Max(MinDamage, users * DamagePerUser));
            gs.LaunchSuit(new GameSettings.Lawsuit(def.SubjectKey, amount, def.Difficulty), false);
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

        public override void Serialize(WriteDictionary data, GameReader.LoadMode mode)
        {
            List<float> flat = new List<float>();
            for (int i = 0; i < _incidents.Count; i++)
            {
                Incident incident = _incidents[i];
                flat.Add(incident.Threat);
                flat.Add(incident.StartDay);
                flat.Add(incident.DeadlineDay);
                flat.Add(incident.Work);
                flat.Add(incident.Progress);
                flat.Add(incident.Warned ? 1f : 0f);
            }
            data["CyberIncidents"] = flat;
            data["CyberDay"] = _dayCounter;
            data["CyberLastIncident"] = _lastIncidentDay;
        }

        public override void Deserialize(WriteDictionary data, GameReader.LoadMode mode)
        {
            _loadedThisGame = true;
            _incidents.Clear();

            List<float> flat = data.Get("CyberIncidents", new List<float>());
            for (int i = 0; i + 5 < flat.Count; i += 6)
            {
                int threat = (int)flat[i];
                if (threat < 0 || threat >= Threats.Length) continue;

                Incident incident = new Incident();
                incident.Threat = threat;
                incident.StartDay = (int)flat[i + 1];
                incident.DeadlineDay = (int)flat[i + 2];
                incident.Work = flat[i + 3];
                incident.Progress = flat[i + 4];
                incident.Warned = flat[i + 5] > 0.5f;
                _incidents.Add(incident);
            }
            _dayCounter = data.Get("CyberDay", 0);
            _lastIncidentDay = data.Get("CyberLastIncident", -1000);
        }
    }
}
