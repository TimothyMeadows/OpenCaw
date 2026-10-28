using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;

namespace OpenCaw.ProofToModel.Infrastructure;

/// <summary>Bounded lossless 8-bit RGBA/gray-alpha PNG input and transparent canvas padding.</summary>
public static class RgbaPng
{
    public sealed record Image(int Width, int Height, byte[] Pixels);
    public const int MaximumDimension = 8192;
    public const int MaximumPixels = 16777216;
    const int MaximumEncodedBytes = 134217728;
    static readonly byte[] Signature = [137, 80, 78, 71, 13, 10, 26, 10];
    static readonly uint[] CrcTable = Enumerable.Range(0, 256).Select(value =>
    {
        var crc = (uint)value;
        for (var bit = 0; bit < 8; bit++)
            crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
        return crc;
    }).ToArray();

    public static Image Read(string path)
    {
        using var file = File.OpenRead(path);
        if (file.Length > MaximumEncodedBytes)
            throw new InvalidOperationException("Encoded PNG exceeds byte budget");
        Span<byte> signature = stackalloc byte[8];
        file.ReadExactly(signature);
        if (!signature.SequenceEqual(Signature))
            throw new InvalidOperationException("Padding requires a PNG with actual alpha");
        int width = 0, height = 0, channels = 0;
        bool hasHeader = false, hasData = false, dataEnded = false, hasPalette = false, hasEnd = false;
        using var compressed = new MemoryStream();
        Span<byte> integer = stackalloc byte[4];
        Span<byte> tag = stackalloc byte[4];
        while (file.Position < file.Length)
        {
            file.ReadExactly(integer);
            var length = BinaryPrimitives.ReadInt32BigEndian(integer);
            if (length < 0 || length > MaximumEncodedBytes || length > file.Length - file.Position - 8)
                throw new InvalidOperationException("Invalid or oversized PNG chunk");
            file.ReadExactly(tag);
            if (tag.ToArray().Any(b => b is not (>= (byte)'A' and <= (byte)'Z') and not (>= (byte)'a' and <= (byte)'z')) || (tag[2] & 32) != 0)
                throw new InvalidOperationException("Invalid PNG chunk type");
            var type = Encoding.ASCII.GetString(tag);
            if (!hasHeader && type != "IHDR")
                throw new InvalidOperationException("PNG must start with IHDR");
            var data = new byte[length];
            file.ReadExactly(data);
            file.ReadExactly(integer);
            if (BinaryPrimitives.ReadUInt32BigEndian(integer) != Crc(tag, data))
                throw new InvalidOperationException("PNG chunk checksum mismatch");
            if (hasData && type != "IDAT")
                dataEnded = true;
            switch (type)
            {
                case "IHDR":
                    if (hasHeader || length != 13)
                        throw new InvalidOperationException("PNG needs exactly one valid IHDR");
                    width = BinaryPrimitives.ReadInt32BigEndian(data);
                    height = BinaryPrimitives.ReadInt32BigEndian(data.AsSpan(4));
                    Dimensions(width, height);
                    if (data[8] != 8 || data[9] is not (4 or 6) || data[10] != 0 || data[11] != 0 || data[12] != 0)
                        throw new InvalidOperationException("Padding supports only noninterlaced 8-bit RGBA or gray-alpha PNG; normalize explicitly first");
                    channels = data[9] == 6 ? 4 : 2;
                    hasHeader = true;
                    break;
                case "PLTE":
                    if (channels != 4 || hasPalette || hasData || length < 3 || length > 768 || length % 3 != 0)
                        throw new InvalidOperationException("Invalid optional RGBA PNG palette");
                    hasPalette = true;
                    break;
                case "IDAT":
                    if (dataEnded || compressed.Length + length > MaximumEncodedBytes)
                        throw new InvalidOperationException("PNG data must be contiguous and bounded");
                    compressed.Write(data);
                    hasData = true;
                    break;
                case "IEND":
                    if (!hasData || length != 0 || file.Position != file.Length)
                        throw new InvalidOperationException("PNG needs final empty IEND without trailing data");
                    hasEnd = true;
                    break;
                default:
                    if ((tag[0] & 32) == 0)
                        throw new InvalidOperationException("Unsupported critical PNG chunk: " + type);
                    break;
            }
            if (hasEnd)
                break;
        }
        if (!hasHeader || !hasData || !hasEnd)
            throw new InvalidOperationException("Incomplete PNG");
        var pixels = new byte[checked(width * height * 4)];
        var stride = checked(width * channels);
        var previous = new byte[stride];
        var row = new byte[stride];
        compressed.Position = 0;
        using var zip = new ZLibStream(compressed, CompressionMode.Decompress);
        for (var y = 0; y < height; y++)
        {
            var filter = zip.ReadByte();
            if (filter is < 0 or > 4)
                throw new InvalidOperationException("Invalid or missing PNG scanline filter");
            zip.ReadExactly(row);
            for (var x = 0; x < stride; x++)
            {
                int left = x >= channels ? row[x - channels] : 0, up = previous[x], corner = x >= channels ? previous[x - channels] : 0;
                var predictor = filter switch { 0 => 0, 1 => left, 2 => up, 3 => (left + up) / 2, 4 => Paeth(left, up, corner), _ => 0 };
                row[x] = unchecked((byte)(row[x] + predictor));
            }
            for (var x = 0; x < width; x++)
            {
                var target = (y * width + x) * 4;
                var source = x * channels;
                pixels[target] = row[source];
                pixels[target + 1] = channels == 4 ? row[source + 1] : row[source];
                pixels[target + 2] = channels == 4 ? row[source + 2] : row[source];
                pixels[target + 3] = row[source + channels - 1];
            }
            (row, previous) = (previous, row);
        }
        if (zip.ReadByte() != -1)
            throw new InvalidOperationException("PNG decompression exceeds declared scanlines");
        return new(width, height, pixels);
    }

