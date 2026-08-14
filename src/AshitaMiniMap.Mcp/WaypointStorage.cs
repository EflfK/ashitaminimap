using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AshitaMiniMap.Mcp;

public static class WaypointStorage
{
    private const string RequestFileName = "mcp_waypoint_request.lua";
    private const string StatusFileName = "mcp_waypoint_status.json";
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
}

public sealed record WaypointPublishResult(string RequestId, DateTime ExpiresAtUtc);
