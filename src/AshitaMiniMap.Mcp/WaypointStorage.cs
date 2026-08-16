using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AshitaMiniMap.Mcp;

public static class WaypointStorage
{
    private const string RequestFileName = "mcp_waypoint_request.lua";
    private const string StatusFileName = "mcp_waypoint_status.json";
    private const string LinkCandidateFileName = "link_candidate.json";
    private const string DefaultAshitaRoot = @"C:\Games\CatsEyeXI\catseyexi-client\Ashita";
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private static readonly object PublicationLock = new();

    public static WaypointPublishResult PublishSet(
        int zoneId,
        double x,
        double y,
        int? mapId,
        double? z)
    {
        if (zoneId is < 0 or > 999)
        {
            throw new ArgumentException("zoneId must be between 0 and 999.");
        }
        ValidateCoordinate(x, "x");
        ValidateCoordinate(y, "y");
        if (mapId is < 0 or > 255)
        {
            throw new ArgumentException("mapId must be between 0 and 255 when supplied.");
        }
        if (z.HasValue)
        {
            ValidateCoordinate(z.Value, "z");
        }

        return Publish("set", writer =>
        {
            writer.AppendLine("    waypoint = {");
            writer.AppendLine($"        zone_id = {zoneId},");
            if (mapId.HasValue)
            {
                writer.AppendLine($"        map_id = {mapId.Value},");
            }
            writer.AppendLine($"        x = {LuaNumber(x)},");
            writer.AppendLine($"        y = {LuaNumber(y)},");
            if (z.HasValue)
            {
                writer.AppendLine($"        z = {LuaNumber(z.Value)},");
            }
            writer.AppendLine("    },");
        });
    }

    public static WaypointPublishResult PublishClear() => Publish("clear", null);

