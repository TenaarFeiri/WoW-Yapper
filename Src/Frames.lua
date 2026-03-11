--[[
    Frames.lua
    Lightweight frame factory and container.
]]

local YapperName, YapperTable = ...

local Frame = {
    defined = true, -- Marker to prevent nil indexing when the module fails to load.
} -- Container for methods.
local EventFrames    = {}
local Container = {}
Container.Events = {}
Container.UI = {} -- For non-event frames (settings, etc.)
YapperTable.Frame = Frame
YapperTable.EventFrames           = EventFrames
YapperTable.EventFrames.Container = Container.Events -- Expose event frames externally, but not the factory itself.

--- Create the main hidden event-listening frame.
function EventFrames:Init()
    if not YapperTable.Events then
        YapperTable.Error:Throw("MISSING_EVENTS")
        return
    end
    local id = YapperTable.Config.System.FRAME_ID_PARENT
    Container.Events[id] = CreateFrame("Frame", YapperName .. "EventFrame", UIParent)
end

--- Hide the main event frame (used during override/disable).
function EventFrames:HideParent()
    local f = Container.Events[YapperTable.Config.System.FRAME_ID_PARENT]
    if f then f:Hide() end
end

--[[
    TODO: Create frame factory.
    Must be able to:
    - Create frames of various types (Button, EditBox, etc.)
    - Set common properties (size, position, scripts)
    - Store references for later use (locally, to be called from Frames via methods)
    - Expose API for the rest of the addon.
]]

--- Factory method for creating a frame of any type and storing it in the container.
--- `name` is the key for storing the frame in Container.UI, and also forms the global name of the frame (prefixed with the addon name).  `parent` and `template` are passed directly to CreateFrame.
--- Example usage: `Frames:Create("SettingsPanel", UIParent, "BackdropTemplate")` creates a frame named "YapperSettingsPanel" and stores it in `Frames.Container.UI.SettingsPanel`.
--- Optionally specify a key for a subtable to store the frame in.
function Frame:CreateBasicFrame(name, parent, template, ...)
    local subtable = ...
    if subtable then
        Container.UI[subtable] = Container.UI[subtable] or {}
        Container.UI[subtable][name] = CreateFrame("Frame", name, parent, template)
        return Container.UI[subtable][name]
    else
        local frame = CreateFrame("Frame", name, parent, template)
        Container.UI[name] = frame
        return frame
    end
end

--- Create a default interface frame with default properties,
--- a centred title at the top, a close button at the bottom centre,
--- and a content area filling the rest of the space.
function Frame:CreateInterfaceFrame(name, parent)
    local frame = self:CreateBasicFrame(name, parent, "BackdropTemplate")
    if not frame then return end
    frame:SetSize(400, 300)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
end

--- Factory method for creating a Button widget and storing it in the container.
--- Pass the parent frame's name as the subtable argument to group the button under that frame's entry in Container.UI.
--- Example: `Frame:CreateButton("CloseBtn", frame, nil, "SettingsPanel")` stores the button at `Container.UI.SettingsPanel.CloseBtn`,
--- retrievable via `Frame:Get("CloseBtn", "SettingsPanel")`.
function Frame:CreateButton(name, parent, template, ...)
    local subtable = ...
    if subtable then
        Container.UI[subtable] = Container.UI[subtable] or {}
        Container.UI[subtable][name] = CreateFrame("Button", name, parent, template)
        return Container.UI[subtable][name]
    else
        local button = CreateFrame("Button", name, parent, template)
        Container.UI[name] = button
        return button
    end
end

function Frame:SetButtonProperties(button, text, width, height, texture, onClick)
    if not button then return end
    button:SetSize(width or 100, height or 30)
    button:SetNormalFontObject("GameFontNormal")
    button:SetHighlightFontObject("GameFontHighlight")
    button:SetText(text or "Button")
    if texture then
        button:SetNormalTexture(texture)
    end
    if onClick then
        button:SetScript("OnClick", onClick)
    end
end

--- Create a simple grid layout helper attached to a parent frame.
--- The returned object exposes methods `Add(frame)` and `Reset()`.
---
--- Usage:
---   local grid = Frames:MakeGrid(myFrame, 100, 30, 5)
---   grid:Add(Frames:CreateButton("Btn1", myFrame))
---   grid:Add(Frames:CreateButton("Btn2", myFrame))
---
--- The grid will position elements left‑to‑right, wrap when it reaches
--- the right edge of `parent`, and automatically grow `parent` vertically
--- if elements extend past its current height. Cell dimensions are used
--- as defaults when the element reports a zero size.
function Frame:MakeGrid(parent, cellW, cellH, padding)
    local max = math.max
    local grid = {
        parent = parent,
        cellW = cellW or parent:GetWidth(),
        cellH = cellH or parent:GetHeight(),
        padding = padding or 0,
        cursorX = 0,
        cursorY = 0,
        rowHeight = 0,
        items = {},
    }

    function grid:Reset()
        self.cursorX = 0
        self.cursorY = 0
        self.rowHeight = 0
        for _, item in ipairs(self.items) do
            item:ClearAllPoints()
        end
    end

    function grid:Add(elem)
        table.insert(self.items, elem)
        elem:ClearAllPoints()
        elem:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.cursorX, -self.cursorY)

        local w, h = elem:GetSize()
        if w == 0 then w = self.cellW end
        if h == 0 then h = self.cellH end

        self.cursorX = self.cursorX + w + self.padding
        self.rowHeight = max(self.rowHeight, h)

        if self.cursorX + w > self.parent:GetWidth() then
            self.cursorX = 0
            self.cursorY = self.cursorY + self.rowHeight + self.padding
            self.rowHeight = 0
        end

        local neededHeight = self.cursorY + h + self.padding
        if neededHeight > self.parent:GetHeight() then
            self.parent:SetHeight(neededHeight)
        end
    end

    return grid
end

--- Get the UI frame from the container.
--- Optionally specify a key category it is stored in, if you saved it under a subtable (e.g. `Frame.Container.UI` vs `Frame.Container.Events`).
function Frame:Get(name, ...)
    local subtable = ...
    if subtable then
        return Container.UI[subtable] and Container.UI[subtable][name]
    else
        return Container.UI[name]
    end
end
