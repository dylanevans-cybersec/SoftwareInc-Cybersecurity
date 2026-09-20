using System;
using System.Collections.Generic;
using UnityEngine;

namespace CybersecurityMod
{
    // A cyber incident as a real work item, like a lawsuit: it has a progress bar and a deadline, shows up in the
    // work list and can be assigned to a team. Service staff work on it; those trained in the Support specialisation are much faster.
    //
    // The game saves Company.WorkItems by type name and cannot resolve a type that lives in a mod assembly, so these
    // items are never left in the company while the game is saved: CyberBehaviour detaches them during Serialize,
    // puts them back afterwards and rebuilds them from its own saved data when a game loads.
    public class IncidentWork : WorkItem
    {
        // Response points per day of an employee without the specialisation. A specialist works at their level (1-3).
        public const float UntrainedRate = 0.25f;

        public int Threat;          // index into CyberBehaviour's threat table
        public int StartDay;
        public int DeadlineDay;
        public float Progress;      // 0..1
        public bool Warned;

        public IncidentWork(int threat, int startDay, int deadlineDay)
            : base(CyberBehaviour.ThreatName(threat), null, 0u, null, -1)
        {
            Threat = threat;
            StartDay = startDay;
            DeadlineDay = deadlineDay;
        }

        // ---------------- who can work on it ----------------

        public override HasWorkReturn HasWork(Actor actor, bool secondary, bool actualCheck)
        {
            if (Progress >= 1f) return HasWorkReturn.Finished;
            return actor.employee.IsRoleSecondary(Employee.RoleBit.Service, secondary);
        }

        public override Employee.EmployeeRole? GetBoostRole(Actor actor, bool secondary)
        {
            if (actor.employee.IsRole(Employee.EmployeeRole.Service, secondary) && Level(actor) > 0) return Employee.EmployeeRole.Service;
            return null;
        }

        private static int Level(Actor actor)
        {
            return actor.employee.GetSpecialization(Employee.EmployeeRole.Service, CyberBehaviour.SpecName, actor);
        }

        // ---------------- doing the work ----------------

        public override void DoWork(Actor actor, float effectiveness, float delta, bool secondary)
        {
            if (Progress >= 1f) return;
            CyberBehaviour behaviour = CyberBehaviour.Current;
            if (behaviour == null) return;

            float pointsPerDay = Math.Max(UntrainedRate, (float)Level(actor));
            float skill = Utilities.MapRange(actor.employee.GetSkill(Employee.EmployeeRole.Service), 0f, 1f, 0.5f, 1f, false);

            // Utilities.PerDay(x, ...) spreads x over a game month, so scale the per-day rate up first.
            float points = Utilities.PerDay(pointsPerDay * GameSettings.DaysPerMonth * skill * effectiveness * actor.GetPCAddonBonus(Employee.EmployeeRole.Service), delta, true);
            Progress += points / CyberBehaviour.ThreatWork(Threat);

            if (Progress >= 1f)
            {
                Progress = 1f;
                behaviour.IncidentContained(this);
                Kill(false);
            }
        }

        // Whatever removes the item (contained, failed, cancelled, the game), the mod stops tracking it.
        public override void Kill(bool cancelled)
        {
            base.Kill(cancelled);
            CyberBehaviour behaviour = CyberBehaviour.Current;
            if (behaviour != null) behaviour.IncidentRemoved(this);
        }

        // The player cancelled it: that is the same as letting the deadline pass.
        protected override void Cancelled()
        {
            CyberBehaviour behaviour = CyberBehaviour.Current;
            if (behaviour != null) behaviour.IncidentAbandoned(this);
        }

        // ---------------- how it looks ----------------

        public override string GetSubjectName()
        {
            return CyberBehaviour.ThreatName(Threat);
        }

        public override string Category()
        {
            return CyberBehaviour.ThreatName(Threat);
        }

        // The names below are keys in Localization/English/UI.tyd.
        public override string GetWorkTypeName()
        {
            return "IncidentWork";
        }

        public override string GetTypeName()
        {
            return "IncidentWork";
        }

        // Incidents are listed together, under one heading, the way lawsuits are.
        public override string GetGroupType()
        {
            return "CyberIncident";
        }

        public override string GetGroupProject()
        {
            return Localization.Loc("CyberIncident");
        }

        public override string GetIcon()
        {
            return "Exclamation";
        }

        public override Color BackColor
        {
            get { return new Color(0.2f, 0.3f, 0.5f); }
        }

        public override float GetProgress()
        {
            return Progress;
        }

        public override string CurrentStage()
        {
            CyberBehaviour behaviour = CyberBehaviour.Current;
            int left = behaviour == null ? 0 : Math.Max(0, DeadlineDay - behaviour.GetDayCounter());
            return left + (left == 1 ? " day" : " days") + " to contain it";
        }

        public override float StressMultiplier()
        {
            return 1f;
        }

        public override Actor.WorkParticle EmitType(Actor actor, bool secondary)
        {
            return Actor.WorkParticle.Binary;
        }

        public override IEnumerable<KeyValuePair<string, Action>> GetButtons()
        {
            return new List<KeyValuePair<string, Action>>();
        }

        // Nothing to tell HR: incidents do not ask for any particular training.
        public override void GetNeeds(Dictionary<HRManagement.EdNeed, int>[] needs)
        {
        }
    }
}
