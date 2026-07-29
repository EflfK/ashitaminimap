# Home Point and Survival Guide references

AshitaMinimap treats Home Points and Survival Guides as display-only,
map-owned reference data. Guides do not supply these records, and the addon
does not interact with an NPC or automate travel.

The addon does read AshitaCore's existing read-only travel-registration masks
to distinguish registered destinations from ones the current player can still
obtain. An unregistered Home Point or Survival Guide pulses with a translucent,
enlarged copy of its normal icon. A registered destination remains static. If
the masks are unavailable, the addon does not guess and renders the ordinary
static icon.

## Pinned source

The authoritative source for the current dataset is CatsEyeXI
`sql/npc_list.sql` at commit
`314deaf03465f2b24b6a1e4e73a016ca036f1084`.

For each non-vanilla map, include only uncommented NPC records whose internal
name is `HomePoint#N` or `Survival_Guide`, whose status is active (`0`), and
whose entity flag is nonzero. Placeholder rows at `(0, 0, 0)`, disabled rows,
and `-- NC:` rows are excluded. A map with no matching record must still
declare `travel_references = travel_reference_set({})` to show that it was
audited.

The SQL tuple stores `(pos_x, vertical, pos_z)`. AshitaMinimap stores the same
position as:

```text
x = pos_x
y = pos_z
z = vertical
```

Multi-page maps must assign `page_id` from the authored page rules and measure
the point against that page's navigation graph. Keep a truthful marker visible
even when the verified NPC stands beyond the graph's snap radius; do not extend
or connect navigation geometry without traversal evidence. Elevation-aware
structure maps use `z` to dim references that belong to another authored floor.

## Audited coverage

| Zone | Map | Home Points | Survival Guides |
| ---: | --- | ---: | ---: |
| 107 | South Gustaberg | 0 | 0 |
| 174 | Kuftal Tunnel | 0 | 1 |
| 200 | Garlaige Citadel | 0 | 1 |
| 236 | Port Bastok | 2 | 0 |
| 237 | Metalworks | 1 | 0 |
| 241 | Windurst Woods | 5 | 0 |
| 243 | Ru'Lude Gardens | 2 | 1 |
| 244 | Upper Jeuno | 3 | 0 |
| 245 | Lower Jeuno | 2 | 0 |
| 246 | Port Jeuno | 2 | 0 |

Davoi is included when its authored map is installed and contributes one
Survival Guide reference from the same pinned source.

## Symbols and validation

- `kind = 'home_point'` renders a cyan faceted crystal.
- `kind = 'survival_guide'` renders an open brown-and-parchment book.
- Home Point records declare the retail `unlock_index`; Survival Guide records
  declare the bit within the Survival Guide mask as `unlock_bit`.
- An unset registration bit adds a pulsing glow in the icon's own color.
- Every record requires a stable display name and finite `x`, `y`, and `z`.
- The layer is controlled by **Home Points and Survival Guides** in the
  configuration window.
- Re-audit the pinned SQL source whenever a map is completed or the source
  commit changes.
