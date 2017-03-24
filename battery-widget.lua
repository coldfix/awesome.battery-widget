-- Battery widget

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")

------------------------------------------
-- Private utility functions
------------------------------------------

local function file_exists(command)
    local f = io.open(command)
    if not f then return false end
    f:close()
    return true
end

local function readfile(command)
    local file = io.open(command)
    if file == nil then
        return nil
    end
    local text = file:read('*all')
    file:close()
    return text
end

local function fg(color, text)
    if color == nil then
        return text
    else
        return '<span color="' .. color .. '">' .. text .. '</span>'
    end
end

local function round(value)
  return math.floor(value + 0.5)
end

local function trim(s)
    if s == nil then return nil end
  -- from PiL2 20.4
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end


------------------------------------------
-- Battery widget interface
------------------------------------------

local battery_widget = {}

function battery_widget:new(args)
    return setmetatable({}, {__index = self}):init(args)
end

function battery_widget:init(args)
    self.adapter = args.adapter or "BAT0"
    self.ac_prefix = args.ac_prefix or "AC: "
    self.battery_prefix = args.battery_prefix or "Bat: "
    self.limits = args.limits or {
        {25, "red"},
        {50, "orange"},
        {100, "green"}
    }
    self.widget_prefix = args.widget_prefix or ""
    self.widget_suffix = args.widget_suffix or ""

    self.widget = wibox.widget.textbox()
    self.widget.set_align("right")
    self.tooltip = awful.tooltip({objects={self.widget}})

    self.widget:buttons(awful.util.table.join(
        awful.button({ }, 1, function() self:update() end),
        awful.button({ }, 3, function() self:update() end)
    ))

    self.timer = gears.timer({ timeout = args.timeout or 10 })
    self.timer:connect_signal("timeout", function() self:update() end)
    self.timer:start()
    self:update()

    return self
end

local sysfs_names = {
    charging = {
        present   = "present",
        state     = "status",
        rate      = "current_now",
        charge    = "charge_now",
        capacity  = "charge_full",
        design    = "charge_full_design",
        ac_state  = "AC/online",
        percent   = "capacity",
    },
    discharging = {
        present   = "present",
        state     = "status",
        rate      = "power_now",
        charge    = "energy_now",
        capacity  = "energy_full",
        design    = "energy_full_design",
        ac_state  = "AC/online",
        percent   = "capacity"
    }
}

function battery_widget:get_state()
    local present, capacity, state, rate, charge
    local percent, time, is_charging

    local pre   = "/sys/class/power_supply/"
    local dir   = pre .. self.adapter
    local sysfs = (file_exists(dir.."/"..sysfs_names.charging.rate)
                   and sysfs_names.charging
                   or sysfs_names.discharging)

    present   = readfile(dir.."/"..sysfs.present)
    state     = trim(readfile(dir.."/"..sysfs.state):lower())
    rate      = readfile(dir.."/"..sysfs.rate)
    charge    = readfile(dir.."/"..sysfs.charge)
    capacity  = readfile(dir.."/"..sysfs.capacity)
    design    = readfile(dir.."/"..sysfs.design)
    ac_state  = readfile(pre.."/"..sysfs.ac_state)
    percent   = readfile(dir.."/"..sysfs.percent)

    if state == "unknown" then
        state = "charged"
    end

    rate     = tonumber(rate)
    charge   = tonumber(charge)
    capacity = tonumber(capacity)
    design   = tonumber(design)
    ac_state = tonumber(ac_state)
    percent  = tonumber(percent)

    -- loaded percentage
    if charge and capacity and not percent then
        percent = round(charge * 100 / capacity)
    end

    -- estimate time
    is_charging = 0
    time = -1
    if rate ~= 0 and rate ~= nil then
        if state == "charging" then
            time = (capacity - charge) / rate
            is_charging = 1
        elseif state == "discharging" or state == nil then
            time = charge / rate
            is_charging = -1
        end
    end

    return percent, ac_state, time, state, is_charging, capacity, design
end

function battery_widget:update()
    local percent, ac_state, time, state, is_charging, capacity, design = self:get_state()
    local prefix, text
    local time_hour, time_minute, time_str, est_postfix

    -- AC/battery prefix
    if ac_state == 1 then
        prefix = self.ac_prefix
    else
        prefix = self.battery_prefix
    end

    -- Percentage
    -- text =  "⚡ ".. percent .. "%"
    if percent == nil then
        text = "Err!%"
    else
      text =  percent .. "%"
      for k,v in ipairs(self.limits) do
          if percent <= v[1] then
              text = fg(v[2], text)
              if ac_state ~= 1 and v[3] ~= nil then
                  prefix = v[3]
              end
              break
          end
      end
    end

    -- Time
    if time == -1 then
        est_postfix = "..."
    else
        time_hour = math.floor(time)
        time_minute = math.floor((time - time_hour) * 60)
        time_str = ""
        if time_hour ~= 0 then
            time_str = time_hour .. "h "
        end
        time_str = time_str .. time_minute .. "m"
        est_postfix = ": "..time_str.." remaining"
    end


    -- update text
    self.widget:set_markup(
            self.widget_prefix
            .. prefix .. text
            .. self.widget_suffix
        )

    -- capacity text
    if capacity ~= nil and design ~= nil then
        captext = "\nCapacity: " .. round(capacity/design*100) .. "%"
    else
        captext = "\nCapacity: Err!"
    end

    -- update tooltip
    if state == nil then
        state = "Err!"
    end
    if is_charging == 1 then
        self.tooltip:set_text("Battery "..state..est_postfix..captext)
    elseif is_charging == -1 then
        self.tooltip:set_text("Battery "..state..est_postfix..captext)
    else
        self.tooltip:set_text("Battery "..state..captext)
    end
end

return setmetatable(battery_widget, {
  __call = battery_widget.new,
})
