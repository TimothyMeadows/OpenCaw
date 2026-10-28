using OpenCaw.ProofToModel.Domain;
static class CompatibilityTests
{
    public static int Run()
    {
        var count = 0;
        void Check(bool value, string name)
        {
            if (!value)
                throw new Exception(name);
            Console.WriteLine("PASS " + name);
            count++;
        }
        Check(Compatibility.CudaVersionFromLog("stdout: | NVIDIA-SMI 575.86 Driver Version: 575.86 CUDA Version: 12.9 |\n") == "12.9", "legacy NVIDIA CUDA banner parsed");
        Check(Compatibility.CudaVersionFromLog("stdout: | NVIDIA-SMI 617.42 KMD Version: 617.42 CUDA UMD Version: 13.4 |\n") == "13.4", "actual 617.42 KMD/CUDA UMD banner parsed");
        Check(Compatibility.CudaVersionFromLog("stdout: CUDA Ustderr: MD Verstdout: sion: 1stdout: 3.4") == "13.4", "CUDA parser strips stream prefixes across chunk boundaries");
        Check(Compatibility.CudaVersionFromLog("stdout: NVIDIA-SMI failed") is null, "missing CUDA compatibility remains unavailable");
        Check(Compatibility.IsBlender45Log("stdout: Blestderr: nder 4.stdout: 5.10\n"), "Blender version parser strips chunk-boundary prefixes");
        Check(!Compatibility.IsBlender45Log("stdout: Blender 4.4.9\n"), "unsupported Blender version rejected");
        Check(Compatibility.StripStreamMarkers("stdout: 61stderr: 7.stdout: 42") == "617.42", "driver version reconstructed across streamed chunks");
        Console.WriteLine($"PASS {count} compatibility assertions");
        return count;
    }
}
