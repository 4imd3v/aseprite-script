--[[

Description:
A script to save all different layers in different files.

Made by Gaspi.
   - Itch.io: https://gaspi.itch.io/
   - Twitter: @_Gaspi
Further Contributors:
    - Levy E ("StoneLabs")
    - David Höchtl ("DavidHoechtl")
    - Demonkiller8973
--]]

local sourceSprite = app.activeSprite
if not sourceSprite then
    app.alert("No active sprite.")
    return 1
end

local Sep = app.fs.pathSeparator

local function MsgDialog(title, text)
    local dlg = Dialog(title)
    dlg:label{text = text}
    dlg:button{text = "OK"}
    return dlg
end

local function Dirname(filename)
    return app.fs.filePath(filename)
end

local function Basename(filename)
    return app.fs.fileName(filename)
end

local function RemoveExtension(filename)
    return app.fs.fileTitle(filename)
end

local function SafeFilename(name, fallback)
    name = tostring(name):gsub('[<>:"/\\|?*%c]', "_"):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or fallback or "layer"
end

local function UniqueFilename(filename, used_filenames)
    local title = app.fs.filePathAndTitle(filename)
    local ext = app.fs.fileExtension(filename)
    local unique = filename
    local i = 2
    while used_filenames[unique] or app.fs.isFile(unique) do
        unique = title .. "_" .. i .. "." .. ext
        i = i + 1
    end
    used_filenames[unique] = true
    return unique
end

local function IsSpritesheetFormat(format)
    return format == "png" or format == "jpg" or format == "jpeg" or
           format == "gif" or format == "webp" or format == "bmp" or
           format == "tga"
end

local function HideLayers(root_layer, data)
    data = data or {}
    for _, layer in ipairs(root_layer.layers) do
        data[layer.id] = layer.isVisible
        layer.isVisible = false
        if layer.isGroup then HideLayers(layer, data) end
    end
    return data
end

-- Variable to keep track of the number of layers exported.
local n_layers = 0


-- Function to calculate the bounding box of the non-transparent pixels in a layer
local function calculateBoundingBox(layer)
    local minX, minY, maxX, maxY = nil, nil, nil, nil
    for _, cel in ipairs(layer.cels) do
        local image = cel.image
        local position = cel.position
        if not image:isEmpty() then
            local bounds = image:shrinkBounds()
            local x1 = position.x + bounds.x
            local y1 = position.y + bounds.y
            local x2 = x1 + bounds.width - 1
            local y2 = y1 + bounds.height - 1
            if not minX or x1 < minX then minX = x1 end
            if not minY or y1 < minY then minY = y1 end
            if not maxX or x2 > maxX then maxX = x2 end
            if not maxY or y2 > maxY then maxY = y2 end
        end
    end
    if not minX then return nil end
    return Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1)
end

-- Exports every layer individually.
local function exportLayers(sprite, root_layer, filename, group_sep, data, state, parent_visible)
    for _, layer in ipairs(root_layer.layers) do
        local filename = filename
        local originally_visible = parent_visible and state.visibility[layer.id]
        if layer.isGroup then
            -- Recursive for groups.
            local previousVisibility = layer.isVisible
            layer.isVisible = true
            filename = filename:gsub("{layergroups}", function()
                return SafeFilename(layer.name) .. group_sep .. "{layergroups}"
            end)
            exportLayers(sprite, layer, filename, group_sep, data, state, originally_visible)
            layer.isVisible = previousVisibility
        else
            local bounds = calculateBoundingBox(layer)
            local should_export = (data.includeHidden or originally_visible) and
                                  (data.exportEmpty or bounds)

            if should_export then
                -- Individual layer. Export it.
                layer.isVisible = true
                filename = filename:gsub("{layergroups}", "")
                filename = filename:gsub("{layername}", function()
                    return SafeFilename(layer.name)
                end)
                filename = UniqueFilename(filename, state.used_filenames)
                app.fs.makeAllDirectories(Dirname(filename))
                local exported = true
                if data.spritesheet then
                    local sheettype=SpriteSheetType.HORIZONTAL
                    if (data.tagsplit == "To Rows") then
                        sheettype=SpriteSheetType.ROWS
                    elseif (data.tagsplit == "To Columns") then
                        sheettype=SpriteSheetType.COLUMNS
                    end
                    app.command.ExportSpriteSheet{
                        ui=false,
                        askOverwrite=false,
                        type=sheettype,
                        columns=0,
                        rows=0,
                        width=0,
                        height=0,
                        bestFit=false,
                        textureFilename=filename,
                        dataFilename="",
                        dataFormat=SpriteSheetDataFormat.JSON_HASH,
                        borderPadding=0,
                        shapePadding=0,
                        innerPadding=0,
                        trimSprite=data.trimSprite,
                        trim=data.trimCells,
                        trimByGrid=data.trimByGrid,
                        mergeDuplicates=data.mergeDuplicates,
                        extrude=false,
                        openGenerated=false,
                        layer="",
                        tag="",
                        splitLayers=false,
                        splitTags=(data.tagsplit ~= "No"),
                        listLayers=layer,
                        listTags=true,
                        listSlices=true,
                    }
                elseif data.trim then -- Trim the layer
                    if bounds then
                        -- make a selection on the active layer
                        app.activeLayer = layer;
                        sprite.selection = Selection(bounds);

                        -- create a new sprite from that selection
                        app.command.NewSpriteFromSelection()

                        -- save it using the selected export format
                        app.command.SaveFile {
                            ui=false,
                            filename=filename
                        }
                        app.command.CloseFile()

                        app.activeSprite = layer.sprite  -- Set the active sprite to the current layer's sprite
                        sprite.selection = Selection();
                    else
                        sprite:saveCopyAs(filename)
                    end
                else
                    sprite:saveCopyAs(filename)
                end
                layer.isVisible = false
                if exported then n_layers = n_layers + 1 end
            end
        end
    end
