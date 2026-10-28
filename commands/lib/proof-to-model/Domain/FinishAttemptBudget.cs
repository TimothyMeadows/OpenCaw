using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace OpenCaw.ProofToModel.Domain;

/// <summary>A recorded human assertion for one extra finish start, not an asset approval or identity authentication.</summary>
public sealed record FinishAttemptBudget(string Reviewer, string Reason, string ManifestSha256, int ConsumedFinishAttempts, int MaxFinishAttempts)
{
    public const int MaximumBytes = 16384;
    public const int MaximumAttempts = 100;
    public static FinishAttemptBudget Parse(byte[] bytes)
    {
        if (bytes.Length is 0 or > MaximumBytes)
            throw new InvalidOperationException("Finish budget receipt must contain 1..16384 UTF-8 bytes");
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 4 });
        var root = document.RootElement;
        var required = new HashSet<string>(["schemaVersion", "kind", "stage", "decision", "human", "reviewer", "reason", "manifestSha256", "consumedFinishAttempts", "maxFinishAttempts"], StringComparer.Ordinal);
        if (root.ValueKind != JsonValueKind.Object) throw new InvalidOperationException("Finish budget receipt must be an object");
        foreach (var field in root.EnumerateObject())
            if (!required.Remove(field.Name)) throw new InvalidOperationException("Unknown or duplicate finish budget field: " + field.Name);
        if (required.Count != 0) throw new InvalidOperationException("Missing finish budget fields: " + string.Join(", ", required));
        Integer(root.GetProperty("schemaVersion"), "schemaVersion", 1, 1);
        if (Text(root, "kind") != "finish-attempt-budget" || Text(root, "stage") != "finish" || Text(root, "decision") != "approved" || root.GetProperty("human").ValueKind != JsonValueKind.True)
            throw new InvalidOperationException("Finish budget requires kind=finish-attempt-budget, stage=finish, decision=approved and human:true");
        var reviewer = Text(root, "reviewer"); var reason = Text(root, "reason");
        if (string.IsNullOrWhiteSpace(reviewer) || reviewer.EnumerateRunes().Count() > 200 || reviewer.Any(char.IsControl) || reviewer.IndexOfAny(['\u2028', '\u2029']) >= 0)
            throw new InvalidOperationException("Finish budget reviewer must be nonblank, single-line and at most 200 Unicode characters");
        if (string.IsNullOrWhiteSpace(reason) || reason.EnumerateRunes().Count() > 4000)
            throw new InvalidOperationException("Finish budget reason must be nonblank and at most 4000 Unicode characters");
        var hash = Text(root, "manifestSha256");
        if (hash.Length != 64 || !Regex.IsMatch(hash, "^[a-f0-9]{64}$", RegexOptions.CultureInvariant)) throw new InvalidOperationException("Finish budget manifestSha256 must be 64 lowercase hexadecimal characters");
        var consumed = Integer(root.GetProperty("consumedFinishAttempts"), "consumedFinishAttempts", 0, MaximumAttempts - 1);
        var maximum = Integer(root.GetProperty("maxFinishAttempts"), "maxFinishAttempts", 1, MaximumAttempts);
        if (maximum != consumed + 1) throw new InvalidOperationException("Finish budget authorizes exactly one additional attempt: maxFinishAttempts must equal consumedFinishAttempts + 1");
        return new(reviewer, reason, hash, consumed, maximum);
    }
    static string Text(JsonElement root, string field)
    {
        var value = root.GetProperty(field);
        return value.ValueKind == JsonValueKind.String ? value.GetString()! : throw new InvalidOperationException("Finish budget " + field + " must be a string");
    }
    static int Integer(JsonElement value, string field, int minimum, int maximum)
    {
        InvalidOperationException Invalid() => new("Finish budget " + field + " must be an exact JSON integer inside " + minimum + ".." + maximum);
        if (value.ValueKind != JsonValueKind.Number) throw Invalid();
        // Normalize exact base10 digits rather than rounding through binary64:
        // 3.0 and 30e-1 are integers, but 3.000000000000000000001 is not.
        var raw = value.GetRawText(); var exponentIndex = raw.IndexOfAny(['e', 'E']);
        var mantissa = exponentIndex < 0 ? raw : raw[..exponentIndex];
        var negative = mantissa[0] == '-'; if (negative) mantissa = mantissa[1..];
        var dot = mantissa.IndexOf('.'); var fractionalDigits = dot < 0 ? 0 : mantissa.Length - dot - 1;
        var digits = mantissa.Replace(".", "").TrimStart('0');
        if (digits.Length == 0)
        {
            if (minimum > 0) throw Invalid();
            return 0; // Exact zero remains zero even with an enormous exponent.
        }
        var exponent = 0;
        if (exponentIndex >= 0)
        {
            var text = raw[(exponentIndex + 1)..]; var minus = text[0] == '-';
            if (text[0] is '+' or '-') text = text[1..];
            text = text.TrimStart('0');
            // A nonzero coefficient has at most MaximumBytes digits, so a
            // larger shift cannot be cancelled into this bounded integer range.
            if (text.Length > 5 || (text.Length > 0 && (!int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out exponent) || exponent > MaximumBytes + 4))) throw Invalid();
            if (minus) exponent = -exponent;
        }
        var shift = exponent - fractionalDigits;
        if (shift < 0)
        {
            var remove = -shift;
            if (remove >= digits.Length || digits.AsSpan(digits.Length - remove).IndexOfAnyExcept('0') >= 0) throw Invalid();
            digits = digits[..^remove]; shift = 0;
        }
        if (digits.Length + shift > maximum.ToString(CultureInfo.InvariantCulture).Length) throw Invalid();
        if (!int.TryParse(digits, NumberStyles.None, CultureInfo.InvariantCulture, out var number)) throw Invalid();
        while (shift-- > 0) number *= 10; // At most three decimal digits survive.
        if (negative) number = -number;
        if (number < minimum || number > maximum) throw Invalid();
        return number;
    }
}
