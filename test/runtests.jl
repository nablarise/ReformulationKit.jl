######## Step 1: define test modules.
#
# Each test suite (unit, integration, e2e) should be a in a specific module and
# exposed by a `run` method.
# The module is loaded from a specific file.
# Example : if you want to run unit tests, you must define them in a `EmptyPackageUnitTests`
# subodule that contains a `run` method to run them all.
# The `EmptyPackageUnitTests` module is loaded from the file `EmptyPackageUnitTests/EmptyPackageUnitTests.jl`.$
# The folder and file must share the same name (like a package).

# Put all test modules in the LOAD_PATH.
# Trick from:
# https://discourse.julialang.org/t/basic-revise-jl-usage-when-developing-a-module/19140/16
for submodule in filter(item -> isdir(joinpath(@__DIR__, item)), readdir())
    push!(LOAD_PATH, joinpath(@__DIR__, submodule))
end
########

using Revise
using Test

######## Step 2: set the name of your app.
using ReformulationKit
########

######## Step 3: use test modules
using ReformulationKitUnitTests
########

# Load the script that contains the method that tracks the changes and runs
# the tests.
include("revise.jl")

######## Step 4: Put all the modules to track here.
MODULES_TO_TRACK = [
    ReformulationKit
]
########

######## Step 5: Put all the test modules to track and run here.
TEST_MODULES_TO_TRACK_AND_RUN = [
    ReformulationKitUnitTests
]
########

# The first argument is "from_sh" when the script is run from the shell.
# Take a look at `runtests.sh`.
if length(ARGS) >= 1 && ARGS[1] == "auto"
    while run_tests_on_change(
        TEST_MODULES_TO_TRACK_AND_RUN,
        MODULES_TO_TRACK
    ) end
    exit(222)
else
    for mod in TEST_MODULES_TO_TRACK_AND_RUN
        mod.run()
    end
end