    public static void Write(string path, Image image)
    {
        Dimensions(image.Width, image.Height);
        if (image.Pixels.Length != checked(image.Width * image.Height * 4))
            throw new InvalidOperationException("RGBA pixel count differs from dimensions");
        using var data = new MemoryStream();
        using (var zip = new ZLibStream(data, CompressionLevel.Optimal, true))
            for (var y = 0; y < image.Height; y++)
            {
                zip.WriteByte(0);
                zip.Write(image.Pixels, y * image.Width * 4, image.Width * 4);
            }
        using var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        file.Write(Signature);
        var header = new byte[13];
        BinaryPrimitives.WriteInt32BigEndian(header, image.Width);
        BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), image.Height);
        header[8] = 8;
        header[9] = 6;
        Chunk(file, "IHDR", header);
        Chunk(file, "IDAT", data.GetBuffer().AsSpan(0, checked((int)data.Length)));
        Chunk(file, "IEND", []);
    }

    public static void PadSquare(string input, string output, int side)
    {
        Dimensions(side, side);
        if (Path.GetFullPath(input).Equals(Path.GetFullPath(output), OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
            throw new InvalidOperationException("Padding must preserve its input and write a new working copy");
        if (File.Exists(output) || Directory.Exists(output))
            throw new InvalidOperationException("Padding never overwrites an existing artifact");
        var source = Read(input);
        if (side < source.Width || side < source.Height)
            throw new InvalidOperationException("Padding canvas cannot crop or resize the source");
        if (!Enumerable.Range(0, source.Width * source.Height).Any(i => source.Pixels[i * 4 + 3] > 0))
            throw new InvalidOperationException("Padding rejects an empty foreground");
        if (!Enumerable.Range(0, source.Width * source.Height).Any(i => source.Pixels[i * 4 + 3] < 250))
            throw new InvalidOperationException("Padding requires a real alpha matte; it cannot remove a background");
        var pixels = new byte[checked(side * side * 4)];
        var left = (side - source.Width) / 2;
        var top = (side - source.Height) / 2;
        for (var y = 0; y < source.Height; y++)
            source.Pixels.AsSpan(y * source.Width * 4, source.Width * 4).CopyTo(pixels.AsSpan(((y + top) * side + left) * 4));
        Write(output, new(side, side, pixels));
    }

    static void Dimensions(int width, int height)
    {
        if (width < 1 || height < 1 || width > MaximumDimension || height > MaximumDimension || (long)width * height > MaximumPixels)
            throw new InvalidOperationException("PNG dimensions exceed the bounded pixel budget");
    }
    static int Paeth(int a, int b, int c)
    {
        var p = a + b - c;
        var pa = Math.Abs(p - a);
        var pb = Math.Abs(p - b);
        var pc = Math.Abs(p - c);
        return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
    }
    static uint Crc(ReadOnlySpan<byte> tag, ReadOnlySpan<byte> data)
    {
        var crc = 0xffffffffu;
        foreach (var value in tag)
            crc = CrcTable[(crc ^ value) & 255] ^ (crc >> 8);
        foreach (var value in data)
            crc = CrcTable[(crc ^ value) & 255] ^ (crc >> 8);
        return ~crc;
    }
    static void Chunk(Stream stream, string type, ReadOnlySpan<byte> data)
    {
        var tag = Encoding.ASCII.GetBytes(type);
        Span<byte> integer = stackalloc byte[4];
        BinaryPrimitives.WriteInt32BigEndian(integer, data.Length);
        stream.Write(integer);
        stream.Write(tag);
        stream.Write(data);
        BinaryPrimitives.WriteUInt32BigEndian(integer, Crc(tag, data));
        stream.Write(integer);
    }
}
