-- By and for Weird Vibes of Turtle WoW

-- local _G = _G or getfenv()

local has_vanillautils = pcall(UnitXP, "nop", "nop") and true or false
local has_superwow = SetAutoloot and true or false

local updates_per_sec = 60

-- Cache global functions and constants for efficiency

-- Math library caching
local math               = math
local cos                = math.cos
local sin                = math.sin
local sqrt               = math.sqrt
local atan2              = math.atan2
local mod                = math.mod
local pi                 = math.pi
local abs                = math.abs
local tan                = math.tan
local floor              = math.floor

-- WoW API functions frequently used in loops or OnUpdate handlers
local UnitXP             = UnitXP
local GetTime            = GetTime
local GetScreenWidth     = GetScreenWidth
local GetScreenHeight    = GetScreenHeight
local UnitName           = UnitName
local SpellInfo          = SpellInfo
local GetActionText      = GetActionText
local IsActionInRange    = IsActionInRange
local UnitExists         = UnitExists
local UnitIsVisible      = UnitIsVisible
local UnitIsDead         = UnitIsDead
local UnitCanAssist      = UnitCanAssist
local UnitClassification = UnitClassification
local UnitIsPlayer       = UnitIsPlayer
local UnitCanAttack      = UnitCanAttack
local UnitRace           = UnitRace

-- Table and string library functions
local pairs              = pairs
local ipairs             = ipairs
local getn               = getn            -- For WoW 1.12, using getn is common

local settings

if not (has_vanillautils and has_superwow) then
  StaticPopupDialogs["NO_SWOW_VU"] = {
    text = "|cff77ff00Combat Range Finder|r requires the SuperWoW and VanillaUtils dlls to operate.",
    button1 = TEXT(OKAY),
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = 1,
  }

  StaticPopup_Show("NO_SWOW_VU")
  return
end

local function crf_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- Create the main frame that covers the entire screen
local crfFrame = CreateFrame("Frame", "crfFrame", UIParent)
crfFrame:SetAllPoints(UIParent)  -- Covers the entire screen

function RotateTexture(texture, angle)
  -- Calculate sine and cosine of the angle
  local cosTheta = cos(angle)
  local sinTheta = sin(angle)

  -- SetTexCoord parameters for rotation
  texture:SetTexCoord(
    0.5 - cosTheta * 0.5 + sinTheta * 0.5, 0.5 - sinTheta * 0.5 - cosTheta * 0.5, -- Top-left
    0.5 + cosTheta * 0.5 + sinTheta * 0.5, 0.5 + sinTheta * 0.5 - cosTheta * 0.5, -- Top-right
    0.5 - cosTheta * 0.5 - sinTheta * 0.5, 0.5 - sinTheta * 0.5 + cosTheta * 0.5, -- Bottom-left
    0.5 + cosTheta * 0.5 - sinTheta * 0.5, 0.5 + sinTheta * 0.5 + cosTheta * 0.5  -- Bottom-right
  )
end

local textures = {
  in_range = "Interface\\Addons\\CombatRangeFinder\\line2",
  out_range = "Interface\\Addons\\CombatRangeFinder\\line",
}

function ScaleTexture(texture, scaleX, scaleY)
  -- Adjust scaling to make higher values increase size
  scaleX = 1 / scaleX
  scaleY = 1 / scaleY

  -- Calculate offsets based on scale
  local offsetX = (1 - scaleX) / 2
  local offsetY = (1 - scaleY) / 2

  -- SetTexCoord parameters for scaling
  texture:SetTexCoord(
      0 + offsetX, 0 + offsetY, -- Top-left
      1 - offsetX, 0 + offsetY, -- Top-right
      0 + offsetX, 1 - offsetY, -- Bottom-left
      1 - offsetX, 1 - offsetY  -- Bottom-right
  )
end