end

-- Open main dialog.
local dlg = Dialog("Export layers")
dlg:file{
    id = "directory",
    label = "Output directory:",
    filename = sourceSprite.filename,
    open = false
}
dlg:entry{
    id = "filename",
    label = "File name format:",
    text = "{layergroups}{layername}"
}
dlg:entry{
    id = 'format',
    label = 'Export Format:',
    text = 'png'
}
dlg:combobox{
    id = 'group_sep',
    label = 'Group separator:',
    option = Sep,
    options = {Sep, '-', '_'}
}
dlg:slider{id = 'scale', label = 'Export Scale:', min = 1, max = 10, value = 1}
dlg:check{
    id = "spritesheet",
    label = "Export as spritesheet:",
    selected = false,
    onclick = function()
        -- Hide these options when spritesheet is checked.
        dlg:modify{
            id = "trim",
            visible = not dlg.data.spritesheet
        }
        -- Show these options when spritesheet is checked.
        dlg:modify{
            id = "trimSprite",
            visible = dlg.data.spritesheet
        }
        dlg:modify{
            id = "trimCells",
            visible = dlg.data.spritesheet
        }
        dlg:modify{
            id = "mergeDuplicates",
            visible = dlg.data.spritesheet
        }
        dlg:modify{
            id = "tagsplit",
            visible = dlg.data.spritesheet
        }
    end
}
dlg:check{
    id = "trim",
    label = "Trim:",
    selected = false
}
dlg:check{
    id = "exportEmpty",
    label = "Export empty layers:",
    selected = true
}
dlg:check{
    id = "includeHidden",
    label = "Include hidden layers:",
    selected = false
}
dlg:check{
    id = "trimSprite",
    label = "  Trim Sprite:",
    selected = false,
    visible = false,
    onclick = function()
        dlg:modify{
            id = "trimByGrid",
            visible = dlg.data.trimSprite or dlg.data.trimCells,
        }
    end
}
dlg:check{
    id = "trimCells",
    label = "  Trim Cells:",
    selected = false,
    visible = false,
    onclick = function()
        dlg:modify{
            id = "trimByGrid",
            visible = dlg.data.trimSprite or dlg.data.trimCells,
        }
    end
}
dlg:check{
    id = "trimByGrid",
    label = "  Trim Grid:",
    selected = false,
    visible = false
}
dlg:combobox{ -- Spritesheet export only option
    id = "tagsplit",
    label = "  Split Tags:",
    visible = false,
    option = 'No',
    options = {'No', 'To Rows', 'To Columns'}
}
dlg:check{ -- Spritesheet export only option
    id = "mergeDuplicates",
    label = "  Merge duplicates:",
    selected = false,
    visible = false
}
dlg:check{id = "save", label = "Save sprite:", selected = false}
dlg:button{id = "ok", text = "Export"}
dlg:button{id = "cancel", text = "Cancel"}
dlg:show()

if not dlg.data.ok then return 0 end

-- Get path and filename
local output_path = Dirname(dlg.data.directory)
local format = dlg.data.format:gsub("^%s*%.?", ""):gsub("%s*$", ""):lower()
local filename = dlg.data.filename .. "." .. format

if output_path == nil or output_path == "" then
    local dlg = MsgDialog("Error", "No output directory was specified.")
    dlg:show()
    return 1
end
if format == "" then
    local dlg = MsgDialog("Error", "No export format was specified.")
    dlg:show()
    return 1
end

local group_sep = dlg.data.group_sep
filename = filename:gsub("{spritename}", function()
    return SafeFilename(RemoveExtension(Basename(sourceSprite.filename)), "sprite")
end)
filename = filename:gsub("{groupseparator}", group_sep)

if dlg.data.spritesheet and not IsSpritesheetFormat(format) then
    local dlg = MsgDialog("Error", "Spritesheet export needs an image format like png, jpg, gif, webp, bmp, or tga.")
    dlg:show()
    return 1
end

-- Finally, perform everything.
local workSprite = nil
local layers_visibility_data = nil
local ok, err = pcall(function()
    workSprite = Sprite(sourceSprite)
    layers_visibility_data = HideLayers(workSprite)
    workSprite:resize(workSprite.width * dlg.data.scale, workSprite.height * dlg.data.scale)
    exportLayers(workSprite, workSprite, app.fs.joinPath(output_path, filename), group_sep, dlg.data, {
        visibility = layers_visibility_data,
        used_filenames = {}
    }, true)
end)
if workSprite then
    workSprite:close()
end
if not ok then
    local dlg = MsgDialog("Error", tostring(err))
    dlg:show()
    return 1
end

-- Save the original file if specified
if dlg.data.save then sourceSprite:saveAs(dlg.data.directory) end

-- Success dialog.
local dlg = MsgDialog("Success!", "Exported " .. n_layers .. " layers.")
dlg:show()

return 0
