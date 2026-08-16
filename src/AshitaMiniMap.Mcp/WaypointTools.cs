using System.ComponentModel;
using System.Text.Json;
using ModelContextProtocol.Server;

namespace AshitaMiniMap.Mcp;

[McpServerToolType]
public static class WaypointTools
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
    };

    [McpServerTool]
    [Description("Sets one temporary, display-only AshitaMiniMap waypoint using exact FFXI world coordinates. It uses the same marker and route state as a player right-click and overrides AshitaGuide routing until cleared. No game command, input, target change, packet, or movement is sent.")]
    public static string set_minimap_waypoint(
        [Description("Exact FFXI zone id from 0 through 999.")] int zoneId,
        [Description("Exact FFXI world X coordinate.")] double x,
        [Description("Exact FFXI world Y coordinate.")] double y,
        [Description("Optional live map/floor id from 0 through 255. Required for a remote destination; recommended in multi-page zones.")] int? mapId = null,
        [Description("Optional exact world Z coordinate. Omit it to let AshitaMiniMap resolve an unambiguous floor from its authored graph.")] double? z = null)
    {
        try
        {
            var result = WaypointStorage.PublishSet(zoneId, x, y, mapId, z);
            return JsonSerializer.Serialize(new
            {
                ok = true,
                result.RequestId,
                result.ExpiresAtUtc,
                state = "pending",
                next = "Use minimap_waypoint_status to confirm whether AshitaMiniMap accepted a route or marker-only waypoint.",
                safety = "Display-only request published. No game command, input, target change, packet, or movement was sent.",
            }, JsonOptions);
        }
        catch (ArgumentException ex)
        {
            return JsonSerializer.Serialize(new { ok = false, error = ex.Message }, JsonOptions);
        }
        catch (Exception ex)
        {
            return JsonSerializer.Serialize(new
            {
                ok = false,
                error = $"Minimap waypoint could not be published: {ex.Message}",
            }, JsonOptions);
        }
    }

    [McpServerTool]
    [Description("Clears the temporary AshitaMiniMap waypoint and restores AshitaGuide routing. No game command, input, target change, packet, or movement is sent.")]
    public static string clear_minimap_waypoint()
    {
        try
        {
            var result = WaypointStorage.PublishClear();
            return JsonSerializer.Serialize(new
            {
                ok = true,
                result.RequestId,
                result.ExpiresAtUtc,
                state = "pending_clear",
                safety = "Display-only clear request published. No game command, input, target change, packet, or movement was sent.",
            }, JsonOptions);
        }
        catch (Exception ex)
        {
            return JsonSerializer.Serialize(new
            {
                ok = false,
                error = $"Minimap waypoint clear could not be published: {ex.Message}",
            }, JsonOptions);
        }
    }

    [McpServerTool]
    [Description("Reports AshitaMiniMap's acknowledgment of the latest MCP waypoint request, including whether the waypoint is active, routed, marker-only, cleared, expired, or rejected.")]
    public static string minimap_waypoint_status()
    {
        try
        {
            return WaypointStorage.ReadStatus();
        }
        catch (Exception ex)
        {
            return JsonSerializer.Serialize(new { ok = false, error = ex.Message }, JsonOptions);
        }
    }

    [McpServerTool]
    [Description("Returns the latest attended connection candidate saved from AshitaMiniMap Developer mode, including ordered live X/Y/Z points, graph nodes and components, direction, connection type, mechanism name, and forward/reverse action instructions. It does not modify the production graph.")]
    public static string minimap_link_candidate_status()
    {
        try
        {
            return WaypointStorage.ReadLinkCandidate();
        }
        catch (Exception ex)
        {
            return JsonSerializer.Serialize(new { ok = false, error = ex.Message }, JsonOptions);
        }
    }

    [McpServerTool]
    [Description("Deletes the currently saved attended connection candidate after its exact candidate id has been processed. It does not modify the production graph or game state.")]
    public static string clear_minimap_link_candidate(
        [Description("Exact candidateId returned by minimap_link_candidate_status.")] string candidateId)
    {
        try
        {
            var cleared = WaypointStorage.ClearLinkCandidate(candidateId);
            return JsonSerializer.Serialize(new
            {
                ok = true,
                cleared,
                candidateId,
                safety = "Saved evidence file only; production graph and game state were not changed.",
            }, JsonOptions);
        }
        catch (ArgumentException ex)
        {
            return JsonSerializer.Serialize(new { ok = false, error = ex.Message }, JsonOptions);
        }
        catch (Exception ex)
        {
            return JsonSerializer.Serialize(new
            {
                ok = false,
                error = $"Saved link candidate could not be cleared: {ex.Message}",
            }, JsonOptions);
        }
    }
}
