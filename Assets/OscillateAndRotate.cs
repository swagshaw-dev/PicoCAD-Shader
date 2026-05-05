using UnityEngine;

public class OscillateAndRotate : MonoBehaviour
{
    [Header("Oscillation")]
    public Vector3 oscillationAxis = Vector3.up;
    public float oscillationAmplitude = 1f;
    public float oscillationSpeed = 1f;

    [Header("Rotation")]
    public Vector3 rotationSpeed = new Vector3(0f, 90f, 0f);

    private Vector3 startPosition;

    void Start()
    {
        startPosition = transform.position;
    }

    void Update()
    {
        // Oscillate
        float offset = Mathf.Sin(Time.time * oscillationSpeed) * oscillationAmplitude;
        transform.position = startPosition + oscillationAxis.normalized * offset;

        // Rotate
        transform.Rotate(rotationSpeed * Time.deltaTime);
    }
}