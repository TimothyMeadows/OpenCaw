using System.Diagnostics;
namespace OpenCaw.AssetProduction;

public class NativeProcess : INativeProcess
{
    public bool SupportsPrivateMemoryLimit => OperatingSystem.IsWindows() && Environment.Is64BitProcess;
    public Task Run(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
        => RunCore(executable, arguments, cwd, log, seconds, null, cancellation, maximumLogBytes, environment);
    public Task RunWithLimits(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, long maximumPrivateBytes, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
    {
        if (maximumPrivateBytes is < 67_108_864 or > 68_719_476_736)
            throw new InvalidOperationException("Owned-job committed-memory budget must be 64MiB..64GiB");
        if (!SupportsPrivateMemoryLimit)
            throw new PlatformNotSupportedException("The selected aggregate committed-memory ceiling requires 64-bit Windows owned jobs; blocked before launch and log creation");
        cancellation.ThrowIfCancellationRequested();
        return RunCore(executable, arguments, cwd, log, seconds, maximumPrivateBytes, cancellation, maximumLogBytes, environment);
    }
    async Task RunCore(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, long? maximumPrivateBytes, CancellationToken cancellation, long maximumLogBytes, IReadOnlyDictionary<string, string>? environment)
    {
        if (seconds < 1 || seconds > 86400)
            throw new InvalidOperationException("Deadline must be 1..86400 seconds");
        if (maximumLogBytes < 1024 || maximumLogBytes > 1073741824)
            throw new InvalidOperationException("Log budget must be 1KiB..1GiB");
        var processGroup = OperatingSystem.IsLinux() && File.Exists("/usr/bin/setsid");
        if (!OperatingSystem.IsWindows() && !processGroup)
            throw new PlatformNotSupportedException("Owned native process cleanup requires Windows jobs or Linux /usr/bin/setsid; this platform is blocked before launch. No OS sandbox is implied.");
        var info = new ProcessStartInfo(processGroup ? "/usr/bin/setsid" : executable) { WorkingDirectory = cwd, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        if (processGroup)
            info.ArgumentList.Add(executable);
        foreach (var argument in arguments)
            info.ArgumentList.Add(argument);
        if (environment is not null)
            foreach (var variable in environment)
                info.Environment[variable.Key] = variable.Value;
        Directory.CreateDirectory(Path.GetDirectoryName(log)!);
        await using var writer = new StreamWriter(new FileStream(log, FileMode.CreateNew, FileAccess.Write, FileShare.Read));
        using var process = new Process { StartInfo = info };
        if (!process.Start())
            throw new InvalidOperationException("Native process could not start");
        OwnedProcessTree lifetime;
        try
        {
            lifetime = new OwnedProcessTree(process, maximumPrivateBytes);
        }
        catch { if (!process.HasExited) process.Kill(true); await process.WaitForExitAsync(); throw; }
        using var owned = lifetime;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        deadline.CancelAfter(TimeSpan.FromSeconds(seconds));
        var gate = new SemaphoreSlim(1, 1);
        long logged = 0;
        if (maximumPrivateBytes is { } memory)
        {
            var policy = $"resource-policy: windows-owned-job-aggregate-committed-memory maxPrivateBytes={memory}; process-start-to-job-assignment window is not sandboxed; resident RAM and GPU memory are not measured\n";
            logged = System.Text.Encoding.UTF8.GetByteCount(policy);
            await writer.WriteAsync(policy);
            await writer.FlushAsync();
        }
        var maximumLog = maximumLogBytes;
        if (maximumLog < 1024 || maximumLog > 1073741824)
            throw new InvalidOperationException("Log budget must be 1KiB..1GiB");
        var failed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        async Task Pump(StreamReader stream, string channel)
        {
            try
            {
                var buffer = new char[4096];
                int count;
                while ((count = await stream.ReadAsync(buffer.AsMemory(), deadline.Token)) > 0)
                {
                    var chunk = new string(buffer, 0, count);
                    await gate.WaitAsync(deadline.Token);
                    try
                    {
                        logged += System.Text.Encoding.UTF8.GetByteCount(channel + ": " + chunk);
                        if (logged > maximumLog)
                            throw new InvalidOperationException("Native log exceeded configured byte budget");
                        await writer.WriteAsync(channel + ": " + chunk);
                        await writer.FlushAsync();
                    }
                    finally { gate.Release(); }
                    Console.Error.Write(chunk);
                }
            }
            catch (Exception e) { failed.TrySetException(e); throw; }
        }
        var output = Pump(process.StandardOutput, "stdout");
        var error = Pump(process.StandardError, "stderr");
        try
        {
            var exit = process.WaitForExitAsync(deadline.Token);
            await await Task.WhenAny(exit, failed.Task);
            await Task.WhenAll(output, error).WaitAsync(deadline.Token);
            if (process.ExitCode != 0)
                throw new InvalidOperationException($"Native process exited {process.ExitCode}; see {log}");
        }
        catch { owned.Dispose(); if (processGroup) OwnedProcessTree.kill(-process.Id, 9); if (!process.HasExited) process.Kill(entireProcessTree: true); deadline.Cancel(); await process.WaitForExitAsync(); try { await Task.WhenAll(output, error); } catch (Exception) { } throw; }
        finally { if (processGroup) OwnedProcessTree.kill(-process.Id, 9); }
    }
}