function TransformTexture(texture, angle, scaleX, scaleY)
  -- Precompute sine and cosine of the angle
  local cosTheta = cos(angle)
  local sinTheta = sin(angle)

  -- scaleX = 1 / scaleX
  -- scaleY = 1 / scaleY

  -- Define the four original UV corners (centered around 0.5, 0.5)
  local corners = {
      {x = -0.5 * scaleX, y =  0.5 * scaleY}, -- Top-left
      {x =  0.5 * scaleX, y =  0.5 * scaleY}, -- Top-right
      {x = -0.5 * scaleX, y = -0.5 * scaleY}, -- Bottom-left
      {x =  0.5 * scaleX, y = -0.5 * scaleY}, -- Bottom-right
  }

  -- Rotate each corner around the center (0.5, 0.5)
  for i, corner in ipairs(corners) do
      local x = corner.x
      local y = corner.y
      corner.u = 0.5 + (x * cosTheta - y * sinTheta) -- Rotated u
      corner.v = 0.5 + (x * sinTheta + y * cosTheta) -- Rotated v
  end

  -- Apply the transformed UV coordinates
  texture:SetTexCoord(
      corners[1].u, corners[1].v, -- Top-left
      corners[2].u, corners[2].v, -- Top-right
      corners[3].u, corners[3].v, -- Bottom-left
      corners[4].u, corners[4].v  -- Bottom-right
  )
end

local UnitPosition = function (unit)
  return UnitXP("unitPosition",unit)
end

local CameraPosition = function ()
  return UnitXP("cameraPosition")
end

local UnitFacing = function (unit)
  return UnitXP("unitFacing",unit)
end