    public static string ReadStatus()
    {
        lock (PublicationLock)
        {
            var directory = ResolveConfigDirectory();
            var requestPath = Path.Combine(directory, RequestFileName);
            var requestText = File.Exists(requestPath)
                ? File.ReadAllText(requestPath, Utf8NoBom)
                : string.Empty;
            var requestId = Regex.Match(
                requestText,
                "request_id\\s*=\\s*\\\"([A-Za-z0-9-]{1,64})\\\"").Groups[1].Value;
            var expiresMatch = Regex.Match(requestText, "expires_at\\s*=\\s*([0-9]+)");
            var expiresAt = expiresMatch.Success
                && long.TryParse(expiresMatch.Groups[1].Value, out var expiresUnix)
                ? DateTimeOffset.FromUnixTimeSeconds(expiresUnix)
                : (DateTimeOffset?)null;

            var path = Path.Combine(directory, StatusFileName);
            if (!File.Exists(path))
            {
                return JsonSerializer.Serialize(new
                {
                    ok = true,
                    acknowledged = false,
                    requestId,
                    state = requestId.Length == 0
                        ? "unavailable"
                        : expiresAt < DateTimeOffset.UtcNow
                            ? "expired_unacknowledged"
                            : "pending",
                    message = requestId.Length == 0
                        ? "No MCP waypoint request has been published."
                        : "AshitaMiniMap has not acknowledged the latest waypoint request.",
                });
            }

            for (var attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    using var document = JsonDocument.Parse(File.ReadAllText(path, Utf8NoBom));
                    var acknowledgedId = document.RootElement.TryGetProperty("requestId", out var property)
                        ? property.GetString() ?? string.Empty
                        : string.Empty;
                    if (requestId.Length > 0
                        && !string.Equals(requestId, acknowledgedId, StringComparison.Ordinal))
                    {
                        return JsonSerializer.Serialize(new
                        {
                            ok = true,
                            acknowledged = false,
                            requestId,
                            state = expiresAt < DateTimeOffset.UtcNow
                                ? "expired_unacknowledged"
                                : "pending",
                            message = "AshitaMiniMap has not acknowledged the latest waypoint request.",
                        });
                    }
                    return document.RootElement.GetRawText();
                }
                catch (JsonException) when (attempt < 2)
                {
                    Thread.Sleep(15);
                }
            }

            throw new InvalidDataException("AshitaMiniMap waypoint status is temporarily unreadable.");
        }
    }

    public static string ReadLinkCandidate()
    {
        lock (PublicationLock)
        {
            var path = Path.Combine(ResolveConfigDirectory(), LinkCandidateFileName);
            if (!File.Exists(path))
            {
                return JsonSerializer.Serialize(new
                {
                    ok = true,
                    available = false,
                    state = "unavailable",
                    message = "No in-game link candidate has been saved.",
                });
            }

            for (var attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    var text = File.ReadAllText(path, Utf8NoBom);
                    using var document = JsonDocument.Parse(text);
                    ValidateLinkCandidate(document.RootElement);
                    return document.RootElement.GetRawText();
                }
                catch (JsonException) when (attempt < 2)
                {
                    Thread.Sleep(15);
                }
            }

            throw new InvalidDataException("AshitaMiniMap link candidate is temporarily unreadable.");
        }
    }

    public static bool ClearLinkCandidate(string candidateId)
    {
        if (string.IsNullOrWhiteSpace(candidateId)
            || candidateId.Length > 96
            || !Regex.IsMatch(candidateId, "^[A-Za-z0-9-]+$"))
        {
            throw new ArgumentException("candidateId must be the exact saved candidate identifier.");
        }
        lock (PublicationLock)
        {
            var path = Path.Combine(ResolveConfigDirectory(), LinkCandidateFileName);
            if (!File.Exists(path))
            {
                return false;
            }
            using var document = JsonDocument.Parse(File.ReadAllText(path, Utf8NoBom));
            ValidateLinkCandidate(document.RootElement);
            var savedId = document.RootElement.GetProperty("candidateId").GetString();
            if (!string.Equals(candidateId, savedId, StringComparison.Ordinal))
            {
                throw new ArgumentException("candidateId does not match the currently saved candidate.");
            }
            File.Delete(path);
            return true;
        }
    }

    public static void RunSelfTest()
    {
        var previous = Environment.GetEnvironmentVariable("ASHITAMINIMAP_CONFIG_DIR");
        var directory = Path.Combine(Path.GetTempPath(), $"ashitaminimap-mcp-{Guid.NewGuid():N}");
        try
        {
            Environment.SetEnvironmentVariable("ASHITAMINIMAP_CONFIG_DIR", directory);
            var set = PublishSet(100, 12.5, -42.25, 3, 7.75);
            var requestPath = Path.Combine(directory, RequestFileName);
            var request = File.ReadAllText(requestPath, Utf8NoBom);
            if (!request.Contains($"request_id = \"{set.RequestId}\"", StringComparison.Ordinal)
                || !request.Contains("action = \"set\"", StringComparison.Ordinal)
                || !request.Contains("zone_id = 100", StringComparison.Ordinal)
                || !request.Contains("map_id = 3", StringComparison.Ordinal)
                || !request.Contains("x = 12.5", StringComparison.Ordinal)
                || !request.Contains("y = -42.25", StringComparison.Ordinal)
                || !request.Contains("z = 7.75", StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Set request serialization self-test failed.");
            }

            var statusPath = Path.Combine(directory, StatusFileName);
            File.WriteAllText(
                statusPath,
                $"{{\"ok\":true,\"acknowledged\":true,\"requestId\":\"{set.RequestId}\",\"state\":\"routed\"}}",
                Utf8NoBom);
            if (!ReadStatus().Contains("\"state\":\"routed\"", StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Status read self-test failed.");
            }

            var clear = PublishClear();
            request = File.ReadAllText(requestPath, Utf8NoBom);
            if (!request.Contains($"request_id = \"{clear.RequestId}\"", StringComparison.Ordinal)
                || !request.Contains("action = \"clear\"", StringComparison.Ordinal)
                || request.Contains("waypoint =", StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Clear request serialization self-test failed.");
            }

            ExpectArgumentError(() => PublishSet(-1, 0, 0, null, null));
            ExpectArgumentError(() => PublishSet(1, double.NaN, 0, null, null));
            ExpectArgumentError(() => PublishSet(1, 0, 0, 256, null));

            var candidatePath = Path.Combine(directory, LinkCandidateFileName);
            File.WriteAllText(
                candidatePath,
                """
                {"ok":true,"version":1,"source":"ashitaminimap_developer","candidateId":"245-0-123","state":"pending_validation","zoneId":245,"mapId":0,"direction":"one_way","actionKind":"door","actionName":"Door: Neptune's Spire","actionNote":"Open the door.","reverseActionNote":"","points":[{"role":"start","x":1.0,"y":2.0,"z":3.0},{"role":"end","x":4.0,"y":5.0,"z":6.0}]}
                """,
                Utf8NoBom);
            var candidate = ReadLinkCandidate();
            if (!candidate.Contains("\"candidateId\":\"245-0-123\"", StringComparison.Ordinal)
                || !candidate.Contains("\"actionKind\":\"door\"", StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Link candidate read self-test failed.");
            }
            if (!ClearLinkCandidate("245-0-123") || File.Exists(candidatePath))
            {
                throw new InvalidOperationException("Link candidate clear self-test failed.");
            }
            ExpectArgumentError(() => ClearLinkCandidate("wrong id!"));

            File.WriteAllText(
                candidatePath,
                """
                {"ok":true,"version":1,"source":"ashitaminimap_developer","candidateId":"245-0-456","state":"pending_validation","zoneId":245,"mapId":0,"direction":"bidirectional","actionKind":"walk","actionName":"","actionNote":"","reverseActionNote":"","points":[{"role":"start","x":1.0,"y":2.0,"z":3.0},{"role":"checkpoint","x":2.0,"y":3.0,"z":3.5},{"role":"end","x":4.0,"y":5.0,"z":6.0}]}
                """,
                Utf8NoBom);
            candidate = ReadLinkCandidate();
            if (!candidate.Contains("\"direction\":\"bidirectional\"", StringComparison.Ordinal)
                || !candidate.Contains("\"role\":\"checkpoint\"", StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Checkpoint candidate self-test failed.");
            }
            ExpectArgumentError(() => ClearLinkCandidate("245-0-stale"));
            if (!ClearLinkCandidate("245-0-456"))
            {
                throw new InvalidOperationException("Checkpoint candidate clear self-test failed.");
            }

            File.WriteAllText(
                candidatePath,
                """
                {"ok":true,"version":1,"source":"ashitaminimap_developer","candidateId":"245-0-789","state":"pending_validation","zoneId":245,"mapId":0,"direction":"one_way","actionKind":"geyser","actionName":"","actionNote":"","reverseActionNote":"","points":[{"role":"start","x":1.0,"y":2.0,"z":3.0},{"role":"end","x":4.0,"y":5.0,"z":6.0}]}
                """,
                Utf8NoBom);
            ExpectInvalidData(() => ReadLinkCandidate());
        }
        finally
        {
            Environment.SetEnvironmentVariable("ASHITAMINIMAP_CONFIG_DIR", previous);
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, true);
            }
        }
    }

    private static WaypointPublishResult Publish(string action, Action<StringBuilder>? appendWaypoint)
    {
        lock (PublicationLock)
        {
            var now = DateTimeOffset.UtcNow;
            var expires = now.AddSeconds(60);
            var requestId = Guid.NewGuid().ToString("N");
            var output = new StringBuilder();
            output.AppendLine("return {");
            output.AppendLine("    version = 1,");
            output.AppendLine("    source = \"ashitaminimap_mcp\",");
            output.AppendLine($"    request_id = \"{requestId}\",");
            output.AppendLine($"    action = \"{action}\",");
            output.AppendLine($"    issued_at = {now.ToUnixTimeSeconds()},");
            output.AppendLine($"    expires_at = {expires.ToUnixTimeSeconds()},");
            appendWaypoint?.Invoke(output);
            output.AppendLine("}");

            var directory = ResolveConfigDirectory();
            Directory.CreateDirectory(directory);
            AtomicWrite(Path.Combine(directory, RequestFileName), output.ToString());
            return new WaypointPublishResult(requestId, expires.UtcDateTime);
        }
    }

    private static string ResolveConfigDirectory()
    {
        var configured = Environment.GetEnvironmentVariable("ASHITAMINIMAP_CONFIG_DIR");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return Path.GetFullPath(configured);
        }
        var ashitaRoot = Environment.GetEnvironmentVariable("ASHITA_ROOT");
        if (string.IsNullOrWhiteSpace(ashitaRoot))
        {
            ashitaRoot = DefaultAshitaRoot;
        }
        return Path.Combine(Path.GetFullPath(ashitaRoot), "config", "addons", "ashitaminimap");
    }

    private static void ValidateLinkCandidate(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("version", out var version)
            || version.GetInt32() != 1
            || !root.TryGetProperty("candidateId", out var candidateId)
            || string.IsNullOrWhiteSpace(candidateId.GetString())
            || !root.TryGetProperty("zoneId", out var zoneId)
            || zoneId.GetInt32() is < 0 or > 999
            || !root.TryGetProperty("mapId", out var mapId)
            || mapId.GetInt32() is < 0 or > 255
            || !root.TryGetProperty("direction", out var direction)
            || direction.GetString() is not ("bidirectional" or "one_way")
            || !root.TryGetProperty("actionKind", out var actionKind)
            || actionKind.GetString() is not (
                "walk" or "door" or "geyser" or "elevator" or "portal" or "other")
            || !root.TryGetProperty("points", out var points)
            || points.ValueKind != JsonValueKind.Array
            || points.GetArrayLength() < 2)
        {
            throw new InvalidDataException("Saved link candidate failed schema validation.");
        }

        var kind = actionKind.GetString();
        if (kind != "walk"
            && (!TryBoundedText(root, "actionName", 96, requireValue: true)
                || !TryBoundedText(root, "actionNote", 160, requireValue: true)))
        {
            throw new InvalidDataException(
                "A manual route action requires a mechanism name and forward instruction.");
        }
        if (!TryBoundedText(root, "reverseActionNote", 160, requireValue: false))
        {
            throw new InvalidDataException("Reverse route-action instruction is too long.");
        }

        var index = 0;
        foreach (var point in points.EnumerateArray())
        {
            var expectedRole = index == 0
                ? "start"
                : index == points.GetArrayLength() - 1
                    ? "end"
                    : "checkpoint";
            if (!point.TryGetProperty("role", out var role)
                || role.GetString() != expectedRole
                || !TryFiniteCoordinate(point, "x")
                || !TryFiniteCoordinate(point, "y")
                || !TryFiniteCoordinate(point, "z"))
            {
                throw new InvalidDataException("Saved link candidate contains an invalid ordered point.");
            }
            index++;
        }
    }

    private static bool TryFiniteCoordinate(JsonElement point, string propertyName) =>
        point.TryGetProperty(propertyName, out var property)
        && property.TryGetDouble(out var value)
        && double.IsFinite(value)
        && Math.Abs(value) <= 100000;

    private static bool TryBoundedText(
        JsonElement root,
        string propertyName,
        int maximumLength,
        bool requireValue)
    {
        if (!root.TryGetProperty(propertyName, out var property)
            || property.ValueKind != JsonValueKind.String)
        {
            return !requireValue;
        }
        var value = property.GetString() ?? string.Empty;
        return value.Length <= maximumLength
            && (!requireValue || !string.IsNullOrWhiteSpace(value));
    }

    private static void AtomicWrite(string path, string contents)
    {
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        try
        {
            File.WriteAllText(temporaryPath, contents, Utf8NoBom);
            File.Move(temporaryPath, path, true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }

    private static string LuaNumber(double value) =>
        value.ToString("0.################", CultureInfo.InvariantCulture);

    private static void ValidateCoordinate(double value, string name)
    {
        if (!double.IsFinite(value) || Math.Abs(value) > 100000)
        {
            throw new ArgumentException($"{name} must be a finite coordinate between -100000 and 100000.");
        }
    }

    private static void ExpectArgumentError(Action action)
    {
        try
        {
            action();
        }
        catch (ArgumentException)
        {
            return;
        }
        throw new InvalidOperationException("Expected input validation to reject the self-test value.");
    }

    private static void ExpectInvalidData(Action action)
    {
        try
        {
            action();
        }
        catch (InvalidDataException)
        {
            return;
        }
        throw new InvalidOperationException("Expected schema validation to reject the self-test value.");
    }
}

public sealed record WaypointPublishResult(string RequestId, DateTime ExpiresAtUtc);
