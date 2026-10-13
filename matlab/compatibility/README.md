# MATLAB compatibility shims

Two small adapters let the unmodified third-party toolboxes run on current MATLAB (developed with
R2025a). Neither changes what is computed. The toolbox installations themselves are not edited;
the engine puts these folders first on the path while it runs.

| Folder | Replaces | Why |
|---|---|---|
| `amt_rms/rms.m` | MATLAB's `rms` while AMT runs | AMT 1.6 `barumerli2023_featureextraction` calls `rms(x, 'dim', n)` (the LTFAT signature), which MATLAB's built-in `rms` rejects. The adapter accepts that form and LTFAT's `'ac'`/`'noac'` flags and returns `sqrt(mean(abs(x).^2, dim))`. Added by `activate_barumerli_compatibility` and removed again when the run ends. |
| `sfs_findvoronoi/findvoronoi.m` | SFS Toolbox 2.5.0 `findvoronoi` (bundled with SUpDEq, used by its natural-neighbour interpolation) | Upstream loops over `1:size(idx)`, which recent MATLAB rejects for a non-scalar size. The copy uses `1:size(idx, 1)` in the two loops; otherwise it is the upstream file (MIT licence, header retained), apart from trailing whitespace. `configure_toolbox_paths` checks that this copy is the one selected. |

`configure_toolbox_paths` also removes the older `rms.m` copies bundled with SFS (`sfs_octave`) and
LTFAT (`sigproc`) from the path, for the same reason as the first shim.
