using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace OpenCaw.AssetProduction;
// Lifetime containment for owned native subprocesses; not a security sandbox.
internal sealed class OwnedProcessTree : IDisposable
{
    IntPtr job;
    public OwnedProcessTree(Process process, long? maximumPrivateBytes = null)
    {
        if (!OperatingSystem.IsWindows())
        {
            if (maximumPrivateBytes is not null) throw new PlatformNotSupportedException("Owned-job aggregate committed-memory ceiling requires Windows; no unbounded fallback");
            return;
        }
        job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero)
            throw new Win32Exception();
        var info = new ExtendedLimit { BasicLimitInformation = new BasicLimit { LimitFlags = 0x2000 } };
        if (maximumPrivateBytes is { } memory)
        {
            // JOB_OBJECT_LIMIT_JOB_MEMORY caps aggregate committed memory charged
            // to the owned job, including descendants. It is not resident RAM,
            // GPU memory or an OS sandbox. Process.Start precedes assignment;
            // an assignment failure kills the launched tree in the caller.
            info.BasicLimitInformation.LimitFlags |= 0x200;
            info.JobMemoryLimit = new UIntPtr(checked((ulong)memory));
        }
        if (!SetInformationJobObject(job, 9, ref info, (uint)Marshal.SizeOf<ExtendedLimit>()) || !AssignProcessToJobObject(job, process.Handle))
        {
            var error = Marshal.GetLastWin32Error();
            CloseHandle(job);
            job = IntPtr.Zero;
            throw new Win32Exception(error, "Cannot establish owned native process lifetime");
        }
    }
    public void Dispose()
    {
        if (job != IntPtr.Zero)
        {
            CloseHandle(job);
            job = IntPtr.Zero;
        }
    }
    [StructLayout(LayoutKind.Sequential)]
    struct BasicLimit
    {
        public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IoCounters
    {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ExtendedLimit
    {
        public BasicLimit BasicLimitInformation; public IoCounters IoInfo; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr attributes, string? name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref ExtendedLimit info, uint length);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("libc", SetLastError = true)] internal static extern int kill(int pid, int signal);
}
