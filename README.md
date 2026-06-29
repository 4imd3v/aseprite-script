# Aseprite Export Layers Script

`export_layers.lua` exports each layer in the active Aseprite sprite as its own file. It supports nested layer groups, custom filename patterns, custom export extensions, optional trimming, optional spritesheet export, duplicate filename protection, and hidden/empty layer controls.

## Requirements

- Aseprite with scripting support.
- Tested by the user on Aseprite `v1.3.17.2`.
- One open sprite before running the script.

## Install

1. Open Aseprite.
2. Go to `File > Scripts > Open Scripts Folder`.
3. Copy `export_layers.lua` into that folder.
4. Go to `File > Scripts > Rescan Scripts Folder`.
5. Run it from `File > Scripts > export_layers`.

On Windows the scripts folder is usually similar to:

```text
C:\Users\USER\AppData\Roaming\Aseprite\scripts
```

## Basic Use

1. Open a sprite in Aseprite.
2. Run `File > Scripts > export_layers`.
3. Choose an output directory.
4. Choose the filename pattern and export format.
5. Press `Export`.

The script exports from a temporary duplicate of your sprite. It hides/resizes/selects layers only in that duplicate, then closes it. Your original open sprite is not modified by the export process unless `Save sprite` is checked.

## Dialog Options

### Output directory

Where exported files will be written.

The file picker starts from the active sprite filename. Pick a file/location in the target folder; the script uses its directory as the export folder.

### File name format

Controls the exported filename before the extension.

Default:

```text
{layergroups}{layername}
```

Supported tokens:

- `{layername}`: current layer name.
- `{layergroups}`: parent group names, if the layer is inside groups.
- `{spritename}`: active sprite filename without extension. Unsaved sprites use `sprite`.
- `{groupseparator}`: selected group separator.

Examples:

```text
{layername}
{spritename}_{layername}
{layergroups}{layername}
{spritename}_{layergroups}{layername}
```

Layer, group, and sprite names are sanitized for filenames. Unsafe characters like `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, and `|` are replaced with `_`.

### Export Format

The output file extension.

Examples:

```text
png
svg
gif
jpg
webp
bmp
tga
aseprite
```

The script strips a leading dot and lowercases the value, so `.PNG` becomes `png`.

Aseprite is still the final authority on whether a format can be saved. If Aseprite cannot save that extension, export will fail.

### Group separator

Used when `{layergroups}` or `{groupseparator}` is in the filename format.

Available choices:

- Your platform path separator: `/` on Linux/macOS, `\` on Windows.
- `-`
- `_`

Using the platform separator can create subfolders for group names. Using `-` or `_` keeps all files in one folder.

### Export Scale

Scales the temporary duplicate before exporting.

Example:

- `1`: original size.
- `2`: double size.
- `3`: triple size.

The original open sprite is not resized.

### Export as spritesheet

Exports each layer as a spritesheet instead of a normal single image.

When enabled, the script shows spritesheet-specific options:

- `Trim Sprite`
- `Trim Cells`
- `Trim Grid`
- `Split Tags`
- `Merge duplicates`

Spritesheet export is limited to image formats:

```text
png, jpg, jpeg, gif, webp, bmp, tga
```

SVG is blocked for spritesheets because spritesheets need raster/image output.

### Trim

Only shown when `Export as spritesheet` is off.

When enabled, the script finds the smallest rectangle containing non-transparent pixels in the layer and exports only that area.

How empty detection works:

- The script checks every cel in the layer.
- `image:isEmpty()` checks whether all pixels are transparent.
- `image:shrinkBounds()` finds the non-transparent bounds.
- One non-transparent pixel makes the layer non-empty.

For indexed sprites, this depends on Aseprite's transparent color/index rules.

### Export empty layers

Default: on.

When on, visible layers are exported even if Aseprite detects them as empty.

When off, layers with no non-transparent pixels are skipped.

This defaults on because some pixel-art/indexed workflows can make Aseprite's empty-layer detection surprising.

### Include hidden layers

Default: off.

When off, only originally visible layers are exported. Layers inside hidden groups are skipped too.

When on, hidden layers are also exported.

### Save sprite

Default: off.

When on, the original active sprite is saved after export using its current filename.

The export itself still happens from a temporary duplicate.

## Duplicate Filenames

If two layers would export to the same filename, or if a file already exists, the script adds a number:

```text
Arrow.svg
Arrow_2.svg
Arrow_3.svg
```

This avoids accidental overwrites.

## Notes

- The script exports regular layers, recursively including layers inside groups.
- It does not export group layers themselves as images; it exports child layers.
- The export count is the number of files the script attempted to export successfully.
- Security prompts from Aseprite are normal when a script writes files. Grant access if the output path is correct.

