using UnityEngine;
using UnityEngine.UI;
using TMPro;

[RequireComponent(typeof(Collider))]
public class TriggerDialog : MonoBehaviour
{
    [Header("UI References")]
    [Tooltip("The UI GameObject containing your dialog (Panel, Text, etc.)")]
    public GameObject dialogUI;

    [Tooltip("The Text component to update with the message")]
    public TextMeshProUGUI dialogText; // Use UnityEngine.UI.Text if you're not using TMP

    [Header("Content")]
    public string initialMessage = "You found a secret area!";
    public string secondaryMessage = "";
    public KeyCode keyToChangeMessage = KeyCode.E;

    [Header("Settings")]
    public string playerTag = "Player";
    public bool hideOnExit = true;

    private bool isPlayerInside = false;

    private void Start()
    {
        // Auto-assign references if left empty in the Inspector
        if (dialogUI == null) dialogUI = GetComponentInChildren<Canvas>()?.gameObject;
        if (dialogText == null && dialogUI != null) dialogText = dialogUI.GetComponentInChildren<TextMeshProUGUI>();

        // Ensure UI starts hidden
        if (dialogUI != null) dialogUI.SetActive(false);

        // Force the collider to be a trigger if it isn't already
        if (GetComponent<Collider>().isTrigger == false)
            GetComponent<Collider>().isTrigger = true;
    }

    private void OnTriggerEnter(Collider other)
    {
        if (other.CompareTag(playerTag))
        {
            isPlayerInside = true;
            ShowDialog(initialMessage);
        }
    }

    private void OnTriggerExit(Collider other)
    {
        if (other.CompareTag(playerTag))
        {
            isPlayerInside = false;
            if (hideOnExit) HideDialog();
        }
    }

    private void OnTriggerStay(Collider other)
    {
        // Optional: Change message while inside (matches your example's functionality)
        if (other.CompareTag(playerTag) && !string.IsNullOrEmpty(secondaryMessage) && Input.GetKeyDown(keyToChangeMessage))
        {
            dialogText.text = secondaryMessage;
        }
    }

    private void ShowDialog(string message)
    {
        if (dialogUI != null) dialogUI.SetActive(true);
        if (dialogText != null) dialogText.text = message;
    }

    private void HideDialog()
    {
        if (dialogUI != null) dialogUI.SetActive(false);
    }
}
