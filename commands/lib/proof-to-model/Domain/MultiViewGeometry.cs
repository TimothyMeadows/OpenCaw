using System.Text.Json.Nodes;
using System.Text.Json;
using System.Globalization;

namespace OpenCaw.ProofToModel.Domain;

/// <summary>The prescribed Blender/NeRF Z-up rig. A generated camera is nominal, not measured.</summary>
public static class MultiViewGeometry
{
    public static readonly string[] Views = ["front", "right", "back", "left", "top", "bottom"];
    public const double DefaultDistance = 3.1192049980163574;
    const double Tolerance = 1e-7;

    public static JsonArray Matrix(string view, double distance = DefaultDistance)
    {
        Positive(distance, "camera distance");
        double[][] rows = view switch
        {
            "front" => [[1, 0, 0, 0], [0, 0, -1, -distance], [0, 1, 0, 0], [0, 0, 0, 1]],
            "right" => [[0, 0, -1, -distance], [-1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]],
            "back" => [[-1, 0, 0, 0], [0, 0, 1, distance], [0, 1, 0, 0], [0, 0, 0, 1]],
            "left" => [[0, 0, 1, distance], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]],
            "top" => [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, distance], [0, 0, 0, 1]],
            "bottom" => [[1, 0, 0, 0], [0, -1, 0, 0], [0, 0, -1, -distance], [0, 0, 0, 1]],
            _ => throw new InvalidOperationException("Unknown prescribed view: " + view)
        };
        return new JsonArray(rows.Select(row => (JsonNode)new JsonArray(row.Select(x => (JsonNode)JsonValue.Create(x)!).ToArray())).ToArray());
    }

    public static void Validate(JsonObject proofSet)
    {
        var camera = proofSet["camera"] as JsonObject ?? throw new InvalidOperationException("Proof set needs a camera contract");
        if (Text(camera["convention"]) != "blender-nerf-z-up")
            throw new InvalidOperationException("Camera convention must be blender-nerf-z-up");
        if (Text(camera["calibration"]) is not ("nominal-prescribed" or "measured"))
            throw new InvalidOperationException("Camera calibration must distinguish nominal-prescribed from measured");
        var meshScale = Number(camera["meshScale"], "meshScale");
        Positive(meshScale, "meshScale");
        Fov(Number(camera["cameraAngleX"], "cameraAngleX"));
        var distance = Number(camera["distance"], "distance");
        Positive(distance, "distance");
        // The pinned engine projects grid coordinates as grid / mesh_scale / 2.
        // Each cardinal camera must be outside that cube, with positive depth
        // even at its nearest face. A smaller meshScale makes this cube larger.
        var halfExtent = 0.5 / meshScale;
        if (!double.IsFinite(halfExtent) || distance - halfExtent <= 1e-6 * Math.Max(distance, halfExtent))
            throw new InvalidOperationException("Camera is inside or on the Pixal3D conditioning cube; meshScale is inverse scale (cube half-extent = 0.5 / meshScale). Choose consistent meshScale and distance, revise the camera contract and obtain fresh proof-set approval before inference.");
        var views = proofSet["views"] as JsonArray ?? throw new InvalidOperationException("Proof set needs six ordered views");
        if (views.Count != Views.Length)
            throw new InvalidOperationException("Proof set needs exactly six views: " + string.Join(", ", Views));
        for (var i = 0; i < Views.Length; i++)
        {
            var entry = views[i] as JsonObject ?? throw new InvalidOperationException("A proof view must be an object");
            if (Text(entry["view"]) != Views[i])
                throw new InvalidOperationException("Proof views must be unique and ordered front, right, back, left, top, bottom");
            if (entry["cameraAngleX"] is not null)
                Fov(Number(entry["cameraAngleX"], Views[i] + " cameraAngleX"));
            var matrix = entry["cameraToWorld"] as JsonArray;
            if (matrix is null || matrix.Count != 4 || matrix.Any(row => row is not JsonArray a || a.Count != 4))
                throw new InvalidOperationException(Views[i] + " cameraToWorld must be a 4x4 matrix");
            var values = new double[4, 4];
            for (var row = 0; row < 4; row++)
                for (var col = 0; col < 4; col++)
                    values[row, col] = Number(matrix[row]![col], Views[i] + " matrix entry");
            for (var col = 0; col < 4; col++)
                Near(values[3, col], col == 3 ? 1 : 0, "Camera must have a homogeneous last row");
            for (var a = 0; a < 3; a++)
                for (var b = 0; b < 3; b++)
                {
                    var dot = 0.0;
                    for (var row = 0; row < 3; row++)
                        dot += values[row, a] * values[row, b];
                    Near(dot, a == b ? 1 : 0, "Camera rotation must be orthonormal");
                }
            var determinant = values[0, 0] * (values[1, 1] * values[2, 2] - values[1, 2] * values[2, 1])
                - values[0, 1] * (values[1, 0] * values[2, 2] - values[1, 2] * values[2, 0])
                + values[0, 2] * (values[1, 0] * values[2, 1] - values[1, 1] * values[2, 0]);
            Near(determinant, 1, "Camera rotation must be right-handed");
            var prescribed = Matrix(Views[i], distance);
            for (var row = 0; row < 4; row++)
                for (var col = 0; col < 4; col++)
                    Near(values[row, col], Number(prescribed[row]![col], "prescribed camera"), Views[i] + " camera differs from the prescribed pose or polar roll");
        }
    }

    /// <summary>Keep focal length in pixels when padding a centered image; no crop or resize.</summary>
    public static double PaddedFov(double fov, int originalWidth, int canvasSide)
    {
        Fov(fov);
        if (originalWidth < 1 || canvasSide < originalWidth)
            throw new InvalidOperationException("Padding needs a positive width and a canvas at least that wide");
        var adjusted = 2 * Math.Atan(Math.Tan(fov / 2) * ((double)canvasSide / originalWidth));
        Fov(adjusted);
        return adjusted;
    }

    static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;
    static double Number(JsonNode? node, string name)
    {
        if (node is not JsonValue value || value.GetValueKind() != JsonValueKind.Number
            || !double.TryParse(value.ToJsonString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var number) || !double.IsFinite(number))
            throw new InvalidOperationException(name + " must be a finite JSON number");
        return number;
    }
    static void Positive(double value, string name)
    {
        if (!double.IsFinite(value) || value <= 0)
            throw new InvalidOperationException(name + " must be finite and positive");
    }
    static void Fov(double fov)
    {
        if (!double.IsFinite(fov) || fov <= 0 || fov >= Math.PI)
            throw new InvalidOperationException("Horizontal FOV must satisfy 0 < radians < pi");
    }
    static void Near(double actual, double expected, string reason)
    {
        if (!double.IsFinite(actual) || Math.Abs(actual - expected) > Tolerance * Math.Max(1, Math.Abs(expected)))
            throw new InvalidOperationException(reason);
    }
}
