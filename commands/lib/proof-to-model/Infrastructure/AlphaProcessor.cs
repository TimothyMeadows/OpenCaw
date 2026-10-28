using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
namespace OpenCaw.ProofToModel.Infrastructure;

public sealed class AlphaProcessor : IAlphaProcessor
{
    public AlphaMatte? Inspect(string path) => PngAlpha.Inspect(path);
    public void SaveMask(string path, AlphaMatte matte) => PngAlpha.SaveMask(path, matte);
    public void PadSquare(string input, string output, int side) => RgbaPng.PadSquare(input, output, side);
}
