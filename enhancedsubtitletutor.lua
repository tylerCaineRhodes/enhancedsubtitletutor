-- luacheck: globals mp

-- configuration
local minimum_pause_time = 0.5
local pause_time_modifier = 0.6
local minimum_sub_length = 0.7
local minimum_word_count = 3
local ignore_formatted_subs = true

-- state
local active = false
local pause_at_start = false
local skip_next = false
local timer = nil

local function count_words(text)
    local count = 0
    for _word in string.gmatch(text, "[%w']+") do
        count = count + 1
    end
    return count
end

local function is_formatted_subtitle()
    local sub_style = mp.get_property("sub-style")
    if sub_style and (sub_style:find("italic") or sub_style:find("bold") or sub_style:find("sign")) then
        return true
    end
    return false
end

local function should_pause(sub_duration, sub_time, word_count)
    local is_long_enough_time = sub_time >= minimum_pause_time
    local is_long_enough_sub = sub_duration >= minimum_sub_length
    local is_long_enough_words = word_count >= minimum_word_count

    return is_long_enough_time and is_long_enough_sub and is_long_enough_words
end

local function pause()
    local sub_start = mp.get_property_number('sub-start')
    local sub_end = mp.get_property_number('sub-end')
    local sub_text = mp.get_property("sub-text")


    if not sub_start or not sub_end or not sub_text then return end

    if ignore_formatted_subs and is_formatted_subtitle() then return end

    local sub_duration = sub_end - sub_start
    local sub_time = sub_duration * pause_time_modifier
    local word_count = count_words(sub_text)

    local should_pause = should_pause(sub_duration, sub_time, word_count)

    if should_pause then
        if skip_next then
            skip_next = false
            return
        end

        mp.set_property_bool("pause", true)
        mp.set_property_bool("sub-visibility", true)
        mp.osd_message(" ", 0.001)

        timer = mp.add_timeout(sub_time, function()
            mp.set_property_bool("pause", false)
            mp.set_property_bool("sub-visibility", false)
            mp.remove_key_binding("override-pause")
        end)

        mp.add_forced_key_binding("SPACE", "override-pause", function()
            if timer then
                timer:kill()
                timer = nil
            end
            mp.remove_key_binding("override-pause")
        end)
    end
end

local function handle_sub_text_change(_, sub_text)
    if (sub_text ~= nil and sub_text ~= "") then
        if (pause_at_start) then
            pause()
        end
    end
end


local function display_state()
    local msg
    if (active) then
        msg = "Enhanced subtitle tutor (enabled)"
    else
        msg = "Enhanced subtitle tutor (disabled)"
    end
    mp.osd_message(msg)
end

local function handle_seek()
    if timer then
        timer:kill()
        timer = nil
    end

    skip_next = false
    mp.remove_key_binding("override-pause")
    mp.set_property_bool("sub-visibility", true)
end

local function handle_playback_restart()
    skip_next = false
end


local function toggle()
    pause_at_start = not pause_at_start

    if (active) then
        if (pause_at_start) then return end

        skip_next = false
        mp.unobserve_property(handle_sub_text_change)
        active = false
    else
        mp.observe_property("sub-text", "string", handle_sub_text_change)
        active = true
    end
    display_state()
end

local function replay_sub()
    if (pause_at_start) then
        skip_next = true
    end

    local sub_start = mp.get_property_number("sub-start")
    if (sub_start) ~= nil then
        mp.set_property("time-pos", sub_start + mp.get_property_number("sub-delay"))
        mp.set_property("pause", "no")
    end
end

mp.add_key_binding("n", "sub-pause-toggle-start", function() toggle() end)
mp.add_key_binding("Alt+r", "sub-pause-skip-next", function() skip_next = true end)
mp.add_key_binding("Ctrl+r", "sub-pause-replay", function() replay_sub() end)

mp.register_event("seek", handle_seek)
mp.register_event("playback-restart", handle_playback_restart)
