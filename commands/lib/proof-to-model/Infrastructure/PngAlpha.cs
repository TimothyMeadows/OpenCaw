using System.Buffers.Binary;
using System.IO.Compression;
using OpenCaw.ProofToModel.Domain;
namespace OpenCaw.ProofToModel.Infrastructure;
// Explicit alpha inspection, not foreground inference. Unsupported encodings require
// the configured BiRefNet stage; opaque RGBA never counts as an existing matte.
public static class PngAlpha
{
    public static AlphaMatte? Inspect(string path)
    {
        using var input = File.OpenRead(path);
        using var reader = new BinaryReader(input);
        if (!reader.ReadBytes(8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }))
            return null;
        int width = 0, height = 0, color = 0;
        using var compressed = new MemoryStream();
        while (input.Position < input.Length)
        {
            var length = BinaryPrimitives.ReadInt32BigEndian(reader.ReadBytes(4));
            if (length < 0 || length > 67108864)
                throw new InvalidOperationException("PNG chunk exceeds budget");
            var type = System.Text.Encoding.ASCII.GetString(reader.ReadBytes(4));
            var data = reader.ReadBytes(length);
            reader.ReadBytes(4);
            if (type == "IHDR")
            {
                width = BinaryPrimitives.ReadInt32BigEndian(data);
                height = BinaryPrimitives.ReadInt32BigEndian(data.AsSpan(4));
                color = data[9];
                if (width < 1 || height < 1 || width > 8192 || height > 8192)
                    throw new InvalidOperationException("PNG dimensions exceed budget");
                if (data[8] != 8 || data[12] != 0 || color is not (4 or 6))
                    return null;
            }
            if (type == "IDAT")
                compressed.Write(data);
            if (type == "IEND")
                break;
        }
        if (width == 0)
            return null;
        var channels = color == 6 ? 4 : 2;
        var stride = checked(width * channels);
        var alpha = new byte[checked(width * height)];
        compressed.Position = 0;
        using var z = new ZLibStream(compressed, CompressionMode.Decompress);
        var previous = new byte[stride];
        var row = new byte[stride];
        for (var y = 0; y < height; y++)
        {
            var filter = z.ReadByte();
            z.ReadExactly(row);
            for (var x = 0; x < stride; x++)
            {
                int left = x >= channels ? row[x - channels] : 0, up = previous[x], corner = x >= channels ? previous[x - channels] : 0;
                row[x] = unchecked((byte)(row[x] + (filter switch
                {
                    0 => 0,
                    1 => left,
                    2 => up,
                    3 => (left + up) / 2,
                    4 => Paeth(left, up, corner),
                    _ => throw new InvalidOperationException("Invalid PNG filter")
                })));
            }
            for (var x = 0; x < width; x++)
                alpha[y * width + x] = row[x * channels + channels - 1];
            (row, previous) = (previous, row);
        }
        return new(width, height, alpha, alpha.Any(x => x == 0) && alpha.Any(x => x > 0));
    }
    static int Paeth(int a, int b, int c)
    {
        var p = a + b - c;
        var pa = Math.Abs(p - a);
        var pb = Math.Abs(p - b);
        var pc = Math.Abs(p - c);
        return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
    }
    public static void SaveMask(string path, AlphaMatte matte)
    {
        using var file = File.Create(path);
        file.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        void Chunk(string type, byte[] bytes)
        {
            var tag = System.Text.Encoding.ASCII.GetBytes(type);
            Span<byte> size = stackalloc byte[4];
            BinaryPrimitives.WriteInt32BigEndian(size, bytes.Length);
            file.Write(size);
            file.Write(tag);
            file.Write(bytes);
            uint crc = 0xffffffff;
            foreach (var b in tag.Concat(bytes))
            {
                crc ^= b;
                for (var n = 0; n < 8; n++)
                    crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
            }
            BinaryPrimitives.WriteUInt32BigEndian(size, ~crc);
            file.Write(size);
        }
        var header = new byte[13];
        BinaryPrimitives.WriteInt32BigEndian(header, matte.Width);
        BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), matte.Height);
        header[8] = 8;
        header[9] = 0;
        Chunk("IHDR", header);
        using var buffer = new MemoryStream();
        using (var zip = new ZLibStream(buffer, CompressionLevel.SmallestSize, true))
        {
            for (var y = 0; y < matte.Height; y++)
            {
                zip.WriteByte(0);
                zip.Write(matte.Alpha, y * matte.Width, matte.Width);
            }
        }
        Chunk("IDAT", buffer.ToArray());
        Chunk("IEND", []);
    }
}