function calculateDistance(x1,y1,z1,x2,y2,z2)
  if (type(x1) == "table") and (type(y1) == "table") then
    return sqrt((x1.x - y1.x)^2 + (x1.y - y1.y)^2 + (x1.z - y1.z)^2)
  else
    return sqrt((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2)
  end
end

-- not neccesarily player first, just easy convention
function IsUnitFacingUnit(playerX, playerY, playerFacing, targetX, targetY, maxAngle)
  -- 1. Calculate the angle to the target
  local angleToTarget = atan2(targetY - playerY, targetX - playerX)

  -- 2. Normalize both angles to 0..2*pi
  if angleToTarget < 0 then
    angleToTarget = angleToTarget + 2 * pi
  end

  -- 3. Calculate the angular difference and normalize it to [-pi, pi]
  local angularDifference = mod(angleToTarget - playerFacing, 2 * pi)
  if angularDifference > pi then
    angularDifference = angularDifference - 2 * pi
  elseif angularDifference < -pi then
    angularDifference = angularDifference + 2 * pi
  end

  -- 4. Check if the player is facing the target within the maxAngle range
  return (abs(angularDifference) <= maxAngle),angularDifference
end

local function round_to(z,x)
  return floor(x * z) / z
end

-- Create a pool for managing dots
local DotPool = {}

-- TODO reusing a dot should reset some of the values
-- Create a method to get a dot from the pool (or create a new one if none available)
function DotPool:GetDot()
  for i = 1, getn(self) do
    if not self[i].inUse then
      self[i].inUse = true
      self[i]:Show()
      return self[i]
    end
  end

  -- If no available dot, create a new one
  local dot = CreateFrame("Frame", nil, UIParent)
  dot:SetFrameStrata("BACKGROUND")
  dot:SetFrameLevel(0)  -- or 1, if 0 is not allowed in your context
  dot:SetWidth(100)
  dot:SetHeight(100)

  dot.inUse = true
  dot.x = 0
  dot.y = 0
  dot.z = 0
  dot.width = 32
  dot.height = 32
  dot.screenX = 0
  dot.screenY = 0

  -- accept positions or a table of positions
  dot.SetPosition = function (self,x,y,z)
    if type(x) == "table" then
      self.x = x.x or self.x
      self.y = x.y or self.y
      self.z = x.z or self.z
    else
      self.x = x or self.x
      self.y = y or self.y
      self.z = z or self.z
    end
  end

  local dotIcon = dot:CreateTexture(nil, "ARTWORK")
  dotIcon:SetWidth(dot.width)
  dotIcon:SetHeight(dot.height)
  dotIcon:SetPoint("CENTER", dot, "CENTER")
  dotIcon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

  -- local dotRing = dot:CreateTexture(nil, "ARTWORK")
  -- dotRing.width = 512
  -- dotRing.height = 512
  -- dotRing:SetWidth(dotRing.width)
  -- dotRing:SetHeight(dotRing.height)
  -- dotRing:SetPoint("CENTER", dot, "CENTER")
  -- dotRing:SetTexture("Interface\\AddOns\\Rings\\thin.tga")
  -- -- dotRing:SetScale(1) -- ignore uiscale

  local dotText = dot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  -- dotRing:SetWidth(512)
  -- dotRing:SetHeight(512)
  dotText:SetPoint("BOTTOM", dotIcon, "TOP", 0, 0) -- Position it above the texture
  dotText:SetText("Dot") -- You can change this dynamically later
  dotText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

  dot.text = dotText
  dot.text.font,dot.text.size,dot.text.flags = dotText:GetFont()
  dot.icon = dotIcon
  -- dot.ring = dotRing
  -- store dot world facing and pitch?
  -- dot.yaw

  -- local no-scale = 0.9
  -- dot.SetRadius = function (self,rad,eff)
  --   -- dot.text.size = rad
  --   -- dotText:SetFont(dot.text.font,dot.text.size,dot.text.flags)
  --   -- dot.ring.width = (rad) / (10 * dot:GetEffectiveScale()) * 512 * (fovScale * 0.9)
  --   -- dot.ring.height = (rad) / (10 * dot:GetEffectiveScale()) * 512 * (fovScale * 0.9)
  --   local base = 256
  --   -- local diff = 1 - dot:GetEffectiveScale()
  --   local s = 0.9 - UIParent:GetScale()
  --   -- print(s)
  --   local r = rad / (10) * base / (1 + s*2)
  --   self.ring.width  = 2 * r
  --   self.ring.height = 2 * r
  -- end
  -- dot:SetRadius(10)

  dot.SetFontSize = function (self,size)
    self.text.size = size
    self.text:SetFont(dot.text.font,dot.text.size,dot.text.flags)
  end

  dot:Show()

  -- Add to the pool
  table.insert(self, dot)
  return dot
end

-- Create a method to return a dot back to the pool (hide it and mark as unused)
function DotPool:ReturnDot(dot)
  dot:Hide()
  dot.inUse = false
end


-- Instants to use to check for in-melee range
local instants = {
  ["Backstab"] = 1,
  ["Sinister Strike"] = 1,
  ["Kick"] = 1,
  ["Expose Armor"] = 1,
  ["Eviscerate"] = 1,
  ["Rupture"] = 1,
  ["Kidney Shot"] = 1,
  ["Garrote"] = 1,
  ["Ambush"] = 1,
  ["Cheap Shot"] = 1,
  ["Gouge"] = 1,
  ["Feint"] = 1,
  ["Ghosly Strike"] = 1,
  ["Hemorrhage"] = 1,
  -- ["Riposte"] = 1, -- maybe

  ["Hamstring"] = 1,
  ["Sunder Armor"] = 1,
  ["Bloodthirst"] = 1,
  ["Mortal Strike"] = 1,
  ["Shield Slam"] = 1,
  ["Overpower"] = 1,
  ["Revenge"] = 1,
  ["Pummel"] = 1,
  ["Shield Bash"] = 1,
  ["Disarm"] = 1,
  ["Execute"] = 1,
  ["Taunt"] = 1,
  ["Mocking Blow"] = 1,
  ["Slam"] = 1,
  -- ["Decisive Strike"] = 1, -- gone
  ["Rend"] = 1,

  ["Crusader Strike"] = 1,
  ["Holy Strike"] = 1,

  ["Storm Strike"] = 1,

  ["Savage Bite"] = 1,
  ["Growl"] = 1,
  ["Bash"] = 1,
  ["Swipe"] = 1,
  ["Claw"] = 1,
  ["Rip"] = 1,
  ["Ferocious Bite"] = 1,
  ["Shred"] = 1,
  ["Rake"] = 1,
  ["Cower"] = 1,
  ["Ravage"] = 1,
  ["Pounce"] = 1,

  ["Wing Clip"] = 1,
  ["Disengage"] = 1,
  ["Carve"] = 1, -- twow
  ["Counterattack"] = 1, -- hunter, also war on twow
}

-- store one of your instant actions to check for melee range
local range_check_slot = nil
local function Check_Actions(slot)
  if slot then
    local name,actionType,identifier = GetActionText(slot);

    if actionType and identifier and actionType == "SPELL" then
      local name,rank,texture = SpellInfo(identifier)
      if instants[name] then
        range_check_slot = i
        return -- done
      end
    end
  end

  for i=1,120 do
    local name,actionType,identifier = GetActionText(i);
    -- if ActionHasRange(i) then
    --   print(SpellInfo(identifier))
    -- end

    if actionType and identifier and actionType == "SPELL" then
      local name,rank,texture = SpellInfo(identifier)
      if instants[name] then
        range_check_slot = i
        -- print(range_check_slot)
        -- print(name)
        return
      end
    end
  end
  -- no hits?
  range_check_slot = nil
end

crfFrame:SetScript("OnEvent", function ()
  -- Handle shutdown to prevent SuperWoW API crashes during logout
  if event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
    crf_isShuttingDown = true
    this:UnregisterAllEvents()
    this:SetScript("OnUpdate", nil)
    this:SetScript("OnEvent", nil)
    -- Hide all dots
    for i = 1, getn(DotPool) do
      if DotPool[i] then
        DotPool[i]:Hide()
      end
    end
    return
  end
  crfFrame[event](this,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg0)
end)

-- Shutdown flag to prevent SuperWoW API calls during logout (crash prevention)
local crf_isShuttingDown = false

crfFrame:RegisterEvent("ADDON_LOADED")
crfFrame:RegisterEvent("PLAYER_LOGOUT")
crfFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

local function GetRestofMessage(args)
  if args[2] then
    local name = args[2]
    for i = 3, table.getn(args) do
      name = name .. " " .. args[i]
    end
    return name
  end
end

local commands = {
  { name = "enable",      default = true,  desc = "Enable or disable addon" },
  { name = "arrow",       default = true,  desc = "Show indicator arrow for (attackable) target" },
  { name = "any",         default = false, desc = "When arrow is enabled, show for non-attackable targets too" },
  { name = "markers",     default = true,  desc = "Show raid markers at enemy feet" },
  { name = "markerssize", default = 48,    desc = "Size of markers (default 48)" },
  { name = "largearrow",  default = true,  desc = "Use a larger arrow for enemies who are in range" },
}

local function OffOn(on)
  return on and "|cff00ff00On|r" or "|cffff0000Off|r"
end

--Display commands
local function ShowCommands()
  crf_print("|cff77ff00Combat Range Finder:|r")
  for _,data in ipairs(commands) do
    if type(data.default) == "boolean" then
      crf_print(data.name .. " - " .. OffOn(settings[data.name]) .. " - " .. data.desc)
    else
      crf_print(data.name .. " - |cff00cccc" .. settings[data.name] .. "|r - " .. data.desc)
    end
  end
end

function MakeSlash()
  SlashCmdList["CRFCOMMAND"] = function(msg)
    local args = {}
    for word in string.gfind(msg, "[^%s]+") do
      table.insert(args, word)
    end
    local cmd = string.lower(args[1] or "")
    local num = tonumber(args[2])
    
    for _,data in ipairs(commands) do
      if cmd == data.name then
        if type(data.default) == "boolean" then
          settings[data.name] = not settings[data.name]
          crf_print("|cff77ff00CRF:|r " .. data.name .. " - " .. OffOn(settings[data.name]))
        elseif num then
          settings[data.name] = num
          crf_print("|cff77ff00CRF:|r " .. data.name .. " - |cff00cccc" .. num .. "|r")
        end
        return
      end
    end
    ShowCommands()
  end
  SLASH_CRFCOMMAND1 = "/crf"
end

function crfFrame:ADDON_LOADED(addon)
  if addon ~= "CombatRangeFinder" then return end

  CRFDB = CRFDB or {}
  CRFDB.settings = CRFDB.settings or {}
  settings = CRFDB.settings
  for _,data in ipairs(commands) do
    if settings[data.name] == nil then
      settings[data.name] = data.default
    end
  end
  CRFDB.units = CRFDB.units or {}

  MakeSlash()
  crf_print("|cff77ff00Combat Range Finder|r loaded: |cffffff00/crf|r")

  -- RingsDB = RingsDB or {}
  -- RingsDB.heal_mark_waypoints = heal_mark_waypoints
  -- RingsDB.heal_mark_waypoints = RingsDB.heal_mark_waypoints or {}

  -- self:PlaceHealWaypoints()
  -- stopPoints,totalDistance = crfFrame:initializeStopPointsAndDistance(RingsDB.heal_mark_waypoints)

  -- self:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLY_DEATH")
  -- self:RegisterEvent("UNIT_CASTEVENT")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("UNIT_MODEL_CHANGED")
  self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

  playerdot1 = DotPool:GetDot()
  -- playerdot1.ring:Hide()
  playerdot1.text:Hide()
  playerdot1.icon:Hide()
  playerdot1:Hide()
  -- playerdot1.icon:SetTexture("Interface/Minimap/MinimapArrow")

  targetdot1 = DotPool:GetDot()
  -- targetdot1.ring:Hide()
  targetdot1.text:Hide()
  targetdot1.icon:Hide()
  targetdot1.icon:SetTexture("Interface/Minimap/MinimapArrow")
  
  -- targetmarkerdot1 = DotPool:GetDot()
  -- targetmarkerdot1.text:Hide()

  targetdot1:Hide()

  self:CreateRaidMarkers()

  -- if rings_debug then MakeHealMarkers() end
end

-- local died_at = { x = 0.00000001, y = 0.00000001, z = 0.00000001 }

local deds = {}
function crfFrame:CheckDeaths()
  for i=1,GetNumRaidMembers() do
    local unit = "raid"..i
    if UnitCanAssist("player",unit) and UnitIsDead(unit) and UnitIsConnected(unit) and not deds[unit] then
      local dot = DotPool:GetDot()
      DeathDot(dot,unit)
      deds[unit] = dot
    elseif not UnitIsDead(unit) and deds[unit] then
      DotPool:ReturnDot(deds[unit])
      deds[unit] = nil
    end
  end
end

-- Set texture coordinates for a specific raid marker
-- MarkerIndex is the position in the 4x4 grid, starting from 1 for the top-left icon
function SetRaidMarkerTexture(texture, markerIndex)
  texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  local rows, cols = 4, 4  -- 4x4 grid
  local row = floor((markerIndex - 1) / cols)
  local col = mod(markerIndex - 1, cols)
  local left = col / cols
  local right = (col + 1) / cols
  local top = row / rows
  local bottom = (row + 1) / rows
  texture:SetTexCoord(left, right, top, bottom)
end

function CreateRaidMarker(markerIndex)
  local marker = DotPool:GetDot()
  SetRaidMarkerTexture(marker.icon, markerIndex)
  marker.icon.original_width = 48
  marker.icon.original_height = 48
  marker.icon:SetWidth(marker.icon.original_width)
  marker.icon:SetHeight(marker.icon.original_height)
  marker.text:SetText("")
  -- marker:SetFrameStrata(marker:GetFrameStrata() - 1)
  return marker
end

function GetUnitData(unit)
  local _,guid = UnitExists(unit)
  local type = UnitIsPlayer(unit) and "player" or UnitClassification(unit)
  return { guid = guid, name = UnitName(unit), type = type }
end

function crfFrame:UpdateRaidMarkers()
  if not self.raidMarkers then return end

  local mark_table = { "mark1", "mark2", "mark3", "mark4", "mark5", "mark6", "mark7", "mark8" }
  local px, py, pz = UnitPosition("player") -- Player position

  -- Scaling configuration
  local maxDistance = 40 -- Distance at which markers are smallest
  local minDistance = 5  -- Distance at which markers are full size
  local minScale = 0.5   -- Minimum scale (50% of original size)
  for mark, marker in ipairs(self.raidMarkers) do
    local _,unit = UnitExists(mark_table[mark])
    if unit and settings.markers and UnitIsVisible(unit) and not UnitIsDead(unit) then
      local tx, ty, tz = UnitPosition(unit) -- Target position
      marker:SetPosition(tx, ty, tz)
      marker.icon.original_width = settings.markerssize
      marker.icon.original_height = settings.markerssize

      local distance = calculateDistance(px, py, pz, tx, ty, tz)

      -- Smooth scaling: normalize distance to a scale factor
      local scale = 1
      if distance > minDistance then
        scale = 1 - ((distance - minDistance) / (maxDistance - minDistance)) * (1 - minScale)
        scale = max(minScale, scale) -- Clamp to minScale
      end

      -- Apply the scaled size
      marker.icon:SetWidth(marker.icon.original_width * scale)
      marker.icon:SetHeight(marker.icon.original_height * scale)

      if distance > 40 then
        marker.icon:Hide()
      else
        marker.icon:Show()
      end
    else
      marker.icon:Hide()
    end
  end
end

function crfFrame:CreateRaidMarkers()
  self.raidMarkers = {}
  for i=1,8 do
    self.raidMarkers[i] = CreateRaidMarker(i)
  end
end

function crfFrame:UpdateBossMarkers()
  if not self.bossMarkers then return end

  local px, py, pz = UnitPosition("player") -- Player position

  -- Scaling configuration
  local maxDistance = 40 -- Distance at which markers are smallest
  local minDistance = 5  -- Distance at which markers are full size
  local minScale = 0.5   -- Minimum scale (50% of original size)

  for guid, marker in ipairs(self.bossMarkers) do
    -- local unit = "mark"..mark
    if UnitExists(guid) and UnitIsVisible(guid) then
      if not UnitIsDead(guid) then
        local tx, ty, tz = UnitPosition(unit) -- Target position
        marker:SetPosition(tx, ty, tz)

        local distance = calculateDistance(px, py, pz, tx, ty, tz)

        -- Smooth scaling: normalize distance to a scale factor
        local scale = 1
        if distance > minDistance then
          scale = 1 - ((distance - minDistance) / (maxDistance - minDistance)) * (1 - minScale)
          scale = max(minScale, scale) -- Clamp to minScale
        end

        -- Apply the scaled size
        marker.icon:SetWidth(marker.icon.original_width * scale)
        marker.icon:SetHeight(marker.icon.original_height * scale)

        if distance > 40 then
          marker.icon:Hide()
        else
          marker.icon:Show()
        end
      else
        marker.icon:Hide()
      end
    else
      self.bossMarkers[guid] = nil
      marker.icon:Hide()
      ReturnDot(marker)
    end
  end
end

function crfFrame:CreateBossMarker(guid,r,g,b,a)
  self.bossMarkers = self.bossMarkers or {}

  local marker = DotPool:GetDot()
  marker.icon:SetTexture("Interface\\Addons\\CombatRangeFinder\\arrow1.tga")
  marker.icon.original_width = 64
  marker.icon.original_height = 64
  marker.icon:SetWidth(marker.icon.original_width)
  marker.icon:SetHeight(marker.icon.original_height)
  marker.icons:SetVertexColor(r,g,b,a)
  marker.text:SetText("")

  self.bossMarkers[guid] = marker
end

function crfFrame:ACTIONBAR_SLOT_CHANGED(slot)
  Check_Actions(slot)
end

local function IsInRange(distance)
  local melee_range = (UnitRace("player") == "Tauren") and 6.5 or 5
  local can_attack = UnitCanAttack("player", "target")

  if range_check_slot and can_attack then
      return IsActionInRange(range_check_slot) == 1
  end

  return distance <= melee_range
end

function crfFrame:PLAYER_ENTERING_WORLD()
  Check_Actions()

  -- clean seen-units
  for k,entry in pairs(CRFDB.units) do
    if not UnitExists(entry.guid) then
      CRFDB.units[k] = nil
    end
  end
end

function crfFrame:UNIT_MODEL_CHANGED(guid)
  if not CRFDB.units[guid] then CRFDB.units[guid] = GetUnitData(guid) end
end

function ScaleFOV(fov)
  -- Define the known FOV and corresponding scaled values
  local fov_values = {0.2, 1, 1.57, 2, 3, 3.14}
  local scaled_values = {0.14, 0.69, 1.135, 1.3125, 1.82, 1.885}

  -- Handle the case where FOV is below the smallest known value or above the largest known value
  if fov <= fov_values[1] then
      return scaled_values[1]
  elseif fov >= fov_values[table.getn(fov_values)] then
      return scaled_values[table.getn(scaled_values)]
  end

  -- Perform piecewise linear interpolation
  for i = 1, table.getn(fov_values) - 1 do
      local fov1, fov2 = fov_values[i], fov_values[i + 1]
      local scale1, scale2 = scaled_values[i], scaled_values[i + 1]

      if fov >= fov1 and fov <= fov2 then
          -- Calculate the slope (m) and intercept (b) for the linear interpolation
          local m = (scale2 - scale1) / (fov2 - fov1)
          local b = scale1 - m * fov1

          -- Return the interpolated value
          return m * fov + b
      end
  end
end

local c_fov = UnitXP("cameraFoV")
FOV = ScaleFOV(c_fov)
fovScale = tan(FOV / 2)
-- fovScale = tan(ScaleFOV(2) / 2)
-- print(format("%.2f _ %.2f _ %.2f _ %.2f _ %.2f",ScaleFOV(0.2),ScaleFOV(1),ScaleFOV(2),ScaleFOV(3),ScaleFOV(3.14)))

-- Projection parameters
local screenWidth = GetScreenWidth()
local screenHeight = GetScreenHeight()
local uiScale = UIParent:GetEffectiveScale()
local aspectRatio = screenWidth / screenHeight

-- Field of view scale factor for projection

function PosToScreen(x,y,z)

  return screenX,screenY
end

crfFrame.camera_data = { sinPitch = 0, cosPitch = 0, yaw = 0, sinYaw = 0, cosYaw = 0, x = 0, y = 0, z = 0 }

function crfFrame:GetScaleBasedOnDistance(distance,limit)
  if distance >= (limit or 150) then
      return 0
  elseif distance <= 0 then
      return 1
  end
  return 1 - (distance / (limit or 150))
end

-- set, and store
local function SetElementScale(ele,scale,w,h)
  ele.width = ele.width or ele:GetWidth()
  ele.height = ele.height or ele:GetHeight()
  w = w or ele.width
  h = h or ele.height
  ele:SetWidth(max(1,scale * w))
  ele:SetHeight(max(1,scale * h))
end

local function SetTextScale(text,scale,size)
  local f_path,f_size,f_flags = text:GetFont()
  local path,flags = text.path or f_path, text.flags or f_flags
  size = size or text.size
  text:SetFont(path,max(1,scale*size),flags)
end

local function calculateYaw(x1, y1, x2, y2)
  local deltaX = x2 - x1
  local deltaY = y2 - y1
  return atan2(deltaY, deltaX)
end

function crfFrame:UpdateCamera()
  local camera = self.camera_data
  
  local px, py = UnitPosition("player") --or UnitPosition("player")
  local dy,dx = camera.y - py,camera.x - px
  camera.x, camera.y, camera.z = CameraPosition()
  if not camera.x then
    camera.x = 0
    camera.y = 0
    camera.z = 0
  end

  -- Only update yaw if it's actually changed. Accounts for some odd motion glitches
  local deltaThreshold = 0.04

  camera.yaw = -atan2(camera.y - py, camera.x - px)

  camera.sinYaw = sin(camera.yaw)
  camera.cosYaw = cos(camera.yaw)

  camera.sinPitch = -UnitXP("cameraPitch")
  camera.cosPitch = sqrt(1 - camera.sinPitch^2)
end

function crfFrame:ShowArrow()
  return settings.arrow
    and UnitExists("target")
    and UnitIsVisible("target")
    and (settings.any or UnitCanAttack("player","target"))
    and not UnitIsDead("target")
end

local function NormalizeAngle(angle)
  if angle < 0 then
    return angle + 2 * pi
  end
  return angle
end

local function GetAngleBetweenPoints(x1, y1, x2, y2)
  local angle = atan2(x2 - x1, y2 - y1)
  return NormalizeAngle(angle), angle
end

local function IsUnitFacingUnit(playerX, playerY, playerFacing, targetX, targetY, maxAngle)
  local angleToTarget = atan2(targetY - playerY, targetX - playerX)
  if angleToTarget < 0 then
    angleToTarget = angleToTarget + 2 * pi
  end

  local angularDifference = mod(angleToTarget - playerFacing, 2 * pi)
  if angularDifference > pi then
    angularDifference = angularDifference - 2 * pi
  elseif angularDifference < -pi then
    angularDifference = angularDifference + 2 * pi
  end

  return (abs(angularDifference) <= maxAngle), angularDifference
end

-- Precompute constant values outside the OnUpdate handler
local CONSTANT_FACING_LIMIT = 61 * (pi / 180)  -- constant facing limit in radians

local distance_change = 0
local boss_markers = {}
local elapsed_total = 0
local was_disabled = false

-- Cached color state variables
local lastColorState, lastAlpha = nil, nil
function crfFrame_OnUpdate()
  -- Prevent SuperWoW API calls during shutdown (crash prevention)
  if crf_isShuttingDown then return end

  elapsed_total = elapsed_total + arg1
  if elapsed_total < 1 / updates_per_sec then return end -- 60 updates/s cap
  elapsed_total = 0

  local dotCount = getn(DotPool)
  local settings = settings

  if not settings.enable then
    if not was_disabled then
      for i = 1, dotCount do
        local dot = DotPool[i]
        if dot.inUse then
          dot:Hide()
        end
      end
      playerdot1.icon:Hide()
      was_disabled = true
    end
    return
  elseif settings.enable then
    if was_disabled then
      for i = 1, dotCount do
        local dot = DotPool[i]
        if dot.inUse then
          dot:Show()
        end
      end
      playerdot1.icon:Show()
      was_disabled = false
    end
  end

  local crf = this
  local camera = crf.camera_data
  crf:UpdateCamera()

  local px,py,pz = UnitPosition("player")
  playerdot1:SetPosition(px,py,pz)
  
  local tx,ty,tz
  if UnitExists("target") and UnitIsVisible("target") then
    tx,ty,tz = UnitPosition("target")
    targetdot1:SetPosition(tx,ty,tz)
  end

  -- local cx,cy,cz = CameraPosition()

  crf:UpdateRaidMarkers()
  -- crfFrame:UpdateBossMarkers()

  -- Cache camera values into locals
  local camX, camY, camZ = camera.x, camera.y, camera.z
  local cosYaw, sinYaw = camera.cosYaw, camera.sinYaw
  local cosPitch, sinPitch = camera.cosPitch, camera.sinPitch

  for i = 1, dotCount do
    local dot = DotPool[i]
    if dot.inUse then
      local relX = dot.x - camX
      local relY = dot.y - camY
      local relZ = dot.z - camZ

      -- Yaw rotation
      local yAfterYaw = -(cosYaw * relX - sinYaw * relY)
      local xAfterYaw = (sinYaw * relX + cosYaw * relY)
      local zAfterYaw = relZ

      -- Pitch rotation
      local finalY = (cosPitch * yAfterYaw - sinPitch * zAfterYaw)
      local finalZ = (sinPitch * yAfterYaw + cosPitch * zAfterYaw)
      local finalX = xAfterYaw

      if finalY < 0 then
        dot:Hide()
      else
        dot:Show()
        local normX = finalX / finalY
        local normZ = finalZ / finalY

        local screenX = (normX / fovScale) * (screenWidth / 2)
        local screenY = (normZ * aspectRatio) / fovScale * (screenHeight / 2)

        dot:SetPoint("CENTER", UIParent, "CENTER", screenX, screenY)
        dot.screenX = screenX
        dot.screenY = screenY
      end
    end
  end

  -- Arrow update block using cached values
  if crf:ShowArrow() and tx then
    local obj_distance = calculateDistance(px, py, pz, tx, ty, tz)
    local player_facing = UnitFacing("player")
    local target_facing = UnitFacing("target")

    local is_facing = player_facing and IsUnitFacingUnit(px, py, player_facing, tx, ty, CONSTANT_FACING_LIMIT)
    local is_behind = target_facing and not IsUnitFacingUnit(tx, ty, target_facing, px, py, pi / 2)

    local _, _, _, pxPoint, pyPoint = playerdot1:GetPoint()
    local _, _, _, txPoint, tyPoint = targetdot1:GetPoint()
    local dx = txPoint - pxPoint
    local dy = tyPoint - pyPoint
    local distance = sqrt(dx * dx + dy * dy)
    local midX = (pxPoint + txPoint) / 2
    local midY = (pyPoint + tyPoint) / 2

    playerdot1.icon:SetWidth(distance)
    playerdot1.icon:SetHeight(distance)

    local angle1 = GetAngleBetweenPoints(pxPoint, pyPoint, txPoint, tyPoint) + (pi / 2)
    RotateTexture(playerdot1.icon, angle1)

    local alpha = (obj_distance < 30) and 1 or ((obj_distance > 50) and 0 or (1 - ((obj_distance - 25) / (50 - 25))))

    -- Determine the new color state and desired RGB values.
    local newColorState, r, g, b
    if IsInRange(obj_distance) then
      if settings.largearrow and playerdot1.icon:GetTexture() ~= textures.in_range then
        playerdot1.icon:SetTexture(textures.in_range)
      end

      if not is_facing then
        newColorState = "not_facing"
        r, g, b = 1, 0.5, 0
      elseif is_behind then
        newColorState = "behind"
        r, g, b = 0.25, 0.75, 0.65
      else
        newColorState = "normal"
        r, g, b = 0.1, 0.85, 0.15
      end
    else
      newColorState = "out_range"
      r, g, b = 0.95, 0.1, 0.1
      if playerdot1.icon:GetTexture() ~= textures.out_range then
        playerdot1.icon:SetTexture(textures.out_range)
      end
    end

    -- Only update the vertex color if the new state differs from the cached state.
    if lastColorState ~= newColorState or lastAlpha ~= alpha then
      playerdot1.icon:SetVertexColor(r, g, b, alpha)
      lastColorState = newColorState
      lastAlpha = alpha
    end

    playerdot1.icon:SetPoint("CENTER", UIParent, "CENTER", midX, midY)
    if not playerdot1.icon:IsVisible() then playerdot1.icon:Show() end
  else
    targetdot1.icon:Hide()
    playerdot1.icon:Hide()
  end
end

crfFrame:SetScript("OnUpdate",crfFrame_OnUpdate)
