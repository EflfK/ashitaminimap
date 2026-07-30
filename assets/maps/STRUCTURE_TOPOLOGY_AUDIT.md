# Structure topology audit

Native and inferred selectors are compared for every navmesh-authored structure layer. `exact` rows also reproduce and hash-check the committed PNG. Kuftal rows are selector-only because their final page clipping is recorded separately from the topology selector.

| Layer | Status | Production check | Selected polygons |
| --- | --- | --- | ---: |
| `174_01_main_structure.png` | ok | selector-only | 3084 |
| `174_01_lower_structure.png` | ok | selector-only | 175 |
| `174_02_main_structure.png` | ok | selector-only | 667 |
| `174_02_upper_structure.png` | ok | selector-only | 1479 |
| `174_02_lower_structure.png` | ok | selector-only | 1113 |
| `174_15_main_structure.png` | ok | selector-only | 396 |
| `174_15_upper_structure.png` | ok | selector-only | 31 |
| `174_15_lower_structure.png` | ok | selector-only | 165 |
| `174_16_main_structure.png` | ok | selector-only | 477 |
| `174_16_upper_structure.png` | ok | selector-only | 56 |
| `174_16_left_lower_structure.png` | ok | selector-only | 332 |
| `174_16_right_lower_structure.png` | ok | selector-only | 268 |
| `200_01_structure.png` | ok | exact | 1054 |
| `200_16_structure.png` | ok | exact | 929 |
| `241_structure.png` | ok | exact | 751 |
| `243_structure.png` | ok | exact | 188 |
| `243_stairs_structure.png` | ok | exact | 2 |
| `243_upper_structure.png` | ok | exact | 76 |
| `244_structure.png` | ok | exact | 364 |
| `244_stables_structure.png` | ok | exact | 32 |
| `245_structure.png` | ok | exact | 278 |
| `246_structure.png` | ok | exact | 317 |

Metalworks `237_structure.png` is a legacy linework prototype, not a navmesh-generated production structure. It remains an explicit production-rebuild item and is not certified by this audit.

Kuftal's `174_01_transition_structure.png` is a clipped visual transition treatment derived from verified route evidence rather than a seeded navmesh component.
