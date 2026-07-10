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

local function JsonString(value)
    value = tostring(value or "")
    value = value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. value .. '"'
end

local function WriteManifest(filename, entries)
    local file = io.open(filename, "w")
    if not file then error("Could not write manifest: " .. filename) end
    file:write("{\n  \"files\": [\n")
    for i, entry in ipairs(entries) do
        file:write("    " .. entry .. (i < #entries and "," or "") .. "\n")
    end
    file:write("  ]\n}\n")
    file:close()
end

local function IsLocked(layer)
    local ok, editable = pcall(function() return layer.isEditable end)
    return ok and editable == false
end

local function FrameTagName(sprite, frame_index)
    for _, tag in ipairs(sprite.tags) do
        if frame_index >= tag.fromFrame.frameNumber and frame_index <= tag.toFrame.frameNumber then
            return tag.name
        end
    end
    return ""
end

local function WalkLayers(root_layer, parent_visible, parent_locked, callback)
    for _, layer in ipairs(root_layer.layers) do
        local visible = parent_visible and layer.isVisible
        local locked = parent_locked or IsLocked(layer)
        if layer.isGroup then
            WalkLayers(layer, visible, locked, callback)
        else
            callback(layer, visible, locked)
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

local function TagOptions(sprite)
    local options = {"All tags/frames"}
    for _, tag in ipairs(sprite.tags) do
        options[#options + 1] = tag.name
    end
    return options
end

local function SelectedTag(sprite, name)
    if name == "All tags/frames" then return nil end
    for _, tag in ipairs(sprite.tags) do
        if tag.name == name then return tag end
    end
    return nil
end

local function FrameRange(sprite, tag)
    if tag then return tag.fromFrame.frameNumber, tag.toFrame.frameNumber end
    return 1, #sprite.frames
end

local function KeepFrameRange(sprite, first_frame, last_frame)
    for i = #sprite.frames, last_frame + 1, -1 do
        sprite:deleteFrame(sprite.frames[i])
    end
    for i = first_frame - 1, 1, -1 do
        sprite:deleteFrame(sprite.frames[i])
    end
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
dlg:combobox{
    id = "tag",
    label = "Tag:",
    option = "All tags/frames",
    options = TagOptions(sourceSprite)
}
dlg:slider{id = "frameDigits", label = "Frame digits:", min = 1, max = 6, value = 4}
dlg:slider{id = "scale", label = "Export Scale:", min = 1, max = 10, value = 1}
dlg:check{id = "includeHidden", label = "Include hidden layers:", selected = false}
dlg:check{id = "includeLocked", label = "Include locked layers/groups:", selected = true}
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
local manifest_entries = {}
local exported = 0
local workSprite = nil

local ok, err = pcall(function()
    workSprite = Sprite(sourceSprite)
    workSprite:resize(workSprite.width * dlg.data.scale, workSprite.height * dlg.data.scale)

    local selected_tag = SelectedTag(workSprite, dlg.data.tag)
    local first_frame, last_frame = FrameRange(workSprite, selected_tag)
    local manifest_first_frame = first_frame
    local manifest_last_frame = last_frame
    if selected_tag and dlg.data.mode ~= "Frame sequence" then
        KeepFrameRange(workSprite, first_frame, last_frame)
        first_frame, last_frame = 1, #workSprite.frames
    end

    local targets = {}
    if dlg.data.scope == "Whole sprite" then
        targets[1] = {sprite=workSprite, layername="animation", locked=false}
    else
        WalkLayers(workSprite, true, false, function(layer, visible, locked)
            if (dlg.data.includeHidden or visible) and (dlg.data.includeLocked or not locked) and (dlg.data.exportEmpty or LayerHasCels(layer)) then
                targets[#targets + 1] = {layer=layer, layername=SafeFilename(layer.name), locked=locked}
            end
        end)
    end

    for _, target in ipairs(targets) do
        if target.layer then
            HideImageLayers(workSprite)
            target.layer.isVisible = true
        end

        if dlg.data.mode == "Frame sequence" then
            for frame_index = first_frame, last_frame do
                local tag_name = FrameTagName(workSprite, frame_index)
                local name = BuildFilename(dlg.data.filename, format, {
                    spritename=spritename,
                    layername=target.layername,
                    frame=Pad(frame_index, dlg.data.frameDigits)
                })
                local filename = UniqueFilename(app.fs.joinPath(output_path, name), used_filenames)
                SaveOneFrame(workSprite, frame_index, filename)
                manifest_entries[#manifest_entries + 1] = string.format(
                    '{"file":%s,"layer":%s,"frame":%d,"duration":%s,"tag":%s,"locked":%s}',
                    JsonString(filename), JsonString(target.layername), frame_index, tostring(workSprite.frames[frame_index].duration), JsonString(tag_name), tostring(target.locked)
                )
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
            manifest_entries[#manifest_entries + 1] = string.format(
                '{"file":%s,"layer":%s,"firstFrame":%d,"lastFrame":%d,"tag":%s,"locked":%s,"mode":%s}',
                JsonString(filename), JsonString(target.layername), manifest_first_frame, manifest_last_frame, JsonString(selected_tag and selected_tag.name or ""), tostring(target.locked), JsonString(dlg.data.mode)
            )
            exported = exported + 1
        end
    end
    WriteManifest(UniqueFilename(app.fs.joinPath(output_path, "manifest.json"), {}), manifest_entries)
end)

if workSprite then workSprite:close() end
if not ok then
    MsgDialog("Error", tostring(err)):show()
    return 1
end

MsgDialog("Success!", "Exported " .. exported .. " animation file(s)."):show()
return 0
