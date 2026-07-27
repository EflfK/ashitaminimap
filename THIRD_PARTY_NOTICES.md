# Third-party map geometry

The Windurst Woods walkable-area layer is generated from:

- LandSandBoat `xiNavmeshOBJs`, `Windurst_Woods.obj`, source commit
  `694970ce54a4fb53b69db52b8375c605686bc350`, licensed GPL-3.0.
- LandSandBoat `xiNavmeshes`, `Windurst_Woods.nav`, source commit
  `d5de48de84868bde744e4864768a611e5aad82b0`, used to select traversable
  polygons from the collision coordinate space, licensed GPL-2.0.

The upstream repositories are:

- <https://github.com/LandSandBoat/xiNavmeshOBJs>
- <https://github.com/LandSandBoat/xiNavmeshes>

The generated PNG is a modified visualization: it projects the source geometry
into AshitaMinimap's calibrated coordinate space, selects connected walkable
components from verified seeds, removes only sub-threshold obstacle holes, and
applies the dark-tactical palette. It is not an upstream LandSandBoat asset.
