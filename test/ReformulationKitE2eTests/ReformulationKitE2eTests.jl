module ReformulationKitE2eTests

using JuMP, MathOptInterface, ReformulationKit, Test

const RK = ReformulationKit
const MOI = MathOptInterface

# Annotation functions for GAP E2E tests
gap_annotation(::Val{:x}, machine, job) = RK.dantzig_wolfe_subproblem(machine);
gap_annotation(::Val{:assignment}, job) = RK.dantzig_wolfe_master();
gap_annotation(::Val{:capacity_constr}, machine) = RK.dantzig_wolfe_subproblem(machine);
gap_annotation(::Val{:penalty}, job) = RK.dantzig_wolfe_master();

# Legacy annotation functions for basic GAP test
dw_annotation(::Val{:x}, machine, job) = RK.dantzig_wolfe_subproblem(machine);
dw_annotation(::Val{:cov}, job) = RK.dantzig_wolfe_master();
dw_annotation(::Val{:knp}, machine) = RK.dantzig_wolfe_subproblem(machine);

# Include all E2E test modules
include("dantzig_wolfe/gap_scenarios.jl")
include("dantzig_wolfe/extended_formulation.jl")

function run()
    @testset "ReformulationKit E2E Tests" begin
        test_e2e_dantzig_wolfe_gap_scenarios()
    end

    test_e2e_extended_formulation()
end

end