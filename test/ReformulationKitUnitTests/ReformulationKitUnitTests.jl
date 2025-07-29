module ReformulationKitUnitTests

using JuMP, MathOptInterface, ReformulationKit, Test

const RK = ReformulationKit
const MOI = MathOptInterface

# Legacy annotation functions for testing
dw_annotation(::Val{:x}, machine, job) = RK.dantzig_wolfe_subproblem(machine);
dw_annotation(::Val{:cov}, job) = RK.dantzig_wolfe_master();
dw_annotation(::Val{:knp}, machine) = RK.dantzig_wolfe_subproblem(machine);

# GAP annotation functions for unit tests
gap_annotation(::Val{:x}, machine, job) = RK.dantzig_wolfe_subproblem(machine);
gap_annotation(::Val{:assignment}, job) = RK.dantzig_wolfe_master();
gap_annotation(::Val{:capacity_constr}, machine) = RK.dantzig_wolfe_subproblem(machine);
gap_annotation(::Val{:penalty}, job) = RK.dantzig_wolfe_master();

# Mixed GAP annotation functions
mixed_gap_annotation(::Val{:x}, machine, job) = RK.dantzig_wolfe_subproblem(machine);
mixed_gap_annotation(::Val{:y}, machine, job) = RK.dantzig_wolfe_subproblem(machine);
mixed_gap_annotation(::Val{:z}, job) = RK.dantzig_wolfe_master();
mixed_gap_annotation(::Val{:assignment}, job) = RK.dantzig_wolfe_master();
mixed_gap_annotation(::Val{:capacity_constr}, machine) = RK.dantzig_wolfe_subproblem(machine);

# Helper functions for test data creation
function create_simple_problem()
    J = 1:3
    M = 1:2
    c = [1 2 3; 4 5 6]
    w = [1 1 1; 2 2 2]
    Q = [2, 4]

    model = Model()
    @variable(model, x[M, J], Bin)
    @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
    @constraint(model, knp[m in M], sum(w[m, j] * x[m, j] for j in J) <= Q[m])
    @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))

    return model, J, M, c, w, Q
end

function create_minimal_problem()
    model = Model()
    @variable(model, x[1:1, 1:1], Bin)
    @constraint(model, cov[j in 1:1], sum(x[m, j] for m in 1:1) >= 1)
    @constraint(model, knp[m in 1:1], sum(x[m, j] for j in 1:1) <= 1)
    @objective(model, Min, sum(x[m, j] for m in 1:1, j in 1:1))
    return model
end

# GAP helper functions for unit tests
function create_standard_gap()
    machines = 1:2
    jobs = 1:3
    
    costs = [1 2 3; 4 5 6]
    weights = [1 1 1; 2 2 2] 
    capacities = [2, 4]
    
    model = Model()
    @variable(model, x[machines, jobs], Bin)
    @constraint(model, assignment[j in jobs], sum(x[m, j] for m in machines) >= 1)
    @constraint(model, capacity_constr[m in machines], sum(weights[m, j] * x[m, j] for j in jobs) <= capacities[m])
    @objective(model, Min, sum(costs[m, j] * x[m, j] for m in machines, j in jobs))
    
    return model, machines, jobs
end

function create_gap_with_penalty()
    machines = 1:2
    jobs = 1:3
    
    costs = [1 2 3; 4 5 6]
    weights = [1 1 1; 2 2 2]
    capacities = [2, 4]
    penalty_costs = [10, 12, 8]
    
    model = Model()
    @variable(model, x[machines, jobs], Bin)
    @variable(model, penalty[jobs] >= 0)
    @constraint(model, assignment[j in jobs], sum(x[m, j] for m in machines) + penalty[j] >= 1)
    @constraint(model, capacity_constr[m in machines], sum(weights[m, j] * x[m, j] for j in jobs) <= capacities[m])
    @objective(model, Min, sum(costs[m, j] * x[m, j] for m in machines, j in jobs) + sum(penalty_costs[j] * penalty[j] for j in jobs))
    
    return model, machines, jobs
end

function create_minimal_gap()
    machines = 1:1
    jobs = 1:1
    
    model = Model()
    @variable(model, x[machines, jobs], Bin)
    @constraint(model, assignment[j in jobs], sum(x[m, j] for m in machines) >= 1)
    @constraint(model, capacity_constr[m in machines], sum(x[m, j] for j in jobs) <= 1)
    @objective(model, Min, sum(x[m, j] for m in machines, j in jobs))
    
    return model
end

function create_mixed_gap()
    machines = 1:2
    jobs = 1:3
    
    costs_x = [1 2 3; 4 5 6]
    costs_y = [0.5 1.0 1.5; 2.0 2.5 3.0]
    costs_z = [100, 150, 120]
    weights = [1 1 1; 2 2 2]
    capacities = [2, 4]
    
    model = Model()
    @variable(model, x[machines, jobs], Bin)
    @variable(model, y[machines, jobs] >= 0)
    @variable(model, z[jobs], Int)
    @constraint(model, assignment[j in jobs], sum(x[m, j] for m in machines) + z[j] >= 1)
    @constraint(model, capacity_constr[m in machines], sum(weights[m, j] * (x[m, j] + y[m, j]) for j in jobs) <= capacities[m])
    @objective(model, Min, sum(costs_x[m, j] * x[m, j] + costs_y[m, j] * y[m, j] for m in machines, j in jobs) + sum(costs_z[j] * z[j] for j in jobs))
    
    return model, machines, jobs
end

# Basic structure tests
function test_reformulation_ok()
    model, J, M, c, w, Q = create_simple_problem()
    reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
    
    @test reformulation isa RK.Reformulation

    # master
    master = RK.master(reformulation)
    @test num_variables(master) == 0
    @test num_constraints(master, count_variable_in_set_constraints=false) == 5
    @test objective_sense(master) == MIN_SENSE

    # subproblems

    subproblems = RK.subproblems(reformulation)
    @test length(subproblems) == 2
    for (i, sp) in enumerate(subproblems)
        @test num_variables(sp) == 3
        @test objective_sense(sp) == MIN_SENSE
        @test num_constraints(sp, count_variable_in_set_constraints=false) == 1
    end

    @test length(reformulation.convexity_constraints) == 2
    @test length(reformulation.coupling_constraints) == 3
end



# Include all test modules
include("dantzig_wolfe/partitionning.jl")
include("dantzig_wolfe/models.jl")
include("dantzig_wolfe/reformulation.jl")
include("dantzig_wolfe/main.jl")

function run()
    @testset "ReformulationKit Unit Tests" begin
        # Comprehensive unit tests
        test_unit_partitioning()
        test_unit_models()
        test_unit_reformulation_structure()
        test_unit_main_decomposition()
    end
end

end