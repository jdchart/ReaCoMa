local info = debug.getinfo(1,'S');
local script_path = info.source:match[[^@?(.*[\/])[^\/]-$]]
dofile(script_path .. "/FluidPlumbing/FluidUtils.lua")
dofile(script_path .. "/FluidPlumbing/FluidParams.lua")
dofile(script_path .. "/FluidPlumbing/FluidPaths.lua")
dofile(script_path .. "/FluidPlumbing/FluidSlicing.lua")

if FluidPaths.sanity_check() == false then goto exit; end
local exe = FluidUtils.doublequote(FluidPaths.get_fluid_path() .. "/fluid-ampgate")

local num_selected_items = reaper.CountSelectedMediaItems(0)
if num_selected_items > 0 then

    -- Parameter Get/Set/Prep
    local processor = fluid_archetype.ampgate
    FluidParams.check_params(processor)
    local param_names = "rampup,rampdown,onthreshold,offthreshold,minslicelength,minsilencelength,minlengthabove,minlengthbelow,lookback,lookahead,highpassfreq,maxsize"
    param_values = FluidParams.parse_params(param_names, processor)

    local confirm, user_inputs = reaper.GetUserInputs("Ampgate Parameters", 12, param_names, param_values)
    if confirm then
        FluidParams.store_params(processor, param_names, user_inputs)

        reaper.Undo_BeginBlock()
        -- Algorithm Parameters
        local params = FluidUtils.commasplit(user_inputs)
        local rampup = params[1]
        local rampdown = params[2]
        local onthreshold = params[3]
        local offthreshold = params[4]
        local minslicelength = params[5]
        local minsilencelength = params[6]
        local minlengthabove = params[7]
        local minlengthbelow = params[8]
        local lookback = params[9]
        local lookahead = params[10]
        local highpassfreq = params[11]
        local maxsize = params[12]

        local data = FluidSlicing.container

        for i=1, num_selected_items do
            FluidSlicing.get_data(i, data)

            local cmd = exe .. 
            " -source " .. FluidUtils.doublequote(data.full_path[i]) .. 
            " -indices " .. FluidUtils.doublequote(data.tmp[i]) .. 
            " -rampup " .. rampup ..
            " -rampdown " .. rampdown ..
            " -onthreshold " .. onthreshold ..
            " -offthreshold " .. offthreshold ..
            " -minslicelength " .. minslicelength ..
            " -minsilencelength " .. minsilencelength ..
            " -minlengthabove " .. minlengthabove ..
            " -minlengthbelow " .. minlengthbelow ..
            " -lookback " .. lookahead ..
            " -lookahead " .. lookahead ..
            " -highpassfreq " .. highpassfreq ..
            " -maxsize " .. maxsize ..
            " -numframes " .. data.item_len_samples[i] .. 
            " -startframe " .. data.take_ofs_samples[i]
            table.insert(data.cmd, cmd)
        end

        for i=1, num_selected_items do
            FluidUtils.cmdline(data.cmd[i])
            var = FluidUtils.readfile(data.tmp[i])
            channel_split = FluidUtils.linesplit(var)
            onsets = FluidUtils.commasplit(channel_split[1])
            offsets = FluidUtils.commasplit(channel_split[2])
            laced = FluidUtils.lacetables(onsets, offsets)
            if #laced <= 2 then goto exit; end
            dumb_string = ""
            local state_state = nil
            if laced[1] == 0 then 
                start_state = 0 -- if there is a 0 at the start we start 'off/unmuted'
            else 
                table.insert(laced, 1, "0")
                start_state = 1 -- if there is something else at the start we start muted and prepend a 0
            end
            for i=1, #laced do
                dumb_string = dumb_string .. laced[i] .. ","
            end
            table.insert(data.slice_points_string, dumb_string)
            FluidSlicing.perform_gate_splitting(i, data, start_state)
        end

        reaper.UpdateArrange()
        reaper.Undo_EndBlock("ampgate", 0)
        FluidUtils.cleanup(data.tmp)
    end
end
::exit::