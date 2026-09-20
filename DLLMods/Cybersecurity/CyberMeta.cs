using System;
using UnityEngine;
using UnityEngine.UI;

namespace CybersecurityMod
{
    // Mod entry point. Its Name is also the key the game saves this mod's data under, so do not rename it.
    internal class CyberMeta : ModMeta
    {
        public override string Name
        {
            get { return "Cybersecurity"; }
        }

        public override void ConstructOptionsScreen(RectTransform parent, bool inGame)
        {
            CyberBehaviour behaviour = null;
            if (ModBehaviours != null && ModBehaviours.Count > 0) behaviour = ModBehaviours[0] as CyberBehaviour;

            Text text = WindowManager.SpawnLabel();
            text.text = "Cyber incidents (ransomware, phishing, data breaches, DDoS) target companies with many users and a strong reputation. "
                + "Each incident is a work item: assign a Service team to it and contain it before the deadline, or customers sue. Service staff trained in the Support specialisation work much faster.";
            WindowManager.AddElementToElement(text.gameObject, parent.gameObject, new Rect(0f, 0f, 460f, 84f), new Rect(0f, 0f, 0f, 0f));

            if (behaviour == null) return;
            CyberBehaviour target = behaviour;

            Toggle enabled = WindowManager.SpawnCheckbox();
            SetLabel(enabled.gameObject, "Incidents enabled");
            enabled.isOn = target.Enabled;
            enabled.onValueChanged.AddListener(delegate(bool value) { target.SetEnabled(value); });
            WindowManager.AddElementToElement(enabled.gameObject, parent.gameObject, new Rect(0f, 92f, 300f, 24f), new Rect(0f, 0f, 0f, 0f));

            Text frequencyLabel = WindowManager.SpawnLabel();
            frequencyLabel.text = "Incident frequency";
            WindowManager.AddElementToElement(frequencyLabel.gameObject, parent.gameObject, new Rect(0f, 122f, 300f, 22f), new Rect(0f, 0f, 0f, 0f));

            Slider frequency = WindowManager.SpawnSlider();
            frequency.minValue = 0.25f;
            frequency.maxValue = 3f;
            frequency.value = Mathf.Clamp(target.Frequency, 0.25f, 3f);
            frequency.onValueChanged.AddListener(delegate(float value) { target.SetFrequency(value); });
            WindowManager.AddElementToElement(frequency.gameObject, parent.gameObject, new Rect(0f, 146f, 300f, 20f), new Rect(0f, 0f, 0f, 0f));

            if (inGame)
            {
                Button test = WindowManager.SpawnButton();
                SetLabel(test.gameObject, "Trigger a test incident");
                test.onClick.AddListener(delegate() { target.DebugStart(); });
                WindowManager.AddElementToElement(test.gameObject, parent.gameObject, new Rect(0f, 176f, 220f, 26f), new Rect(0f, 0f, 0f, 0f));
            }
        }

        private static void SetLabel(GameObject element, string label)
        {
            Text text = element.GetComponentInChildren<Text>();
            if (text != null) text.text = label;
        }
    }
}
