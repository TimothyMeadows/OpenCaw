using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;

static class MultiViewGeometryTests
{
    public static async Task Run(Workspace w, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        JsonObject ProofSet() => new()
        {
            ["camera"] = new JsonObject
            {
                ["convention"] = "blender-nerf-z-up", ["calibration"] = "nominal-prescribed",
                ["meshScale"] = 1, ["cameraAngleX"] = Math.PI / 9, ["distance"] = MultiViewGeometry.DefaultDistance
            },
            ["views"] = new JsonArray(MultiViewGeometry.Views.Select(view => (JsonNode)new JsonObject
            {
                ["view"] = view, ["cameraToWorld"] = MultiViewGeometry.Matrix(view)
            }).ToArray())
        };
        var valid = ProofSet();
        MultiViewGeometry.Validate(valid);
        check(true, "six prescribed cameras accept JSON integer mesh scale without coercing strings");
        check(MultiViewGeometry.Matrix("front")[1]![3]!.GetValue<double>() < 0
            && MultiViewGeometry.Matrix("right")[0]![3]!.GetValue<double>() < 0
            && MultiViewGeometry.Matrix("left")[0]![3]!.GetValue<double>() > 0,
            "subject faces minus-Y with anatomical right at minus-X, preserving asymmetric side ownership");
        foreach (var view in MultiViewGeometry.Views)
        {
            var matrix = MultiViewGeometry.Matrix(view);
            var position = Enumerable.Range(0, 3).Select(row => matrix[row]![3]!.GetValue<double>()).ToArray();
            var back = Enumerable.Range(0, 3).Select(row => matrix[row]![2]!.GetValue<double>()).ToArray();
            var distance = Math.Sqrt(position.Sum(x => x * x));
            check(Math.Abs(distance - MultiViewGeometry.DefaultDistance) < 1e-12, view + " camera has the prescribed nonzero distance");
            check(Enumerable.Range(0, 3).All(axis => Math.Abs(position[axis] / distance - back[axis]) < 1e-12), view + " local minus-Z looks at the same origin");
        }
        check(MultiViewGeometry.Matrix("top")[1]![1]!.GetValue<double>() == 1
            && MultiViewGeometry.Matrix("bottom")[1]![1]!.GetValue<double>() == -1,
            "top and bottom preserve declared opposite image-up rolls without a singular look-at");
        valid["camera"]!["calibration"] = "measured";
        MultiViewGeometry.Validate(valid);
        check(true, "camera math permits measured status without manufacturing measurement evidence");
        var independent = MultiViewGeometry.Matrix("front");
        independent[0]![0] = 8;
        check(MultiViewGeometry.Matrix("front")[0]![0]!.GetValue<double>() == 1, "camera matrices are fresh instances");
        foreach (var mutation in new (string Name, Action<JsonObject> Apply)[]
        {
            ("missing camera contract", x => x.Remove("camera")),
            ("wrong coordinate convention", x => x["camera"]!["convention"] = "gltf-y-up"),
            ("unqualified camera estimation", x => x["camera"]!["calibration"] = "automatic"),
            ("zero projection scale", x => x["camera"]!["meshScale"] = 0),
            ("negative camera distance", x => x["camera"]!["distance"] = -1),
            ("numeric camera strings", x => x["camera"]!["meshScale"] = "1"),
            ("zero FOV", x => x["camera"]!["cameraAngleX"] = 0),
            ("FOV at pi", x => x["camera"]!["cameraAngleX"] = Math.PI),
            ("invalid per-view FOV", x => x["views"]![0]!["cameraAngleX"] = -1),
            ("five instead of six views", x => x["views"]!.AsArray().RemoveAt(5)),
            ("seventh extra view", x => x["views"]!.AsArray().Add(x["views"]![0]!.DeepClone())),
            ("duplicate semantic view", x => x["views"]![5]!["view"] = "front"),
            ("wrong side ordering", x => x["views"]![1]!["view"] = "left"),
            ("malformed matrix rows", x => x["views"]![0]!["cameraToWorld"]![0]!.AsArray().RemoveAt(3)),
            ("nonhomogeneous matrix", x => x["views"]![0]!["cameraToWorld"]![3]![0] = 1),
            ("scaled camera rotation", x => x["views"]![0]!["cameraToWorld"]![0]![0] = 2),
            ("sheared camera rotation", x => x["views"]![0]!["cameraToWorld"]![0]![1] = .25),
            ("mirrored camera rotation", x => x["views"]![0]!["cameraToWorld"]![0]![0] = -1),
            ("wrong camera position", x => x["views"]![0]!["cameraToWorld"]![1]![3] = -2),
            ("flipped polar roll", x =>
            {
                x["views"]![4]!["cameraToWorld"]![0]![0] = -1;
                x["views"]![4]!["cameraToWorld"]![1]![1] = -1;
            }),
            ("matrix numeric strings", x => x["views"]![0]!["cameraToWorld"]![0]![0] = "1")
        })
        {
            var candidate = ProofSet();
            mutation.Apply(candidate);
            await reject(() => Task.Run(() => MultiViewGeometry.Validate(candidate)), mutation.Name + " rejected");
        }
        foreach (var distance in new[] { 0, -1, double.PositiveInfinity, double.NaN })
            await reject(() => Task.Run(() => MultiViewGeometry.Matrix("front", distance)), "invalid camera distance rejected: " + distance);
        await reject(() => Task.Run(() => MultiViewGeometry.Matrix("three-quarter")), "unregistered view does not silently select a camera");
        foreach (var fov in new[] { 0, -1, Math.PI, double.PositiveInfinity, double.NaN })
            await reject(() => Task.Run(() => MultiViewGeometry.PaddedFov(fov, 100, 200)), "invalid padding FOV rejected: " + fov);
        await reject(() => Task.Run(() => MultiViewGeometry.PaddedFov(.3, 0, 200)), "zero input width rejected");
        await reject(() => Task.Run(() => MultiViewGeometry.PaddedFov(.3, 201, 200)), "FOV helper cannot imply a crop");
        var fovBefore = Math.PI / 9;
        var fovAfter = MultiViewGeometry.PaddedFov(fovBefore, 320, 640);
        check(Math.Abs(320 / (2 * Math.Tan(fovBefore / 2)) - 640 / (2 * Math.Tan(fovAfter / 2))) < 1e-10,
            "full-canvas padding preserves the centered focal length in pixels");
        check(MultiViewGeometry.PaddedFov(fovBefore, 640, 640) == fovBefore, "square input leaves the FOV unchanged");

        var directory = w.Resolve("multiview-geometry-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        string PathFor(string name) => Path.Combine(directory, name);
        byte[] pixels = [30, 90, 180, 0, 150, 50, 200, 128, 10, 240, 99, 255, 1, 2, 3, 40, 88, 77, 66, 250, 11, 22, 33, 10];
        var image = new RgbaPng.Image(3, 2, pixels);
        RgbaPng.Write(PathFor("original.png"), image);
        var originalHash = Workspace.Hash(PathFor("original.png"));
        var decoded = RgbaPng.Read(PathFor("original.png"));
        check(decoded.Width == 3 && decoded.Height == 2 && decoded.Pixels.SequenceEqual(pixels), "RGBA writer and bounded decoder preserve exact color and soft alpha");
        new AlphaProcessor().PadSquare(PathFor("original.png"), PathFor("padded.png"), 6);
        var padded = RgbaPng.Read(PathFor("padded.png"));
        var expected = new byte[6 * 6 * 4];
        for (var y = 0; y < 2; y++)
            pixels.AsSpan(y * 12, 12).CopyTo(expected.AsSpan(((y + 2) * 6 + 1) * 4));
        check(padded.Width == 6 && padded.Height == 6 && padded.Pixels.SequenceEqual(expected), "padding copies every input pixel unchanged and adds transparent black only");
        check((6 - image.Width) / 2 == 1 && 6 - image.Width - (6 - image.Width) / 2 == 2,
            "odd padding uses documented floor placement and half-pixel offset");
        check(Workspace.Hash(PathFor("original.png")) == originalHash, "padding preserves immutable input bytes");
        RgbaPng.PadSquare(PathFor("padded.png"), PathFor("unchanged-square.png"), 6);
        check(RgbaPng.Read(PathFor("unchanged-square.png")).Pixels.SequenceEqual(padded.Pixels), "already square input receives no crop, shift or resize");
        foreach (var filter in Enumerable.Range(0, 5))
        {
            var path = PathFor("filter-" + filter + ".png");
            WriteFixture(path, 3, 2, pixels, 6, filter);
            check(RgbaPng.Read(path).Pixels.SequenceEqual(pixels), "PNG scanline filter " + filter + " decodes losslessly");
        }
        var gray = new byte[] { 10, 0, 55, 128, 200, 255, 77, 40 };
        WriteFixture(PathFor("gray-alpha.png"), 2, 2, gray, 4, 4);
        check(RgbaPng.Read(PathFor("gray-alpha.png")).Pixels.SequenceEqual(new byte[] { 10, 10, 10, 0, 55, 55, 55, 128, 200, 200, 200, 255, 77, 77, 77, 40 }),
            "gray-alpha input expands gray consistently while preserving actual alpha");
        await reject(() => Task.Run(() => RgbaPng.PadSquare(PathFor("original.png"), PathFor("original.png"), 6)), "padding cannot overwrite original");
        await reject(() => Task.Run(() => RgbaPng.PadSquare(PathFor("original.png"), PathFor("padded.png"), 6)), "padding cannot replace a previous attempt");
        await reject(() => Task.Run(() => RgbaPng.PadSquare(PathFor("original.png"), PathFor("too-small.png"), 2)), "small padding canvas cannot crop source");
        check(!File.Exists(PathFor("too-small.png")), "invalid padding creates no output artifact");
        foreach (var side in new[] { 0, -1, 8193, 8192 })
            await reject(() => Task.Run(() => RgbaPng.PadSquare(PathFor("original.png"), PathFor("oversized-" + side + ".png"), side)), "canvas dimension or decoded pixel budget enforced: " + side);
        foreach (var alpha in new byte[] { 0, 255 })
        {
            var candidate = pixels.ToArray();
            for (var pixel = 0; pixel < candidate.Length / 4; pixel++)
                candidate[pixel * 4 + 3] = alpha;
            RgbaPng.Write(PathFor("alpha-" + alpha + ".png"), new(3, 2, candidate));
            await reject(() => Task.Run(() => RgbaPng.PadSquare(PathFor("alpha-" + alpha + ".png"), PathFor("alpha-padded-" + alpha + ".png"), 6)),
                alpha == 0 ? "fully transparent input cannot become a proof" : "opaque input cannot acquire a fabricated matte by padding");
        }
        var encoded = File.ReadAllBytes(PathFor("original.png"));
        var corrupt = encoded.ToArray();
        corrupt[20] ^= 1;
        File.WriteAllBytes(PathFor("corrupt-crc.png"), corrupt);
        await reject(() => Task.Run(() => RgbaPng.Read(PathFor("corrupt-crc.png"))), "corrupt PNG checksum rejected before pixels are trusted");
        File.WriteAllBytes(PathFor("truncated.png"), encoded[..^3]);
        await reject(() => Task.Run(() => RgbaPng.Read(PathFor("truncated.png"))), "truncated PNG rejected");
        File.WriteAllBytes(PathFor("trailing.png"), encoded.Concat(new byte[] { 1 }).ToArray());
        await reject(() => Task.Run(() => RgbaPng.Read(PathFor("trailing.png"))), "data following IEND rejected");
        WriteFixture(PathFor("unsupported-rgb.png"), 1, 1, [1, 2, 3], 2, 0);
        await reject(() => Task.Run(() => RgbaPng.Read(PathFor("unsupported-rgb.png"))), "RGB PNG cannot masquerade as an alpha matte");
        WriteFixture(PathFor("oversized-header.png"), 8192, 8192, [], 6, 0);
        await reject(() => Task.Run(() => RgbaPng.Read(PathFor("oversized-header.png"))), "encoded header cannot exceed decoded pixel budget");
        WriteFixture(PathFor("bad-filter.png"), 3, 2, pixels, 6, 5);
        await reject(() => Task.Run(() => RgbaPng.Read(PathFor("bad-filter.png"))), "unknown scanline filter rejected");
        WriteFixture(PathFor("excess-inflated.png"), 3, 2, pixels, 6, 0, extraByte: true);
        await reject(() => Task.Run(() => RgbaPng.Read(PathFor("excess-inflated.png"))), "inflation beyond declared rows rejected without unbounded allocation");
    }

    static void WriteFixture(string path, int width, int height, byte[] pixels, byte color, int filter, bool extraByte = false)
    {
        // Independent tiny encoder deliberately exercises all PNG predictor filters and invalid encodings.
        using var file = File.Create(path);
        file.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        void Chunk(string type, byte[] data)
        {
            Span<byte> integer = stackalloc byte[4];
            BinaryPrimitives.WriteInt32BigEndian(integer, data.Length);
            file.Write(integer);
            var tag = Encoding.ASCII.GetBytes(type);
            file.Write(tag);
            file.Write(data);
            var crc = 0xffffffffu;
            foreach (var value in tag.Concat(data))
            {
                crc ^= value;
                for (var bit = 0; bit < 8; bit++)
                    crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
            }
            BinaryPrimitives.WriteUInt32BigEndian(integer, ~crc);
            file.Write(integer);
        }
        var header = new byte[13];
        BinaryPrimitives.WriteInt32BigEndian(header, width);
        BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), height);
        header[8] = 8;
        header[9] = color;
        Chunk("IHDR", header);
        using var buffer = new MemoryStream();
        using (var zip = new ZLibStream(buffer, CompressionLevel.Optimal, true))
        {
            var channels = color == 6 ? 4 : color == 4 ? 2 : 3;
            var stride = width * channels;
            for (var y = 0; pixels.Length > 0 && y < height; y++)
            {
                zip.WriteByte((byte)filter);
                for (var x = 0; x < stride; x++)
                {
                    int left = x >= channels ? pixels[y * stride + x - channels] : 0;
                    int up = y > 0 ? pixels[(y - 1) * stride + x] : 0;
                    int corner = y > 0 && x >= channels ? pixels[(y - 1) * stride + x - channels] : 0;
                    var prediction = 0;
                    if (filter == 1) prediction = left;
                    if (filter == 2) prediction = up;
                    if (filter == 3) prediction = (left + up) / 2;
                    if (filter == 4)
                    {
                        var candidate = left + up - corner;
                        var a = Math.Abs(candidate - left);
                        var b = Math.Abs(candidate - up);
                        var c = Math.Abs(candidate - corner);
                        prediction = a <= b && a <= c ? left : b <= c ? up : corner;
                    }
                    zip.WriteByte(unchecked((byte)(pixels[y * stride + x] - prediction)));
                }
            }
            if (extraByte) zip.WriteByte(99);
        }
        Chunk("IDAT", buffer.ToArray());
        Chunk("IEND", []);
    }
}
