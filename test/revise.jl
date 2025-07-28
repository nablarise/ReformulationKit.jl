# Inspired from https://gist.github.com/torfjelde/62c1281d5fc486d3a404e5de6cf285d4
# and Coluna.jl (https://github.com/atoptima/Coluna.jl/blob/master/test/revise.jl).

function _check_other_errors(e)
    showerror(stderr, e, catch_backtrace())
    return false
end

# Uninformative stacktrace.
function _check_other_errors(e::Base.Meta.ParseError)
    showerror(stderr, e)
    return false
end

# Uninformative stacktrace.
function _check_other_errors(e::TaskFailedException)
    showerror(stderr, e)
    return false
end

# Test pkg prints the error.
_check_other_errors(e::TestSetException) = false

function _check_other_errors(composite::CompositeException)
    return any(e -> _check_other_errors(e), composite)
end

"""
Runs `test_funcs` functions when :
- any of the files in `files_to_track` changes
- any of the modules in `MODULES_TO_TRACK` changes

- returns 
 `false` if you need to restart
 `true` to stop
"""
function run_tests_on_change(TEST_MODULES_TO_TRACK_AND_RUN, MODULES_TO_TRACK)
    # Revise might encounter an error on the files it's watching, in which case
    # we need to re-trigger `Revise.entr`. BUT to avoid this happening repeatedly,
    # we set `postpone=true` in the `Revise.entr` call above. This postpones the first
    # trigger of the provided `f` until an actual change (which should hopefully be fixing
    # the error that caused Revise to fail).
    revise_errored = false
    while true
        try
            entr([], [TEST_MODULES_TO_TRACK_AND_RUN..., MODULES_TO_TRACK...]; postpone=revise_errored, all=true) do
                run(`clear`) # clear terminal
                for mod in TEST_MODULES_TO_TRACK_AND_RUN
                    # All the tests from a test module must be executed by the run method.
                    mod.run()
                end
            end
        catch e
            println("\e[1;37;41m ****** Exception caught $(typeof(e)) ******** \e[00m")
            if isa(e, InterruptException)
                return false
            elseif isa(e, Revise.ReviseEvalException)
                error("""
                    Revise does not support this operation.
                    Need to restart julia session."""
                )
            else
                stop = _check_other_errors(e)
                stop && return false
            end
            revise_errored = true
        end
    end
end