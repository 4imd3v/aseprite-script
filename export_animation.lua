--[[
Description:
Export Aseprite animations as one file, per-layer files, frame sequences, or spritesheets.
--]]

local sourceSprite = app.activeSprite
if not sourceSprite then
    app.alert("No active sprite.")
    return 1
end

local function MsgDialog(title, text)
    local dlg = Dialog(title)
    dlg:label{text = text}
    dlg:button{text = "OK"}
    return dlg
end

local function SafeFilename(name, fallback)
    name = tostring(name):gsub('[<>:"/\\|?*%c]', "_"):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or fallback or "animation"
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

local function IsAnimatedFormat(format)
    return format == "gif" or format == "webp" or format == "aseprite" or format == "ase"
end

local function IsSpritesheetFormat(format)
    return format == "png" or format == "jpg" or format == "jpeg" or
           format == "gif" or format == "webp" or format == "bmp" or
           format == "tga"
end

local function Pad(value, width)
    return string.format("%0" .. width .. "d", value)
end

local function WalkLayers(root_layer, parent_visible, callback)
    for _, layer in ipairs(root_layer.layers) do
        local visible = parent_visible and layer.isVisible
        if layer.isGroup then
            WalkLayers(layer, visible, callback)
        else
            callback(layer, visible)
        end
    end
end

local function HideImageLayers(root_layer)
    for _, layer in ipairs(root_layer.layers) do
        if layer.isGroup then
            layer.isVisible = true
            HideImageLayers(layer)
        else
            layer.isVisible = false
        end
    end
end

local function LayerHasCels(layer)
    return #layer.cels > 0
end

local function BuildFilename(pattern, format, tokens)
    local filename = pattern:gsub("{spritename}", tokens.spritename)
    filename = filename:gsub("{layername}", tokens.layername or "")
    filename = filename:gsub("{frame}", tokens.frame or "")
    return filename .. "." .. format
end

local function SaveSpriteCopy(sprite, filename)
    app.fs.makeAllDirectories(app.fs.filePath(filename))
    app.activeSprite = sprite
    app.command.SaveFile{
        ui=false,
        filename=filename
    }
end

local function SaveOneFrame(sprite, frame_index, filename)
    local frameSprite = Sprite(sprite)
    for i = #frameSprite.frames, 1, -1 do
        if i ~= frame_index then frameSprite:deleteFrame(frameSprite.frames[i]) end
    end
    SaveSpriteCopy(frameSprite, filename)
    frameSprite:close()
end

local function ExportSpritesheet(sprite, filename, sheettype, split_tags)
    app.fs.makeAllDirectories(app.fs.filePath(filename))
    app.activeSprite = sprite
    app.command.ExportSpriteSheet{
        ui=false,
        askOverwrite=false,
        type=sheettype,
        textureFilename=filename,
        dataFilename="",
        dataFormat=SpriteSheetDataFormat.JSON_HASH,
        splitLayers=false,
        splitTags=split_tags,
        listLayers=true,
        listTags=true,
        listSlices=true,
    }
end

local dlg = Dialog("Export animation")
dlg:file{
    id = "directory",
    label = "Output directory:",
    filename = sourceSprite.filename,
    open = false
}
dlg:entry{
    id = "filename",
    label = "File name format:",
    text = "{spritename}_{layername}_{frame}"
}
dlg:entry{
    id = "format",
    label = "Export Format:",
    text = "png"
}
dlg:combobox{
    id = "scope",
    label = "Scope:",
    option = "Whole sprite",
    options = {"Whole sprite", "Each layer"}
}
dlg:combobox{
    id = "mode",
    label = "Output:",
    option = "Frame sequence",
    options = {"Frame sequence", "Animated file", "Spritesheet"}
}
dlg:combobox{
    id = "sheettype",
    label = "Sheet layout:",
    option = "Horizontal",
    options = {"Horizontal", "Rows", "Columns"}
}
dlg:slider{id = "frameDigits", label = "Frame digits:", min = 1, max = 6, value = 4}
dlg:slider{id = "scale", label = "Export Scale:", min = 1, max = 10, value = 1}
dlg:check{id = "includeHidden", label = "Include hidden layers:", selected = false}
dlg:check{id = "exportEmpty", label = "Export empty layers:", selected = true}
dlg:check{id = "splitTags", label = "Split tags in spritesheet:", selected = false}
dlg:button{id = "ok", text = "Export"}
dlg:button{id = "cancel", text = "Cancel"}
dlg:show()

if not dlg.data.ok then return 0 end

local output_path = app.fs.filePath(dlg.data.directory)
local format = dlg.data.format:gsub("^%s*%.?", ""):gsub("%s*$", ""):lower()
if output_path == nil or output_path == "" then
    MsgDialog("Error", "No output directory was specified."):show()
    return 1
end
if format == "" then
    MsgDialog("Error", "No export format was specified."):show()
    return 1
end
if dlg.data.mode == "Animated file" and not IsAnimatedFormat(format) then
    MsgDialog("Error", "Animated file export needs gif, webp, aseprite, or ase."):show()
    return 1
end
if dlg.data.mode == "Spritesheet" and not IsSpritesheetFormat(format) then
    MsgDialog("Error", "Spritesheet export needs png, jpg, gif, webp, bmp, or tga."):show()
    return 1
end

local sheettype = SpriteSheetType.HORIZONTAL
if dlg.data.sheettype == "Rows" then
    sheettype = SpriteSheetType.ROWS
elseif dlg.data.sheettype == "Columns" then
    sheettype = SpriteSheetType.COLUMNS
end

local spritename = SafeFilename(app.fs.fileTitle(app.fs.fileName(sourceSprite.filename)), "sprite")
local used_filenames = {}
local exported = 0
local workSprite = nil

local ok, err = pcall(function()
    workSprite = Sprite(sourceSprite)
    workSprite:resize(workSprite.width * dlg.data.scale, workSprite.height * dlg.data.scale)

    local targets = {}
    if dlg.data.scope == "Whole sprite" then
        targets[1] = {sprite=workSprite, layername="animation"}
    else
        WalkLayers(workSprite, true, function(layer, visible)
            if (dlg.data.includeHidden or visible) and (dlg.data.exportEmpty or LayerHasCels(layer)) then
                targets[#targets + 1] = {layer=layer, layername=SafeFilename(layer.name)}
            end
        end)
    end

    for _, target in ipairs(targets) do
        if target.layer then
            HideImageLayers(workSprite)
            target.layer.isVisible = true
        end

        if dlg.data.mode == "Frame sequence" then
            for frame_index = 1, #workSprite.frames do
                local name = BuildFilename(dlg.data.filename, format, {
                    spritename=spritename,
                    layername=target.layername,
                    frame=Pad(frame_index, dlg.data.frameDigits)
                })
                local filename = UniqueFilename(app.fs.joinPath(output_path, name), used_filenames)
                SaveOneFrame(workSprite, frame_index, filename)
                exported = exported + 1
            end
        else
            local name = BuildFilename(dlg.data.filename, format, {
                spritename=spritename,
                layername=target.layername,
                frame=""
            })
            local filename = UniqueFilename(app.fs.joinPath(output_path, name), used_filenames)
            if dlg.data.mode == "Animated file" then
                SaveSpriteCopy(workSprite, filename)
            else
                ExportSpritesheet(workSprite, filename, sheettype, dlg.data.splitTags)
            end
            exported = exported + 1
        end
    end
end)

if workSprite then workSprite:close() end
if not ok then
    MsgDialog("Error", tostring(err)):show()
    return 1
end

MsgDialog("Success!", "Exported " .. exported .. " animation file(s)."):show()
return 0
